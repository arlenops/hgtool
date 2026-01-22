#!/bin/bash
# ============================================================
# Docker 管理插件
# 包含: Docker 安装、数据迁移、容器管理
# ============================================================

PLUGIN_NAME="Docker 管理"
PLUGIN_DESC="Docker 安装、数据迁移"

# 插件主入口
plugin_main() {
    while true; do
        hg_title "Docker 管理"

        # 检查 Docker 状态
        local docker_status="未安装"
        local docker_version=""
        if command_exists docker; then
            docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
            if systemctl is-active docker >/dev/null 2>&1; then
                docker_status="运行中 (v$docker_version)"
            else
                docker_status="已停止 (v$docker_version)"
            fi
        fi

        hg_info "Docker 状态: $docker_status"

        local choice=$(hg_choose "请选择操作" \
            "📦 安装 Docker" \
            "🚚 数据目录迁移" \
            "📊 Docker 信息" \
            "🔄 重启 Docker" \
            "🧹 清理未使用资源" \
            "🔙 返回主菜单")

        case "$choice" in
            "📦 安装 Docker")
                install_docker
                ;;
            "🚚 数据目录迁移")
                migrate_docker_data
                ;;
            "📊 Docker 信息")
                show_docker_info
                ;;
            "🔄 重启 Docker")
                restart_docker
                ;;
            "🧹 清理未使用资源")
                cleanup_docker
                ;;
            "🔙 返回主菜单"|"")
                return 0
                ;;
        esac
    done
}

# 安装 Docker
install_docker() {
    require_root || return 1

    hg_title "安装 Docker"

    if command_exists docker; then
        local version=$(docker --version 2>/dev/null)
        hg_warn "Docker 已安装: $version"
        if ! hg_confirm "是否重新安装？"; then
            return 0
        fi
    fi

    local install_method=$(hg_choose "选择安装方式" \
        "🚀 官方一键脚本 (推荐)" \
        "📦 手动安装 (国内镜像)" \
        "🔙 返回")

    case "$install_method" in
        "🚀 官方一键脚本 (推荐)")
            install_docker_official
            ;;
        "📦 手动安装 (国内镜像)")
            install_docker_manual
            ;;
        "🔙 返回"|"")
            return 0
            ;;
    esac
}

# 官方脚本安装
install_docker_official() {
    hg_info "使用官方脚本安装 Docker..."

    # 选择镜像源
    local mirror=$(hg_choose "选择镜像源" \
        "官方源 (国外服务器推荐)" \
        "阿里云镜像 (国内推荐)" \
        "DaoCloud 镜像")

    local script_url=""
    case "$mirror" in
        "官方源 (国外服务器推荐)")
            script_url="https://get.docker.com"
            ;;
        "阿里云镜像 (国内推荐)")
            script_url="https://get.docker.com"
            export DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce"
            ;;
        "DaoCloud 镜像")
            script_url="https://get.daocloud.io/docker"
            ;;
    esac

    hg_spin "下载安装脚本..." curl -fsSL "$script_url" -o /tmp/get-docker.sh

    if [ ! -f /tmp/get-docker.sh ]; then
        hg_error "下载安装脚本失败"
        return 1
    fi

    hg_info "开始安装 Docker（可能需要几分钟）..."
    sh /tmp/get-docker.sh

    rm -f /tmp/get-docker.sh

    # 启动 Docker
    hg_spin "启动 Docker..." systemctl enable docker && systemctl start docker

    # 验证安装
    if command_exists docker && docker info >/dev/null 2>&1; then
        hg_success "Docker 安装成功！"

        # 配置镜像加速
        if hg_confirm "是否配置 Docker 镜像加速？"; then
            configure_docker_mirror
        fi
    else
        hg_error "Docker 安装失败"
        return 1
    fi

    log_info "Docker 安装完成"
}

