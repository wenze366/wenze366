#!/bin/bash
# ===============================================================================
# 脚本名称: 01.monitor_scheduler.sh
# 脚本用途: GBase 监控系统主调度器
#
# 功能说明:
#   1. 按顺序调度执行所有监控子脚本
#   2. 检查执行环境和脚本依赖完整性
#   3. 记录执行日志和错误信息
#   4. 管理日志文件生命周期(清理最新状态日志)
#   5. 提供容错机制(子脚本失败不中断主流程)
#
# 执行方式:
#   手动执行: bash /path/to/01.monitor_scheduler.sh
#   定时任务: */5 * * * * /path/to/01.monitor_scheduler.sh
#   HA调度: 通过 05.ha_monitor_*.sh 自动调用
#
# 依赖项:
#   - 00.monitor_global_config.sh (全局配置文件)
#   - 02.monitor_os_resources.sh (系统资源监控脚本)
#   - 03.monitor_cluster_health.sh (集群健康监控脚本)
#   - 04.monitor_db_metrics.sh (数据库业务监控脚本)
#
# 版本信息:
#   版本: v1.1
#   作者: 数据库运维组
#   创建日期: 2024-11-15
#   最后更新: 2025-12-24
#   更新说明: 完善环境检查、优化错误处理、添加日志清理逻辑
#
# 维护说明:
#   1. 建议通过crontab每5分钟执行一次
#   2. 子脚本执行失败不会中断主流程,但会记录警告
#   3. 日志目录不存在时会自动创建
#   4. 配合logrotate管理日志文件大小(见运维文档)
# ===============================================================================


# 1. 获取当前脚本的绝对路径
SCRIPT_FULL_PATH=$(readlink -f "$0")

# 2. 提取脚本所在的目录路径
SCRIPT_DIR=$(dirname "$SCRIPT_FULL_PATH")

# 3. 加载全局配置文件
# 假设 00.monitor_global_config.sh 与本脚本在同一目录
source "${SCRIPT_DIR}/00.monitor_global_config.sh"

# 4. 设置主目录路径（用于后续构造子脚本路径）
HOME_PATCH="${SCRIPT_DIR}"

# ===============================================
# 【第二部分】脚本路径定义
# ===============================================
# 说明: 定义所有需要的配置文件和子脚本的完整路径

# 配置文件路径
CONFIG_FILE="${HOME_PATCH}/00.monitor_global_config.sh"

# 系统资源监控脚本（监控临时目录大小）
SYSTEM_SCRIPT="${HOME_PATCH}/02.monitor_os_resources.sh"

# 集群状态监控脚本（监控服务状态、数据一致性）
CLUSTER_SCRIPT="${HOME_PATCH}/03.monitor_cluster_health.sh"

# 数据库业务监控脚本（监控会话数、慢查询、表锁等）
DB_SCRIPT="${HOME_PATCH}/04.monitor_db_metrics.sh"

# ===============================================
# 【第三部分】环境检查
# ===============================================
# 说明: 在执行监控前，确保所有必需的文件和目录都存在

# 步骤1: 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：配置文件 $CONFIG_FILE 不存在。请确保它在同一目录下。"
    exit 1
fi

# 步骤2: 引入统一配置（使用严格模式确保 source 成功）
# set -e: 遇到错误立即退出
# set +e: 关闭严格模式（避免影响后续的容错逻辑）
set -e
source "$CONFIG_FILE"
set +e

# 步骤3: 检查日志目录是否存在，不存在则创建
if [ ! -d "$LOG_DIR" ]; then
    echo "注意：日志目录 $LOG_DIR 不存在，正在尝试创建..." | tee -a "$HISTORY_LOG"
    mkdir -p "$LOG_DIR"

    # 检查目录创建是否成功
    if [ $? -ne 0 ]; then
        echo "致命错误：无法创建日志目录 $LOG_DIR。请检查权限。"
        exit 1
    fi

    echo "日志目录创建成功。" | tee -a "$HISTORY_LOG"
fi

# 步骤4: 清除上一次的最新状态日志
# 说明: 确保 LATEST_STATUS_LOG 总是只包含最新的检查结果
# 技术细节: 使用 rm -f 避免文件不存在时报错
if [ -f "$LATEST_STATUS_LOG" ]; then
    rm -f "$LATEST_STATUS_LOG"
fi

# 【新增】清除上一次的带颜色状态日志
if [ -f "$COLOUR_LATEST_STATUS_LOG" ]; then
    rm -f "$COLOUR_LATEST_STATUS_LOG"
fi


