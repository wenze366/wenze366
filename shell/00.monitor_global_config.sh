#!/bin/bash
# ===============================================================================
# 脚本名称: 00.monitor_global_config.sh
# 脚本用途: GBase 监控系统全局配置文件
#
# 功能说明:
#   1. 定义所有监控脚本共用的配置参数(数据库连接、日志路径、阈值等)
#   2. 提供核心辅助函数(告警输出、数据库查询、IP映射等)
#   3. 统一管理监控系统的全局变量和公共函数
#
# 执行方式: 被其他脚本通过 source 命令引用
#   示例: source /path/to/00.monitor_global_config.sh
#
# 依赖项:
#   - gccli (GBase数据库客户端工具)
#   - ssh (远程执行命令)
#   - bc (浮点数计算)
#
# 配置项说明:
#   【必修改】MY_IP: 监控机本机IP地址
#   【必修改】ROOT_USER/ROOT_PASSWD: 数据库监控账号
#   【必修改】DB_CONNECT_HOST: 数据库集群节点IP列表(逗号分隔)
#   【必修改】HOST_NAMES: 主机名映射(必须与DB_CONNECT_HOST顺序一致)
#   【可选】LOG_DIR: 日志文件存放目录
#   【可选】各监控阈值: 根据实际业务调整
#
# 版本信息:
#   版本: v1.2
#   作者: 数据库运维组
#   创建日期: 2024-11-15
#   最后更新: 2025-12-24
#   更新说明: 添加密码脱敏、完善回溯日志、优化函数注释
#
# 维护说明:
#   1. 修改配置项时请同步更新版本号和更新日期
#   2. 新增函数时请添加规范的函数注释
#   3. 密码建议使用MySQL配置文件方式(见PASSWORD_ENCRYPTION_GUIDE.md)
#   4. 修改阈值后建议观察1-2周再决定是否调整
# ===============================================================================

DD_DATE=$(date "+%Y-%m-%d")
HO_DATE=$(date "+%H:%M:%S")

# **********************************************
# ** 部署时请修改此处的 IP 地址为本机 IP **
# **********************************************
MY_IP='81.52.209.118'

# --- 颜色变量定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 数据库连接信息 ---
ROOT_USER=gbasechk
ROOT_PASSWD=gbasechk@AQDY2025

# 连接数据库所需的 IP (必须确保该 IP 可连接到 GBase 集群)
DB_CONNECT_HOST='172.16.213.100,172.16.213.101,172.16.213.102'

# 内部地址
DB_INTERMAL_HOST='172.16.213.100,172.16.213.101,172.16.213.102'

# 【统一变量】主机名映射 (数组索引必须与 DB_CONNECT_HOST 保持一致)
# 用途：
# 1. 日志显示名称（如 GBase_01）
# 2. 自动推导数据库主机名（如 GBase_01 → gbase01）
HOST_NAMES='GBase_01,GBase_02,GBase_03'

# --- SSH 配置 ---
# 【新增】SSH 远程执行命令的端口
SSH_PORT="10022"

# --- 日志和数据目录配置 ---
#LOG_DIR="/data/dbuser/gbase/gbase_app/ops/monitor/log"
LOG_DIR="./log"

# 历史日志归档
HISTORY_LOG="$LOG_DIR/gbase_history.log"
# 告警日志归档
ALARM_LOG="$LOG_DIR/gbase_alarm.log"
# 当前检查状态
LATEST_STATUS_LOG="$LOG_DIR/gbase_latest_status.log"

# --- 阈值配置 ---
# 数据库监控阈值 (db_monitor.sh 使用)
TABLE_LOCK_THRESHOLD=50

# 【新增】会话数监控阈值
SESSION_THRESHOLD_WARNING=1000
SESSION_THRESHOLD_CRITICAL=2000

# 【新增】等待 SQL 数量阈值
WAITING_SQL_THRESHOLD=50

# 【新增】慢查询阈值 (单位: 秒)
SLOW_QUERY_THRESHOLD=1800

