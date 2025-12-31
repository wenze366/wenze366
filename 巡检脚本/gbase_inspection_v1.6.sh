#!/bin/bash
#==============================================================================
# 脚本名称: gbase_inspection_v1.6.sh
# 版本号:   v1.6.1
# 最后更新: 2025-01-01
# 脚本用途: GBase数据库巡检工具（基于连接测试的智能节点识别版）
#
#------------------------------------------------------------------------------
# 使用方法:
#   方式1: ./gbase_inspection_v1.6.sh               # 交互式输入密码
#   方式2: ./gbase_inspection_v1.6.sh "password"    # 命令行传参密码
#   方式3: bash gbase_inspection_v1.6.sh "password" # 显式调用bash执行
#
#------------------------------------------------------------------------------
# 日志存放位置:
#   执行日志: ./log/inspection_YYYYMMDD.log         # 脚本执行过程日志
#   巡检报告: ./log/IP_ADDRESS_YYYY-MM.log          # 巡检结果报告
#
#------------------------------------------------------------------------------
# 依赖环境:
#   - GBase 8a 数据库
#   - gccli 命令行工具
#   - gcadmin 管理工具
#   - 系统工具: ethtool, sar, lscpu, df, free
#   - 操作系统: Linux
#
#------------------------------------------------------------------------------
# 权限要求:
#   - 执行用户: 需要读取 /data 目录权限
#   - 数据库用户: gbasechk (可在脚本内修改)
#   - 建议以数据库安装用户执行
#
#------------------------------------------------------------------------------
# 输出说明:
#   1. 系统配置检查（CPU、内存、网络、磁盘、THP、NUMA等）
#   2. 资源使用情况（磁盘空间、内存使用、网络流量、CPU负载）
#   3. 数据库逻辑检查（版本、表统计、内存、一致性）【仅管理节点】
#   4. 数据库日志检查（日志文件状态、Core/Dump文件检测）
#   5. 数据库安全检查（用户列表、权限详情）【仅管理节点】
#   6. 数据库性能检查（锁信息、进程列表）【仅管理节点】
#   7. 本地进程检查（GBase相关进程状态）
#
#------------------------------------------------------------------------------
# 注意事项:
#   1. 管理节点：需要输入正确的数据库密码，执行完整巡检
#   2. 数据节点：密码验证失败时，仅执行系统层面检查
#   3. 脚本会自动识别节点类型（通过 gccli 连接测试）
#   4. 报告文件权限设置为 640，请注意查看权限
#   5. 建议定期清理 ./log 目录下的历史日志文件
#   6. 首次执行会在当前目录创建 log 子目录
#
#------------------------------------------------------------------------------
# 可配置参数（脚本内修改）:
#   IP_ADDRESS    - 数据库IP地址 (默认: 172.16.213.100)
#   DB_USER       - 数据库用户名 (默认: gbasechk)
#   NET_INTERFACE - 网卡名称 (默认: ens160)
#   DISK_PATH     - 磁盘路径 (默认: /dev/mapper/klas-root)
#
#------------------------------------------------------------------------------
# 常见问题:
#   Q: 提示"密码验证失败"？
#   A: 检查 gbasechk 用户密码是否正确，或数据库服务是否正常
#
#   Q: 提示"sar命令未安装"？
#   A: 安装 sysstat 工具包: yum install -y sysstat
#
#   Q: 提示"权限不足"？
#   A: 检查对 /data 目录的访问权限，建议用数据库用户执行
#
#   Q: 日志目录创建失败？
#   A: 检查当前目录的写权限
#
#   Q: 如何查看历史巡检报告？
#   A: 所有报告保存在 ./log 目录，按月份命名，可直接查看
#
#------------------------------------------------------------------------------
# 更新历史:
#   v1.6.1 (2025-01-01):
#     * 变量命名标准化（统一使用前缀规范）
#     * 新增脚本版本常量和元信息
#     * 优化用户交互提示（增加状态符号）
#     * 提升文件权限安全性（640替代777）
#
#   v1.6 (2025-01-01):
#     * 支持密码传参：./script.sh "password"
#     * 无参数时交互式输入密码
#     * 新增执行日志记录功能（记录到log/目录）
#     * 智能识别管理节点和数据节点
#
#==============================================================================
#
# Author:        未央
# Philosophy:    代码无言，逻辑有踪。
#
#==============================================================================

