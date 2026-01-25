#!/bin/bash
# ============================================================
# deps.sh - 依赖管理模块
# 自动检测 OS/Arch 并下载 gum/fzf 二进制文件
# ============================================================

# 版本配置
GUM_VERSION="0.14.5"
FZF_VERSION="0.67.0"

# 镜像源配置
GITHUB_MIRROR="https://github.com"
GITEE_MIRROR="https://gitee.com/mirrors"

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
        echo "错误: 需要 curl 或 wget 来下载依赖"
        return 1
    fi
}

# 下载 gum
download_gum() {
    local bin_dir="$1"
    local arch="$2"
    local os="$3"
    local url=""

    # 构建下载 URL
    case "${os}_${arch}" in
        linux_amd64)
            url="${GITHUB_MIRROR}/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_x86_64.tar.gz"
            ;;
        linux_arm64)
            url="${GITHUB_MIRROR}/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_arm64.tar.gz"
            ;;
        darwin_amd64)
            url="${GITHUB_MIRROR}/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Darwin_x86_64.tar.gz"
            ;;
        darwin_arm64)
            url="${GITHUB_MIRROR}/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Darwin_arm64.tar.gz"
            ;;
        *)
            echo "错误: 不支持的系统架构 ${os}_${arch}"
            return 1
            ;;
    esac

    echo "  下载地址: $url"

    # 创建临时目录
    local tmp_dir=$(mktemp -d)
    local tmp_file="${tmp_dir}/gum.tar.gz"

    # 下载
    if ! download_file "$url" "$tmp_file"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    # 解压
    tar -xzf "$tmp_file" -C "$tmp_dir" 2>/dev/null

    # 查找并移动 gum 二进制
    if [ -f "${tmp_dir}/gum" ]; then
        mv "${tmp_dir}/gum" "${bin_dir}/gum"
    else
        # 某些版本可能在子目录中
        find "$tmp_dir" -name "gum" -type f -exec mv {} "${bin_dir}/gum" \;
    fi

    chmod +x "${bin_dir}/gum"
    rm -rf "$tmp_dir"

    return 0
}

# 主检查函数
check_and_install_dependencies() {
    local bin_dir="${ROOT_DIR}/bin"
    local arch=$(get_arch)
    local os=$(get_os)

    # 创建必要目录
    mkdir -p "$bin_dir"
    mkdir -p "${ROOT_DIR}/logs"

    local need_download=false

    # 检查 gum
    if [ ! -x "${bin_dir}/gum" ]; then
        need_download=true
        echo ""
        echo "┌─────────────────────────────────────────┐"
        echo "│  首次运行，正在下载依赖组件...          │"
        echo "└─────────────────────────────────────────┘"
        echo ""
        echo "[1/1] 正在下载 gum v${GUM_VERSION}..."
        if download_gum "$bin_dir" "$arch" "$os"; then
            echo "  ✓ gum 下载成功"
        else
            echo "  ✗ gum 下载失败"
            echo ""
            echo "请手动下载 gum 并放置到 ${bin_dir}/gum"
            echo "下载地址: https://github.com/charmbracelet/gum/releases"
            exit 1
        fi
    fi

    if [ "$need_download" = true ]; then
        echo ""
        echo "✓ 所有依赖已就绪！"
        sleep 1
    fi

    # 导出路径
    export PATH="${bin_dir}:$PATH"
    export GUM_BIN="${bin_dir}/gum"
}

# 验证依赖是否可用
verify_dependencies() {
    local bin_dir="${ROOT_DIR}/bin"

    if [ ! -x "${bin_dir}/gum" ]; then
        echo "错误: gum 不可用"
        return 1
    fi

    return 0
}
