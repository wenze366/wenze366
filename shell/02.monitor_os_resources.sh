#!/bin/bash
# ===============================================================================
# 脚本名称: 02.monitor_os_resources.sh
# 脚本用途: GBase 集群系统资源监控
#
# 功能说明:
#   1. 通过SSH监控所有数据库节点的临时表空间使用量
#   2. 检查 /data/*/gnode/tmpdata 目录大小
#   3. 超过阈值(100GB)时触发3级告警
#   4. 容错处理SSH连接失败和目录异常情况
#   5. 记录回溯日志供问题追踪
#
# 执行方式:
#   直接执行: bash /path/to/02.monitor_os_resources.sh
#   调度执行: 由 01.monitor_scheduler.sh 自动调用
#
# 依赖项:
#   - 00.monitor_global_config.sh (全局配置文件)
#   - ssh (需配置免密登录到所有数据库节点)
#   - du (磁盘使用统计命令)
#   - bc (浮点数计算工具)
#
# 版本信息:
#   版本: v1.1
#   作者: 数据库运维组
#   创建日期: 2024-11-15
#   最后更新: 2025-12-24
#   更新说明: 增加告警日志换行分隔、添加SSH -q参数、完善回溯日志
#
# 维护说明:
#   1. 确保监控机到所有数据库节点的SSH免密登录已配置
#   2. SSH端口使用配置文件中的SSH_PORT变量(默认10022)
#   3. SSH超时设置为10秒,避免长时间等待
#   4. 应急预案: GBase_C_011 (临时表空间清理)
# ===============================================================================


# 引入统一配置脚本 (自动获取当前路径并加载 00 脚本)
SCRIPT_FULL_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_FULL_PATH")
source "${SCRIPT_DIR}/00.monitor_global_config.sh"

# 确保日志目录存在
[ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR"

# --------------------------------------------------------
# 函数: check_tmpdata_usage
# 参数: $1 = 目标 IP
# --------------------------------------------------------
function check_tmpdata_usage() {
    local target_ip=$1
    local alarm_id=601
    local threshold_kb=104857600  # 100GB 转换为 KB (100 * 1024 * 1024)
    local threshold_display="100G"

    # --- 1. 构造回溯命令 ---
    # 使用通配符匹配 /data/*/gnode/tmpdata 并汇总
    local remote_cmd="du -sk /data/*/gnode/tmpdata 2>/dev/null | awk '{sum+=\$1} END {print sum}'"
    echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 磁盘检查命令: ssh -p$SSH_PORT $target_ip \"$remote_cmd\"" >> "$HISTORY_LOG"

    # --- 2. SSH 执行统计 (设置 10 秒超时防止卡死) ---
    local raw_kb
    raw_kb=$(ssh -q -p"$SSH_PORT" -o ConnectTimeout=10 "$target_ip" "$remote_cmd" 2>>"$HISTORY_LOG")
    local exit_code=$?

    # --- 3. 结果判定与逻辑容错 ---
    # 情况 A: SSH 连接失败或执行报错
    if [ $exit_code -ne 0 ] || [ -z "$raw_kb" ]; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 检查失败 (原因: SSH连接失败或目录不存在)，判定结果: 正常(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 ${target_ip} 临时空间检查异常(SSH失败)，默认为正常" "$alarm_id" "$target_ip"
        return
    fi

    # 情况 B: 处理非数字输出 (例如目录为空或权限问题)
    if [[ ! "$raw_kb" =~ ^[0-9]+$ ]]; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 返回值非数字 [$raw_kb]，判定结果: 正常(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 ${target_ip} 临时空间获取数据异常，计为正常" "$alarm_id" "$target_ip"
        return
    fi

    # 计算 GB 供日志显示
    local current_gb=$(echo "scale=2; $raw_kb / 1024 / 1024" | bc)

    # 情况 C: 超过 100G 阈值
    if [ "$raw_kb" -ge "$threshold_kb" ]; then
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 统计值 ${current_gb}GB 超过阈值 ${threshold_display}，判定结果: 告警(3级)" >> "$HISTORY_LOG"
        output_alarm 3 "GBASE 集群临时表空间超过阈值 [ ${threshold_display} ]，当前 [ ${current_gb}GB ]，请按照应急预案GBase_C_011进行处理" "$alarm_id" "$target_ip"

    # 情况 D: 正常范围内
    else
        echo "[$DD_DATE $HO_DATE] [回溯] 节点 $target_ip 统计值 ${current_gb}GB 在正常范围内，判定结果: 正常(1级)" >> "$HISTORY_LOG"
        output_alarm 1 "节点 ${target_ip} 临时表空间使用正常 (${current_gb}GB)" "$alarm_id" "$target_ip"
    fi
}

# ---------------------------- 主程序 ----------------------------

function main() {
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

    # 从 00.monitor_global_config.sh 的 DB_CONNECT_HOST 获取 3 台机器 IP
    IFS=',' read -r -a ip_array <<< "$DB_CONNECT_HOST"

    # 遍历所有节点
    for ip in "${ip_array[@]}"; do
        check_tmpdata_usage "$ip"
    done
}

# 执行
main
