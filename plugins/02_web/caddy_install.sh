#!/bin/bash
# ============================================================
# Caddy 安装脚本
# 支持多种安装方式，自动检测系统架构
# ============================================================

# 脚本元信息（用于菜单显示）
PLUGIN_NAME="Caddy 管理"
PLUGIN_DESC="安装高性能 Web 服务器 Caddy"
PLUGIN_CATEGORY="Web"

# Caddy 版本
CADDY_VERSION="${CADDY_VERSION:-2.7.6}"

# ============================================================
# 安装方法
# ============================================================

# 方法1: 使用官方脚本安装（推荐）
install_caddy_official() {
    hg_process "正在使用官方脚本安装 Caddy..." \
        "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/setup.deb.sh' | bash && apt-get install -y caddy"
}

# 方法2: 使用包管理器安装（Debian/Ubuntu）
install_caddy_apt() {
    hg_process "添加 Caddy 官方源..." \
        "apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl"
    
    hg_process "导入 GPG 密钥..." \
        "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    
    hg_process "添加 APT 源..." \
        "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list"
    
    hg_process "更新软件包列表..." "apt-get update"
    
    hg_process "安装 Caddy..." "apt-get install -y caddy"
}

# 方法3: 使用包管理器安装（CentOS/RHEL/Fedora）
install_caddy_yum() {
    hg_process "添加 Caddy 官方源..." \
        "yum install -y yum-plugin-copr && yum copr enable -y @caddy/caddy"
    
    hg_process "安装 Caddy..." "yum install -y caddy"
}

# 方法4: 使用 dnf 安装（Fedora）
install_caddy_dnf() {
    hg_process "添加 Caddy 官方源..." \
        "dnf install -y 'dnf-command(copr)' && dnf copr enable -y @caddy/caddy"
    
    hg_process "安装 Caddy..." "dnf install -y caddy"
}

# 方法5: 二进制安装（通用）
install_caddy_binary() {
    local arch=$(get_arch)
    local os=$(get_os)
    local download_url=""
    local install_dir="/usr/local/bin"
    
    # 构建下载 URL
    case "${os}_${arch}" in
        linux_amd64)
            download_url="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
            ;;
        linux_arm64)
            download_url="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_arm64.tar.gz"
            ;;
        darwin_amd64)
            download_url="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_mac_amd64.tar.gz"
            ;;
        darwin_arm64)
            download_url="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_mac_arm64.tar.gz"
            ;;
        *)
            hg_error "不支持的系统架构: ${os}_${arch}"
            return 1
            ;;
    esac
    
    # 创建临时目录
    local tmp_dir=$(mktemp -d)
    local tmp_file="${tmp_dir}/caddy.tar.gz"
    
    hg_process "下载 Caddy v${CADDY_VERSION}..." \
        "curl -sL '${download_url}' -o '${tmp_file}'"
    
    hg_process "解压并安装..." \
        "tar -xzf '${tmp_file}' -C '${tmp_dir}' && mv '${tmp_dir}/caddy' '${install_dir}/caddy' && chmod +x '${install_dir}/caddy'"
    
    # 清理临时文件
    rm -rf "$tmp_dir"
    
    # 创建 systemd 服务文件
    create_caddy_service
}

# 创建 Caddy systemd 服务
create_caddy_service() {
    local service_file="/etc/systemd/system/caddy.service"
    
    # 创建 Caddy 用户和组
    if ! id "caddy" &>/dev/null; then
        hg_process "创建 caddy 用户..." \
            "groupadd --system caddy && useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy"
    fi
    
    # 创建配置目录
    mkdir -p /etc/caddy
    mkdir -p /var/lib/caddy
    mkdir -p /var/log/caddy
    chown -R caddy:caddy /var/lib/caddy /var/log/caddy
    
    # 创建默认 Caddyfile
    if [ ! -f /etc/caddy/Caddyfile ]; then
        cat > /etc/caddy/Caddyfile << 'EOF'
# Caddy 全局配置
{
    # 管理端点（可选）
    # admin localhost:2019
    
    # 日志配置
    log {
        output file /var/log/caddy/access.log
        format json
    }
}

# 默认站点配置示例
# :80 {
#     respond "Hello, Caddy!"
# }
EOF
        chown caddy:caddy /etc/caddy/Caddyfile
    fi
    
    # 创建 systemd 服务文件
    cat > "$service_file" << 'EOF'
[Unit]
Description=Caddy Web Server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    
    hg_process "重载 systemd 配置..." "systemctl daemon-reload"
}