# 步骤5: 检查所有子脚本是否存在
if [ ! -f "$CLUSTER_SCRIPT" ] || [ ! -f "$DB_SCRIPT" ] || [ ! -f "$SYSTEM_SCRIPT" ]; then
    echo "错误：缺少一个或多个子脚本 ($CLUSTER_SCRIPT, $DB_SCRIPT, $SYSTEM_SCRIPT)。请检查文件是否存在。" | tee -a "$HISTORY_LOG"
    exit 1
fi

# ===============================================
# 【第四部分】辅助函数定义
# ===============================================

# ------------------------------------------------------------------
# 函数名: run_monitor_script
# 功能: 执行监控子脚本并记录日志
# 参数:
#   $1 = script_path  脚本的完整路径
#   $2 = script_name  脚本的描述名称（用于日志显示）
# 返回值: 子脚本的退出状态码
# 工作流程:
#   1. 记录开始执行日志
#   2. 使用 bash 命令执行子脚本
#   3. 捕获子脚本的退出状态码
#   4. 根据退出状态码记录成功或失败日志
#   5. 返回退出状态码（供调用方判断）
# 技术细节:
#   - 使用 tee -a 同时输出到终端和日志文件
#   - 不中断主流程（即使子脚本失败，仍继续执行后续脚本）
# ------------------------------------------------------------------
function run_monitor_script() {
    local script_path=$1
    local script_name=$2

    # 记录开始执行
    echo "=> 正在执行 $script_name ($script_path)..." | tee -a "$HISTORY_LOG"

    # 使用 bash 执行子脚本（确保配置变量已通过 source 传递）
    bash "$script_path"
    local exit_status=$?

    # 根据退出状态码判断执行结果
    if [ $exit_status -eq 0 ]; then
        echo "=> $script_name 执行成功。" | tee -a "$HISTORY_LOG"
    else
        echo "=> 警告：$script_name 执行失败或返回异常状态 (退出码: $exit_status)。" | tee -a "$HISTORY_LOG"
        # 注意: 此处可以选择触发主脚本级别的报警（当前未实现）
    fi

    # 记录分隔线
    echo "--------------------------------------------------------" | tee -a "$HISTORY_LOG"

    return $exit_status
}

# ===============================================
# 【第五部分】监控任务主流程
# ===============================================
# 说明: 按顺序执行所有监控子脚本

# 步骤1: 记录监控周期开始
echo "--- $(date '+%Y-%m-%d %H:%M:%S') - 开始执行监控任务 ---" | tee -a "$HISTORY_LOG"
echo "本地 IP: $MY_IP" | tee -a "$HISTORY_LOG"
echo "日志目录: $LOG_DIR" | tee -a "$HISTORY_LOG"
echo "--------------------------------------------------------" | tee -a "$HISTORY_LOG"

# 步骤2: 初始化最新状态日志文件
# 说明: 确保文件存在，避免后续追加写入时出错
echo "" > "$LATEST_STATUS_LOG"

# 步骤3: 执行系统资源监控脚本
# 监控内容: /data/*/gnode/tmpdata 目录大小
run_monitor_script "$SYSTEM_SCRIPT" "系统资源监控"

# 步骤4: 执行集群状态监控脚本
# 监控内容:
#   - 集群模式（NORMAL/READONLY/RECOVERY）
#   - 服务状态（GCWARE/GCLUSTER/GNODE/SYNCSERVER）
#   - 数据一致性（GCLUSTER层/GNODE层）
run_monitor_script "$CLUSTER_SCRIPT" "集群状态监控"

# 步骤5: 执行数据库业务监控脚本
# 监控内容:
#   - 会话数
#   - 慢查询
#   - 表锁数量
#   - 等待SQL数量
run_monitor_script "$DB_SCRIPT" "数据库业务监控"

# ===============================================
# 【第六部分】监控周期结束
# ===============================================

# 记录监控周期结束
echo "--- $(date '+%Y-%m-%d %H:%M:%S') - 所有监控任务执行完毕 ---" | tee -a "$HISTORY_LOG"

# 正常退出
exit 0

# ===============================================
# 【脚本结束】
# ===============================================
# 注意事项:
# 1. 本脚本不处理具体的监控逻辑，只负责调度
# 2. 所有监控逻辑在子脚本中实现
# 3. 即使某个子脚本失败，仍会继续执行后续脚本
# 4. 可通过 crontab 设置定时执行，例如:
#    */5 * * * * /path/to/01.monitor_scheduler.sh >> /tmp/scheduler.log 2>&1
# 5. 如需接收告警，可配合告警系统读取日志文件
# ===============================================
