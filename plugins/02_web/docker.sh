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
        print_title "Docker 管理"

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

        print_info "Docker 状态: $docker_status"

        local choice
        choice=$(interactive_menu "请选择操作" \
            "安装 Docker|安装 Docker 引擎" \
            "数据目录迁移|迁移 Docker 数据" \
            "Docker 信息|查看 Docker 状态" \
            "重启 Docker|重启 Docker 服务" \
            "清理未使用资源|清理镜像/容器" \
            "返回主菜单|Back")

        case "${choice%%|*}" in
            "安装 Docker")
                install_docker
                ;;
            "数据目录迁移")
                migrate_docker_data
                ;;
            "Docker 信息")
                show_docker_info
                ;;
            "重启 Docker")
                restart_docker
                ;;
            "清理未使用资源")
                cleanup_docker
                ;;
            "返回主菜单"|"")
                return 0
                ;;
        esac
    done
}

# 安装 Docker
install_docker() {
    require_root || return 1

    print_title "安装 Docker"

    if command_exists docker; then
        local version=$(docker --version 2>/dev/null)
        print_warn "Docker 已安装: $version"
        if ! confirm "是否重新安装？"; then
            pause
            return 0
        fi
    fi

    local install_choice
    install_choice=$(interactive_menu "选择安装方式" \
        "官方一键脚本|推荐" \
        "手动安装|国内镜像" \
        "返回|Back")

    case "${install_choice%%|*}" in
        "官方一键脚本")
            install_docker_official
            ;;
        "手动安装")
            install_docker_manual
            ;;
        "返回"|"")
            return 0
            ;;
    esac
}

# 官方脚本安装
install_docker_official() {
    print_info "使用官方脚本安装 Docker..."

    # 选择镜像源
    local mirror_choice
    mirror_choice=$(interactive_menu "选择镜像源" \
        "官方源|国外服务器推荐" \
        "阿里云镜像|国内推荐" \
        "DaoCloud 镜像|备用")

    local script_url="https://get.docker.com"
    case "${mirror_choice%%|*}" in
        "阿里云镜像")
            export DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce"
            ;;
        "DaoCloud 镜像")
            script_url="https://get.daocloud.io/docker"
            ;;
    esac

    spinner "下载安装脚本..." curl -fsSL "$script_url" -o /tmp/get-docker.sh

    if [ ! -f /tmp/get-docker.sh ]; then
        print_error "下载安装脚本失败"
        pause
        return 1
    fi

    print_info "开始安装 Docker（可能需要几分钟）..."
    sh /tmp/get-docker.sh

    rm -f /tmp/get-docker.sh

    # 启动 Docker
    spinner "启动 Docker..." systemctl enable docker && systemctl start docker

    # 验证安装
    if command_exists docker && docker info >/dev/null 2>&1; then
        print_success "Docker 安装成功！"

        # 配置镜像加速
        if confirm "是否配置 Docker 镜像加速？"; then
            configure_docker_mirror
        fi
    else
        print_error "Docker 安装失败"
        pause
        return 1
    fi

    log_info "Docker 安装完成"
    pause
}

# 手动安装
install_docker_manual() {
    local pkg_mgr=$(get_pkg_manager)
    local distro=$(get_distro)

    print_info "检测到: $distro ($pkg_mgr)"

    case "$pkg_mgr" in
        apt)
            spinner "安装依赖..." apt-get update && apt-get install -y ca-certificates curl gnupg

            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$distro/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$distro $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

            spinner "安装 Docker..." apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;

        yum|dnf)
            spinner "安装依赖..." $pkg_mgr install -y yum-utils

            yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo

            spinner "安装 Docker..." $pkg_mgr install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;

        *)
            print_error "不支持的包管理器: $pkg_mgr"
            pause
            return 1
            ;;
    esac

    spinner "启动 Docker..." systemctl enable docker && systemctl start docker

    if docker info >/dev/null 2>&1; then
        print_success "Docker 安装成功！"
        configure_docker_mirror
    else
        print_error "Docker 安装失败"
        pause
        return 1
    fi
}

# 配置 Docker 镜像加速
configure_docker_mirror() {
    print_subtitle "配置镜像加速"

    local daemon_json="/etc/docker/daemon.json"
    mkdir -p /etc/docker

    local mirror_choice
    mirror_choice=$(interactive_menu "选择镜像加速器" \
        "阿里云|稳定" \
        "腾讯云|备用" \
        "华为云|备用" \
        "DaoCloud|备用" \
        "全部使用|推荐")

    local mirror_urls=""
    case "${mirror_choice%%|*}" in
        "阿里云") mirror_urls='"https://registry.cn-hangzhou.aliyuncs.com"' ;;
        "腾讯云") mirror_urls='"https://mirror.ccs.tencentyun.com"' ;;
        "华为云") mirror_urls='"https://mirrors.huaweicloud.com"' ;;
        "DaoCloud") mirror_urls='"https://docker.m.daocloud.io"' ;;
        "全部使用"|"") mirror_urls='"https://registry.cn-hangzhou.aliyuncs.com","https://mirror.ccs.tencentyun.com","https://docker.m.daocloud.io"' ;;
    esac

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

        spinner "重启 Docker..." systemctl daemon-reload && systemctl restart docker

        print_success "镜像加速配置完成！"
    fi
}