# 加载环境变量
source ~/.bash_profile 2>/dev/null || true

#==============================================================================
# 全局变量配置
# 说明: 使用全大写命名全局常量，统一前缀规范
#==============================================================================

# ============================================================
# 脚本元信息常量
# ============================================================
readonly SCRIPT_NAME="gbase_inspection"
readonly SCRIPT_VERSION="v1.6.1"

# ============================================================
# 数据库配置常量（DB_* 前缀）
# ============================================================
readonly DB_HOST="172.16.213.100"
readonly DB_USER="gbasechk"

# ============================================================
# 系统配置常量（SYS_* 前缀 或 直接语义化命名）
# ============================================================
readonly IP_ADDRESS="172.16.213.100"
readonly NET_INTERFACE="ens160"
readonly DISK_PATH="/dev/mapper/klas-root"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# ============================================================
# 日志目录配置（LOG_* 前缀）
# ============================================================
readonly LOG_DIR="${SCRIPT_DIR}/log"
readonly LOG_FILE="${LOG_DIR}/inspection_$(date +%Y%m%d).log"

# 创建日志目录
mkdir -p "${LOG_DIR}" 2>/dev/null

# 数据库日志路径配置
readonly LOG_HOME="/data/$IP_ADDRESS"
readonly LOG_GCLUSTER_SYSTEM="${LOG_HOME}/gcluster/log/gcluster/system.log"
readonly LOG_GNODE_SYSTEM="${LOG_HOME}/gnode/log/gbase/system.log"
readonly LOG_GCLUSTER_EXPRESS="${LOG_HOME}/gcluster/log/gcluster/express.log"
readonly LOG_GNODE_EXPRESS="${LOG_HOME}/gnode/log/gbase/express.log"
readonly LOG_GCWARE="${LOG_HOME}/gcware/log/gcware.log"

# ============================================================
# 报告输出配置（REPORT_* 前缀）
# ============================================================
readonly REPORT_MONTH=$(date +%Y-%m)
readonly REPORT_FILE="${LOG_DIR}/${IP_ADDRESS}_${REPORT_MONTH}.log"
readonly HOST_NAME=$(hostname)


#==============================================================================
# 函数名: log_message
# 功能: 记录执行日志到log目录
# 参数: $1 - 日志级别（INFO/WARN/ERROR）
#       $2 - 日志内容
# 输出: 追加日志到执行日志文件
#==============================================================================
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

#==============================================================================
# 函数名: get_db_password
# 功能: 获取数据库密码（从参数或交互式输入）
# 参数: $1 - 命令行传入的密码（可选）
# 返回: 无（设置全局变量DB_PASS）
# 输出: 提示信息到stderr
#==============================================================================
get_db_password() {
    local input_password="$1"

    if [[ -n "$input_password" ]]; then
        # 从参数获取密码
        DB_PASS="$input_password"
        log_message "INFO" "密码通过命令行参数传入"
        echo "密码已通过参数传入。" >&2
    else
        # 交互式输入密码
        echo "========================================" >&2
        echo "  GBase数据库巡检工具 ${SCRIPT_VERSION}" >&2
        echo "========================================" >&2
        echo "" >&2
        echo -n "请输入 ${DB_USER} 用户密码: " >&2
        read -s DB_PASS
        echo "" >&2

        if [[ -z "$DB_PASS" ]]; then
            echo "错误：密码不能为空！" >&2
            log_message "ERROR" "密码为空，脚本退出"
            exit 1
        fi

        log_message "INFO" "密码通过交互式输入获取"
        echo "密码已接收，开始执行巡检..." >&2
        echo "" >&2
    fi

    readonly DB_PASS
}

# 获取密码（从第一个参数）
get_db_password "$1"

# 记录脚本开始执行
log_message "INFO" "========== 巡检脚本开始执行 =========="
log_message "INFO" "脚本版本: ${SCRIPT_VERSION}"
log_message "INFO" "执行主机: ${HOST_NAME}"
log_message "INFO" "执行用户: $(whoami)"
log_message "INFO" "脚本目录: ${SCRIPT_DIR}"
log_message "INFO" "输出文件: ${REPORT_FILE}"

