#!/bin/bash
# ===============================================================================
# 脚本名称: 03.monitor_cluster_health.sh
# 脚本用途: GBase 集群健康状态全面监控
#
# 功能说明:
#   1. 检查数据库连接基本可用性
#   2. 检查集群运行模式(NORMAL/READONLY/RECOVERY)
#   3. 检查各服务进程状态(GCWARE/GCLUSTER/GNODE/SYNCSERVER)
#   4. 检查数据一致性(GCLUSTER层/GNODE层)
#   5. 定期更新gcadmin状态文件并防重复告警
#
# 执行方式:
#   直接执行: bash /path/to/03.monitor_cluster_health.sh
#   调度执行: 由 01.monitor_scheduler.sh 自动调用
#
# 依赖项:
#   - 00.monitor_global_config.sh (全局配置文件)
#   - gccli (GBase数据库客户端)
#   - ssh (需配置免密登录到所有数据库节点)
#   - gcadmin (GBase集群管理命令)
#
# 版本信息:
#   版本: v3.8
#   作者: 数据库运维组
#   创建日期: 2024-11-01
#   最后更新: 2025-12-24
#   更新说明: 添加数据库连接回溯日志、增加SSH -q参数、完善gcadmin检查
#
# 维护说明:
#   1. 集群模式告警使用标志文件防止重复告警
#   2. 标志文件位置: $LOG_DIR/.cluster_mode_alarm_sent
#   3. 模式恢复NORMAL时自动清除标志文件
#   4. gcadmin状态文件5分钟更新一次
#   5. 应急预案: 见告警ID对应表(GBase_B_001, GBase_C_003等)
# ===============================================================================

# ===============================================
# --- 配置信息 ---
# ===============================================

# 引入统一配置脚本 (使用动态路径加载)

# 1. 获取当前脚本的绝对路径
# $0 是脚本自身的名字。readlink -f 解析出符号链接和绝对路径。
SCRIPT_FULL_PATH=$(readlink -f "$0")

# 2. 提取脚本所在的目录路径
SCRIPT_DIR=$(dirname "$SCRIPT_FULL_PATH")

# 3. 使用相对路径加载配置文件
# 假设 00.monitor_global_config.sh 与 03.monitor_cluster_health.sh 在同一目录
source "${SCRIPT_DIR}/00.monitor_global_config.sh"



# 确保日志目录存在
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# ===============================================
# --- 标志文件定义 ---
# ===============================================

# 用于标记集群模式告警是否已输出，防止多节点重复告警
CLUSTER_MODE_ALARM_FLAG="${LOG_DIR}/.cluster_mode_alarm_sent"

# ===============================================
# --- IP 列表解析 (保持不变) ---
# ===============================================
GBASE_NODES_LIST=$(echo "$DB_CONNECT_HOST" | tr ',' ' ')

# ===============================================
# --- 工具函数 (已恢复) ---
# ===============================================

# 函数: init_log_files
function init_log_files() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    touch "$LATEST_STATUS_LOG" "$HISTORY_LOG" "$ALARM_LOG"
    echo "========== $timestamp ==========" >> "$HISTORY_LOG"
    echo "========== $timestamp ==========" >> "$ALARM_LOG"
    >> "$LATEST_STATUS_LOG"
}

