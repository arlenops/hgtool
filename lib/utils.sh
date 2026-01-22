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

# 检查 Root 权限
check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo "警告: 部分功能需要 root 权限运行"
        # 不强制退出，只是警告
    fi
}

# 检查并安装依赖（gum 和 fzf）
check_and_install_dependencies() {
    local bin_dir="$ROOT_DIR/bin"
    local arch=$(get_arch)
    local os=$(get_os)
    
    # 创建 bin 目录
    mkdir -p "$bin_dir"
    
    # 检查 gum
    if [ ! -x "$bin_dir/gum" ]; then
        echo "正在下载 gum..."
        download_gum "$bin_dir" "$arch" "$os"
    fi
    
    # 检查 fzf
    if [ ! -x "$bin_dir/fzf" ]; then
        echo "正在下载 fzf..."
        download_fzf "$bin_dir" "$arch" "$os"
    fi
    
    # 添加到 PATH
    export PATH="$bin_dir:$PATH"
}

# 下载 gum
download_gum() {
    local bin_dir="$1"
    local arch="$2"
    local os="$3"
    
    # gum 版本
    local version="0.13.0"
    local url=""
    
    case "${os}_${arch}" in
        linux_amd64)
            url="https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_Linux_x86_64.tar.gz"
            ;;
        linux_arm64)
            url="https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_Linux_arm64.tar.gz"
            ;;
        darwin_amd64)
            url="https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_Darwin_x86_64.tar.gz"
            ;;
        darwin_arm64)
            url="https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_Darwin_arm64.tar.gz"
            ;;
        *)
            echo "错误: 不支持的系统架构 ${os}_${arch}"
            exit 1
            ;;
    esac
    
    # 下载并解压
    local tmp_file=$(mktemp)
    curl -sL "$url" -o "$tmp_file"
    tar -xzf "$tmp_file" -C "$bin_dir" gum
    rm -f "$tmp_file"
    chmod +x "$bin_dir/gum"
}

# 下载 fzf
download_fzf() {
    local bin_dir="$1"
    local arch="$2"
    local os="$3"
    
    # fzf 版本
    local version="0.46.1"
    local url=""
    
    case "${os}_${arch}" in
        linux_amd64)
            url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version}-linux_amd64.tar.gz"
            ;;
        linux_arm64)
            url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version}-linux_arm64.tar.gz"
            ;;
        darwin_amd64)
            url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version}-darwin_amd64.zip"
            ;;
        darwin_arm64)
            url="https://github.com/junegunn/fzf/releases/download/${version}/fzf-${version}-darwin_arm64.zip"
            ;;
        *)
            echo "错误: 不支持的系统架构 ${os}_${arch}"
            exit 1
            ;;
    esac
    
    # 下载并解压
    local tmp_file=$(mktemp)
    curl -sL "$url" -o "$tmp_file"
    
    if [[ "$url" == *.zip ]]; then
        unzip -q "$tmp_file" -d "$bin_dir"
    else
        tar -xzf "$tmp_file" -C "$bin_dir"
    fi
    
    rm -f "$tmp_file"
    chmod +x "$bin_dir/fzf"
}

# 获取本机 IP 地址
get_local_ip() {
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip" ]; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
    echo "${ip:-未知}"
}

# 获取公网 IP 地址
get_public_ip() {
    local ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null)
    if [ -z "$ip" ]; then
        ip=$(curl -s --connect-timeout 3 ip.sb 2>/dev/null)
    fi
    echo "${ip:-未知}"
}