# --- 核心修改：通过连接测试判断节点角色 ---
echo "正在检测数据库连接状态..." >&2
log_message "INFO" "开始检测数据库连接状态"

if gccli -u${DB_USER} -p${DB_PASS} -e "select 1" >/dev/null 2>&1; then
    readonly IS_MGMT_NODE=true
    echo "✓ 密码验证成功，按 [管理节点] 执行。" >&2
    log_message "INFO" "密码验证成功，节点类型：管理节点"
else
    readonly IS_MGMT_NODE=false
    echo "✗ 密码验证失败，按 [数据节点] 执行（跳过数据库检查）。" >&2
    log_message "WARN" "密码验证失败，节点类型：数据节点"
fi
echo "" >&2

#==============================================================================
# 函数名: print_separator
# 功能: 输出分隔线
# 参数: 无
# 返回: 无
# 输出: 打印15个等号到标准输出
#==============================================================================
print_separator() {
    echo '==============='
}

#==============================================================================
# 函数名: print_header
# 功能: 输出巡检报告的头部信息
# 参数: 无
# 返回: 无
# 输出: 打印报告标题、主机名、节点类型、当前时间等信息
# 说明: 根据IS_MGMT_NODE变量判断节点类型
#==============================================================================
print_header() {
    local node_type="数据节点 (Data Node)"
    [[ "$IS_MGMT_NODE" == true ]] && node_type="管理节点 (Management Node)"

    echo "========================================"
    echo "  GBase数据库巡检报告"
    echo "  主机: ${HOST_NAME} (${node_type})"
    echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  版本: ${SCRIPT_VERSION}"
    echo "========================================"
}

#==============================================================================
# 函数名: execute_gccli_query
# 功能: 执行GBase数据库SQL查询
# 参数:
#   $1 - SQL查询语句（必需）
#   $2 - 详细输出选项（可选，传入"-vvv"启用详细模式）
# 返回:
#   0 - 成功执行或非管理节点跳过
#   其他 - SQL执行失败的返回码
# 输出: SQL查询结果到标准输出
# 说明:
#   - 仅在管理节点（IS_MGMT_NODE=true）执行查询
#   - 数据节点自动跳过，返回0
#   - 支持普通模式和详细模式(-vvv)两种输出格式
#==============================================================================
execute_gccli_query() {
    # 只有连接成功的管理节点才执行 SQL 查询
    [[ "$IS_MGMT_NODE" == false ]] && return 0

    local sql_query="$1"
    local verbose_mode="${2:-}"

    if [[ "$verbose_mode" == "-vvv" ]]; then
        gccli -u${DB_USER} -p${DB_PASS} -vvv -e "${sql_query}" 2>/dev/null
    else
        gccli -u${DB_USER} -p${DB_PASS} -e "${sql_query}" 2>/dev/null
    fi
}

#==============================================================================
# 函数名: check_system_config
# 功能: 检查服务器基础配置信息
# 参数: 无
# 返回: 无
# 输出: 系统配置信息到标准输出
# 检查项:
#   1.1 服务器配置信息
#       - CPU详细配置（lscpu）
#       - 网卡速率（ethtool）
#       - 操作系统版本
#   1.2 系统关键参数
#       - NUMA拓扑信息
#       - 透明大页(THP)状态
#       - 内核脏页参数
#       - 文件句柄限制
#       - 自启动配置
#==============================================================================
check_system_config() {
    log_message "INFO" "开始执行：系统配置检查"

    echo -e "\n1.1 服务器配置信息"
    echo "===== CPU 详细配置 (lscpu) ======"
    lscpu | grep -Ev "Vulnerability|Flags"
    print_separator

    echo -e "\n===== 网卡速率 (Ethtool) ======"
    ethtool $NET_INTERFACE 2>/dev/null | grep Speed || echo "Speed: Unknown"
    print_separator

    echo -e "\n===== 操作系统发行版本 ======"
    cat /etc/os-release
    print_separator

    echo -e "\n1.2 系统关键参数"
    echo "===== NUMA 拓扑信息 ======"
    lscpu | grep -i numa
    print_separator

    echo -e "\n===== 透明大页 (THP) 状态 ======"
    echo "--- Grub 配置检查 ---"
    grep -i transparent_hugepage /etc/grub2.cfg 2>/dev/null || echo "Grub中未发现THP配置"
    echo "--- 运行时状态 ---"
    echo "/sys/kernel/mm/transparent_hugepage/enabled"
    echo "Enabled: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
    echo "/sys/kernel/mm/transparent_hugepage/defrag"
    echo "Defrag: $(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)"
    print_separator

    echo -e "\n===== 内核脏页相关参数 ======"
    sysctl -a 2>/dev/null | grep -E "vm.dirty_(background_ratio|expire_centisecs|writeback_centisecs)"
    print_separator

    echo -e "\n===== 文件句柄限制 (File Limits) ======"
    echo "系统最大文件数 (fs.file-max):"
    sysctl -a 2>/dev/null | grep fs.file-max
    echo "当前用户进程限制 (ulimit -n):"
    ulimit -n
    print_separator

    echo -e "\n===== 自启动配置信息 ======"
    cat /etc/rc.d/rc.local 2>/dev/null | grep -v "#" | grep -v "^$" || echo "rc.local 中无自启动配置"
    print_separator

    echo -e "\n===== 定时任务 (crontab -l) ======"
    crontab -l 2>/dev/null || echo "无定时任务"
    print_separator

    log_message "INFO" "完成：系统配置检查"
}

