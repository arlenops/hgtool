#!/bin/bash
# ============================================================
# deps.sh - 依赖管理模块
# 轻量版：无外部依赖，仅检查基本命令
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

# 获取发行版信息
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

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 下载文件（支持 curl 和 wget）
download_file() {
    local url="$1"
    local output="$2"

    if command_exists curl; then
        curl -fsSL --connect-timeout 30 --retry 3 "$url" -o "$output"
    elif command_exists wget; then
        wget -q --timeout=30 --tries=3 "$url" -O "$output"
    else
        echo "错误: 需要 curl 或 wget"
        return 1
    fi
}

# 主检查函数（简化版）
check_and_install_dependencies() {
    # 创建必要目录
    mkdir -p "${ROOT_DIR}/logs"
    mkdir -p "${ROOT_DIR}/config"
    
    # 检查基本命令
    local missing_cmds=""
    
    for cmd in grep sed awk; do
        if ! command_exists "$cmd"; then
            missing_cmds="$missing_cmds $cmd"
        fi
    done
    
    if [ -n "$missing_cmds" ]; then
        echo "错误: 缺少基本命令:$missing_cmds"
        exit 1
    fi
}

# 验证依赖是否可用
verify_dependencies() {
    return 0
}