# 【新增】临时表空间监控阈值 (单位: GB)
TMPDATA_THRESHOLD_GB=100
# 【新增】临时表空间告警ID
ALARM_ID_TMPDATA=706

# ===============================================
# --- 路径变量定义 (依赖 LOG_DIR) ---
# ===============================================

# --- 路径变量定义 (依赖 LOG_DIR) ---
GCADMIN_FILE="$LOG_DIR/gcadmin.txt"
GCADMIN_TS_FILE="$LOG_DIR/gcadmin_last_run.ts"

# 原有纯文本日志
LATEST_STATUS_LOG="$LOG_DIR/gbase_latest_status.log"
# 【新增】带颜色的状态日志
COLOUR_LATEST_STATUS_LOG="$LOG_DIR/colour_gbase_latest_status.log"

# 【新增】慢查询明细日志
SLOW_SQL_DETAIL_LOG="$LOG_DIR/slow_sql_detail.log"


# ===============================================
# --- 核心辅助函数 ---
# ===============================================

# 函数: get_current_date
# 功能: 获取当前日期 (YYYY-MM-DD)
function get_current_date() {
    date "+%Y-%m-%d"
}

# 函数: get_current_time
# 功能: 获取当前时间 (HH:MM:SS)
function get_current_time() {
    date "+%H:%M:%S"
}

# 函数: get_timestamp
# 功能: 获取完整时间戳 (YYYY-MM-DD HH:MM:SS)
function get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# 报警输出函数 (修正版本: 支持动态 IP 和新增字段)
# 新日志格式: 日期 | 时间 | 被管IP | 类型码 | 级别 | 被管主机名 | 描述信息 | 告警来源 | 唯一标识符
# 告警级别颜色: 3级=黄色, 4级=红色
function output_alarm() {
    local level=$1       # 级别
    local desc=$2        # 描述信息
    local alarm_id=$3    # 唯一标识符
    local log_source_ip=${4:-$MY_IP}
    local log_hostname_temp=$(map_ip_to_hostname "$log_source_ip")
    local log_hostname=${5:-$log_hostname_temp}
    local type_code="11"

    # 【修正】使用实时时间戳
    local current_date=$(get_current_date)
    local current_time=$(get_current_time)

    # 1. 构造标准日志条目 (不带颜色)
    local log_entry="$current_date|$current_time|$log_source_ip|$type_code|$level|$log_hostname|$desc|GBase|AlarmID=$alarm_id"

    # 2. 构造带颜色的日志条目 (使用变量 RED/YELLOW/NC)
    local log_entry_color="$log_entry"
    if [ "$level" -eq 4 ]; then
        log_entry_color="${RED}${log_entry}${NC}"  #
    elif [ "$level" -eq 3 ]; then
        log_entry_color="${YELLOW}${log_entry}${NC}" #
    fi

    # --- 写入逻辑 ---

    # 写入普通日志 (维持原样)
    echo "$log_entry" >> "$LATEST_STATUS_LOG"
    echo "$log_entry" >> "$HISTORY_LOG"

    # 【关键步骤】写入带颜色日志文件 (必须使用 -e 参数)
    echo -e "$log_entry_color" >> "$COLOUR_LATEST_STATUS_LOG"

    # 【新增】只有告警级别 >= 3 才写入告警日志
    if [ "$level" -ge 3 ]; then
        echo "$log_entry" >> "$ALARM_LOG"
    fi

    # 终端实时输出
    echo -e "$log_entry_color"
}

