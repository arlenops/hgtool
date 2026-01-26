#!/bin/bash
# ============================================================
# 系统管理插件
# 包含: 系统更新、时区设置、Swap管理
# ============================================================

PLUGIN_NAME="系统管理"
PLUGIN_DESC="系统更新、时区设置、Swap管理"

# 插件主入口
plugin_main() {
    while true; do
        print_title "系统管理"

        local choice
        choice=$(interactive_menu "请选择操作" \
            "系统更新|更新系统软件包" \
            "时区设置|设置系统时区" \
            "Swap 管理|创建/删除 Swap" \
            "系统信息|查看系统详情" \
            "返回主菜单|Back")

        case "${choice%%|*}" in
            "系统更新")
                system_update
                ;;
            "时区设置")
                timezone_setup
                ;;
            "Swap 管理")
                swap_manager
                ;;
            "系统信息")
                show_system_info
                ;;
            "返回主菜单"|"")
                return 0
                ;;
        esac
    done
}

# 系统更新
system_update() {
    require_root || return 1

    print_title "系统更新"

    local pkg_mgr=$(get_pkg_manager)

    print_info "检测到包管理器: $pkg_mgr"

    if ! confirm "确认执行系统更新？"; then
        print_warn "已取消"
        pause
        return 0
    fi

    case "$pkg_mgr" in
        apt)
            spinner "更新软件源..." apt-get update -qq
            spinner "升级软件包..." apt-get upgrade -y -qq
            spinner "清理缓存..." apt-get autoremove -y -qq && apt-get clean
            ;;
        yum)
            spinner "更新软件包..." yum update -y -q
            spinner "清理缓存..." yum clean all -q
            ;;
        dnf)
            spinner "更新软件包..." dnf update -y -q
            spinner "清理缓存..." dnf clean all -q
            ;;
        *)
            print_error "不支持的包管理器: $pkg_mgr"
            pause
            return 1
            ;;
    esac

    print_success "系统更新完成！"
    log_info "系统更新完成"
    pause
}

# 时区设置
timezone_setup() {
    require_root || return 1

    print_title "时区设置"

    local current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "未知")
    print_info "当前时区: $current_tz"

    local tz_choice
    tz_choice=$(interactive_menu "选择时区" \
        "Asia/Shanghai|中国-上海" \
        "Asia/Hong_Kong|中国-香港" \
        "Asia/Taipei|中国-台北" \
        "Asia/Tokyo|日本-东京" \
        "Asia/Singapore|新加坡" \
        "America/New_York|美国-纽约" \
        "America/Los_Angeles|美国-洛杉矶" \
        "Europe/London|英国-伦敦" \
        "UTC|协调世界时" \
        "返回|Back")

    if [[ -z "$tz_choice" ]] || [[ "${tz_choice%%|*}" == "返回" ]]; then
        return 0
    fi

    local timezone="${tz_choice%%|*}"

    if command_exists timedatectl; then
        spinner "设置时区..." timedatectl set-timezone "$timezone"
    else
        ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
        echo "$timezone" > /etc/timezone
    fi

    # 同步硬件时钟
    if command_exists hwclock; then
        hwclock --systohc 2>/dev/null
    fi

    print_success "时区已设置为: $timezone"
    log_info "时区设置为: $timezone"
    pause
}

# Swap 管理
swap_manager() {
    require_root || return 1

    print_title "Swap 管理"

    # 显示当前 Swap 状态
    local swap_total=$(free -h | awk '/^Swap:/{print $2}')
    local swap_used=$(free -h | awk '/^Swap:/{print $3}')
    print_info "当前 Swap: 总计 $swap_total / 已用 $swap_used"

    local choice
    choice=$(interactive_menu "选择操作" \
        "创建 Swap 文件|创建新的 Swap" \
        "删除 Swap 文件|移除 Swap" \
        "查看 Swap 状态|详情" \
        "返回|Back")

    case "${choice%%|*}" in
        "创建 Swap 文件")
            create_swap
            ;;
        "删除 Swap 文件")
            remove_swap
            ;;
        "查看 Swap 状态")
            show_swap_status
            ;;
        "返回"|"")
            return 0
            ;;
    esac
}