# 函数: is_number
function is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# 函数: update_gcadmin_data (使用 SSH 远程执行并支持冗余切换)
function update_gcadmin_data() {
    local alarm_id=999
    local target_host=""
    local success=false
    # 集群节点列表，按优先级尝试获取
    # HOSTS_TO_TRY 依赖 00.monitor_global_config.sh 中的 DB_CONNECT_HOST
    local HOSTS_TO_TRY=$(echo "$DB_CONNECT_HOST" | tr ',' ' ')

    # 确保 SSH 端口已在 00.monitor_global_config.sh 中定义：SSH_PORT="10022"

    # 1. 检查时间戳：如果文件不存在或超过 4 分钟才需要更新
    if [ ! -f "$GCADMIN_TS_FILE" ] || [ -n "$(find "$GCADMIN_TS_FILE" -mmin +4 2>/dev/null)" ]; then

        output_alarm 1 "开始尝试通过 SSH 远程执行 gcadmin 获取数据..." $alarm_id "$MY_IP" # <--- IP参数

        # 2. 遍历节点列表，尝试远程执行命令
        for ip in $HOSTS_TO_TRY; do
            target_host="$ip"

            # --- 【核心逻辑：如果 SSH 远程执行成功，则将输出重定向到本地文件】 ---
            # -q 静默模式，抑制警告和诊断信息
            # -p ${SSH_PORT} 使用配置的端口
            # -o ConnectTimeout=10 设置连接超时
            # > "$GCADMIN_FILE" 将远程命令的输出写入本地文件
            if ssh -q -p ${SSH_PORT} -o ConnectTimeout=10 "${ip}" "gcadmin" > "$GCADMIN_FILE" 2>/dev/null; then

                # 成功执行
                success=true
                break # 成功后立即跳出循环，不再尝试后续节点
            fi
        done

        # 3. 根据最终结果处理
        if $success; then
            touch "$GCADMIN_TS_FILE"
            # 确认文件是否为空
            if [ -s "$GCADMIN_FILE" ]; then
                # 使用实际连接的节点 IP 作为被管 IP
                output_alarm 1 "GCADMIN 数据已通过 SSH 远程执行 ${target_host} 成功更新" $alarm_id "$target_host" # <--- IP参数
            else
                # 文件为空，可能远程命令执行失败但 SSH 退出码不正确
                output_alarm 1 "GCADMIN 数据文件为空！虽然 SSH 连接成功，但远程 ${target_host} 上的 gcadmin 命令可能执行失败。" $alarm_id "$target_host" # <--- IP参数
                success=false
            fi
        fi

        # 4. 如果最终失败，触发报警
        if ! $success; then
            output_alarm 1 "GCADMIN 命令执行失败！无法通过 SSH 远程执行 gcadmin，请检查 SSH 密钥和集群节点状态" $alarm_id "$MY_IP" # <--- IP参数
        fi
    fi
}

# 函数: check_db_connection
function check_db_connection() {
    local alarm_id=601

    # 【新增】记录回溯命令
    local check_query="SELECT 1;"
    local check_cmd="gccli -u\"$ROOT_USER\" -p******** -h\"$DB_CONNECT_HOST\" -P25258 -Ns -e \"$check_query\""
    echo "[$(get_timestamp)] [回溯] 数据库连接检查命令: $check_cmd" >> "$HISTORY_LOG"

    if execute_gccli_query "SELECT 1;" >/dev/null 2>&1; then
        echo "[$(get_timestamp)] [回溯] 数据库连接检查成功，目标: ${DB_CONNECT_HOST}" >> "$HISTORY_LOG"
        output_alarm 1 "数据库连接正常 (目标: ${DB_CONNECT_HOST})" $alarm_id "$MY_IP" # <--- IP参数
        return 0
    else
        echo "[$(get_timestamp)] [回溯] 数据库连接检查失败，所有节点不可达" >> "$HISTORY_LOG"
        # 此处不传入 target_ip，使用默认 MY_IP (监控机 IP)
        output_alarm 5 "GBASE 集群 GCLUSTER 所有连接中断[错误码:ERROR 2003]，请按照应急预案GBase_B_001进行处理" $alarm_id "$MY_IP" # <--- IP参数
        return 1
    fi
}

# 函数: check_gcadmin_status
function check_gcadmin_status() {
    local alarm_id=900
    local keywords='FAILURE|UNAVAILABLE'

    # 【新增】记录回溯命令
    echo "[$(get_timestamp)] [回溯] GCADMIN 文件检查命令: grep -Eiwq '$keywords' '$GCADMIN_FILE'" >> "$HISTORY_LOG"

    if [ ! -f "$GCADMIN_FILE" ]; then
        echo "[$(get_timestamp)] [回溯] GCADMIN 文件 $GCADMIN_FILE 不存在，跳过检查" >> "$HISTORY_LOG"
        output_alarm 1 "GCADMIN 检查文件 $GCADMIN_FILE 不存在，跳过检查" $alarm_id "$MY_IP" # <--- IP参数
        return 1
    fi

    if grep -Eiwq "$keywords" "$GCADMIN_FILE"; then
        echo "[$(get_timestamp)] [回溯] GCADMIN 文件检查发现异常关键字: FAILURE/UNAVAILABLE" >> "$HISTORY_LOG"
        output_alarm 1 "GCADMIN 文件检查发现异常！发现关键字: FAILURE/UNAVAILABLE，脚本立即退出" $alarm_id "$MY_IP" # <--- IP参数
        exit 1
    else
        echo "[$(get_timestamp)] [回溯] GCADMIN 文件检查通过，未发现异常关键字" >> "$HISTORY_LOG"
        output_alarm 1 "GCADMIN 文件检查通过" $alarm_id "$MY_IP" # <--- IP参数
        return 0
    fi
}