# 数据目录迁移
migrate_docker_data() {
    require_root || return 1

    print_title "Docker 数据目录迁移"

    if ! command_exists docker; then
        print_error "Docker 未安装"
        pause
        return 1
    fi

    # 获取当前数据目录
    local current_root=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')
    current_root=${current_root:-/var/lib/docker}

    print_info "当前数据目录: $current_root"

    local current_size=$(du -sh "$current_root" 2>/dev/null | awk '{print $1}')
    print_info "当前目录大小: $current_size"

    # 输入新目录
    local new_root
    new_root=$(input "新数据目录" "/data/docker")

    if [ -z "$new_root" ]; then
        print_warn "已取消"
        pause
        return 0
    fi

    if [ "$new_root" = "$current_root" ]; then
        print_warn "新目录与当前目录相同"
        pause
        return 0
    fi

    # 检查目标目录空间
    local target_free=$(df -h "$new_root" 2>/dev/null | tail -1 | awk '{print $4}')
    print_info "目标磁盘剩余空间: $target_free"

    if ! confirm "确认将 Docker 数据迁移到 $new_root ？"; then
        pause
        return 0
    fi

    echo ""
    echo -e " ${YELLOW}${BOLD}⚠ 迁移过程将：${PLAIN}"
    echo "   1. 停止所有容器"
    echo "   2. 停止 Docker 服务"
    echo "   3. 同步数据到新目录"
    echo "   4. 修改 Docker 配置"
    echo "   5. 重启 Docker 服务"

    if ! confirm_danger "确认开始迁移？"; then
        pause
        return 0
    fi

    # 创建目标目录
    mkdir -p "$new_root"

    # 停止 Docker
    spinner "停止 Docker 服务..." systemctl stop docker

    # 同步数据
    print_info "同步数据中（这可能需要较长时间）..."
    rsync -avP "$current_root/" "$new_root/"

    if [ $? -ne 0 ]; then
        print_error "数据同步失败"
        systemctl start docker
        pause
        return 1
    fi

    # 修改配置
    local daemon_json="/etc/docker/daemon.json"
    backup_file "$daemon_json" 2>/dev/null

    if [ -f "$daemon_json" ]; then
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
    spinner "重启 Docker..." systemctl daemon-reload && systemctl start docker

    # 验证
    local new_current=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')

    if [ "$new_current" = "$new_root" ]; then
        print_success "数据迁移成功！"
        print_info "新数据目录: $new_root"

        if confirm "是否删除旧数据目录？"; then
            rm -rf "$current_root"
            print_success "旧数据目录已删除"
        fi
    else
        print_error "迁移可能未完成，请检查配置"
    fi

    log_info "Docker 数据迁移: $current_root -> $new_root"

    pause
}

# 显示 Docker 信息
show_docker_info() {
    print_title "Docker 信息"

    if ! command_exists docker; then
        print_error "Docker 未安装"
        pause
        return
    fi

    echo ""
    docker info 2>/dev/null | head -30
    echo ""

    print_subtitle "运行中的容器"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null

    print_subtitle "磁盘使用"
    docker system df 2>/dev/null

    pause
}

# 重启 Docker
restart_docker() {
    require_root || return 1

    if ! confirm "确认重启 Docker？所有容器将临时停止"; then
        pause
        return 0
    fi

    spinner "重启 Docker..." systemctl restart docker

    if systemctl is-active docker >/dev/null 2>&1; then
        print_success "Docker 重启成功"
    else
        print_error "Docker 重启失败"
    fi

    pause
}

# 清理 Docker
cleanup_docker() {
    require_root || return 1

    print_title "清理 Docker 资源"

    if ! command_exists docker; then
        print_error "Docker 未安装"
        pause
        return
    fi

    print_subtitle "当前磁盘使用"
    docker system df

    local clean_choice
    clean_choice=$(interactive_menu "选择清理类型" \
        "清理悬空镜像和缓存|安全" \
        "清理所有未使用资源|谨慎" \
        "返回|Back")

    case "${clean_choice%%|*}" in
        "清理悬空镜像和缓存")
            spinner "清理中..." docker system prune -f
            print_success "清理完成！"
            ;;
        "清理所有未使用资源")
            if confirm_danger "这将删除所有未使用的镜像、容器、网络和卷，确认？"; then
                spinner "清理中..." docker system prune -a --volumes -f
                print_success "清理完成！"
            fi
            ;;
        "返回"|"")
            return 0
            ;;
    esac

    print_subtitle "清理后磁盘使用"
    docker system df

    pause
}

# 执行插件
plugin_main
