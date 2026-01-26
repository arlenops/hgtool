#!/bin/bash
# ============================================================
# Nginx 安装脚本
# 支持多种安装方式，自动检测系统架构
# ============================================================

# 脚本元信息（用于菜单显示）
PLUGIN_NAME="Nginx管理·····安装Nginx服务器"
PLUGIN_DESC="安装高性能 Web 服务器 Nginx"
PLUGIN_CATEGORY="Web"

# Nginx 版本（编译安装时使用）
NGINX_VERSION="${NGINX_VERSION:-1.24.0}"

# ============================================================
# 安装方法
# ============================================================

# 方法1: 使用包管理器安装（Debian/Ubuntu）
install_nginx_apt() {
    hg_process "更新软件包列表..." "apt-get update"
    hg_process "安装 Nginx..." "apt-get install -y nginx"
}

# 方法2: 使用官方源安装（Debian/Ubuntu）- 获取最新稳定版
install_nginx_apt_official() {
    hg_process "安装依赖..." \
        "apt-get install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring"
    
    # 导入官方 GPG 密钥
    hg_process "导入 Nginx 官方 GPG 密钥..." \
        "curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg"
    
    # 添加官方源
    local os_codename=$(lsb_release -cs 2>/dev/null || echo "focal")
    hg_process "添加 Nginx 官方源..." \
        "echo 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu ${os_codename} nginx' > /etc/apt/sources.list.d/nginx.list"
    
    # 设置优先级
    hg_process "设置软件源优先级..." \
        "echo -e 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900' > /etc/apt/preferences.d/99nginx"
    
    hg_process "更新软件包列表..." "apt-get update"
    hg_process "安装 Nginx..." "apt-get install -y nginx"
}

# 方法3: 使用包管理器安装（CentOS/RHEL）
install_nginx_yum() {
    # 添加官方源
    cat > /etc/yum.repos.d/nginx.repo << 'EOF'
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/$releasever/$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
    
    hg_process "安装 Nginx..." "yum install -y nginx"
}

# 方法4: 使用 dnf 安装（Fedora）
install_nginx_dnf() {
    hg_process "安装 Nginx..." "dnf install -y nginx"
}

# 方法5: 编译安装（通用，可自定义模块）
install_nginx_compile() {
    local install_prefix="/usr/local/nginx"
    local src_dir="/usr/local/src"
    
    # 安装编译依赖
    local pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)
            hg_process "安装编译依赖..." \
                "apt-get install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev libgd-dev libgeoip-dev"
            ;;
        yum|dnf)
            hg_process "安装编译依赖..." \
                "yum install -y gcc gcc-c++ make pcre pcre-devel zlib zlib-devel openssl openssl-devel gd gd-devel GeoIP GeoIP-devel"
            ;;
        *)
            hg_error "无法自动安装编译依赖，请手动安装"
            return 1
            ;;
    esac
    
    # 创建 nginx 用户
    if ! id "nginx" &>/dev/null; then
        hg_process "创建 nginx 用户..." \
            "useradd -r -s /sbin/nologin nginx"
    fi
    
    # 下载源码
    cd "$src_dir"
    hg_process "下载 Nginx v${NGINX_VERSION} 源码..." \
        "curl -sLO http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && tar -xzf nginx-${NGINX_VERSION}.tar.gz"
    
    cd "nginx-${NGINX_VERSION}"
    
    # 配置编译选项
    hg_process "配置编译选项..." \
        "./configure \
        --prefix=${install_prefix} \
        --user=nginx \
        --group=nginx \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_image_filter_module \
        --with-http_geoip_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-pcre"
    
    # 编译
    local cpu_cores=$(nproc 2>/dev/null || echo 2)
    hg_process "编译 Nginx (使用 ${cpu_cores} 核心)..." "make -j${cpu_cores}"
    
    # 安装
    hg_process "安装 Nginx..." "make install"
    
    # 创建软链接
    ln -sf "${install_prefix}/sbin/nginx" /usr/local/bin/nginx
    
    # 创建 systemd 服务
    create_nginx_service_compile "$install_prefix"
    
    # 清理
    cd /
    rm -rf "${src_dir}/nginx-${NGINX_VERSION}" "${src_dir}/nginx-${NGINX_VERSION}.tar.gz"
}

# 创建编译安装版本的 systemd 服务
create_nginx_service_compile() {
    local install_prefix="$1"
    local service_file="/etc/systemd/system/nginx.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=${install_prefix}/logs/nginx.pid
ExecStartPre=${install_prefix}/sbin/nginx -t
ExecStart=${install_prefix}/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    hg_process "重载 systemd 配置..." "systemctl daemon-reload"
}

# ============================================================
# 优化配置
# ============================================================