# ===============================================
# --- 核心检查函数 ---
# ===============================================

# ------------------------------------------------------------------
# 函数: check_cluster_mode_status
# 功能: 检查集群模式 (NORMAL/READONLY/RECOVERY)
# 逻辑: 仅 1 为正常(1级)，非 1 为异常(4级)，查询失败记为记录(1级)
# ------------------------------------------------------------------
function check_cluster_mode_status() {
    local target_ip=$1 # 目标IP
    local alarm_id=602

    # 转换内部IP用于 SQL 查询过滤
    local internal_ip=$(map_external_to_internal_ip "$target_ip")

    # 构造查询命令并记录回溯
    local query="SELECT CLUSTER_MODE FROM information_schema.CLUSTER_MONIT_INFO WHERE host = '$internal_ip';"
    echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 集群模式查询: $query" >> "$HISTORY_LOG"

    # 执行查询
    local state=$(execute_gccli_query "$query")
    local query_status=$?

    # --- 情况 1: 无法连接服务器或查询结果为空 ---
    if [ $query_status -ne 0 ] || [ -z "$state" ]; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 查询失败，可能数据库连接异常，判定为记录(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 [${target_ip}]: 集群模式状态查询失败，可能数据库连接异常" $alarm_id "$target_ip"
        return 1
    fi

    # --- 情况 2: 结果为 1 (NORMAL 正常) ---
    if [ "$state" == "1" ]; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 状态为 1 (NORMAL)，判定为正常(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 [${target_ip}]: NORMAL 集群正常状态" $alarm_id "$target_ip"
        return 0
    fi

    # --- 情况 3: 结果非 1 (异常状态判定) ---
    # 定义显示名称
    local mode_name="未知模式($state)"
    [ "$state" == "2" ] && mode_name="READONLY模式"
    [ "$state" == "3" ] && mode_name="RECOVERY模式"

    echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 状态为 $state ($mode_name)，判定为异常(4级)" >> "$HISTORY_LOG"

    if [ ! -f "$CLUSTER_MODE_ALARM_FLAG" ]; then
        # 首次检测到异常，发送 4 级告警
        output_alarm 4 "节点 [${target_ip}]: GBASE 集群模式异常 [$mode_name] ，请按照应急预案GBase_C_003进行处理" $alarm_id "$target_ip"
        touch "$CLUSTER_MODE_ALARM_FLAG"
    else
        # 已经有节点报过 4 级了，其余节点降级为 1 级展示，避免重复骚扰
        output_alarm 1 "节点 [${target_ip}]: GBASE 集群处于 $mode_name (已由其他节点上报告警)" $alarm_id "$target_ip"
    fi

    return 0
}


# ------------------------------------------------------------------
# 函数: check_service_state
# 功能: 通用服务状态检查 (GCWARE, GCLUSTER, GNODE, SYNCSERVER)
# 逻辑: 1和0为正常(1级)，2为异常(4级)，查询失败记为记录(1级)
# ------------------------------------------------------------------
function check_service_state() {
    local target_ip="$1"
    local service_name="$2"
    local field_name="$3"
    local alarm_id="$4"
    local service_desc="${5:-$service_name}"

    # 转换内部IP
    local internal_ip=$(map_external_to_internal_ip "$target_ip")

    # 构造查询并记录回溯日志
    local query="SELECT $field_name FROM information_schema.CLUSTER_MONIT_INFO WHERE host = '$internal_ip';"
    echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 状态查询: $query" >> "$HISTORY_LOG"

    local state=$(execute_gccli_query "$query")
    local query_status=$?

    # --- 情况 1: 查询失败或返回为空 ---
    if [ $query_status -ne 0 ] || [ -z "$state" ]; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 查询失败，判定为记录(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 [${target_ip}]: $service_desc 状态查询失败，可能数据库连接异常" $alarm_id "$target_ip"
        return 1
    fi

    # --- 情况 2: 返回值非数字 ---
    if ! is_number "$state"; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 返回非数字 [$state]，判定为记录(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 [${target_ip}]: $service_desc 状态返回值异常: '$state' (非数字)" $alarm_id "$target_ip"
        return 1
    fi

    case "$state" in
        1)
            # 正常值
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 状态为 1 (正常)" >> "$HISTORY_LOG"
            output_alarm 1 "节点 [${target_ip}]: $service_desc 服务正常" $alarm_id "$target_ip"
            ;;
        0)
            # 视为正常 (本节点不包含该服务)
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 状态为 0 (不包含服务)，判定为正常(1级)" >> "$HISTORY_LOG"
            output_alarm 1 "节点 [${target_ip}]: 本节点不包含 $service_desc 服务" $alarm_id "$target_ip"
            ;;
        2)
            # 异常状态 (4级告警)
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 状态为 2 (异常)，触发4级告警" >> "$HISTORY_LOG"
            if [ "$service_name" == "GNODE" ]; then
                output_alarm 4 "节点 [${target_ip}] GNODE 服务进程处于异常 [关闭] 状态,请按照应急预案GBase_C_007进行处理" $alarm_id "$target_ip"
            elif [ "$service_name" == "GCLUSTER" ]; then
                output_alarm 4 "节点 [${target_ip}] GCLUSTER 服务进程处于异常 [关闭] 状态,请按照应急预案GBase_C_005进行处理" $alarm_id "$target_ip"
            elif [ "$service_name" == "SYNCSERVER" ]; then
                output_alarm 4 "节点 [${target_ip}] SYNCSERVER 服务进程处于异常 [关闭] 状态,请按照应急预案GBase_C_008进行处理" $alarm_id "$target_ip"
            elif [ "$service_name" == "GCWARE" ]; then
                output_alarm 4 "节点 [${target_ip}] GCWARE 服务进程处于异常 [关闭] 状态,请按照应急预案GBase_C_004进行处理" $alarm_id "$target_ip"
            else
                output_alarm 4 "节点 [${target_ip}]: $service_desc 服务异常" $alarm_id "$target_ip"
            fi
            ;;
        *)
            # 其他未知状态，默认设为 1 级展示
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 返回未知状态 [$state]，判定为记录(1级)" >> "$HISTORY_LOG"
            output_alarm 1 "节点 [${target_ip}]: $service_desc 状态返回值异常: '$state' (未知状态)" $alarm_id "$target_ip"
            ;;
    esac
    return 0
}