# 通用 GBase 查询执行函数 (最终版：基于最后一行是否有 ERROR 来判断连接是否成功)
function execute_gccli_query() {
    local query=$1

    # 1. 执行查询，将结果和错误信息都捕获到 output 变量中
    # 使用 -Ns (No names, Silent) 确保只输出结果，2>&1 捕获所有输出
    local output=$(gccli -u"$ROOT_USER" -p"$ROOT_PASSWD" -h"$DB_CONNECT_HOST" -P25258 -Ns -e "$query" 2>&1)
    local status=$? # 捕获 gccli 的退出状态码

    # 2. 检查 gccli 退出状态码。如果是非 0，则命令本身执行失败
    if [ $status -ne 0 ]; then
        echo ""
        return 1
    fi

    # 3. 提取有效数据行：过滤掉空行，并取最后一行作为最终结果
    local last_line=$(echo "$output" | grep -vE '^$' | tail -n 1)

    # 4. 核心判断：如果最后一行包含 ERROR 关键字，则认为连接/查询失败
    # 注意：使用 -i 忽略大小写
    if echo "$last_line" | grep -qE "ERROR"; then
        echo "" # 失败时输出空字符串
        return 1
    fi

    # 5. 如果最后一行不包含 ERROR，且结果非空，则成功
    if [ -z "$last_line" ]; then
        # 即使 $? == 0 且没有 ERROR，但结果是空，也可能是查询失败 (除非查询本身预期返回空)
        # 为保证严谨性，我们只返回空，并让调用方判断
        echo ""
        # 注意：此处不返回 1，因为 status=0 且无 ERROR。
        # 依赖上层 check_* 函数中的 [ -z "$state" ] 来判断空结果。
        return 0
    fi

    # 6. 成功时输出提取到的查询结果
    echo "$last_line"
    return 0
}

# 函数: is_number
# 功能: 检查输入字符串是否是有效的非负整数
function is_number() {
    local input=$1
    # 使用 Bash 正则表达式检查是否只包含数字
    [[ "$input" =~ ^[0-9]+$ ]]
}

function map_external_to_internal_ip() {
	local external_ip=$1
	local index=-1

	local OLD_IFS=$IFS
	IFS=',' read -ra external_ips_arr <<< "$DB_CONNECT_HOST"
	IFS=',' read -ra internal_ips_arr <<< "$DB_INTERMAL_HOST"
	IFS=$OLD_IFS

	for i in "${!external_ips_arr[@]}"; do
	   if [[ "${external_ips_arr[$i]}" == "$external_ip" ]]; then
		   index=$i
		   break
	   fi
   	done

	if [ "$index" -ne -1 ]; then
		echo "${internal_ips_arr[$index]}"
	else
		echo "$external_ip"
	fi
}

# 函数: map_ip_to_hostname
# 功能: 将外部 IP 映射到对应的主机名
function map_ip_to_hostname() {
    local external_ip=$1
    local index=-1

    local OLD_IFS=$IFS
    IFS=',' read -ra external_ips_arr <<< "$DB_CONNECT_HOST"
    IFS=',' read -ra host_names_arr <<< "$HOST_NAMES"
    IFS=$OLD_IFS

    for i in "${!external_ips_arr[@]}"; do
        if [[ "${external_ips_arr[$i]}" == "$external_ip" ]]; then
            index=$i
            break
        fi
    done

    if [ "$index" -ne -1 ]; then
        echo "${host_names_arr[$index]}"
    else
        # 无法映射时，返回 IP 本身
        echo "$external_ip"
    fi
}

# 【修改】函数: normalize_hostname
# 功能: 将主机名统一转换为小写用于比较
# 参数: $1 = 主机名
# 返回: 小写的主机名
function normalize_hostname() {
    local hostname=$1
    echo "$hostname" | tr '[:upper:]' '[:lower:]'
}

# 【修改】函数: map_db_hostname_to_ip
# 功能: 将数据库返回的主机名映射到对应的 IP 地址
# 参数: $1 = 数据库主机名 (不区分大小写)
# 返回: 对应的 IP 地址，或空字符串 (未找到时)
function map_db_hostname_to_ip() {
    local db_hostname=$1
    local db_hostname_lower=$(normalize_hostname "$db_hostname")
    local index=-1

    local OLD_IFS=$IFS
    IFS=',' read -ra host_names_arr <<< "$HOST_NAMES"
    IFS=',' read -ra internal_ips_arr <<< "$DB_INTERMAL_HOST"
    IFS=$OLD_IFS

    # 遍历 HOST_NAMES，不区分大小写进行比较
    for i in "${!host_names_arr[@]}"; do
        local hostname_lower=$(normalize_hostname "${host_names_arr[$i]}")
        if [[ "$hostname_lower" == "$db_hostname_lower" ]]; then
            index=$i
            break
        fi
    done

    if [ "$index" -ne -1 ]; then
        echo "${internal_ips_arr[$index]}"
    else
        echo ""
    fi
}

