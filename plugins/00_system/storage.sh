#!/bin/bash
# ============================================================
# 存储管理插件
# ============================================================

PLUGIN_NAME="存储管理"
PLUGIN_DESC="磁盘挂载、分区扩容"

plugin_main() {
    while true; do
        print_title "存储管理"

        interactive_menu "挂载新磁盘" "分区扩容" "磁盘信息" "返回主菜单"

        case "$MENU_RESULT" in
            "挂载新磁盘") mount_new_disk ;;
            "分区扩容") resize_partition ;;
            "磁盘信息") show_disk_info ;;
            "返回主菜单"|"") return 0 ;;
        esac
    done
}

mount_new_disk() {
    require_root || return 1
    print_title "挂载新磁盘"
    print_info "扫描可用磁盘..."
    echo ""
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | column -t
    echo ""

    local -a disk_items=()
    while IFS= read -r line; do
        disk_items+=("$line")
    done < <(lsblk -dpno NAME,SIZE,TYPE | grep "disk" | awk '{print $1" ("$2")"}')

    if [ ${#disk_items[@]} -eq 0 ]; then
        print_error "未找到可用磁盘"
        pause; return 1
    fi
    disk_items+=("返回")

    interactive_menu "${disk_items[@]}"
    [[ -z "$MENU_RESULT" ]] || [[ "$MENU_RESULT" == "返回" ]] && return 0

    local disk_path=$(echo "$MENU_RESULT" | awk '{print $1}')

    echo -e " ${RED}${BOLD}⚠ 警告：格式化将删除 $disk_path 上的所有数据！${PLAIN}"
    confirm_danger "确认格式化磁盘 $disk_path ？" || { pause; return 0; }

    interactive_menu "ext4" "xfs" "btrfs"
    local fs_type="${MENU_RESULT:-ext4}"

    local mount_point=$(input "挂载点" "/data")
    mount_point="${mount_point:-/data}"

    spinner "创建分区表..." parted -s "$disk_path" mklabel gpt
    spinner "创建分区..." parted -s "$disk_path" mkpart primary "$fs_type" 0% 100%

    local partition="${disk_path}1"
    [[ "$disk_path" == *"nvme"* ]] && partition="${disk_path}p1"
    sleep 1

    spinner "格式化分区..." mkfs."$fs_type" -f "$partition" 2>/dev/null || mkfs."$fs_type" "$partition"
    mkdir -p "$mount_point"
    spinner "挂载分区..." mount "$partition" "$mount_point"

    local uuid=$(blkid -s UUID -o value "$partition")
    grep -q "$uuid" /etc/fstab || { backup_file /etc/fstab; echo "UUID=$uuid $mount_point $fs_type defaults 0 2" >> /etc/fstab; }

    print_success "磁盘挂载成功！挂载点: $mount_point"
    log_info "挂载磁盘: $disk_path -> $mount_point"
    pause
}

resize_partition() {
    require_root || return 1
    print_title "分区扩容"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | column -t
    echo ""

    local -a part_items=()
    while IFS= read -r line; do
        part_items+=("$line")
    done < <(lsblk -pno NAME,SIZE,MOUNTPOINT | grep -E "part|lvm" | awk '{print $1" "$2" "$3}')

    [ ${#part_items[@]} -eq 0 ] && { print_error "未找到可扩容的分区"; pause; return 1; }
    part_items+=("返回")

    interactive_menu "${part_items[@]}"
    [[ -z "$MENU_RESULT" ]] || [[ "$MENU_RESULT" == "返回" ]] && return 0

    local partition=$(echo "$MENU_RESULT" | awk '{print $1}')
    local mount_point=$(echo "$MENU_RESULT" | awk '{print $3}')
    local disk=$(echo "$partition" | sed 's/[0-9]*$//' | sed 's/p$//')
    local part_num=$(echo "$partition" | grep -oE '[0-9]+$')

    confirm "确认扩容分区 $partition ？" || { pause; return 0; }

    command_exists growpart || {
        local pkg_mgr=$(get_pkg_manager)
        case "$pkg_mgr" in
            apt) apt-get install -y cloud-guest-utils >/dev/null 2>&1 ;;
            yum|dnf) $pkg_mgr install -y cloud-utils-growpart >/dev/null 2>&1 ;;
        esac
    }

    spinner "扩展分区..." growpart "$disk" "$part_num"

    local fs_type=$(blkid -s TYPE -o value "$partition")
    case "$fs_type" in
        ext4|ext3|ext2) spinner "扩展文件系统..." resize2fs "$partition" ;;
        xfs) [ -n "$mount_point" ] && spinner "扩展文件系统..." xfs_growfs "$mount_point" ;;
        btrfs) [ -n "$mount_point" ] && spinner "扩展文件系统..." btrfs filesystem resize max "$mount_point" ;;
    esac

    print_success "分区扩容完成！"
    df -h "$partition" 2>/dev/null
    pause
}

show_disk_info() {
    print_title "磁盘信息"
    print_subtitle "磁盘列表"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
    echo ""
    print_subtitle "磁盘使用"
    df -h | grep -E "^Filesystem|^/dev"
    pause
}

plugin_main
