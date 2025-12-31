#!/bin/bash
# ===============================================================================
# 脚本名称: 05.ha_monitor_Primary.sh
# 脚本用途: GBase 监控系统主HA调度器
# 部署位置: 172.16.213.104 (Primary HA 监控机)
#
# 功能说明:
#   1. SSH读取所有集群节点(100/101/102)的状态文件
#   2. 统计各状态节点数量(Primary/Backup/Unreachable)
#   3. 根据决策规则判断是否执行监控任务
#   4. 记录决策日志和执行结果
#   5. 与105备监控机实现互斥执行
#
# 执行方式:
#   手动执行: bash /path/to/05.ha_monitor_Primary.sh
#   定时任务: */5 * * * * /path/to/05.ha_monitor_Primary.sh >> /var/log/ha_104.log 2>&1
#
# 依赖项:
#   - 00.monitor_global_config.sh (全局配置文件)
#   - 01.monitor_scheduler.sh (实际监控调度脚本)
#   - ssh (需配置免密登录到集群节点100/101/102)
#
# 版本信息:
#   版本: v1.1
#   作者: 数据库运维组
#   创建日期: 2024-11-15
#   最后更新: 2025-12-24
#   更新说明: SSH命令增加-q参数、优化决策逻辑、完善日志输出
#
# 维护说明:
#   1. 确保SSH免密登录到所有集群节点已配置
#   2. 确保ha_monitor_status_reporter.sh已在集群节点部署
#   3. 建议在crontab中添加日志重定向
#   4. 可通过日志查看决策原因和执行状态
#   5. 测试时可手动修改/data/monitor.pid内容验证决策
# ===============================================================================
#
# ===============================================
# --- 配置信息 (动态加载) ---
# ===============================================

# 1. 获取当前脚本的绝对路径
SCRIPT_FULL_PATH=$(readlink -f "$0")

# 2. 提取脚本所在的目录路径
SCRIPT_DIR=$(dirname "$SCRIPT_FULL_PATH")

# 3. 动态定义 GLOBAL_CONFIG 和 SCHEDULER_SCRIPT 变量
GLOBAL_CONFIG="${SCRIPT_DIR}/00.monitor_global_config.sh"
SCHEDULER_SCRIPT="${SCRIPT_DIR}/01.monitor_scheduler.sh"

# 4. 加载全局配置
if [ -f "$GLOBAL_CONFIG" ]; then
    source "$GLOBAL_CONFIG"
else
    # 致命错误：如果全局配置不存在，无法获取所有关键信息
    echo "FATAL ERROR: Global configuration file $GLOBAL_CONFIG not found. Exiting."
    exit 1
fi

# 5. 定义 HA 调度器特有的配置
# **********************************************
# * MONITORED_NODES 改为使用 00 脚本中的 $DB_CONNECT_HOST *
# **********************************************
# 将 DB_CONNECT_HOST 逗号分隔的字符串转换为 Bash 数组，以便于循环
IFS=',' read -r -a MONITORED_NODES <<< "$DB_CONNECT_HOST"

# 状态文件路径 (固定在被监控节点上)
STATE_FILE="/data/monitor.pid"

# --- 辅助函数 ---

# 检查文件是否存在和配置是否正确
check_env() {
    if [ ! -f "$GLOBAL_CONFIG" ]; then
        echo "错误：全局配置文件 $GLOBAL_CONFIG 不存在。"
        exit 1
    fi
    source "$GLOBAL_CONFIG" # 引入配置，获取 SSH_PORT
    if [ ! -f "$SCHEDULER_SCRIPT" ]; then
        echo "错误：核心调度脚本 $SCHEDULER_SCRIPT 不存在。"
        exit 1
    fi
    # 确保 SSH_PORT 已正确从配置中引入，如果未定义，使用默认值
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT="22"
    fi
}