# --- 以下子函数保持 AlarmID 映射关系 ---

function check_gcware_state() {
    local target_ip=$1
    check_service_state "$target_ip" "GCWARE" "GCWARE_STATE" 603
}

function check_gcluster_state() {
    local target_ip=$1
    check_service_state "$target_ip" "GCLUSTER" "GCLUSTER_STATE" 604
}

function check_gnode_state() {
    local target_ip=$1
    check_service_state "$target_ip" "GNODE" "GNODE_STATE" 605
}

function check_syncserver_state() {
    local target_ip=$1
    check_service_state "$target_ip" "SYNCSERVER" "SYNCSERVER_STATE" 606
}
# ------------------------------------------------------------------
# 函数: check_data_status
# 功能: 检查集群数据状态 (GCLUSTER层/GNODE层)
# 逻辑: 1和0为正常(1级)，2为不一致(4级)，异常/失败记为记录(1级)
# ------------------------------------------------------------------
function check_data_status() {
    local target_ip="$1"
    local service_name="$2"
    local field_name="$3"
    local alarm_id="$4"
    local node_type="$5"

    # 转换内部IP
    local internal_ip=$(map_external_to_internal_ip "$target_ip")

    # 构造查询并记录回溯日志
    local query="SELECT $field_name FROM information_schema.CLUSTER_MONIT_INFO WHERE host = '$internal_ip';"
    echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 数据状态查询: $query" >> "$HISTORY_LOG"

    local state=$(execute_gccli_query "$query")
    local query_status=$?

    # --- 情况 1: 查询失败或返回为空 ---
    if [ $query_status -ne 0 ] || [ -z "$state" ]; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 数据状态查询失败，判定为记录(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 [${target_ip}]: $service_name 数据状态查询失败，可能数据库连接异常" $alarm_id "$target_ip"
        return 1
    fi

    # --- 情况 2: 返回值非数字 ---
    if ! is_number "$state"; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 返回非数字 [$state]，判定为记录(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 [${target_ip}]: $service_name 数据状态返回值异常: '$state' (非数字)" $alarm_id "$target_ip"
        return 1
    fi

    case "$state" in
        1)
            # 数据一致
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 状态为 1 (数据一致)" >> "$HISTORY_LOG"
            output_alarm 1 "节点 [${target_ip}]: $service_name 数据一致" $alarm_id "$target_ip"
            ;;
        0)
            # 视为正常 (非对应类型节点)
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 状态为 0 (非 $node_type 节点)，判定为正常(1级)" >> "$HISTORY_LOG"
            output_alarm 1 "节点 [${target_ip}]: 本节点不是 $node_type 节点" $alarm_id "$target_ip"
            ;;
        2)
            # 异常状态: 数据不一致 (触发 4 级告警)
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 状态为 2 (数据不一致)，触发4级告警" >> "$HISTORY_LOG"
            if [ "$service_name" == "GCLUSTER" ]; then
                output_alarm 4 "节点 [${target_ip}] GCLUSTER 层数据处于 [不一致] 状态,请按照应急预案GBase_C_006进行处理" $alarm_id "$target_ip"
            elif [ "$service_name" == "GNODE" ]; then
                output_alarm 4 "节点 [${target_ip}] GNODE 层数据处于 [不一致] 状态,请按照应急预案GBase_C_010进行处理" $alarm_id "$target_ip"
            else
                output_alarm 4 "节点 [${target_ip}]: $service_name 数据不一致" $alarm_id "$target_ip"
            fi
            ;;
        *)
            # 未知状态，统一设为 4 级告警（数据状态未知视为不安全）
            echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip $service_name 返回未知状态 [$state]，触发4级告警" >> "$HISTORY_LOG"
            output_alarm 4 "节点 [${target_ip}]: $service_name 数据状态返回值异常: '$state' (未知状态)" $alarm_id "$target_ip"
            ;;
    esac
    return 0
}