#==============================================================================
# 函数名: check_resource_usage
# 功能: 检查系统资源使用情况
# 参数: 无
# 返回: 无
# 输出: 资源使用情况到标准输出
# 检查项:
#   2.1 磁盘空间使用情况
#   2.2 内存使用情况
#   2.3 网络错误包核查
#   2.4 网络即时传输速率
#   2.5 CPU使用率核查
#   2.6 系统运行时间
#   2.7 Schema统计（管理节点）
#==============================================================================
check_resource_usage() {
    log_message "INFO" "开始执行：资源使用检查"

    echo -e "\n2.1 磁盘空间使用情况"
    echo "===== 磁盘空间 ======"
    df -h | grep -E "${DISK_PATH}"
    print_separator

    echo -e "\n2.2 内存使用情况"
    echo "===== 内存统计 ======"
    free -h
    print_separator

    echo -e "\n2.3 网络错误包核查"
    echo "===== 网络EDEV ======"
    if command -v sar &>/dev/null; then
        sar -n EDEV 1 1 | grep -iE "IFACE|$NET_INTERFACE"
    else
        echo "sar命令未安装，跳过网络统计检查"
        log_message "WARN" "sar命令未安装"
    fi
    print_separator

    echo -e "\n2.4 网络即时传输速率"
    echo "===== 网络DEV ======"
    if command -v sar &>/dev/null; then
        sar -n DEV 1 1 | grep -iE "IFACE|$NET_INTERFACE"
    else
        echo "sar命令未安装，跳过网络统计检查"
    fi
    print_separator

    echo -e "\n2.5 cpu使用率核查"
    echo "===== CPU状态 ======"
    if command -v sar &>/dev/null; then
        sar 1 1 | egrep -v '^$'
    else
        echo "sar命令未安装，跳过CPU统计检查"
    fi
    print_separator

    echo -e "\n2.6 系统运行时间"
    echo "===== 系统运行时间 ======"
    uptime
    print_separator

    echo -e "\n2.7 Schema统计"
    echo "===== 数据库统计 ======"
    if [[ "$IS_MGMT_NODE" == true ]]; then
        execute_gccli_query "select distinct(table_schema) as Schema, count(1) as TableCount from information_schema.tables group by table_schema;"
    else
        echo "数据节点跳过Schema统计"
    fi
    print_separator

    log_message "INFO" "完成：资源使用检查"
}