# 远程获取状态文件内容
# 返回: 0=Primary, 1=Backup, 3=Unreachable (SSH失败/文件不存在)
get_remote_status() {
    local ip=$1
    local content
    local status_code=3 # 默认是 Unreachable/SSH 失败

    # 使用 cat 读取远程文件，并设置连接超时
    # -q 静默模式，抑制警告和诊断信息
    # -T 禁用伪终端分配
    # -p ${SSH_PORT} 使用配置的端口
    # -o ConnectTimeout=5 设置连接超时
    # 2>/dev/null 隐藏 ssh 的连接错误信息，只关注返回码和输出内容
    content=$(ssh -q -T -p "${SSH_PORT}" -o ConnectTimeout=5 "${ip}" "cat ${STATE_FILE} 2>/dev/null" 2>/dev/null)
    local ssh_status=$?

    if [ $ssh_status -eq 0 ]; then
        if [ "$content" == "Primary ID:1000" ]; then
            status_code=0
        elif [ "$content" == "Backup ID:2000" ]; then
            status_code=1
        fi
        # 其他内容（如 Undetermined State 或空）仍保持 status_code=3，按无法获取处理
    fi
    echo "$status_code" # 返回状态码
}

# --- 主逻辑 ---
check_env

# 初始化计数器
primary_count=0     # 状态码 0: Primary ID:1000
backup_count=0      # 状态码 1: Backup ID:2000
unreachable_count=0 # 状态码 3: SSH/Cat 失败 (无法获取信息)

echo "--- $(date '+%Y-%m-%d %H:%M:%S') - Primary HA 状态检查 (104) ---"

for node_ip in "${MONITORED_NODES[@]}"; do
    node_status=$(get_remote_status "$node_ip")

    case "$node_status" in
        0)
            echo "节点 ${node_ip} 状态: Primary ID:1000"
            primary_count=$((primary_count + 1))
            ;;
        1)
            echo "节点 ${node_ip} 状态: Backup ID:2000"
            backup_count=$((backup_count + 1))
            ;;
        3)
            echo "节点 ${node_ip} 状态: Unreachable (SSH 失败)"
            unreachable_count=$((unreachable_count + 1))
            ;;
        *)
            echo "节点 ${node_ip} 状态: 未知/非预期状态 (按 Unreachable 计数)"
            unreachable_count=$((unreachable_count + 1))
            ;;
    esac
done

# --- 决策逻辑 (172.16.213.104 规则) ---

SHOULD_RUN_MONITOR="false"
ACTION_REASON="Primary 监控机 (104) 默认停止执行"

# 规则 1: 其中一台 monitor.pid 内容为 Primary ID:1000
if [ "$primary_count" -ge 1 ]; then
    SHOULD_RUN_MONITOR="true"
    ACTION_REASON="检测到至少一个节点状态为 Primary ID:1000，开始执行"

# 规则 2: 三台机器都无法 ssh 获取信息
elif [ "$unreachable_count" -eq 3 ]; then
    SHOULD_RUN_MONITOR="true"
    ACTION_REASON="检测到所有节点都 Unreachable (SSH 失败)，开始执行"

# 规则 3: 只有三台机器，monitor.pid 内容为都为 Backup ID:2000，停止执行
elif [ "$backup_count" -eq 3 ]; then
    SHOULD_RUN_MONITOR="false"
    ACTION_REASON="检测到所有节点状态都为 Backup ID:2000，停止执行"

fi

# 执行判断
echo "--- 决策结果 ---"
echo "决策原因: ${ACTION_REASON}"

if [ "$SHOULD_RUN_MONITOR" == "true" ]; then
    echo "结论: 执行 $SCHEDULER_SCRIPT 脚本。"
    bash "$SCHEDULER_SCRIPT"
    EXEC_STATUS=$?
    if [ $EXEC_STATUS -ne 0 ]; then
        echo "错误：$SCHEDULER_SCRIPT 执行失败，退出码: $EXEC_STATUS"
        exit $EXEC_STATUS
    fi
else
    echo "结论: 停止执行 $SCHEDULER_SCRIPT 脚本。"
fi

echo "--- $(date '+%Y-%m-%d %H:%M:%S') - Primary HA 状态检查结束 ---"
exit 0
