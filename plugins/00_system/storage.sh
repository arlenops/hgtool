#!/bin/bash
# ============================================================
# 存储管理插件
# 包含: 挂载新磁盘、分区扩容
# ============================================================

PLUGIN_NAME="存储管理"
PLUGIN_DESC="磁盘挂载、分区扩容"

# 插件主入口
plugin_main() {
    while true; do
        print_title "存储管理"

        # 使用交互式菜单
        local choice
        choice=$(interactive_menu "请选择操作" \
            "挂载新磁盘|格式化并挂载新磁盘" \
            "分区扩容|扩展现有分区" \
            "磁盘信息|查看磁盘状态" \
            "返回主菜单|Back")

        case "${choice%%|*}" in
            "挂载新磁盘")
                mount_new_disk
                ;;
            "分区扩容")
                resize_partition
                ;;
            "磁盘信息")
                show_disk_info
                ;;
            "返回主菜单"|"")
                return 0
                ;;
        esac
    done
}

# 挂载新磁盘
mount_new_disk() {
    require_root || return 1

    print_title "挂载新磁盘"

    # 获取未挂载的磁盘列表
    print_info "扫描可用磁盘..."
    echo ""

    # 显示所有磁盘
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | column -t
    echo ""

    # 获取未挂载的磁盘
    local -a disk_items=()
    while IFS= read -r line; do
        disk_items+=("$line")
    done < <(lsblk -dpno NAME,SIZE,TYPE | grep "disk" | awk '{print $1" ("$2")"}')

    if [ ${#disk_items[@]} -eq 0 ]; then
        print_error "未找到可用磁盘"
        pause
        return 1
    fi

    disk_items+=("返回|Back")

    # 选择磁盘
    local selected_disk
    selected_disk=$(interactive_menu "选择要操作的磁盘" "${disk_items[@]}")
    
    if [[ -z "$selected_disk" ]] || [[ "$selected_disk" == "返回|Back" ]]; then
        return 0
    fi

    local disk_path=$(echo "$selected_disk" | awk '{print $1}')

    # 危险确认
    echo ""
    echo -e " ${RED}${BOLD}⚠ 警告：格式化将删除 $disk_path 上的所有数据！${PLAIN}"
    
    if ! confirm_danger "确认格式化磁盘 $disk_path ？"; then
        pause
        return 0
    fi

    # 选择文件系统
    local fs_choice
    fs_choice=$(interactive_menu "选择文件系统" \
        "ext4|推荐，兼容性好" \
        "xfs|高性能" \
        "btrfs|现代文件系统")
    
    local fs_type="${fs_choice%%|*}"
    [ -z "$fs_type" ] && fs_type="ext4"

    # 输入挂载点
    local mount_point
    mount_point=$(input "挂载点" "/data")
    mount_point="${mount_point:-/data}"

    # 创建分区
    spinner "创建分区表..." parted -s "$disk_path" mklabel gpt
    spinner "创建分区..." parted -s "$disk_path" mkpart primary "$fs_type" 0% 100%

    # 获取分区名
    local partition="${disk_path}1"
    if [[ "$disk_path" == *"nvme"* ]]; then
        partition="${disk_path}p1"
    fi

    sleep 1  # 等待内核识别分区

    # 格式化
    spinner "格式化分区 ($fs_type)..." mkfs."$fs_type" -f "$partition" 2>/dev/null || mkfs."$fs_type" "$partition"

    # 创建挂载点
    mkdir -p "$mount_point"

    # 挂载
    spinner "挂载分区..." mount "$partition" "$mount_point"

    # 获取 UUID
    local uuid=$(blkid -s UUID -o value "$partition")

    # 添加到 fstab
    if ! grep -q "$uuid" /etc/fstab; then
        backup_file /etc/fstab
        echo "UUID=$uuid $mount_point $fs_type defaults 0 2" >> /etc/fstab
    fi

    print_success "磁盘挂载成功！"
    print_info "分区: $partition"
    print_info "挂载点: $mount_point"
    print_info "文件系统: $fs_type"

    log_info "挂载磁盘: $disk_path -> $mount_point ($fs_type)"

    pause
}

# 分区扩容
resize_partition() {
    require_root || return 1

    print_title "分区扩容"

    print_info "此功能用于云服务器磁盘扩容后的分区扩展"
    echo ""

    # 显示当前磁盘信息
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | column -t
    echo ""

    # 获取可扩容的分区
    local -a part_items=()
    while IFS= read -r line; do
        part_items+=("$line")
    done < <(lsblk -pno NAME,SIZE,MOUNTPOINT | grep -E "part|lvm" | awk '{print $1" "$2" "$3}')

    if [ ${#part_items[@]} -eq 0 ]; then
        print_error "未找到可扩容的分区"
        pause
        return 1
    fi

    part_items+=("返回|Back")

    # 选择分区
    local selected_part
    selected_part=$(interactive_menu "选择要扩容的分区" "${part_items[@]}")
    
    if [[ -z "$selected_part" ]] || [[ "$selected_part" == "返回|Back" ]]; then
        return 0
    fi

    local partition=$(echo "$selected_part" | awk '{print $1}')
    local mount_point=$(echo "$selected_part" | awk '{print $3}')

    # 获取磁盘设备
    local disk=$(echo "$partition" | sed 's/[0-9]*$//' | sed 's/p$//')
    local part_num=$(echo "$partition" | grep -oE '[0-9]+$')

    print_info "磁盘: $disk"
    print_info "分区: $partition (分区号: $part_num)"
    print_info "挂载点: $mount_point"

    if ! confirm "确认扩容分区 $partition ？"; then
        print_warn "已取消"
        pause
        return 0
    fi

    # 检查是否安装 growpart
    if ! command_exists growpart; then
        print_info "安装 growpart..."
        local pkg_mgr=$(get_pkg_manager)
        case "$pkg_mgr" in
            apt)
                apt-get install -y cloud-guest-utils >/dev/null 2>&1
                ;;
            yum|dnf)
                $pkg_mgr install -y cloud-utils-growpart >/dev/null 2>&1
                ;;
        esac
    fi

    # 扩展分区
    spinner "扩展分区..." growpart "$disk" "$part_num"

    # 获取文件系统类型
    local fs_type=$(blkid -s TYPE -o value "$partition")

    # 扩展文件系统
    case "$fs_type" in
        ext4|ext3|ext2)
            spinner "扩展文件系统 (ext4)..." resize2fs "$partition"
            ;;
        xfs)
            if [ -n "$mount_point" ]; then
                spinner "扩展文件系统 (xfs)..." xfs_growfs "$mount_point"
            else
                print_error "XFS 分区需要先挂载才能扩容"
                pause
                return 1
            fi
            ;;
        btrfs)
            if [ -n "$mount_point" ]; then
                spinner "扩展文件系统 (btrfs)..." btrfs filesystem resize max "$mount_point"
            fi
            ;;
        *)
            print_error "不支持的文件系统: $fs_type"
            pause
            return 1
            ;;
    esac

    print_success "分区扩容完成！"

    # 显示新的大小
    echo ""
    df -h "$partition" 2>/dev/null || lsblk "$partition"

    log_info "分区扩容: $partition"

    pause
}

# 显示磁盘信息
show_disk_info() {
    print_title "磁盘信息"

    # 磁盘列表
    print_subtitle "磁盘列表"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null | column -t | while IFS= read -r line; do
        echo -e "   ${CYAN}${line}${PLAIN}"
    done
    echo ""

    # 磁盘使用情况
    print_subtitle "磁盘使用情况"
    df -h 2>/dev/null | grep -E "^Filesystem|^文件系统|^/dev" | column -t | while IFS= read -r line; do
        echo -e "   ${CYAN}${line}${PLAIN}"
    done
    echo ""

    pause
}

# 执行插件
plugin_main
