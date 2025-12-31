#!/bin/bash
# ===============================================================================
# 脚本名称: 04.monitor_db_metrics.sh
# 脚本用途: GBase 数据库业务指标监控
#
# 功能说明:
#   1. 监控集群总会话数(两级阈值告警)
#   2. 监控慢查询SQL(执行时间超30分钟)
#   3. 监控表锁数量
#   4. 监控处于等待状态的SQL数量
#   5. 记录慢查询详细信息到专用日志文件
#
# 执行方式:
#   直接执行: bash /path/to/04.monitor_db_metrics.sh
#   调度执行: 由 01.monitor_scheduler.sh 自动调用
#   函数调用: source后调用 check_db_status 函数
#
# 依赖项:
#   - 00.monitor_global_config.sh (全局配置文件)
#   - gccli (GBase数据库客户端)
#
# 版本信息:
#   版本: v1.1
#   作者: 数据库运维组
#   创建日期: 2024-11-15
#   最后更新: 2025-12-24
#   更新说明: 添加数据库连接检查回溯日志、密码脱敏、完善错误处理
#
# 维护说明:
#   1. 所有指标自动汇总所有节点数据
#   2. 节点连接失败时该节点计为0,不影响其他节点
#   3. 阈值可在00配置文件中修改
#   4. 慢查询详细日志建议定期归档(配合logrotate)
#   5. 应急预案: GBase_C_010 (性能优化和会话管理)
# ===============================================================================

# 引入统一配置脚本 (使用动态路径加载)

# 1. 获取当前脚本的绝对路径
SCRIPT_FULL_PATH=$(readlink -f "$0")

# 2. 提取脚本所在的目录路径
SCRIPT_DIR=$(dirname "$SCRIPT_FULL_PATH")

# 3. 使用相对路径加载配置文件
source "${SCRIPT_DIR}/00.monitor_global_config.sh"

# 确保日志目录存在
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# ===============================================
# --- 检查函数 (基于表格指标) ---
# 使用全局配置中的变量和函数
# ===============================================

# 检查 SQL 执行时间 (sql_execute_time) - AlarmID=702
# 查询所有节点，汇总结果后判断告警
function check_sql_execute_time() {
    local log_ip=$1
    local alarm_id=702
    # 使用全局配置中的阈值
    local threshold=${SLOW_QUERY_THRESHOLD:-1800}

    local total_count=0
    local all_slow_queries_detail=""

    # 从全局配置获取节点列表
    IFS=',' read -r -a node_list <<< "$DB_CONNECT_HOST"

    for node_ip in "${node_list[@]}"; do
        # 构造回溯命令字符串
        local cmd="gccli -u\"$ROOT_USER\" -p******** -h$node_ip -P25258 -Ns -e \"show full processlist;\" | awk '\$7 > $threshold' | grep -vE \"Sleep|Daemon\""
        echo "[$(get_timestamp)] [回溯] 节点 $node_ip 检测命令: $cmd" >> "$HISTORY_LOG"

        # 执行检测
        local node_output
        node_output=$(gccli -u"$ROOT_USER" -p"$ROOT_PASSWD" -h"$node_ip" -P25258 -Ns -e "show full processlist;" 2>>"$HISTORY_LOG" | awk -v t="$threshold" '$7 > t' | grep -vE "Sleep|Daemon") || true

        # 统计该节点数量
        local node_count=$(echo "$node_output" | grep -v "^$" | wc -l)

        if [ -z "$node_output" ] && [ "$node_count" -eq 0 ]; then
            echo "[$(get_timestamp)] [WARN] 节点 $node_ip 连接异常或无响应，该节点慢查询计为 0，继续后续检查。" >> "$HISTORY_LOG"
        fi

        total_count=$((total_count + node_count))

        # 如果有慢SQL，记录该节点明细
        if [ "$node_count" -gt 0 ]; then
            all_slow_queries_detail="${all_slow_queries_detail}\n[ 节点: $node_ip | 发现: $node_count 条 ]\n${node_output}"
        fi
    done

    # 告警逻辑判断
    if [ "$total_count" -ge 1 ]; then
        # 使用全局配置中的日志路径
        echo -e "\n>>> $(get_timestamp) 慢查询汇总报告 <<<" >> "$SLOW_SQL_DETAIL_LOG"
        echo -e "$all_slow_queries_detail" >> "$SLOW_SQL_DETAIL_LOG"
        echo -e "--------------------------------------------------------" >> "$SLOW_SQL_DETAIL_LOG"

        local threshold_minutes=$((threshold / 60))
        output_alarm 3 "GBASE 集群SQL执行超过阈值${threshold_minutes}分钟 [ $total_count 个 ]，请按照应急预案GBase_C_010进行处理" "$alarm_id" "$log_ip"
    else
        local threshold_minutes=$((threshold / 60))
        output_alarm 1 "SQL 执行时间正常 ($total_count 个超过 ${threshold_minutes} 分钟的慢查询)" "$alarm_id" "$log_ip"
    fi
}