#==============================================================================
# 函数名: check_database_logic
# 功能: 检查数据库逻辑信息（仅管理节点）
# 参数: 无
# 返回:
#   0 - 成功执行或数据节点跳过
# 输出: 数据库版本、表信息、内存信息等到标准输出
# 检查项:
#   3.0 数据库版本
#   3.1 数据库表信息统计（总数、复制表、随机分布表、哈希分布表）
#   3.2 本节点内存使用信息
#   3.3 节点数据一致性检测（gcadmin）
#   3.4 数据库空间情况检测
# 说明:
#   - 仅在管理节点执行
#   - 数据节点会显示提示信息后跳过
#==============================================================================
check_database_logic() {
    if [[ "$IS_MGMT_NODE" == false ]]; then
        echo -e "\n[提示] 数据库连接测试失败，已跳过逻辑巡检项（版本、权限、集群状态等）。"
        log_message "INFO" "跳过：数据库逻辑检查（数据节点）"
        return 0
    fi

    log_message "INFO" "开始执行：数据库逻辑检查"

    echo -e "\n3.0 数据库版本"
    execute_gccli_query "select version();" "-vvv"
    print_separator

    echo -e "\n3.1 数据库表信息统计"
    echo "===== 表分布统计 ======"
    execute_gccli_query "select count(1) as Total from gbase.table_distribution;"
    execute_gccli_query "select count(1) as Replicated from gbase.table_distribution where isReplicate='YES'"
    execute_gccli_query "select count(1) as Random from gbase.table_distribution where isReplicate='NO' and hash_column is null;"
    execute_gccli_query "select count(1) as Hash from gbase.table_distribution where isReplicate='NO' and hash_column is not null;"
    print_separator

    echo -e "\n3.2 本节点内存部分总览信息"
    echo "===== 内存使用统计 ======"
    execute_gccli_query "select * from performance_schema.MEMORY_USAGE_INFO;" "-vvv"
    print_separator

    echo -e "\n3.3 节点数据一致性检测 (gcadmin)"
    echo "===== 数据一致性状态 ======"
    gcadmin
    print_separator

    echo -e "\n3.4 数据库空间情况检测"
    echo "===== 数据库库容量统计 (du -sh) ======"
    echo "--- GNode数据空间 ---"
    du -sh ${LOG_HOME}/gnode/userdata/gbase/* 2>/dev/null || echo "GNode数据目录不存在或无权限"
    echo "--- GCluster数据空间 ---"
    du -sh ${LOG_HOME}/gcluster/userdata/* 2>/dev/null || echo "GCluster数据目录不存在或无权限"
    print_separator

    log_message "INFO" "完成：数据库逻辑检查"
}

#==============================================================================
# 函数名: check_database_logs
# 功能: 检查数据库日志文件状态
# 参数: 无
# 返回: 无
# 输出: 日志文件信息到标准输出
# 检查项:
#   4.1 日志文件状态（大小、修改时间）
#   4.2 Core/Dump文件检查
#==============================================================================
check_database_logs() {
    log_message "INFO" "开始执行：数据库日志检查"

    echo -e "\n4 数据库日志检查"

    echo -e "\n4.1 日志文件状态"
    echo "===== 日志文件大小和修改时间 ======"
    ls -lh "${LOG_GCLUSTER_SYSTEM}" "${LOG_GNODE_SYSTEM}" "${LOG_GCLUSTER_EXPRESS}" "${LOG_GNODE_EXPRESS}" "${LOG_GCWARE}" 2>/dev/null | awk '{print $5, $6, $7, $8, $NF}' || echo "部分日志文件不存在"
    print_separator

    echo -e "\n4.2 Core/Dump文件检查"
    echo "===== 异常转储文件 ======"
    local dump_files=$(ls -l ${LOG_HOME}/*/userdata/gbase/ 2>/dev/null | grep -iE "core|dump")
    [[ -z "$dump_files" ]] && echo "未发现 .core 或 .dump 文件" || echo "$dump_files"
    print_separator

    log_message "INFO" "完成：数据库日志检查"
}