# 生成优化后的 nginx.conf
generate_optimized_config() {
    local conf_dir="${1:-/etc/nginx}"
    local cpu_cores=$(nproc 2>/dev/null || echo 2)
    local worker_connections=$((cpu_cores * 1024))
    
    # 备份原配置
    if [ -f "${conf_dir}/nginx.conf" ]; then
        cp "${conf_dir}/nginx.conf" "${conf_dir}/nginx.conf.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    cat > "${conf_dir}/nginx.conf" << EOF
# Nginx 优化配置
# 由 hgtool 自动生成

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

# 工作进程可打开最大文件数
worker_rlimit_nofile 65535;

events {
    # 单个工作进程最大并发连接数
    worker_connections ${worker_connections};
    # 使用 epoll 事件模型 (Linux)
    use epoll;
    # 允许同时接受多个连接
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # 日志格式
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # 基础优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # 隐藏版本号
    server_tokens off;

    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1000;
    gzip_types text/plain text/css text/xml application/json application/javascript 
               application/rss+xml application/atom+xml image/svg+xml;

    # 客户端请求限制
    client_max_body_size 50m;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;

    # 代理缓冲区
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;

    # 包含站点配置
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # 创建必要的目录
    mkdir -p "${conf_dir}/conf.d"
    mkdir -p "${conf_dir}/sites-available"
    mkdir -p "${conf_dir}/sites-enabled"
    mkdir -p /var/log/nginx
    
    hg_success "优化配置已生成"
}

# ============================================================
# 检测与验证
# ============================================================

# 检查 Nginx 是否已安装
check_nginx_installed() {
    if command -v nginx &>/dev/null; then
        local version=$(nginx -v 2>&1 | grep -oP 'nginx/\K[\d.]+')
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
    else
        echo "unknown"
    fi
}

# ============================================================
# 主流程
# ============================================================

install_nginx_main() {
    hg_banner
    echo ""
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║           Nginx Web 服务器安装            ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo ""
    
    # 检查是否已安装
    local current_version=""
    current_version=$(check_nginx_installed) || true
    if [ -n "$current_version" ]; then
        echo "  检测到 Nginx 已安装: v${current_version}"
        echo ""
        if ! hg_confirm "是否继续重新安装/升级？"; then
            echo "已取消安装。"
            return 0
        fi
    fi
    
    # 检测包管理器
    local pkg_manager=$(detect_package_manager)
    echo "  检测到包管理器: $pkg_manager"
    echo "  系统架构: $(get_os) / $(get_arch)"
    echo ""
    
    # 选择安装方式
    local choice
    choice=$(hg_choose "请选择安装方式" \
        "1) 系统包管理器安装 (快速)" \
        "2) 官方源安装 (推荐)" \
        "3) 编译安装 (自定义模块)" \
        "4) 取消")
    
    case "$choice" in
        "1)"*|*"系统包管理器"*)
            case "$pkg_manager" in
                apt)
                    install_nginx_apt
                    ;;
                yum)
                    install_nginx_yum
                    ;;
                dnf)
                    install_nginx_dnf
                    ;;
                *)
                    hg_error "当前系统不支持包管理器安装"
                    return 1
                    ;;
            esac
            ;;
        "2)"*|*"官方源"*)
            case "$pkg_manager" in
                apt)
                    install_nginx_apt_official
                    ;;
                yum)
                    install_nginx_yum  # yum 方式已包含官方源
                    ;;
                dnf)
                    install_nginx_dnf
                    ;;
                *)
                    hg_error "当前系统不支持官方源安装，请使用编译安装"
                    return 1
                    ;;
            esac
            ;;
        "3)"*|*"编译安装"*)
            # 询问版本
            echo ""
            local input_version
            input_version=$(hg_input "请输入 Nginx 版本号 (默认: ${NGINX_VERSION})")
            if [ -n "$input_version" ]; then
                NGINX_VERSION="$input_version"
            fi
            install_nginx_compile
            ;;
        *)
            echo "已取消安装。"
            return 0
            ;;
    esac
    
    # 验证安装
    echo ""
    if check_nginx_installed &>/dev/null; then
        hg_success "Nginx 安装成功！"
        echo ""
        echo "  版本: $(nginx -v 2>&1)"
        echo ""
        
        # 询问是否生成优化配置
        if hg_confirm "是否生成优化后的配置文件？"; then
            local conf_dir="/etc/nginx"
            if [ -d "/usr/local/nginx/conf" ]; then
                conf_dir="/usr/local/nginx/conf"
            fi
            generate_optimized_config "$conf_dir"
        fi
        
        echo ""
        echo "  常用命令:"
        echo "    启动服务:   systemctl start nginx"
        echo "    停止服务:   systemctl stop nginx"
        echo "    重启服务:   systemctl restart nginx"
        echo "    重载配置:   systemctl reload nginx"
        echo "    查看状态:   systemctl status nginx"
        echo "    开机自启:   systemctl enable nginx"
        echo "    测试配置:   nginx -t"
        echo ""
        
        # 询问是否启动服务
        if hg_confirm "是否现在启动 Nginx 服务？"; then
            hg_process "启动 Nginx 服务..." "systemctl start nginx && systemctl enable nginx"
            hg_success "Nginx 服务已启动并设置为开机自启"
        fi
    else
        hg_error "Nginx 安装失败，请检查错误信息"
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
    
    install_nginx_main
else
    # 作为插件被 source 时执行
    install_nginx_main
fi
