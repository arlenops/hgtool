#!/bin/bash
# ============================================================
# 系统自检插件
# ============================================================

PLUGIN_NAME="系统自检·····健康度检测与报告"
PLUGIN_DESC="磁盘、时区、防火墙、流量等健康检测"

# 直接运行，无二级菜单
plugin_main() {
    print_title "系统健康自检"

    local report=""
    local warnings=0
    local errors=0
    local passed=0

    echo ""
    print_info "正在进行系统健康检测..."
    echo ""

    # ========== 1. 磁盘使用量检测 ==========
    print_subtitle "磁盘使用量"
    local disk_warning=0
    while IFS= read -r line; do
        local mount=$(echo "$line" | awk '{print $6}')
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')

        if [ "$usage" -ge 90 ]; then
            echo -e "  ${RED}[危险]${PLAIN} $mount: ${usage}% (已用 $used / 总共 $size)"
            ((errors++))
            disk_warning=1
        elif [ "$usage" -ge 80 ]; then
            echo -e "  ${YELLOW}[警告]${PLAIN} $mount: ${usage}% (已用 $used / 总共 $size)"
            ((warnings++))
            disk_warning=1
        else
            echo -e "  ${GREEN}[正常]${PLAIN} $mount: ${usage}% (已用 $used / 总共 $size)"
            ((passed++))
        fi
    done < <(df -h | grep -E "^/dev" | awk '{print $0}')

    if [ $disk_warning -eq 0 ]; then
        report+="磁盘使用: 正常\n"
    else
        report+="磁盘使用: 存在告警\n"
    fi

    # ========== 2. 空闲磁盘检测 ==========
    echo ""
    print_subtitle "空闲磁盘检测"
    local free_disks=$(lsblk -dpno NAME,SIZE,TYPE | grep "disk" | while read disk size type; do
        # 检查是否有分区
        partitions=$(lsblk -no NAME "$disk" 2>/dev/null | wc -l)
        if [ "$partitions" -le 1 ]; then
            echo "$disk ($size)"
        fi
    done)

    if [ -n "$free_disks" ]; then
        echo -e "  ${CYAN}[信息]${PLAIN} 发现空闲磁盘:"
        echo "$free_disks" | while read line; do
            echo -e "         $line"
        done
        report+="空闲磁盘: 有未使用的磁盘\n"
    else
        echo -e "  ${GREEN}[正常]${PLAIN} 无空闲未分区磁盘"
        report+="空闲磁盘: 无\n"
        ((passed++))
    fi

    # ========== 3. 时区检测 ==========
    echo ""
    print_subtitle "时区检测"
    local timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "未知")
    local current_time=$(date "+%Y-%m-%d %H:%M:%S")

    if [[ "$timezone" == "Asia/Shanghai" ]] || [[ "$timezone" == "Asia/Hong_Kong" ]]; then
        echo -e "  ${GREEN}[正常]${PLAIN} 时区: $timezone"
        echo -e "  ${GREEN}[正常]${PLAIN} 当前时间: $current_time"
        report+="时区设置: $timezone (正常)\n"
        ((passed++))
    elif [[ "$timezone" == "UTC" ]]; then
        echo -e "  ${YELLOW}[警告]${PLAIN} 时区: $timezone (建议设置为本地时区)"
        echo -e "  ${YELLOW}[警告]${PLAIN} 当前时间: $current_time"
        report+="时区设置: $timezone (建议修改)\n"
        ((warnings++))
    else
        echo -e "  ${CYAN}[信息]${PLAIN} 时区: $timezone"
        echo -e "  ${CYAN}[信息]${PLAIN} 当前时间: $current_time"
        report+="时区设置: $timezone\n"
        ((passed++))
    fi

    # ========== 4. 防火墙检测 ==========
    echo ""
    print_subtitle "防火墙状态"
    local fw_status="未知"
    local fw_type=""

    if command_exists firewall-cmd; then
        fw_type="firewalld"
        if systemctl is-active firewalld &>/dev/null; then
            fw_status="运行中"
            echo -e "  ${GREEN}[正常]${PLAIN} Firewalld: 运行中"
            ((passed++))
        else
            fw_status="未启用"
            echo -e "  ${YELLOW}[警告]${PLAIN} Firewalld: 未启用"
            ((warnings++))
        fi
    elif command_exists ufw; then
        fw_type="ufw"
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            fw_status="运行中"
            echo -e "  ${GREEN}[正常]${PLAIN} UFW: 运行中"
            ((passed++))
        else
            fw_status="未启用"
            echo -e "  ${YELLOW}[警告]${PLAIN} UFW: 未启用"
            ((warnings++))
        fi
    elif command_exists iptables; then
        fw_type="iptables"
        local rules=$(iptables -L -n 2>/dev/null | wc -l)
        if [ "$rules" -gt 8 ]; then
            fw_status="已配置规则"
            echo -e "  ${GREEN}[正常]${PLAIN} iptables: 已配置规则"
            ((passed++))
        else
            fw_status="无规则"
            echo -e "  ${YELLOW}[警告]${PLAIN} iptables: 无自定义规则"
            ((warnings++))
        fi
    else
        echo -e "  ${RED}[危险]${PLAIN} 未检测到防火墙"
        fw_status="未安装"
        ((errors++))
    fi
    report+="防火墙($fw_type): $fw_status\n"

    # ========== 5. 网络流量分析 ==========
    echo ""
    print_subtitle "网络流量分析"

    # 获取主网卡
    local main_iface=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -n "$main_iface" ]; then
        # 获取两次采样计算带宽
        local rx1=$(cat /sys/class/net/$main_iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx1=$(cat /sys/class/net/$main_iface/statistics/tx_bytes 2>/dev/null || echo 0)
        sleep 1
        local rx2=$(cat /sys/class/net/$main_iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx2=$(cat /sys/class/net/$main_iface/statistics/tx_bytes 2>/dev/null || echo 0)

        local rx_speed=$(( (rx2 - rx1) * 8 / 1024 / 1024 ))  # Mbps
        local tx_speed=$(( (tx2 - tx1) * 8 / 1024 / 1024 ))  # Mbps

        echo -e "  ${CYAN}[信息]${PLAIN} 网卡: $main_iface"

        # 下载带宽检测
        if [ "$rx_speed" -ge 50 ]; then
            echo -e "  ${RED}[异常]${PLAIN} 下载带宽: ${rx_speed} Mbps (超过50Mbps)"
            ((errors++))
            report+="下载带宽: ${rx_speed} Mbps (异常)\n"
        else
            echo -e "  ${GREEN}[正常]${PLAIN} 下载带宽: ${rx_speed} Mbps"
            ((passed++))
            report+="下载带宽: ${rx_speed} Mbps (正常)\n"
        fi

        # 上传带宽检测
        if [ "$tx_speed" -ge 50 ]; then
            echo -e "  ${RED}[异常]${PLAIN} 上传带宽: ${tx_speed} Mbps (超过50Mbps)"
            ((errors++))
            report+="上传带宽: ${tx_speed} Mbps (异常)\n"
        else
            echo -e "  ${GREEN}[正常]${PLAIN} 上传带宽: ${tx_speed} Mbps"
            ((passed++))
            report+="上传带宽: ${tx_speed} Mbps (正常)\n"
        fi
    else
        echo -e "  ${YELLOW}[警告]${PLAIN} 无法检测网络接口"
        report+="网络流量: 检测失败\n"
        ((warnings++))
    fi

    # ========== 6. 内存使用检测 ==========
    echo ""
    print_subtitle "内存使用"
    local mem_info=$(free -m | awk '/^Mem:/{print $2,$3,$4}')
    local mem_total=$(echo $mem_info | awk '{print $1}')
    local mem_used=$(echo $mem_info | awk '{print $2}')
    local mem_free=$(echo $mem_info | awk '{print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))

    if [ "$mem_percent" -ge 90 ]; then
        echo -e "  ${RED}[危险]${PLAIN} 内存使用: ${mem_percent}% (${mem_used}MB / ${mem_total}MB)"
        ((errors++))
        report+="内存使用: ${mem_percent}% (危险)\n"
    elif [ "$mem_percent" -ge 80 ]; then
        echo -e "  ${YELLOW}[警告]${PLAIN} 内存使用: ${mem_percent}% (${mem_used}MB / ${mem_total}MB)"
        ((warnings++))
        report+="内存使用: ${mem_percent}% (警告)\n"
    else
        echo -e "  ${GREEN}[正常]${PLAIN} 内存使用: ${mem_percent}% (${mem_used}MB / ${mem_total}MB)"
        ((passed++))
        report+="内存使用: ${mem_percent}% (正常)\n"
    fi

    # ========== 7. 系统负载检测 ==========
    echo ""
    print_subtitle "系统负载"
    local load=$(cat /proc/loadavg | awk '{print $1,$2,$3}')
    local load1=$(echo $load | awk '{print $1}')
    local load5=$(echo $load | awk '{print $2}')
    local load15=$(echo $load | awk '{print $3}')
    local cpu_cores=$(nproc 2>/dev/null || echo 1)
    local load_percent=$(echo "$load1 $cpu_cores" | awk '{printf "%.0f", ($1/$2)*100}')

    if [ "$load_percent" -ge 100 ]; then
        echo -e "  ${RED}[危险]${PLAIN} 负载: $load1 $load5 $load15 (${load_percent}% / ${cpu_cores}核)"
        ((errors++))
        report+="系统负载: ${load_percent}% (危险)\n"
    elif [ "$load_percent" -ge 80 ]; then
        echo -e "  ${YELLOW}[警告]${PLAIN} 负载: $load1 $load5 $load15 (${load_percent}% / ${cpu_cores}核)"
        ((warnings++))
        report+="系统负载: ${load_percent}% (警告)\n"
    else
        echo -e "  ${GREEN}[正常]${PLAIN} 负载: $load1 $load5 $load15 (${load_percent}% / ${cpu_cores}核)"
        ((passed++))
        report+="系统负载: ${load_percent}% (正常)\n"
    fi

    # ========== 生成报告 ==========
    echo ""
    separator 65 ─
    echo ""
    print_subtitle "健康检测报告"

    local total=$((passed + warnings + errors))
    local health_score=$((passed * 100 / total))

    echo -e "  检测项目: $total 项"
    echo -e "  ${GREEN}通过: $passed${PLAIN}  ${YELLOW}警告: $warnings${PLAIN}  ${RED}异常: $errors${PLAIN}"
    echo ""

    if [ $errors -gt 0 ]; then
        echo -e "  健康评分: ${RED}${BOLD}$health_score 分${PLAIN} (需要立即处理)"
    elif [ $warnings -gt 0 ]; then
        echo -e "  健康评分: ${YELLOW}${BOLD}$health_score 分${PLAIN} (建议优化)"
    else
        echo -e "  健康评分: ${GREEN}${BOLD}$health_score 分${PLAIN} (系统健康)"
    fi

    echo ""
    separator 65 ─
    echo ""
    echo -e "  ${DIM}报告详情:${PLAIN}"
    echo -e "$report" | while read line; do
        [ -n "$line" ] && echo -e "  $line"
    done

    pause
}

plugin_main