#==============================================================================
# 函数名: check_database_security
# 功能: 检查数据库安全相关信息（仅管理节点）
# 参数: 无
# 返回:
#   0 - 成功执行或数据节点跳过
# 输出: 用户权限信息到标准输出
# 检查项:
#   5.1 数据库用户列表
#   5.2 用户权限详情
# 说明:
#   - 仅在管理节点执行
#   - 数据节点会自动跳过
#==============================================================================
check_database_security() {
    if [[ "$IS_MGMT_NODE" == false ]]; then
        return 0
    fi

    log_message "INFO" "开始执行：数据库安全检查"

    echo -e "\n5 数据库安全检查"

    echo -e "\n5.1 数据库用户列表"
    echo "===== 非系统用户统计 ======"
    local user_list=$(gccli -u${DB_USER} -p${DB_PASS} -N -e "select distinct user from gbase.user where user not in ('gbasechk','root','gbase');" 2>/dev/null)
    local user_count=$(echo "$user_list" | wc -w)
    echo "非系统用户数量: $user_count"
    if [[ $user_count -gt 0 ]]; then
        echo "用户列表: $user_list"
        log_message "INFO" "发现 $user_count 个非系统用户: $user_list"
    else
        echo "无非系统用户"
        log_message "INFO" "无非系统用户"
    fi
    print_separator

    echo -e "\n5.2 用户权限详情"
    echo "===== 权限授予情况 ======"
    if [[ $user_count -gt 0 ]]; then
        for username in $user_list; do
            echo "--- $username 权限详情 ---"
            execute_gccli_query "show grants for $username;"
            print_separator
        done
    else
        echo "无非系统用户，跳过权限检查"
        print_separator
    fi

    log_message "INFO" "完成：数据库安全检查"
}

#==============================================================================
# 函数名: check_database_performance
# 功能: 检查数据库性能相关信息（仅管理节点）
# 参数: 无
# 返回:
#   0 - 成功执行或数据节点跳过
# 输出: 性能指标到标准输出
# 检查项:
#   6.1 数据库锁信息（gcadmin showlock）
#   6.2 当前进程列表
# 说明:
#   - 仅在管理节点执行
#   - 数据节点会自动跳过
#==============================================================================
check_database_performance() {
    if [[ "$IS_MGMT_NODE" == false ]]; then
        return 0
    fi

    log_message "INFO" "开始执行：数据库性能检查"

    echo -e "\n6 数据库性能检查"

    echo -e "\n6.1 数据库锁信息检查"
    echo "===== 锁状态 (gcadmin showlock) ======"
    gcadmin showlock
    print_separator

    echo -e "\n6.2 当前进程列表"
    echo "===== 数据库连接进程 ======"
    execute_gccli_query "show processlist;" "-vvv"
    print_separator

    log_message "INFO" "完成：数据库性能检查"
}

#==============================================================================
# 函数名: main
# 功能: 主程序入口
# 参数:
#   $@ - 命令行参数（当前未使用）
# 返回: 无
# 输出:
#   - 所有巡检结果重定向到日志文件
#   - 完成提示信息输出到标准输出
# 说明:
#   - 按顺序执行各检查模块
#   - 将所有输出重定向到指定的日志文件
#   - 设置日志文件权限为640（提升安全性）
#   - 复制日志文件到/data目录
# 模块执行顺序:
#   1. 系统配置检查 (check_system_config)
#   2. 资源使用检查 (check_resource_usage)
#   3. 数据库逻辑检查 (check_database_logic) - 仅管理节点
#   4. 日志文件检查 (check_database_logs)
#   5. 数据库安全检查 (check_database_security) - 仅管理节点
#   6. 数据库性能检查 (check_database_performance) - 仅管理节点
#==============================================================================
main() {
    log_message "INFO" "开始生成巡检报告"

    {
        print_header
        check_system_config        # 1. 系统配置检查
        check_resource_usage       # 2. 资源使用检查
        check_database_logic       # 3. 数据库逻辑检查（管理节点）
        check_database_logs        # 4. 日志文件检查
        check_database_security    # 5. 数据库安全检查（管理节点）
        check_database_performance # 6. 数据库性能检查（管理节点）

        echo -e "\n7 本地进程检查"
        echo "===== GBase相关进程 ======"
        ps -ef | grep /data | grep -v grep
        print_separator
    } > "${REPORT_FILE}"

    chmod 640 "${REPORT_FILE}"

    log_message "INFO" "巡检报告生成完成: ${REPORT_FILE}"
    log_message "INFO" "========== 巡检脚本执行结束 =========="

    echo "" >&2
    echo "======================================" >&2
    echo "✓ 巡检完成！" >&2
    echo "======================================" >&2
    echo "巡检报告: ${REPORT_FILE}" >&2
    echo "执行日志: ${LOG_FILE}" >&2
    echo "脚本版本: ${SCRIPT_VERSION}" >&2
    echo "======================================" >&2
}

# 执行主程序
main "$@"
