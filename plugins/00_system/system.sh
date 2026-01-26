#!/bin/bash
# ============================================================
# 系统管理插件
# ============================================================

PLUGIN_NAME="系统管理·····系统更新、时区、Swap"
PLUGIN_DESC="系统更新、时区设置、Swap管理"

plugin_main() {
    while true; do
        print_title "系统管理"

        interactive_menu "系统更新·····更新系统软件包" "时区设置·····配置系统时区" "Swap 管理·····虚拟内存配置" "系统信息·····查看系统详情" "返回主菜单"

        case "$MENU_RESULT" in
            "系统更新·····更新系统软件包") system_update ;;
            "时区设置·····配置系统时区") timezone_setup ;;
            "Swap 管理·····虚拟内存配置") swap_manager ;;
            "系统信息·····查看系统详情") show_system_info ;;
            "返回主菜单"|"") return 0 ;;
        esac
    done
}

system_update() {
    require_root || return 1
    print_title "系统更新"
    local pkg_mgr=$(get_pkg_manager)
    print_info "包管理器: $pkg_mgr"
    confirm "确认执行系统更新？" || { pause; return 0; }

    case "$pkg_mgr" in
        apt) spinner "更新软件源..." apt-get update -qq; spinner "升级软件包..." apt-get upgrade -y -qq ;;
        yum) spinner "更新软件包..." yum update -y -q ;;
        dnf) spinner "更新软件包..." dnf update -y -q ;;
    esac
    print_success "系统更新完成！"
    pause
}

timezone_setup() {
    require_root || return 1
    print_title "时区设置"
    print_info "当前时区: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone)"

    interactive_menu "Asia/Shanghai·····上海时区" "Asia/Hong_Kong·····香港时区" "Asia/Tokyo·····东京时区" "America/New_York·····纽约时区" "Europe/London·····伦敦时区" "UTC·····协调世界时" "返回"
    [[ -z "$MENU_RESULT" ]] || [[ "$MENU_RESULT" == "返回" ]] && return 0

    local timezone="${MENU_RESULT%%·····*}"
    command_exists timedatectl && timedatectl set-timezone "$timezone" || ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    print_success "时区已设置为: $timezone"
    pause
}

swap_manager() {
    require_root || return 1
    print_title "Swap 管理"
    print_info "当前 Swap: $(free -h | awk '/^Swap:/{print $2}')"

    interactive_menu "创建 Swap·····新建虚拟内存" "删除 Swap·····移除虚拟内存" "返回"

    case "$MENU_RESULT" in
        "创建 Swap·····新建虚拟内存") create_swap ;;
        "删除 Swap·····移除虚拟内存") remove_swap ;;
    esac
}

create_swap() {
    local swap_file="/swapfile"
    [ -f "$swap_file" ] && { swapoff "$swap_file" 2>/dev/null; rm -f "$swap_file"; }

    interactive_menu "1G·····1GB大小" "2G·····2GB大小" "4G·····4GB大小" "8G·····8GB大小"
    local size="${MENU_RESULT%%·····*}"
    size="${size:-2G}"

    spinner "创建 Swap ($size)..." fallocate -l "$size" "$swap_file" || dd if=/dev/zero of="$swap_file" bs=1M count=$(echo "$size" | sed 's/G/*1024/' | bc) status=none
    chmod 600 "$swap_file"
    spinner "格式化..." mkswap "$swap_file"
    spinner "启用..." swapon "$swap_file"
    grep -q "$swap_file" /etc/fstab || echo "$swap_file none swap sw 0 0" >> /etc/fstab
    print_success "Swap 创建成功: $size"
    pause
}

remove_swap() {
    local swap_file="/swapfile"
    [ ! -f "$swap_file" ] && { print_error "Swap 不存在"; pause; return; }
    confirm_danger "确认删除 Swap？" || { pause; return; }
    swapoff "$swap_file"; rm -f "$swap_file"; sed -i "\|$swap_file|d" /etc/fstab
    print_success "Swap 已删除"
    pause
}

show_system_info() {
    print_title "系统信息"
    echo " 主机名: $(hostname)"
    echo " 系统:   $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo " 内核:   $(uname -r)"
    echo " 架构:   $(uname -m)"
    echo " 运行:   $(uptime -p 2>/dev/null || uptime)"
    echo " CPU:    $(nproc) 核心"
    echo " 内存:   $(free -h | awk '/^Mem:/{print $3"/"$2}')"
    echo " 磁盘:   $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    echo " IP:     $(get_local_ip)"
    pause
}

plugin_main