# 检查服务会话总数 (session_num) - AlarmID=701
# 使用全局配置中的 query_all_nodes_with_logging 函数
function check_session_num() {
    local log_ip=$1
    local alarm_id=701

    local sql="SELECT COUNT(*) FROM information_schema.PROCESSLIST;"
    local total_session_count=$(query_all_nodes_with_logging "$sql" "会话统计")

    # 使用全局配置中的阈值
    local warning_threshold=${SESSION_THRESHOLD_WARNING:-1000}
    local critical_threshold=${SESSION_THRESHOLD_CRITICAL:-2000}

    # 告警判断
    if [ "$total_session_count" -ge "$critical_threshold" ]; then
        output_alarm 4 "GBASE 集群连接总会话数超过阈值 [ ${critical_threshold}个 ]，请立即按照应急预案GBase_C_010进行紧急处理" "$alarm_id" "$log_ip"
    elif [ "$total_session_count" -ge "$warning_threshold" ]; then
        output_alarm 3 "GBASE 集群连接总会话数超过阈值 [ ${warning_threshold}个 ]，请按照应急预案GBase_C_010进行处理" "$alarm_id" "$log_ip"
    else
        output_alarm 1 "服务会话总数正常 ($total_session_count 个)" "$alarm_id" "$log_ip"
    fi
}

# 检查处于 Waiting 状态的 SQL 数量 - AlarmID=704
# 使用全局配置中的 query_all_nodes_with_logging 函数
function check_waiting_sql_count() {
    local log_ip=$1
    local alarm_id=704

    local sql="SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE STATE LIKE '%checking permissions%';"
    local total_waiting_count=$(query_all_nodes_with_logging "$sql" "等待SQL检查")

    # 使用全局配置中的阈值
    local threshold=${WAITING_SQL_THRESHOLD:-50}

    # 告警判断
    if [ "$total_waiting_count" -ge "$threshold" ]; then
        output_alarm 3 "GBASE 集群处于锁等待的SQL数量超过阈值[ ${threshold}个 ]，请按照应急预案GBase_C_010进行处理" "$alarm_id" "$log_ip"
    else
        output_alarm 1 "处于等待状态的 SQL 数量正常 ($total_waiting_count 个)" "$alarm_id" "$log_ip"
    fi
}

# 检查当前表锁数量 (table_lock_count) - AlarmID=703
# 使用全局配置中的 query_all_nodes_with_logging 函数
function check_table_lock_count() {
    local log_ip=$1
    local alarm_id=703

    local sql="SELECT COUNT(*) FROM information_schema.TABLE_LOCKS;"
    local total_lock_count=$(query_all_nodes_with_logging "$sql" "表锁检查")

    # 使用全局配置中的阈值
    local threshold=${TABLE_LOCK_THRESHOLD:-50}

    # 告警判断
    if [ "$total_lock_count" -ge "$threshold" ]; then
        output_alarm 3 "GBASE 集群加锁数量超过阈值 [ $total_lock_count ]，请按照应急预案GBase_C_010进行处理" "$alarm_id" "$log_ip"
    else
        output_alarm 1 "当前表锁数量正常 (集群汇总: $total_lock_count 个)" "$alarm_id" "$log_ip"
    fi
}

# ===============================================
# ----------------- 主执行逻辑 -----------------
# ===============================================