# 手动安装
install_docker_manual() {
    local pkg_mgr=$(get_pkg_manager)
    local distro=$(get_distro)

    hg_info "检测到: $distro ($pkg_mgr)"

    case "$pkg_mgr" in
        apt)
            # 安装依赖
            hg_spin "安装依赖..." apt-get update && apt-get install -y ca-certificates curl gnupg

            # 添加 GPG 密钥
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$distro/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            # 添加软件源
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$distro $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

            # 安装 Docker
            hg_spin "安装 Docker..." apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;

        yum|dnf)
            # 安装依赖
            hg_spin "安装依赖..." $pkg_mgr install -y yum-utils

            # 添加软件源
            yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo

            # 安装 Docker
            hg_spin "安装 Docker..." $pkg_mgr install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;

        *)
            hg_error "不支持的包管理器: $pkg_mgr"
            return 1
            ;;
    esac

    # 启动 Docker
    hg_spin "启动 Docker..." systemctl enable docker && systemctl start docker

    if docker info >/dev/null 2>&1; then
        hg_success "Docker 安装成功！"
        configure_docker_mirror
    else
        hg_error "Docker 安装失败"
        return 1
    fi
}

# 配置 Docker 镜像加速
configure_docker_mirror() {
    hg_title "配置镜像加速"

    local daemon_json="/etc/docker/daemon.json"

    mkdir -p /etc/docker

    # 选择镜像加速器
    local mirrors=$(hg_choose_multi "选择镜像加速器（可多选）" \
        "阿里云" \
        "腾讯云" \
        "华为云" \
        "DaoCloud")

    local mirror_urls=""
    for m in $mirrors; do
        case "$m" in
            "阿里云")
                mirror_urls="$mirror_urls\"https://registry.cn-hangzhou.aliyuncs.com\","
                ;;
            "腾讯云")
                mirror_urls="$mirror_urls\"https://mirror.ccs.tencentyun.com\","
                ;;
            "华为云")
                mirror_urls="$mirror_urls\"https://mirrors.huaweicloud.com\","
                ;;
            "DaoCloud")
                mirror_urls="$mirror_urls\"https://docker.m.daocloud.io\","
                ;;
        esac
    done

    # 移除末尾逗号
    mirror_urls=$(echo "$mirror_urls" | sed 's/,$//')

    if [ -n "$mirror_urls" ]; then
        backup_file "$daemon_json" 2>/dev/null

        cat > "$daemon_json" <<EOF
{
    "registry-mirrors": [$mirror_urls],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF

        hg_spin "重启 Docker..." systemctl daemon-reload && systemctl restart docker

        hg_success "镜像加速配置完成！"
    fi
}