# ============================================================
# 检测与验证
# ============================================================

# 检查 Caddy 是否已安装
check_caddy_installed() {
    if command -v caddy &>/dev/null; then
        local version=$(caddy version 2>/dev/null | head -1)
        echo "$version"
        return 0
    fi
    return 1
}

# 检测系统包管理器
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v brew &>/dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# ============================================================
# 主流程
# ============================================================

install_caddy_main() {
    hg_banner
    echo ""
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║           Caddy Web 服务器安装            ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo ""
    
    # 检查是否已安装
    local current_version=""
    current_version=$(check_caddy_installed) || true
    if [ -n "$current_version" ]; then
        echo "  ⚠️  检测到 Caddy 已安装: $current_version"
        echo ""
        if ! hg_confirm "是否继续重新安装/升级？"; then
            echo "已取消安装。"
            return 0
        fi
    fi
    
    # 检测包管理器
    local pkg_manager=$(detect_package_manager)
    echo "  📦 检测到包管理器: $pkg_manager"
    echo "  🖥️  系统架构: $(get_os) / $(get_arch)"
    echo ""
    
    # 选择安装方式
    local choice
    choice=$(hg_choose "请选择安装方式" \
        "1) 官方脚本安装 (推荐)" \
        "2) 包管理器安装 (apt/yum/dnf)" \
        "3) 二进制安装 (通用)" \
        "4) 取消")
    
    case "$choice" in
        "1)"*|*"官方脚本"*)
            install_caddy_official
            ;;
        "2)"*|*"包管理器"*)
            case "$pkg_manager" in
                apt)
                    install_caddy_apt
                    ;;
                yum)
                    install_caddy_yum
                    ;;
                dnf)
                    install_caddy_dnf
                    ;;
                *)
                    hg_error "当前系统不支持包管理器安装，请使用二进制安装"
                    return 1
                    ;;
            esac
            ;;
        "3)"*|*"二进制"*)
            install_caddy_binary
            ;;
        *)
            echo "已取消安装。"
            return 0
            ;;
    esac
    
    # 验证安装
    echo ""
    if check_caddy_installed &>/dev/null; then
        hg_success "✅ Caddy 安装成功！"
        echo ""
        echo "  版本: $(caddy version)"
        echo "  配置文件: /etc/caddy/Caddyfile"
        echo ""
        echo "  常用命令:"
        echo "    启动服务:   systemctl start caddy"
        echo "    停止服务:   systemctl stop caddy"
        echo "    重启服务:   systemctl restart caddy"
        echo "    查看状态:   systemctl status caddy"
        echo "    开机自启:   systemctl enable caddy"
        echo "    验证配置:   caddy validate --config /etc/caddy/Caddyfile"
        echo ""
        
        # 询问是否启动服务
        if hg_confirm "是否现在启动 Caddy 服务？"; then
            hg_process "启动 Caddy 服务..." "systemctl start caddy && systemctl enable caddy"
            hg_success "✅ Caddy 服务已启动并设置为开机自启"
        fi
    else
        hg_error "❌ Caddy 安装失败，请检查错误信息"
        return 1
    fi
}

# 如果直接运行此脚本则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 引入核心库
    SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
    ROOT_DIR=$(cd "$SCRIPT_DIR/../.."; pwd)
    source "$ROOT_DIR/lib/utils.sh"
    source "$ROOT_DIR/lib/ui.sh"
    
    install_caddy_main
else
    # 作为插件被 source 时执行
    install_caddy_main
fi
