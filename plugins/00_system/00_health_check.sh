#!/bin/bash
# ============================================================
# 系统自检插件
# ============================================================

PLUGIN_NAME="系统自检·····健康度检测与报告"
PLUGIN_DESC="磁盘、时区、防火墙、流量等健康检测"

# 直接运行，无二级菜单
plugin_main() {
    print_title "系统健康自检"

    local warnings=0
    local errors=0
    local passed=0
    local report=""

    echo ""

    # ========== 1. 磁盘检测 ==========
    while IFS= read -r line; do
        local mount=$(echo "$line" | awk '{print $6}')
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local used=$(echo "$line" | awk '{print $3}')
        local size=$(echo "$line" | awk '{print $2}')

        if [ "$usage" -ge 90 ]; then
            echo -e "  ${RED}[磁盘空间]${PLAIN} $mount ${usage}% (${used}/${size})"
            ((errors++))
        elif [ "$usage" -ge 80 ]; then
            echo -e "  ${YELLOW}[磁盘空间]${PLAIN} $mount ${usage}% (${used}/${size})"
            ((warnings++))
        else
            echo -e "  ${GREEN}[磁盘空间]${PLAIN} $mount ${usage}% (${used}/${size})"
            ((passed++))
        fi
    done < <(df -h | grep -E "^/dev" | awk '{print $0}')

    # ========== 2. 空闲磁盘 ==========
    local free_disk_count=0
    while read disk size type; do
        partitions=$(lsblk -no NAME "$disk" 2>/dev/null | wc -l)
        if [ "$partitions" -le 1 ]; then
            echo -e "  ${CYAN}[空闲磁盘]${PLAIN} $disk ($size) 未使用"
            ((free_disk_count++))
        fi
    done < <(lsblk -dpno NAME,SIZE,TYPE | grep "disk")

    if [ "$free_disk_count" -eq 0 ]; then
        echo -e "  ${GREEN}[空闲磁盘]${PLAIN} 无"
        ((passed++))
    fi

    # ========== 3. 时区检测 ==========
    local timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "未知")
    local current_time=$(date "+%Y-%m-%d %H:%M:%S")

    if [[ "$timezone" == "Asia/Shanghai" ]] || [[ "$timezone" == "Asia/Hong_Kong" ]] || [[ "$timezone" == "Asia/Chongqing" ]]; then
        echo -e "  ${GREEN}[时区检测]${PLAIN} $timezone ($current_time)"
        ((passed++))
    elif [[ "$timezone" == "UTC" ]]; then
        echo -e "  ${YELLOW}[时区检测]${PLAIN} $timezone (建议设为本地时区)"
        ((warnings++))
    else
        echo -e "  ${GREEN}[时区检测]${PLAIN} $timezone ($current_time)"
        ((passed++))
    fi

    # ========== 4. 防火墙检测 ==========
    if command_exists firewall-cmd; then
        if systemctl is-active firewalld &>/dev/null; then
            echo -e "  ${GREEN}[防火墙]${PLAIN} firewalld 运行中"
            ((passed++))
        else
            echo -e "  ${YELLOW}[防火墙]${PLAIN} firewalld 未启用"
            ((warnings++))
        fi
    elif command_exists ufw; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            echo -e "  ${GREEN}[防火墙]${PLAIN} ufw 运行中"
            ((passed++))
        else
            echo -e "  ${YELLOW}[防火墙]${PLAIN} ufw 未启用"
            ((warnings++))
        fi
    elif command_exists iptables; then
        local rules=$(iptables -L -n 2>/dev/null | wc -l)
        if [ "$rules" -gt 8 ]; then
            echo -e "  ${GREEN}[防火墙]${PLAIN} iptables 已配置"
            ((passed++))
        else
            echo -e "  ${YELLOW}[防火墙]${PLAIN} iptables 无规则"
            ((warnings++))
        fi
    else
        echo -e "  ${RED}[防火墙]${PLAIN} 未安装"
        ((errors++))
    fi

    # ========== 5. 网络流量 ==========
    local main_iface=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -n "$main_iface" ]; then
        local rx1=$(cat /sys/class/net/$main_iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx1=$(cat /sys/class/net/$main_iface/statistics/tx_bytes 2>/dev/null || echo 0)
        sleep 1
        local rx2=$(cat /sys/class/net/$main_iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx2=$(cat /sys/class/net/$main_iface/statistics/tx_bytes 2>/dev/null || echo 0)

        local rx_speed=$(( (rx2 - rx1) * 8 / 1024 / 1024 ))
        local tx_speed=$(( (tx2 - tx1) * 8 / 1024 / 1024 ))

        if [ "$rx_speed" -ge 50 ]; then
            echo -e "  ${RED}[下行流量]${PLAIN} ${rx_speed} Mbps (异常)"
            ((errors++))
        else
            echo -e "  ${GREEN}[下行流量]${PLAIN} ${rx_speed} Mbps"
            ((passed++))
        fi

        if [ "$tx_speed" -ge 50 ]; then
            echo -e "  ${RED}[上行流量]${PLAIN} ${tx_speed} Mbps (异常)"
            ((errors++))
        else
            echo -e "  ${GREEN}[上行流量]${PLAIN} ${tx_speed} Mbps"
            ((passed++))
        fi
    else
        echo -e "  ${YELLOW}[网络流量]${PLAIN} 检测失败"
        ((warnings++))
    fi

    # ========== 6. 内存使用 ==========
    local mem_info=$(free -m | awk '/^Mem:/{print $2,$3}')
    local mem_total=$(echo $mem_info | awk '{print $1}')
    local mem_used=$(echo $mem_info | awk '{print $2}')
    local mem_percent=$((mem_used * 100 / mem_total))

    if [ "$mem_percent" -ge 90 ]; then
        echo -e "  ${RED}[内存使用]${PLAIN} ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
        ((errors++))
    elif [ "$mem_percent" -ge 80 ]; then
        echo -e "  ${YELLOW}[内存使用]${PLAIN} ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
        ((warnings++))
    else
        echo -e "  ${GREEN}[内存使用]${PLAIN} ${mem_percent}% (${mem_used}MB/${mem_total}MB)"
        ((passed++))
    fi

    # ========== 7. 系统负载 ==========
    local load1=$(cat /proc/loadavg | awk '{print $1}')
    local cpu_cores=$(nproc 2>/dev/null || echo 1)
    local load_percent=$(echo "$load1 $cpu_cores" | awk '{printf "%.0f", ($1/$2)*100}')

    if [ "$load_percent" -ge 100 ]; then
        echo -e "  ${RED}[系统负载]${PLAIN} ${load1} (${load_percent}%/${cpu_cores}核)"
        ((errors++))
    elif [ "$load_percent" -ge 80 ]; then
        echo -e "  ${YELLOW}[系统负载]${PLAIN} ${load1} (${load_percent}%/${cpu_cores}核)"
        ((warnings++))
    else
        echo -e "  ${GREEN}[系统负载]${PLAIN} ${load1} (${load_percent}%/${cpu_cores}核)"
        ((passed++))
    fi

    # ========== 8. SSH端口 ==========
    local ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    ssh_port=${ssh_port:-22}

    if [ "$ssh_port" -eq 22 ]; then
        echo -e "  ${YELLOW}[SSH端口]${PLAIN} $ssh_port (建议修改默认端口)"
        ((warnings++))
    else
        echo -e "  ${GREEN}[SSH端口]${PLAIN} $ssh_port"
        ((passed++))
    fi

    # ========== 生成报告 ==========
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────${PLAIN}"
    echo ""

    local total=$((passed + warnings + errors))
    local health_score=$((passed * 100 / total))

    echo -e "  检测项: $total  ${GREEN}通过: $passed${PLAIN}  ${YELLOW}警告: $warnings${PLAIN}  ${RED}异常: $errors${PLAIN}"
    echo ""

    if [ $errors -gt 0 ]; then
        echo -e "  健康评分: ${RED}${BOLD}$health_score${PLAIN} 分"
    elif [ $warnings -gt 0 ]; then
        echo -e "  健康评分: ${YELLOW}${BOLD}$health_score${PLAIN} 分"
    else
        echo -e "  健康评分: ${GREEN}${BOLD}$health_score${PLAIN} 分"
    fi

    echo ""
    pause
}

plugin_main