# 【修改】函数: map_db_hostname_to_display_name
# 功能: 将数据库返回的主机名映射到显示名称 (保持 HOST_NAMES 的原始大小写)
# 参数: $1 = 数据库主机名 (不区分大小写)
# 返回: 对应的显示名称，或空字符串 (未找到时)
function map_db_hostname_to_display_name() {
    local db_hostname=$1
    local db_hostname_lower=$(normalize_hostname "$db_hostname")
    local index=-1

    local OLD_IFS=$IFS
    IFS=',' read -ra host_names_arr <<< "$HOST_NAMES"
    IFS=$OLD_IFS

    # 遍历 HOST_NAMES，不区分大小写进行比较
    for i in "${!host_names_arr[@]}"; do
        local hostname_lower=$(normalize_hostname "${host_names_arr[$i]}")
        if [[ "$hostname_lower" == "$db_hostname_lower" ]]; then
            index=$i
            break
        fi
    done

    if [ "$index" -ne -1 ]; then
        # 返回 HOST_NAMES 中定义的原始值（保持原有大小写）
        echo "${host_names_arr[$index]}"
    else
        echo ""
    fi
}

# 【新增】函数: execute_single_node_query
# 功能: 对单个节点执行 gccli 查询
# 参数: $1 = 节点 IP, $2 = SQL 查询语句
# 返回: 查询结果 (数字) 或空字符串 (失败时)
function execute_single_node_query() {
    local node_ip=$1
    local query=$2

    # 执行查询，将结果和错误信息都捕获到 output 变量中
    local output=$(gccli -u"$ROOT_USER" -p"$ROOT_PASSWD" -h"$node_ip" -P25258 -Ns -e "$query" 2>&1)
    local status=$?

    # 检查 gccli 退出状态码
    if [ $status -ne 0 ]; then
        echo ""
        return 1
    fi

    # 提取有效数据行：过滤掉空行，并取最后一行作为最终结果
    local last_line=$(echo "$output" | grep -vE '^$' | tail -n 1)

    # 核心判断：如果最后一行包含 ERROR 关键字，则认为连接/查询失败
    if echo "$last_line" | grep -qE "ERROR"; then
        echo ""
        return 1
    fi

    # 如果结果非空且为数字，则成功
    if [ -n "$last_line" ] && is_number "$last_line"; then
        echo "$last_line"
        return 0
    fi

    echo ""
    return 1
}

# 【新增】函数: query_all_nodes_with_logging
# 功能: 对所有节点执行查询，记录日志，并汇总结果
# 参数: $1 = SQL 查询语句, $2 = 检查项名称 (用于日志)
# 返回: 所有节点结果的总和
function query_all_nodes_with_logging() {
    local query=$1
    local check_name=$2
    local total_sum=0

    local OLD_IFS=$IFS
    IFS=',' read -ra node_ips <<< "$DB_CONNECT_HOST"
    IFS=$OLD_IFS

    for node_ip in "${node_ips[@]}"; do
        # 构造并记录完整命令到历史日志 (回溯用)
        local full_cmd="gccli -u\"$ROOT_USER\" -p******** -h$node_ip -P25258 -Ns -e \"$query\""
        echo "[$(get_timestamp)] [回溯] 节点 $node_ip ${check_name}: $full_cmd" >> "$HISTORY_LOG"

        # 执行查询
        local result=$(execute_single_node_query "$node_ip" "$query")

        if [ -n "$result" ] && is_number "$result"; then
            total_sum=$((total_sum + result))
        else
            # 记录连接异常情况
            echo "[$(get_timestamp)] [WARN] 节点 $node_ip 连接异常或无响应，该节点${check_name}计为 0，继续检查。" >> "$HISTORY_LOG"
        fi
    done

    echo "$total_sum"
    return 0
}
