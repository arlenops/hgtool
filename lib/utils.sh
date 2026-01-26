#!/bin/bash
# ============================================================
# utils.sh - 通用工具函数库
# 封装系统检测、IP获取、Root权限检查等通用功能
# ============================================================

# 获取系统架构
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7*)
            echo "armv7"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 获取操作系统类型
get_os() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    echo "$os"
}

# 获取发行版
get_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

# 获取包管理器
get_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# 检查 Root 权限
check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[33m⚠ 警告: 部分功能需要 root 权限运行\033[0m"
        return 1
    fi
    return 0
}

# 强制要求 root 权限
require_root() {
    if [ "$EUID" -ne 0 ]; then
        hg_error "此操作需要 root 权限，请使用 sudo 运行"
        return 1
    fi
    return 0
}

# 获取本机 IP 地址
get_local_ip() {
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip" ]; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi
    if [ -z "$ip" ]; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
    echo "${ip:-未知}"
}

# 获取公网 IP 地址
get_public_ip() {
    local ip=""
    local services=(
        "ifconfig.me"
        "ip.sb"
        "ipinfo.io/ip"
        "icanhazip.com"
    )

    for service in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 3 --max-time 5 "$service" 2>/dev/null)
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    echo "未知"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查端口是否被占用
port_in_use() {
    local port="$1"
    if command_exists ss; then
        ss -tuln | grep -q ":${port} "
    elif command_exists netstat; then
        netstat -tuln | grep -q ":${port} "
    else
        return 1
    fi
}

# 验证 IP 地址格式
is_valid_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi
    return 1
}

# 验证端口号
is_valid_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

# 获取系统内存（MB）
get_total_mem_mb() {
    local mem=$(free -m | awk '/^Mem:/{print $2}')
    echo "${mem:-0}"
}

# 获取可用内存（MB）
get_free_mem_mb() {
    local mem=$(free -m | awk '/^Mem:/{print $7}')
    echo "${mem:-0}"
}

# 获取磁盘使用率
get_disk_usage() {
    local path="${1:-/}"
    df -h "$path" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%'
}

# 日志记录
log_info() {
    local msg="$1"
    local log_file="${ROOT_DIR}/logs/hgtool.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "$log_file"
}

log_error() {
    local msg="$1"
    local log_file="${ROOT_DIR}/logs/hgtool.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "$log_file"
}

log_warn() {
    local msg="$1"
    local log_file="${ROOT_DIR}/logs/hgtool.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $msg" >> "$log_file"
}

# 备份文件
backup_file() {
    local file="$1"
    local backup_dir="${ROOT_DIR}/backups"

    if [ -f "$file" ]; then
        mkdir -p "$backup_dir"
        local filename=$(basename "$file")
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        cp "$file" "${backup_dir}/${filename}.${timestamp}.bak"
        log_info "已备份文件: $file -> ${backup_dir}/${filename}.${timestamp}.bak"
        return 0
    fi
    return 1
}

# 安全执行命令
safe_exec() {
    local cmd="$1"
    local desc="${2:-执行命令}"

    log_info "执行: $cmd"

    if eval "$cmd" 2>&1; then
        log_info "$desc 成功"
        return 0
    else
        log_error "$desc 失败: $cmd"
        return 1
    fi
}
