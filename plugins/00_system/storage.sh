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

        echo -e " ${BOLD}请选择操作：${PLAIN}"
        echo ""
        echo -e "   ${CYAN}❖${PLAIN}  挂载新磁盘              格式化并挂载新磁盘          ${BOLD}1)${PLAIN}"
        echo -e "   ${CYAN}❖${PLAIN}  分区扩容                扩展现有分区                ${BOLD}2)${PLAIN}"
        echo -e "   ${CYAN}❖${PLAIN}  磁盘信息                查看磁盘状态                ${BOLD}3)${PLAIN}"
        echo -e "   ${CYAN}❖${PLAIN}  返回主菜单              Back                        ${BOLD}0)${PLAIN}"
        echo ""
        echo -ne " ${BOLD}└─ 请输入序号 [ 0-3 ]：${PLAIN}"
        
        local choice
        read -r choice

        case "$choice" in
            1)
                mount_new_disk
                ;;
            2)
                resize_partition
                ;;
            3)
                show_disk_info
                ;;
            0|"")
                return 0
                ;;
            *)
                print_warn "无效选项，请重新选择"
                sleep 1
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
    local disks=$(lsblk -dpno NAME,SIZE,TYPE | grep "disk" | awk '{print $1" ("$2")"}')

    if [ -z "$disks" ]; then
        print_error "未找到可用磁盘"
        pause
        return 1
    fi

    # 选择磁盘
    print_subtitle "可用磁盘"
    local -a disk_list=()
    local i=1
    while IFS= read -r line; do
        echo -e "   ${CYAN}❖${PLAIN}  $line  ${BOLD}${i})${PLAIN}"
        disk_list+=("$line")
        ((i++))
    done <<< "$disks"
    
    echo ""
    echo -ne " ${BOLD}└─ 请选择磁盘 [ 1-$((i-1)) ]：${PLAIN}"
    local disk_choice
    read -r disk_choice
    
    if [[ -z "$disk_choice" ]] || ! [[ "$disk_choice" =~ ^[0-9]+$ ]] || [ "$disk_choice" -lt 1 ] || [ "$disk_choice" -gt $((i-1)) ]; then
        print_warn "已取消"
        pause
        return 0
    fi
    
    local selected_disk="${disk_list[$((disk_choice-1))]}"
    local disk_path=$(echo "$selected_disk" | awk '{print $1}')

    # 危险确认
    echo ""
    echo -e " ${RED}${BOLD}⚠ 警告：格式化将删除 $disk_path 上的所有数据！${PLAIN}"
    
    if ! confirm_danger "确认格式化磁盘 $disk_path ？"; then
        pause
        return 0
    fi

    # 选择文件系统
    print_subtitle "选择文件系统"
    echo -e "   ${CYAN}❖${PLAIN}  ext4 (推荐)                               ${BOLD}1)${PLAIN}"
    echo -e "   ${CYAN}❖${PLAIN}  xfs                                       ${BOLD}2)${PLAIN}"
    echo -e "   ${CYAN}❖${PLAIN}  btrfs                                     ${BOLD}3)${PLAIN}"
    echo ""
    echo -ne " ${BOLD}└─ 请选择 [ 1-3 ]：${PLAIN}"
    local fs_choice
    read -r fs_choice
    
    local fs_type="ext4"
    case "$fs_choice" in
        2) fs_type="xfs" ;;
        3) fs_type="btrfs" ;;
    esac

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

    # 选择要扩容的分区
    local partitions=$(lsblk -pno NAME,SIZE,MOUNTPOINT | grep -E "part|lvm" | awk '{print $1" "$2" "$3}')

    if [ -z "$partitions" ]; then
        print_error "未找到可扩容的分区"
        pause
        return 1
    fi

    print_subtitle "可扩容分区"
    local -a part_list=()
    local i=1
    while IFS= read -r line; do
        echo -e "   ${CYAN}❖${PLAIN}  $line  ${BOLD}${i})${PLAIN}"
        part_list+=("$line")
        ((i++))
    done <<< "$partitions"
    
    echo ""
    echo -ne " ${BOLD}└─ 请选择分区 [ 1-$((i-1)) ]：${PLAIN}"
    local part_choice
    read -r part_choice
    
    if [[ -z "$part_choice" ]] || ! [[ "$part_choice" =~ ^[0-9]+$ ]] || [ "$part_choice" -lt 1 ] || [ "$part_choice" -gt $((i-1)) ]; then
        print_warn "已取消"
        pause
        return 0
    fi

    local selected=$(echo "${part_list[$((part_choice-1))]}")
    local partition=$(echo "$selected" | awk '{print $1}')
    local mount_point=$(echo "$selected" | awk '{print $3}')

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