# --- 子函数映射 ---

function check_coorserver_data_status() {
    local target_ip=$1
    check_data_status "$target_ip" "GCLUSTER" "COORSERVER_DATA_STATUS" 607 "coordinator"
}

function check_dataserver_data_status() {
    local target_ip=$1
    check_data_status "$target_ip" "GNODE" "DATASERVER_DATA_STATUS" 608 "node"
}



# ===============================================
# --- 主执行逻辑 (增加标志清除和换行符分隔) ---
# ===============================================

# 函数: check_cluster_status_multi_node
function check_cluster_status_multi_node() {
    # ===============================================
    # 【新增】在追加日志文件前增加一个换行符
    # 目的: 确保每次执行的告警日志之间有明确分隔
    # ===============================================
    if [ -f "$HISTORY_LOG" ]; then
        echo "" >> "$HISTORY_LOG"
    fi

    if [ -f "$ALARM_LOG" ]; then
        echo "" >> "$ALARM_LOG"
    fi

    init_log_files
    output_alarm 1 "--- 开始集群状态检查 (目标节点: ${GBASE_NODES_LIST}) ---" "999" "$MY_IP" # <--- IP参数

    # 步骤0：清除上次的集群模式告警标记 (确保每次运行都能正常触发告警)
    if [ -f "$CLUSTER_MODE_ALARM_FLAG" ]; then
        rm -f "$CLUSTER_MODE_ALARM_FLAG"
    fi

    update_gcadmin_data

    if ! check_db_connection; then
        output_alarm 4 "节点 GCWARE 服务进程处于异常 [关闭] 状态,请按照应急预案GBase_C_004进行处理" "603" "$MY_IP" # <--- IP参数
        output_alarm 1 "数据库连接失败，无法进行后续 SQL 检查，脚本退出" "999" "$MY_IP" # <--- IP参数
        exit 1
    fi

    check_gcadmin_status

    for target_ip in $GBASE_NODES_LIST; do
        output_alarm 1 "--- 正在检查 GBase 节点: ${target_ip} 的集群状态 ---" "999" "$target_ip" # <--- IP参数

        check_cluster_mode_status "$target_ip"
        check_gcware_state "$target_ip"
        check_gcluster_state "$target_ip"
        check_gnode_state "$target_ip"
        check_syncserver_state "$target_ip"
        check_coorserver_data_status "$target_ip"
        check_dataserver_data_status "$target_ip"

        output_alarm 1 "--- GBase 节点 ${target_ip} 集群状态检查结束 ---" "999" "$target_ip" # <--- IP参数
    done

    output_alarm 1 "--- 结束集群状态检查 ---" "999" "$MY_IP" # <--- IP参数
}


# ===============================================
# ----------------- 脚本执行入口 -----------------
# ===============================================
check_cluster_status_multi_node

exit 0
