#!/bin/bash
# ============================================================
# Docker 管理插件
# ============================================================

PLUGIN_NAME="Docker 管理"
PLUGIN_DESC="Docker 安装、数据迁移"

plugin_main() {
    while true; do
        print_title "Docker 管理"

        local status="未安装"
        command_exists docker && status=$(systemctl is-active docker 2>/dev/null || echo "已安装")
        print_info "Docker: $status"

        interactive_menu "安装 Docker·····一键安装Docker" "数据迁移·····迁移Docker数据目录" "Docker 信息·····查看Docker详情" "清理资源·····清理无用资源" "返回主菜单"

        case "$MENU_RESULT" in
            "安装 Docker·····一键安装Docker") install_docker ;;
            "数据迁移·····迁移Docker数据目录") migrate_docker_data ;;
            "Docker 信息·····查看Docker详情") show_docker_info ;;
            "清理资源·····清理无用资源") cleanup_docker ;;
            "返回主菜单"|"") return 0 ;;
        esac
    done
}

install_docker() {
    require_root || return 1
    print_title "安装 Docker"

    interactive_menu "官方脚本安装·····使用官方源" "阿里云镜像安装·····国内加速" "返回"
    [[ -z "$MENU_RESULT" ]] || [[ "$MENU_RESULT" == "返回" ]] && return 0

    local script_url="https://get.docker.com"
    [[ "$MENU_RESULT" == "阿里云镜像安装·····国内加速" ]] && export DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce"

    spinner "下载脚本..." curl -fsSL "$script_url" -o /tmp/get-docker.sh
    [ ! -f /tmp/get-docker.sh ] && { print_error "下载失败"; pause; return 1; }

    print_info "安装中..."
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh

    spinner "启动 Docker..." systemctl enable docker && systemctl start docker

    if docker info >/dev/null 2>&1; then
        print_success "Docker 安装成功！"
        confirm "配置镜像加速？" && configure_mirror
    else
        print_error "安装失败"
    fi
    pause
}

configure_mirror() {
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": ["https://registry.cn-hangzhou.aliyuncs.com","https://mirror.ccs.tencentyun.com"]
}
EOF
    systemctl daemon-reload && systemctl restart docker
    print_success "镜像加速已配置"
}

migrate_docker_data() {
    require_root || return 1
    print_title "Docker 数据迁移"
    command_exists docker || { print_error "Docker 未安装"; pause; return 1; }

    local current=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}')
    print_info "当前目录: ${current:-/var/lib/docker}"

    local new_root=$(input "新目录" "/data/docker")
    [ -z "$new_root" ] && { pause; return 0; }

    confirm_danger "确认迁移到 $new_root ？" || { pause; return 0; }

    mkdir -p "$new_root"
    spinner "停止 Docker..." systemctl stop docker
    print_info "同步数据..."
    rsync -avP "${current:-/var/lib/docker}/" "$new_root/"

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{"data-root": "$new_root"}
EOF
    spinner "启动 Docker..." systemctl daemon-reload && systemctl start docker
    print_success "迁移完成: $new_root"
    pause
}

show_docker_info() {
    print_title "Docker 信息"
    command_exists docker || { print_error "Docker 未安装"; pause; return; }
    docker info 2>/dev/null | head -20
    echo ""
    print_subtitle "容器"
    docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null
    pause
}

cleanup_docker() {
    require_root || return 1
    command_exists docker || { print_error "Docker 未安装"; pause; return; }

    interactive_menu "清理悬空镜像·····删除无标签镜像" "清理所有未使用·····彻底清理" "返回"

    case "$MENU_RESULT" in
        "清理悬空镜像·····删除无标签镜像") docker system prune -f; print_success "清理完成" ;;
        "清理所有未使用·····彻底清理") confirm_danger "确认？" && docker system prune -a --volumes -f && print_success "清理完成" ;;
    esac
    pause
}

plugin_main
