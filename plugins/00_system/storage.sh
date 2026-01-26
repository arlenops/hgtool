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
        hg_title "存储管理"

        local choice=$(hg_choose "请选择操作" \
            "挂载新磁盘" \
            "分区扩容" \
            "磁盘信息" \
            "返回主菜单")

        case "$choice" in
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

    hg_title "挂载新磁盘"

    # 获取未挂载的磁盘列表
    hg_info "扫描可用磁盘..."

    # 显示所有磁盘
    echo ""
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | "$GUM" style --foreground "$INFO_COLOR"
    echo ""

    # 获取未挂载的磁盘（排除已挂载和系统盘）
    local disks=$(lsblk -dpno NAME,SIZE,TYPE | grep "disk" | awk '{print $1" ("$2")"}')

    if [ -z "$disks" ]; then
        hg_error "未找到可用磁盘"
        return 1
    fi

    # 选择磁盘
    local selected_disk=$(echo "$disks" | fzf_menu_wrapper)

    if [ -z "$selected_disk" ]; then
        hg_warn "已取消"
        return 0
    fi

    local disk_path=$(echo "$selected_disk" | awk '{print $1}')

    # 检查磁盘是否已有分区
    local partitions=$(lsblk -pno NAME "$disk_path" | tail -n +2)

    if [ -n "$partitions" ]; then
        hg_warn "该磁盘已有分区:"
        echo "$partitions"
        echo ""
    fi

    # 危险确认
    "$GUM" style \
        --foreground "$ERROR_COLOR" \
        --bold \
        --border "rounded" \
        --border-foreground "$ERROR_COLOR" \
        --padding "1" \
        "⚠️  警告：格式化将删除 $disk_path 上的所有数据！"

    if ! hg_confirm_danger "确认格式化磁盘 $disk_path ？"; then
        hg_warn "已取消"
        return 0
    fi

    # 二次确认
    local confirm_text=$(hg_input "请输入 YES 确认" "输入 YES 继续")
    if [ "$confirm_text" != "YES" ]; then
        hg_warn "已取消"
        return 0
    fi

    # 选择文件系统
    local fs_type=$(hg_choose "选择文件系统" \
        "ext4 (推荐)" \
        "xfs" \
        "btrfs")

    fs_type=$(echo "$fs_type" | awk '{print $1}')

    # 输入挂载点
    local mount_point=$(hg_input "挂载点" "/data")

    if [ -z "$mount_point" ]; then
        mount_point="/data"
    fi

    # 创建分区
    hg_spin "创建分区表..." parted -s "$disk_path" mklabel gpt
    hg_spin "创建分区..." parted -s "$disk_path" mkpart primary "$fs_type" 0% 100%

    # 获取分区名
    local partition="${disk_path}1"
    if [[ "$disk_path" == *"nvme"* ]]; then
        partition="${disk_path}p1"
    fi

    sleep 1  # 等待内核识别分区

    # 格式化
    hg_spin "格式化分区 ($fs_type)..." mkfs."$fs_type" -f "$partition" 2>/dev/null || mkfs."$fs_type" "$partition"

    # 创建挂载点
    mkdir -p "$mount_point"

    # 挂载
    hg_spin "挂载分区..." mount "$partition" "$mount_point"

    # 获取 UUID
    local uuid=$(blkid -s UUID -o value "$partition")

    # 添加到 fstab
    if ! grep -q "$uuid" /etc/fstab; then
        backup_file /etc/fstab
        echo "UUID=$uuid $mount_point $fs_type defaults 0 2" >> /etc/fstab
    fi

    hg_success "磁盘挂载成功！"
    hg_info "分区: $partition"
    hg_info "挂载点: $mount_point"
    hg_info "文件系统: $fs_type"

    log_info "挂载磁盘: $disk_path -> $mount_point ($fs_type)"

    hg_pause
}

# 分区扩容
resize_partition() {
    require_root || return 1

    hg_title "分区扩容"

    hg_info "此功能用于云服务器磁盘扩容后的分区扩展"
    echo ""

    # 显示当前磁盘信息
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | "$GUM" style --foreground "$INFO_COLOR"
    echo ""

    # 选择要扩容的分区
    local partitions=$(lsblk -pno NAME,SIZE,MOUNTPOINT | grep -E "part|lvm" | awk '{print $1" "$2" "$3}')

    if [ -z "$partitions" ]; then
        hg_error "未找到可扩容的分区"
        return 1
    fi

    local selected=$(echo "$partitions" | fzf_menu_wrapper)

    if [ -z "$selected" ]; then
        hg_warn "已取消"
        return 0
    fi

    local partition=$(echo "$selected" | awk '{print $1}')
    local mount_point=$(echo "$selected" | awk '{print $3}')

    # 获取磁盘设备
    local disk=$(echo "$partition" | sed 's/[0-9]*$//' | sed 's/p$//')
    local part_num=$(echo "$partition" | grep -oE '[0-9]+$')

    hg_info "磁盘: $disk"
    hg_info "分区: $partition (分区号: $part_num)"
    hg_info "挂载点: $mount_point"

    if ! hg_confirm "确认扩容分区 $partition ？"; then
        hg_warn "已取消"
        return 0
    fi

    # 检查是否安装 growpart
    if ! command_exists growpart; then
        hg_info "安装 growpart..."
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
    hg_spin "扩展分区..." growpart "$disk" "$part_num"

    # 获取文件系统类型
    local fs_type=$(blkid -s TYPE -o value "$partition")

    # 扩展文件系统
    case "$fs_type" in
        ext4|ext3|ext2)
            hg_spin "扩展文件系统 (ext4)..." resize2fs "$partition"
            ;;
        xfs)
            if [ -n "$mount_point" ]; then
                hg_spin "扩展文件系统 (xfs)..." xfs_growfs "$mount_point"
            else
                hg_error "XFS 分区需要先挂载才能扩容"
                return 1
            fi
            ;;
        btrfs)
            if [ -n "$mount_point" ]; then
                hg_spin "扩展文件系统 (btrfs)..." btrfs filesystem resize max "$mount_point"
            fi
            ;;
        *)
            hg_error "不支持的文件系统: $fs_type"
            return 1
            ;;
    esac

    hg_success "分区扩容完成！"

    # 显示新的大小
    echo ""
    df -h "$partition" 2>/dev/null || lsblk "$partition"

    log_info "分区扩容: $partition"

    hg_pause
}

# 显示磁盘信息
show_disk_info() {
    hg_title "磁盘信息"

    echo ""
    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "磁盘列表:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID
    echo ""

    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "磁盘使用情况:"
    df -h | grep -E "^/dev|^Filesystem"
    echo ""

    hg_pause
}

# 执行插件
plugin_main