# 创建 Swap
create_swap() {
    local swap_file="/swapfile"

    if [ -f "$swap_file" ]; then
        print_warn "Swap 文件已存在: $swap_file"
        if ! confirm "是否删除并重新创建？" "n"; then
            pause
            return 0
        fi
        swapoff "$swap_file" 2>/dev/null
        rm -f "$swap_file"
    fi

    local size_choice
    size_choice=$(interactive_menu "选择 Swap 大小" \
        "1G|1GB" \
        "2G|2GB" \
        "4G|4GB" \
        "8G|8GB" \
        "自定义|输入自定义大小")
    
    local size="${size_choice%%|*}"
    
    if [[ "$size" == "自定义" ]]; then
        size=$(input "Swap 大小 (如 2G)")
    fi

    if [ -z "$size" ]; then
        print_warn "已取消"
        pause
        return 0
    fi

    spinner "创建 Swap 文件 ($size)..." fallocate -l "$size" "$swap_file" || dd if=/dev/zero of="$swap_file" bs=1M count=$(echo "$size" | sed 's/G/*1024/;s/M//' | bc) status=none

    chmod 600 "$swap_file"
    spinner "格式化 Swap..." mkswap "$swap_file"
    spinner "启用 Swap..." swapon "$swap_file"

    # 添加到 fstab
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
    fi

    print_success "Swap 创建成功！大小: $size"
    log_info "创建 Swap: $size"
    pause
}

# 删除 Swap
remove_swap() {
    local swap_file="/swapfile"

    if [ ! -f "$swap_file" ]; then
        print_error "Swap 文件不存在"
        pause
        return 1
    fi

    if ! confirm_danger "确认删除 Swap 文件？"; then
        pause
        return 0
    fi

    spinner "禁用 Swap..." swapoff "$swap_file"
    rm -f "$swap_file"

    # 从 fstab 移除
    sed -i "\|$swap_file|d" /etc/fstab

    print_success "Swap 已删除"
    log_info "删除 Swap"
    pause
}

# 显示 Swap 状态
show_swap_status() {
    print_title "Swap 状态"

    echo ""
    free -h | head -1
    free -h | grep Swap
    echo ""

    if [ -f /proc/swaps ]; then
        print_info "活动的 Swap 设备:"
        cat /proc/swaps
    fi

    pause
}

# 显示系统信息
show_system_info() {
    print_title "系统信息"

    local hostname=$(hostname)
    local os_name=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
    local kernel=$(uname -r)
    local arch=$(uname -m)
    local uptime=$(uptime -p 2>/dev/null || uptime)
    local cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs)
    local cpu_cores=$(nproc)
    local mem_total=$(free -h | awk '/^Mem:/{print $2}')
    local mem_used=$(free -h | awk '/^Mem:/{print $3}')
    local disk_usage=$(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')
    local local_ip=$(get_local_ip)

    echo ""
    echo -e " ${BOLD}${BLUE}┌─────────────────────────────────────────────────────────────┐${PLAIN}"
    echo -e " ${BOLD}${BLUE}│${PLAIN}                        系统信息                             ${BOLD}${BLUE}│${PLAIN}"
    echo -e " ${BOLD}${BLUE}├─────────────────────────────────────────────────────────────┤${PLAIN}"
    printf " ${BOLD}${BLUE}│${PLAIN}  主机名:    ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$hostname"
    printf " ${BOLD}${BLUE}│${PLAIN}  操作系统:  ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$os_name"
    printf " ${BOLD}${BLUE}│${PLAIN}  内核版本:  ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$kernel"
    printf " ${BOLD}${BLUE}│${PLAIN}  系统架构:  ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$arch"
    printf " ${BOLD}${BLUE}│${PLAIN}  运行时间:  ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$uptime"
    echo -e " ${BOLD}${BLUE}├─────────────────────────────────────────────────────────────┤${PLAIN}"
    printf " ${BOLD}${BLUE}│${PLAIN}  CPU:       ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "${cpu_model:0:45}"
    printf " ${BOLD}${BLUE}│${PLAIN}  CPU 核心:  ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$cpu_cores"
    printf " ${BOLD}${BLUE}│${PLAIN}  内存:      ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$mem_used / $mem_total"
    printf " ${BOLD}${BLUE}│${PLAIN}  磁盘 (/):  ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$disk_usage"
    printf " ${BOLD}${BLUE}│${PLAIN}  本机 IP:   ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$local_ip"
    echo -e " ${BOLD}${BLUE}└─────────────────────────────────────────────────────────────┘${PLAIN}"

    pause
}

# 执行插件
plugin_main
