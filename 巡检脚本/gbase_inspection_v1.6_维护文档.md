# GBase数据库巡检脚本维护文档

## 📋 文档信息

| 项目 | 内容 |
|-----|------|
| **脚本名称** | gbase_inspection_v1.6.sh |
| **当前版本** | v1.6.1 |
| **维护人员** | 未央 |
| **最后更新** | 2025-01-01 |
| **文档类型** | 技术维护文档 |

---

## 📖 目录

1. [脚本概述](#1-脚本概述)
2. [架构设计](#2-架构设计)
3. [全局变量说明](#3-全局变量说明)
4. [核心函数说明](#4-核心函数说明)
5. [执行流程](#5-执行流程)
6. [配置修改指南](#6-配置修改指南)
7. [故障排查](#7-故障排查)
8. [扩展开发指南](#8-扩展开发指南)
9. [版本更新记录](#9-版本更新记录)

---

## 1. 脚本概述

### 1.1 功能简介

GBase数据库巡检工具，用于自动化检查GBase 8a集群数据库的健康状态，支持管理节点和数据节点的智能识别。

### 1.2 核心特性

- ✅ **智能节点识别**: 自动识别管理节点/数据节点，执行对应检查项
- ✅ **双模式密码输入**: 支持命令行传参和交互式输入
- ✅ **双日志系统**: 执行日志(LOG_FILE) + 巡检报告(REPORT_FILE)
- ✅ **标准化命名**: 采用统一的变量命名前缀规范
- ✅ **安全性增强**: 报告文件权限640，密码安全处理

### 1.3 适用场景

| 场景 | 说明 |
|-----|------|
| **日常巡检** | 定期检查数据库健康状态 |
| **故障诊断** | 快速获取系统和数据库关键信息 |
| **性能分析** | 收集性能指标用于分析 |
| **合规审计** | 检查用户权限和安全配置 |

---

## 2. 架构设计

### 2.1 脚本结构

```
gbase_inspection_v1.6.sh
├── 头部注释区
│   ├── 脚本信息
│   ├── 使用说明
│   └── 更新历史
├── 全局变量配置区
│   ├── 脚本元信息 (SCRIPT_*)
│   ├── 数据库配置 (DB_*)
│   ├── 系统配置 (NET_*, DISK_*, IP_ADDRESS)
│   ├── 日志配置 (LOG_*)
│   └── 报告配置 (REPORT_*)
├── 工具函数区
│   ├── log_message()           # 日志记录
│   ├── get_db_password()       # 密码获取
│   ├── print_separator()       # 分隔线
│   ├── print_header()          # 报告头
│   └── execute_gccli_query()   # SQL执行
├── 检查模块区
│   ├── check_system_config()        # 1. 系统配置
│   ├── check_resource_usage()       # 2. 资源使用
│   ├── check_database_logic()       # 3. 数据库逻辑
│   ├── check_database_logs()        # 4. 日志文件
│   ├── check_database_security()    # 5. 安全检查
│   └── check_database_performance() # 6. 性能检查
└── 主程序入口
    └── main()                  # 主函数
```

### 2.2 设计模式

| 模式 | 应用 | 说明 |
|-----|------|------|
| **模块化设计** | 各检查项独立函数 | 便于维护和扩展 |
| **命名规范** | 统一前缀 | 提升可读性 |
| **双日志机制** | 执行日志+巡检报告 | 区分运行记录和检查结果 |
| **智能判断** | 节点类型自动识别 | 减少人工配置 |
| **错误容忍** | 2>/dev/null | 避免非关键错误中断 |

---

## 3. 全局变量说明

### 3.1 变量分类与命名规范

#### 📌 脚本元信息常量 (SCRIPT_*)

```bash
readonly SCRIPT_NAME="gbase_inspection"     # 脚本标识名称
readonly SCRIPT_VERSION="v1.6.1"            # 当前版本号
```

**用途**: 版本管理、日志记录、用户提示

---

#### 📌 数据库配置常量 (DB_*)

```bash
readonly DB_HOST="172.16.213.100"           # 数据库主机IP
readonly DB_USER="gbasechk"                 # 数据库用户名
readonly DB_PASS="******"                   # 数据库密码（运行时赋值）
```

**修改位置**: 第114-115行  
**修改说明**: 
- `DB_HOST`: 如果数据库IP变更，需修改此处
- `DB_USER`: 如果使用其他巡检用户，需修改此处
- `DB_PASS`: 由脚本运行时动态赋值，无需手动修改

---

#### 📌 系统配置常量

```bash
readonly IP_ADDRESS="172.16.213.100"        # 当前节点IP（用于日志路径）
readonly NET_INTERFACE="ens160"             # 监控的网卡名称
readonly DISK_PATH="/dev/mapper/klas-root"  # 监控的磁盘路径
```

**修改位置**: 第120-122行  
**修改说明**:
- `IP_ADDRESS`: 必须与实际节点IP一致，影响日志路径
- `NET_INTERFACE`: 根据实际网卡名修改（如 eth0, bond0）
- `DISK_PATH`: 根据实际磁盘分区修改

**⚠️ 注意**: `IP_ADDRESS` 与 `DB_HOST` 可能不同（集群环境下）

---

#### 📌 日志配置常量 (LOG_*)

```bash
readonly LOG_DIR="${SCRIPT_DIR}/log"                          # 日志目录
readonly LOG_FILE="${LOG_DIR}/inspection_$(date +%Y%m%d).log" # 执行日志
readonly LOG_HOME="/data/$IP_ADDRESS"                         # 数据库日志根目录
readonly LOG_GCLUSTER_SYSTEM="${LOG_HOME}/gcluster/log/gcluster/system.log"
readonly LOG_GNODE_SYSTEM="${LOG_HOME}/gnode/log/gbase/system.log"
readonly LOG_GCLUSTER_EXPRESS="${LOG_HOME}/gcluster/log/gcluster/express.log"
readonly LOG_GNODE_EXPRESS="${LOG_HOME}/gnode/log/gbase/express.log"
readonly LOG_GCWARE="${LOG_HOME}/gcware/log/gcware.log"
```

**修改位置**: 第131-143行  
**修改说明**:
- `LOG_HOME`: 如果数据库安装目录非 `/data/IP`，需修改
- 其他LOG_*: 如果GBase日志路径有变化，相应修改

---

#### 📌 报告输出配置 (REPORT_*)

```bash
readonly REPORT_MONTH=$(date +%Y-%m)                          # 报告月份标识
readonly REPORT_FILE="${LOG_DIR}/${IP_ADDRESS}_${REPORT_MONTH}.log" # 报告文件
readonly HOST_NAME=$(hostname)                                # 主机名
```

**修改位置**: 第148-150行  
**修改说明**:
- `REPORT_MONTH`: 如需按日生成，改为 `$(date +%Y%m%d)`
- `REPORT_FILE`: 可自定义文件名格式

---

#### 📌 节点类型标识 (IS_*)

```bash
readonly IS_MGMT_NODE=true/false    # 是否为管理节点（运行时判断）
```

**生成位置**: 第221-228行（通过 `gccli` 连接测试判断）  
**作用**: 决定是否执行数据库相关检查项

---

### 3.2 变量依赖关系图

```
IP_ADDRESS
    ├── LOG_HOME (日志根目录)
    │   ├── LOG_GCLUSTER_SYSTEM
    │   ├── LOG_GNODE_SYSTEM
    │   ├── LOG_GCLUSTER_EXPRESS
    │   ├── LOG_GNODE_EXPRESS
    │   └── LOG_GCWARE
    └── REPORT_FILE (报告文件名)

SCRIPT_DIR
    └── LOG_DIR
        ├── LOG_FILE (执行日志)
        └── REPORT_FILE (巡检报告)

DB_USER + DB_PASS
    └── IS_MGMT_NODE (通过连接测试判断)
        └── 决定执行范围
```

---

## 4. 核心函数说明

### 4.1 工具函数

#### 📌 log_message()

**功能**: 记录脚本执行日志

```bash
log_message "INFO" "开始执行系统检查"
log_message "WARN" "sar命令未安装"
log_message "ERROR" "密码为空"
```

**参数**:
- `$1`: 日志级别 (INFO/WARN/ERROR)
- `$2`: 日志内容

**输出位置**: `${LOG_FILE}` (执行日志文件)

**日志格式**: `[2025-01-01 10:30:00] [INFO] 日志内容`

**位置**: 第160-165行

---

#### 📌 get_db_password()

**功能**: 获取数据库密码（命令行参数或交互式输入）

**参数**:
- `$1`: 命令行传入的密码（可选）

**行为逻辑**:
```
if [参数有密码]
    ├── 直接使用参数密码
    └── log_message "INFO" "密码通过命令行参数传入"
else
    ├── 提示用户输入
    ├── read -s DB_PASS (隐藏输入)
    ├── 验证非空
    └── log_message "INFO" "密码通过交互式输入获取"
```

**退出码**:
- 0: 成功获取密码
- 1: 密码为空

**位置**: 第174-201行

---

#### 📌 execute_gccli_query()

**功能**: 执行GBase SQL查询（仅管理节点）

**参数**:
- `$1`: SQL查询语句
- `$2`: 详细模式 (可选，"-vvv")

**返回值**:
- 0: 成功执行或数据节点跳过
- 其他: gccli 执行失败

**使用示例**:
```bash
# 普通查询
execute_gccli_query "select version();"

# 详细模式查询
execute_gccli_query "select * from users;" "-vvv"
```

**位置**: 第278-290行

---

### 4.2 检查模块函数

| 函数名 | 功能 | 执行条件 | 位置 |
|-------|------|---------|------|
| **check_system_config** | 系统配置检查 | 所有节点 | 第310行 |
| **check_resource_usage** | 资源使用检查 | 所有节点 | 第369行 |
| **check_database_logic** | 数据库逻辑检查 | 仅管理节点 | 第440行 |
| **check_database_logs** | 日志文件检查 | 所有节点 | 第492行 |
| **check_database_security** | 安全检查 | 仅管理节点 | 第524行 |
| **check_database_performance** | 性能检查 | 仅管理节点 | 第577行 |

#### 检查项详细说明

##### 1. check_system_config() - 系统配置检查

**检查内容**:

| 序号 | 检查项 | 命令 | 说明 |
|-----|--------|------|------|
| 1.1 | CPU配置 | `lscpu` | 获取CPU型号、核数、架构等 |
| 1.1 | 网卡速率 | `ethtool $NET_INTERFACE` | 检查网卡速度（千兆/万兆） |
| 1.1 | 操作系统版本 | `cat /etc/os-release` | 系统版本信息 |
| 1.2 | NUMA拓扑 | `lscpu \| grep numa` | NUMA节点信息 |
| 1.2 | 透明大页(THP) | `cat /sys/kernel/mm/transparent_hugepage/*` | THP状态检查 |
| 1.2 | 内核脏页参数 | `sysctl vm.dirty_*` | 脏页刷新参数 |
| 1.2 | 文件句柄限制 | `sysctl fs.file-max` | 系统文件句柄限制 |
| 1.2 | 自启动配置 | `cat /etc/rc.d/rc.local` | 开机自启动项 |
| 1.2 | 定时任务 | `crontab -l` | 当前用户定时任务 |

**输出**: 直接输出到巡检报告

---

##### 2. check_resource_usage() - 资源使用检查

**检查内容**:

| 序号 | 检查项 | 命令 | 阈值建议 |
|-----|--------|------|---------|
| 2.1 | 磁盘空间 | `df -h \| grep $DISK_PATH` | >20% 可用空间 |
| 2.2 | 内存使用 | `free -h` | >20% 可用内存 |
| 2.3 | 网络错误包 | `sar -n EDEV 1 1` | 错误包 <0.1% |
| 2.4 | 网络传输速率 | `sar -n DEV 1 1` | - |
| 2.5 | CPU使用率 | `sar 1 1` | <80% |
| 2.6 | 系统运行时间 | `uptime` | - |
| 2.7 | Schema统计 | SQL查询 | 仅管理节点 |

**依赖**: `sar` 命令（sysstat包）

---

##### 3. check_database_logic() - 数据库逻辑检查

**检查内容**:

| 序号 | 检查项 | SQL/命令 | 说明 |
|-----|--------|---------|------|
| 3.0 | 数据库版本 | `select version();` | GBase版本信息 |
| 3.1 | 表分布统计 | 查询 `gbase.table_distribution` | 总表数、复制表、随机表、哈希表 |
| 3.2 | 内存使用 | `performance_schema.MEMORY_USAGE_INFO` | 节点内存使用详情 |
| 3.3 | 数据一致性 | `gcadmin` | 集群一致性状态 |
| 3.4 | 数据库空间 | `du -sh` | GNode和GCluster数据目录大小 |

**执行条件**: `IS_MGMT_NODE=true`

---

##### 4. check_database_logs() - 日志文件检查

**检查内容**:

| 序号 | 检查项 | 路径 | 关注点 |
|-----|--------|------|--------|
| 4.1 | 日志文件状态 | LOG_GCLUSTER_SYSTEM等5个日志 | 文件大小、修改时间 |
| 4.2 | Core/Dump文件 | `${LOG_HOME}/*/userdata/gbase/` | 查找.core/.dump文件 |

**告警**: 发现core/dump文件需重点关注

---

##### 5. check_database_security() - 安全检查

**检查内容**:

| 序号 | 检查项 | SQL | 说明 |
|-----|--------|-----|------|
| 5.1 | 用户列表 | `select distinct user from gbase.user` | 非系统用户统计 |
| 5.2 | 用户权限 | `show grants for user;` | 每个用户的权限详情 |

**排除的系统用户**: gbasechk, root, gbase

**执行条件**: `IS_MGMT_NODE=true`

---

##### 6. check_database_performance() - 性能检查

**检查内容**:

| 序号 | 检查项 | 命令 | 关注点 |
|-----|--------|------|--------|
| 6.1 | 数据库锁 | `gcadmin showlock` | 是否存在锁等待 |
| 6.2 | 进程列表 | `show processlist;` | 当前连接和执行的SQL |

**执行条件**: `IS_MGMT_NODE=true`

---

### 4.3 主程序函数

#### 📌 main()

**功能**: 主程序入口，协调各检查模块执行

**执行流程**:
```
main()
  ├── log_message "开始生成巡检报告"
  ├── {
  │     print_header()              # 输出报告头
  │     check_system_config()       # 1. 系统配置
  │     check_resource_usage()      # 2. 资源使用
  │     check_database_logic()      # 3. 数据库逻辑（管理节点）
  │     check_database_logs()       # 4. 日志文件
  │     check_database_security()   # 5. 安全检查（管理节点）
  │     check_database_performance()# 6. 性能检查（管理节点）
  │     本地进程检查                 # 7. GBase进程
  │   } > ${REPORT_FILE}            # 重定向到报告文件
  ├── chmod 640 ${REPORT_FILE}     # 设置权限
  ├── log_message "巡检完成"
  └── echo "输出提示信息"           # 显示报告位置
```

**输出**:
- 标准输出: 完成提示信息
- 报告文件: `${REPORT_FILE}`
- 执行日志: `${LOG_FILE}`

**位置**: 第635-666行

---

## 5. 执行流程

### 5.1 完整执行流程图

```
┌─────────────────────────────────────┐
│  1. 脚本启动                         │
├─────────────────────────────────────┤
│  source ~/.bash_profile              │ 加载环境变量
│  定义全局常量                        │
│  创建LOG_DIR目录                     │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│  2. 密码获取                         │
├─────────────────────────────────────┤
│  get_db_password "$1"                │
│  ├─ 有参数 → 使用参数密码            │
│  └─ 无参数 → 交互式输入              │
│  设置 readonly DB_PASS               │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│  3. 节点类型识别                     │
├─────────────────────────────────────┤
│  gccli -u${DB_USER} -p${DB_PASS}     │
│       -e "select 1"                  │
│  ├─ 连接成功 → IS_MGMT_NODE=true    │
│  └─ 连接失败 → IS_MGMT_NODE=false   │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│  4. 执行主程序 main()                │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐    │
│  │ print_header()              │    │
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ check_system_config()       │ 全节点
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ check_resource_usage()      │ 全节点
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ check_database_logic()      │ 管理节点
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ check_database_logs()       │ 全节点
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ check_database_security()   │ 管理节点
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ check_database_performance()│ 管理节点
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ 本地进程检查                 │ 全节点
│  └─────────────────────────────┘    │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│  5. 输出报告和日志                   │
├─────────────────────────────────────┤
│  chmod 640 ${REPORT_FILE}            │
│  显示完成提示                        │
│  - 巡检报告位置                      │
│  - 执行日志位置                      │
│  - 脚本版本                          │
└─────────────────────────────────────┘
```

### 5.2 节点类型执行差异

| 检查模块 | 管理节点 | 数据节点 |
|---------|---------|---------|
| check_system_config | ✅ 执行 | ✅ 执行 |
| check_resource_usage | ✅ 执行 | ✅ 执行 |
| check_database_logic | ✅ 执行 | ❌ 跳过 |
| check_database_logs | ✅ 执行 | ✅ 执行 |
| check_database_security | ✅ 执行 | ❌ 跳过 |
| check_database_performance | ✅ 执行 | ❌ 跳过 |
| 本地进程检查 | ✅ 执行 | ✅ 执行 |

---

## 6. 配置修改指南

### 6.1 常见配置修改场景

#### 场景1: 修改数据库连接信息

**需求**: 更换数据库IP或用户名

**修改位置**: 第114-120行

```bash
# 修改前
readonly DB_HOST="172.16.213.100"
readonly DB_USER="gbasechk"
readonly IP_ADDRESS="172.16.213.100"

# 修改后
readonly DB_HOST="192.168.1.100"      # 新的数据库IP
readonly DB_USER="dba_check"          # 新的检查用户
readonly IP_ADDRESS="192.168.1.100"   # 新的节点IP
```

**影响范围**:
- 数据库连接
- 日志路径 (`/data/${IP_ADDRESS}`)
- 报告文件名

---

#### 场景2: 修改监控网卡

**需求**: 服务器网卡名称为 bond0

**修改位置**: 第121行

```bash
# 修改前
readonly NET_INTERFACE="ens160"

# 修改后
readonly NET_INTERFACE="bond0"
```

**影响范围**: 网卡速率检查、网络流量统计

---

#### 场景3: 修改磁盘监控路径

**需求**: 监控 `/dev/sda1` 分区

**修改位置**: 第122行

```bash
# 修改前
readonly DISK_PATH="/dev/mapper/klas-root"

# 修改后
readonly DISK_PATH="/dev/sda1"
```

**影响范围**: 磁盘空间检查

---

#### 场景4: 修改报告生成频率

**需求**: 每天生成一份报告（而非每月）

**修改位置**: 第148行

```bash
# 修改前
readonly REPORT_MONTH=$(date +%Y-%m)

# 修改后
readonly REPORT_MONTH=$(date +%Y%m%d)
```

**影响**: 报告文件名从 `IP_2025-01.log` 变为 `IP_20250101.log`

---

#### 场景5: 修改数据库日志路径

**需求**: GBase安装在 `/opt/gbase` 目录

**修改位置**: 第138-143行

```bash
# 修改前
readonly LOG_HOME="/data/$IP_ADDRESS"

# 修改后
readonly LOG_HOME="/opt/gbase/$IP_ADDRESS"
```

**影响范围**: 所有数据库日志路径检查

---

### 6.2 高级定制

#### 定制1: 增加新的系统检查项

**示例**: 增加内存大页检查

**步骤**:

1. 在 `check_system_config()` 函数中增加检查代码（约第350行）

```bash
echo -e "\n===== 内存大页配置 ======"
grep -i hugepage /proc/meminfo
print_separator
```

2. 更新函数注释的"检查项"部分

---

#### 定制2: 增加新的数据库检查项

**示例**: 增加表空间检查

**步骤**:

1. 在 `check_database_logic()` 函数中增加检查（约第485行）

```bash
echo -e "\n3.5 表空间使用情况"
echo "===== 表空间统计 ======"
execute_gccli_query "SELECT tablespace_name, SUM(data_length+index_length)/1024/1024 AS size_mb 
                     FROM information_schema.tables 
                     GROUP BY tablespace_name;"
print_separator
```

2. 更新函数注释的"检查项"部分

---

#### 定制3: 增加告警阈值检查

**示例**: 磁盘空间低于20%告警

**步骤**:

1. 修改 `check_resource_usage()` 函数（约第373行）

```bash
echo -e "\n2.1 磁盘空间使用情况"
echo "===== 磁盘空间 ======"
disk_info=$(df -h | grep -E "${DISK_PATH}")
echo "$disk_info"

# 新增告警检查
disk_usage=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
if [[ $disk_usage -gt 80 ]]; then
    echo "⚠️ 告警：磁盘使用率 ${disk_usage}% 超过阈值！"
    log_message "WARN" "磁盘使用率 ${disk_usage}% 超过80%阈值"
fi
print_separator
```

---

## 7. 故障排查

### 7.1 常见问题排查表

| 问题现象 | 可能原因 | 排查方法 | 解决方案 |
|---------|---------|---------|---------|
| **密码验证失败** | 1. 密码错误<br>2. gccli命令不可用<br>3. 数据库服务未启动 | 1. 手动执行 `gccli -ugbasechk -p密码 -e "select 1"`<br>2. 检查 `which gccli`<br>3. 检查 `ps -ef \| grep gbase` | 1. 确认正确密码<br>2. 添加gccli到PATH<br>3. 启动数据库服务 |
| **sar命令未安装** | sysstat包未安装 | `which sar` | `yum install -y sysstat` |
| **日志目录创建失败** | 当前目录无写权限 | `ls -ld .` | 切换到有权限的目录执行 |
| **权限不足** | /data目录无读权限 | `ls -ld /data` | 用数据库用户执行或添加权限 |
| **报告文件为空** | 所有检查项失败 | 查看 `${LOG_FILE}` | 根据执行日志定位具体错误 |
| **gcadmin命令失败** | gcadmin不在PATH中 | `which gcadmin` | 添加到PATH或使用绝对路径 |
| **网卡检查失败** | 网卡名称错误 | `ip a` 查看实际网卡名 | 修改 `NET_INTERFACE` 变量 |

---

### 7.2 日志分析方法

#### 执行日志 (LOG_FILE)

**位置**: `./log/inspection_YYYYMMDD.log`

**内容**: 脚本执行过程的关键事件

**示例**:
```
[2025-01-01 10:30:00] [INFO] ========== 巡检脚本开始执行 ==========
[2025-01-01 10:30:00] [INFO] 脚本版本: v1.6.1
[2025-01-01 10:30:00] [INFO] 执行主机: db-server-01
[2025-01-01 10:30:00] [INFO] 密码通过交互式输入获取
[2025-01-01 10:30:01] [INFO] 密码验证成功，节点类型：管理节点
[2025-01-01 10:30:01] [INFO] 开始执行：系统配置检查
[2025-01-01 10:30:02] [WARN] sar命令未安装
[2025-01-01 10:30:05] [INFO] 完成：系统配置检查
...
[2025-01-01 10:31:00] [INFO] 巡检报告生成完成: ./log/172.16.213.100_2025-01.log
[2025-01-01 10:31:00] [INFO] ========== 巡检脚本执行结束 ==========
```

**关键信息**:
- ERROR级别: 严重错误，需立即处理
- WARN级别: 警告信息，可能影响部分功能
- INFO级别: 正常执行记录

---

#### 巡检报告 (REPORT_FILE)

**位置**: `./log/IP_ADDRESS_YYYY-MM.log`

**内容**: 所有检查项的输出结果

**结构**:
```
========================================
  GBase数据库巡检报告
  主机: db-server-01 (管理节点)
  时间: 2025-01-01 10:30:00
  版本: v1.6.1
========================================

1.1 服务器配置信息
===== CPU 详细配置 (lscpu) ======
Architecture:          x86_64
CPU(s):                16
...

2.1 磁盘空间使用情况
===== 磁盘空间 ======
/dev/mapper/klas-root   100G   45G   56G   45% /
...
```

---

### 7.3 调试模式

**启用方式**: 在脚本开头增加调试选项

```bash
#!/bin/bash
set -x  # 启用调试模式，显示所有执行的命令
```

**输出**: 所有执行的命令都会显示在终端

**禁用方式**: 注释或删除 `set -x`

---

## 8. 扩展开发指南

### 8.1 添加新的检查模块

**步骤**:

1. **定义函数** (建议在第600行之前)

```bash
#==============================================================================
# 函数名: check_custom_module
# 功能: 自定义检查模块
# 参数: 无
# 返回: 无
# 输出: 检查结果到标准输出
# 检查项:
#   - 自定义检查项1
#   - 自定义检查项2
#==============================================================================
check_custom_module() {
    log_message "INFO" "开始执行：自定义检查"
    
    echo -e "\n8 自定义检查模块"
    echo "===== 检查项1 ======"
    # 执行检查命令
    your_check_command
    print_separator
    
    echo -e "\n===== 检查项2 ======"
    # 执行检查命令
    another_check_command
    print_separator
    
    log_message "INFO" "完成：自定义检查"
}
```

2. **在main()函数中调用** (第645行附近)

```bash
main() {
    log_message "INFO" "开始生成巡检报告"
    
    {
        print_header
        check_system_config
        check_resource_usage
        check_database_logic
        check_database_logs
        check_database_security
        check_database_performance
        check_custom_module        # 新增模块
        
        echo -e "\n7 本地进程检查"
        ...
    } > "${REPORT_FILE}"
    ...
}
```

3. **更新头部注释** (第34-41行)

```bash
# 输出说明:
#   1. 系统配置检查
#   2. 资源使用情况
#   3. 数据库逻辑检查【仅管理节点】
#   4. 数据库日志检查
#   5. 数据库安全检查【仅管理节点】
#   6. 数据库性能检查【仅管理节点】
#   7. 本地进程检查
#   8. 自定义检查模块  # 新增
```

---

### 8.2 集成外部工具

**示例**: 集成 Prometheus node_exporter 指标

```bash
check_prometheus_metrics() {
    log_message "INFO" "开始执行：Prometheus指标采集"
    
    echo -e "\n9 Prometheus监控指标"
    echo "===== Node Exporter 指标 ======"
    
    if command -v curl &>/dev/null; then
        # 假设 node_exporter 运行在 9100 端口
        curl -s http://localhost:9100/metrics | grep -E "node_cpu|node_memory|node_disk"
    else
        echo "curl命令未安装，跳过Prometheus指标采集"
        log_message "WARN" "curl命令未安装"
    fi
    
    print_separator
    log_message "INFO" "完成：Prometheus指标采集"
}
```

---

### 8.3 结果通知功能

**示例**: 检查完成后发送邮件通知

```bash
# 在main()函数末尾增加（第656行后）

send_notification() {
    local report_path="$1"
    
    if command -v mail &>/dev/null; then
        echo "巡检报告已生成，详见附件" | mail -s "GBase巡检报告 - $(date +%Y-%m-%d)" \
            -a "${report_path}" \
            dba@example.com
        log_message "INFO" "邮件通知已发送"
    else
        log_message "WARN" "mail命令未安装，跳过邮件通知"
    fi
}

# 在main()末尾调用
main() {
    ...
    chmod 640 "${REPORT_FILE}"
    
    send_notification "${REPORT_FILE}"  # 新增
    
    log_message "INFO" "巡检报告生成完成: ${REPORT_FILE}"
    ...
}
```

---

### 8.4 定时任务集成

**配置示例**:

```bash
# 添加到crontab
# 每天凌晨2点执行巡检
0 2 * * * /path/to/gbase_inspection_v1.6.sh "password" >> /var/log/gbase_inspection_cron.log 2>&1
```

**注意事项**:
- 使用绝对路径
- 密码以参数形式传入
- 重定向cron日志便于排查

---

## 9. 版本更新记录

### v1.6.1 (2025-01-01)

**变更内容**:
- ✅ 变量命名标准化（统一前缀规范）
  - DB_* : 数据库配置
  - LOG_* : 日志相关
  - REPORT_* : 报告输出
  - NET_* : 网络配置
- ✅ 新增脚本版本常量 (SCRIPT_VERSION)
- ✅ 优化用户交互提示（✓/✗ 状态符号）
- ✅ 提升文件权限安全性（640 替代 777）
- ✅ 删除备份功能（不再复制到/data目录）

**影响范围**: 内部变量名，不影响使用方式

---

### v1.6 (2025-01-01)

**新增功能**:
- ✅ 支持密码传参：`./script.sh "password"`
- ✅ 无参数时交互式输入密码
- ✅ 新增执行日志记录功能（LOG_FILE）
- ✅ 智能识别管理节点和数据节点

**改进**:
- 双日志系统（执行日志 + 巡检报告）
- 自动节点类型识别（通过gccli连接测试）

---

### 未来计划 (Roadmap)

**v1.7 计划**:
- [ ] 增加JSON格式报告输出
- [ ] 支持多数据库集群配置文件
- [ ] 增加告警阈值检查
- [ ] 集成邮件/企业微信通知

**v2.0 计划**:
- [ ] 重构为Python脚本（更易扩展）
- [ ] 增加Web界面查看历史报告
- [ ] 支持分布式巡检（多节点并发）

---

## 附录

### A. 快速参考卡

#### 常用命令

```bash
# 交互式执行
./gbase_inspection_v1.6.sh

# 命令行传密码
./gbase_inspection_v1.6.sh "your_password"

# 查看执行日志
tail -f ./log/inspection_$(date +%Y%m%d).log

# 查看巡检报告
cat ./log/172.16.213.100_$(date +%Y-%m).log

# 清理历史日志（保留最近7天）
find ./log -name "*.log" -mtime +7 -delete
```

#### 关键文件位置

```bash
脚本位置:   /path/to/gbase_inspection_v1.6.sh
执行日志:   ./log/inspection_YYYYMMDD.log
巡检报告:   ./log/IP_ADDRESS_YYYY-MM.log
数据库日志: /data/IP_ADDRESS/gcluster/log/
           /data/IP_ADDRESS/gnode/log/
```

---

### B. 依赖检查清单

**必需工具**:
- [x] bash (版本 >= 4.0)
- [x] gccli (GBase命令行工具)
- [x] gcadmin (GBase管理工具)

**可选工具** (缺失会跳过相关检查):
- [ ] sar (网络和CPU统计，sysstat包)
- [ ] ethtool (网卡信息)
- [ ] lscpu (CPU信息)
- [ ] df (磁盘空间)
- [ ] free (内存信息)

**检查方法**:
```bash
# 检查必需工具
which gccli gcadmin bash

# 检查可选工具
which sar ethtool lscpu df free

# 安装缺失工具
yum install -y sysstat ethtool util-linux procps-ng
```

---

### C. 联系方式

**维护团队**: 数据库运维组  
**作者**: 未央  
**哲学**: 代码无言，逻辑有踪。

**文档更新**: 请在每次脚本修改后同步更新本文档

---

**文档结束**