# 核心检查函数，后续可以被其他脚本调用
function check_db_status() {
    # 1. 在追加日志文件前增加一个换行
    if [ -f "$HISTORY_LOG" ]; then
        echo "" >> "$HISTORY_LOG"
    fi

    if [ -f "$ALARM_LOG" ]; then
        echo "" >> "$ALARM_LOG"
    fi

    # 记录开始时间到历史日志 (使用默认 $MY_IP)
    output_alarm 1 "--- 开始数据库业务状态检查 ---" "999" "$MY_IP"

    # 【新增】记录数据库连接检查的回溯命令
    local check_query="SELECT 1;"
    local check_cmd="gccli -u\"$ROOT_USER\" -p******** -h\"$DB_CONNECT_HOST\" -P25258 -Ns -e \"$check_query\""
    echo "[$(get_timestamp)] [回溯] 数据库连接检查命令: $check_cmd" >> "$HISTORY_LOG"

    # 检查数据库连接 (尝试连接任意一个节点验证基本连通性)
    execute_gccli_query "SELECT 1;" >/dev/null

    # 如果连接失败，则退出
    if [ $? -ne 0 ]; then
        echo "[$(get_timestamp)] [回溯] 数据库连接检查失败，所有节点不可达" >> "$HISTORY_LOG"
        output_alarm 4 "数据库连接失败，无法进行后续 SQL 检查，脚本退出。" "999" "$MY_IP"
        return
    else
        # 1. 查询实际连接成功的节点名
        local hostname_query="SELECT SUBSTRING_INDEX(@@hostname, ':', 1);"
        local hostname_cmd="gccli -u\"$ROOT_USER\" -p******** -h\"$DB_CONNECT_HOST\" -P25258 -Ns -e \"$hostname_query\""
        echo "[$(get_timestamp)] [回溯] 获取连接节点主机名命令: $hostname_cmd" >> "$HISTORY_LOG"

        local connected_name=$(execute_gccli_query "SELECT SUBSTRING_INDEX(@@hostname, ':', 1);")
        local query_status=$?

        local LOG_IP="$MY_IP" # 默认值
        local CONNECTED_IP=""
        local CONNECTED_HOSTNAME=""

        if [ $query_status -eq 0 ] && [ -n "$connected_name" ]; then
            # 使用全局配置中的映射函数
            CONNECTED_IP=$(map_db_hostname_to_ip "$connected_name")
            CONNECTED_HOSTNAME=$(map_db_hostname_to_display_name "$connected_name")

            if [ -n "$CONNECTED_IP" ]; then
                LOG_IP="$CONNECTED_IP"
                echo "[$(get_timestamp)] [回溯] 数据库连接检查成功，实际连接节点: $connected_name ($CONNECTED_IP)" >> "$HISTORY_LOG"
                output_alarm 1 "数据库连接成功 (目标: $DB_CONNECT_HOST, 实际连接: $CONNECTED_IP)" "999" "$LOG_IP" "$CONNECTED_HOSTNAME"
            else
                echo "[$(get_timestamp)] [回溯] 警告：主机名 [$connected_name] 无法映射到固定IP" >> "$HISTORY_LOG"
                output_alarm 1 "警告：实际连接的主机名 [$connected_name] 无法映射到固定IP，日志将使用 $MY_IP 作为源IP。" "999" "$MY_IP"
            fi
        else
            echo "[$(get_timestamp)] [回溯] 警告：无法获取连接节点主机名" >> "$HISTORY_LOG"
            output_alarm 1 "警告：数据库连接成功但无法获取节点主机名，日志将使用 $MY_IP 作为源IP。" "999" "$MY_IP"
        fi

        # 2. 执行各项检查 (每个检查函数内部会查询所有节点并汇总)
        check_session_num "$LOG_IP"
        check_sql_execute_time "$LOG_IP"
        check_table_lock_count "$LOG_IP"
        check_waiting_sql_count "$LOG_IP"
    fi

    # 记录结束时间到历史日志 (使用默认 $MY_IP)
    output_alarm 1 "--- 结束数据库业务状态检查 ---" "999" "$MY_IP"
}

# 如果作为独立脚本执行，则运行主检查函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_db_status
    exit 0
fi