# 数据目录迁移
migrate_docker_data() {
    require_root || return 1

    hg_title "Docker 数据目录迁移"

    if ! command_exists docker; then
        hg_error "Docker 未安装"
        return 1
    fi

    # 获取当前数据目录
    local current_root=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')
    current_root=${current_root:-/var/lib/docker}

    hg_info "当前数据目录: $current_root"

    local current_size=$(du -sh "$current_root" 2>/dev/null | awk '{print $1}')
    hg_info "当前目录大小: $current_size"

    # 输入新目录
    local new_root=$(hg_input "新数据目录" "/data/docker")

    if [ -z "$new_root" ]; then
        hg_warn "已取消"
        return 0
    fi

    if [ "$new_root" = "$current_root" ]; then
        hg_warn "新目录与当前目录相同"
        return 0
    fi

    # 检查目标目录空间
    local target_mount=$(df "$new_root" 2>/dev/null | tail -1 | awk '{print $6}')
    local target_free=$(df -h "$new_root" 2>/dev/null | tail -1 | awk '{print $4}')
    hg_info "目标磁盘剩余空间: $target_free"

    if ! hg_confirm "确认将 Docker 数据迁移到 $new_root ？"; then
        return 0
    fi

    "$GUM" style \
        --foreground "$WARNING_COLOR" \
        --bold \
        "⚠️ 迁移过程将：
  1. 停止所有容器
  2. 停止 Docker 服务
  3. 同步数据到新目录
  4. 修改 Docker 配置
  5. 重启 Docker 服务"

    if ! hg_confirm_danger "确认开始迁移？"; then
        return 0
    fi

    # 创建目标目录
    mkdir -p "$new_root"

    # 停止 Docker
    hg_spin "停止 Docker 服务..." systemctl stop docker

    # 同步数据
    hg_info "同步数据中（这可能需要较长时间）..."
    rsync -avP "$current_root/" "$new_root/"

    if [ $? -ne 0 ]; then
        hg_error "数据同步失败"
        systemctl start docker
        return 1
    fi

    # 修改配置
    local daemon_json="/etc/docker/daemon.json"
    backup_file "$daemon_json" 2>/dev/null

    if [ -f "$daemon_json" ]; then
        # 如果配置文件存在，添加或修改 data-root
        if grep -q "data-root" "$daemon_json"; then
            sed -i "s|\"data-root\":.*|\"data-root\": \"$new_root\",|" "$daemon_json"
        else
            sed -i "s|{|{\n    \"data-root\": \"$new_root\",|" "$daemon_json"
        fi
    else
        cat > "$daemon_json" <<EOF
{
    "data-root": "$new_root"
}
EOF
    fi

    # 重启 Docker
    hg_spin "重启 Docker..." systemctl daemon-reload && systemctl start docker

    # 验证
    local new_current=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')

    if [ "$new_current" = "$new_root" ]; then
        hg_success "数据迁移成功！"
        hg_info "新数据目录: $new_root"

        if hg_confirm "是否删除旧数据目录？"; then
            rm -rf "$current_root"
            hg_success "旧数据目录已删除"
        fi
    else
        hg_error "迁移可能未完成，请检查配置"
    fi

    log_info "Docker 数据迁移: $current_root -> $new_root"

    hg_pause
}

# 显示 Docker 信息
show_docker_info() {
    hg_title "Docker 信息"

    if ! command_exists docker; then
        hg_error "Docker 未安装"
        return
    fi

    echo ""
    docker info 2>/dev/null | head -30
    echo ""

    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "运行中的容器:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null

    echo ""
    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "磁盘使用:"
    docker system df 2>/dev/null

    hg_pause
}

# 重启 Docker
restart_docker() {
    require_root || return 1

    if ! hg_confirm "确认重启 Docker？所有容器将临时停止"; then
        return 0
    fi

    hg_spin "重启 Docker..." systemctl restart docker

    if systemctl is-active docker >/dev/null 2>&1; then
        hg_success "Docker 重启成功"
    else
        hg_error "Docker 重启失败"
    fi

    hg_pause
}

# 清理 Docker
cleanup_docker() {
    require_root || return 1

    hg_title "清理 Docker 资源"

    if ! command_exists docker; then
        hg_error "Docker 未安装"
        return
    fi

    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "当前磁盘使用:"
    docker system df

    echo ""

    local clean_type=$(hg_choose "选择清理类型" \
        "🧹 清理悬空镜像和缓存" \
        "🔥 清理所有未使用资源 (谨慎)" \
        "🔙 返回")

    case "$clean_type" in
        "🧹 清理悬空镜像和缓存")
            hg_spin "清理中..." docker system prune -f
            ;;
        "🔥 清理所有未使用资源 (谨慎)")
            if hg_confirm_danger "这将删除所有未使用的镜像、容器、网络和卷，确认？"; then
                hg_spin "清理中..." docker system prune -a --volumes -f
            fi
            ;;
        "🔙 返回"|"")
            return 0
            ;;
    esac

    hg_success "清理完成！"

    echo ""
    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "清理后磁盘使用:"
    docker system df

    hg_pause
}

# 执行插件
plugin_main
