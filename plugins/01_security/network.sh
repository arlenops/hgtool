#!/bin/bash
# ============================================================
# 网络安全插件
# 包含: SSH端口修改、防火墙管理
# ============================================================

PLUGIN_NAME="网络安全"
PLUGIN_DESC="SSH端口、防火墙管理"

# 插件主入口
plugin_main() {
    while true; do
        print_title "网络安全"

        echo -e " ${BOLD}请选择操作：${PLAIN}"
        echo ""
        echo -e "   ${CYAN}❖${PLAIN}  修改 SSH 端口           安全加固                    ${BOLD}1)${PLAIN}"
        echo -e "   ${CYAN}❖${PLAIN}  防火墙管理              端口开放/关闭               ${BOLD}2)${PLAIN}"
        echo -e "   ${CYAN}❖${PLAIN}  网络信息                查看网络状态                ${BOLD}3)${PLAIN}"
        echo -e "   ${CYAN}❖${PLAIN}  返回主菜单              Back                        ${BOLD}0)${PLAIN}"
        echo ""
        echo -ne " ${BOLD}└─ 请输入序号 [ 0-3 ]：${PLAIN}"
        
        local choice
        read -r choice

        case "$choice" in
            1)
                change_ssh_port
                ;;
            2)
                firewall_manager
                ;;
            3)
                show_network_info
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

# 修改 SSH 端口
change_ssh_port() {
    require_root || return 1

    print_title "修改 SSH 端口"

    local sshd_config="/etc/ssh/sshd_config"

    if [ ! -f "$sshd_config" ]; then
        print_error "SSH 配置文件不存在"
        pause
        return 1
    fi

    # 获取当前端口
    local current_port=$(grep -E "^Port|^#Port" "$sshd_config" | head -1 | awk '{print $2}')
    current_port=${current_port:-22}

    print_info "当前 SSH 端口: $current_port"

    # 输入新端口
    local new_port
    new_port=$(input "新 SSH 端口 (1024-65535)" "$current_port")

    # 验证端口
    if [ -z "$new_port" ]; then
        print_warn "已取消"
        pause
        return 0
    fi

    if ! is_valid_port "$new_port"; then
        print_error "无效的端口号: $new_port (有效范围: 1-65535)"
        pause
        return 1
    fi

    if [ "$new_port" -lt 1024 ] && [ "$new_port" -ne 22 ]; then
        print_warn "端口 $new_port 是特权端口，建议使用 1024 以上的端口"
        if ! confirm "确认继续？"; then
            pause
            return 0
        fi
    fi

    # 检查端口占用
    if port_in_use "$new_port"; then
        print_error "端口 $new_port 已被占用"
        pause
        return 1
    fi

    if ! confirm "确认将 SSH 端口从 $current_port 修改为 $new_port ？"; then
        pause
        return 0
    fi

    # 备份配置
    backup_file "$sshd_config"

    # 修改配置
    if grep -qE "^Port " "$sshd_config"; then
        sed -i "s/^Port .*/Port $new_port/" "$sshd_config"
    elif grep -qE "^#Port " "$sshd_config"; then
        sed -i "s/^#Port .*/Port $new_port/" "$sshd_config"
    else
        echo "Port $new_port" >> "$sshd_config"
    fi

    # 配置防火墙
    print_info "配置防火墙规则..."
    allow_port "$new_port" "tcp"

    # 重启 SSH
    spinner "重启 SSH 服务..." systemctl restart sshd || service sshd restart

    print_success "SSH 端口已修改为: $new_port"

    echo ""
    echo -e " ${YELLOW}${BOLD}⚠ 重要提醒：${PLAIN}"
    echo -e "   1. 新的连接命令: ${CYAN}ssh -p $new_port user@host${PLAIN}"
    echo -e "   2. 请保持当前会话，新开终端测试连接"
    echo -e "   3. 确认可以连接后再关闭当前会话"

    log_info "SSH 端口修改: $current_port -> $new_port"

    pause
}

# 防火墙管理
firewall_manager() {
    require_root || return 1

    print_title "防火墙管理"

    # 检测防火墙类型
    local fw_type=""
    if command_exists firewall-cmd; then
        fw_type="firewalld"
    elif command_exists ufw; then
        fw_type="ufw"
    elif command_exists iptables; then
        fw_type="iptables"
    else
        print_error "未检测到防火墙"
        pause
        return 1
    fi

    print_info "防火墙类型: $fw_type"
    echo ""

    echo -e " ${BOLD}选择操作：${PLAIN}"
    echo ""
    echo -e "   ${CYAN}❖${PLAIN}  开放端口                                    ${BOLD}1)${PLAIN}"
    echo -e "   ${CYAN}❖${PLAIN}  关闭端口                                    ${BOLD}2)${PLAIN}"
    echo -e "   ${CYAN}❖${PLAIN}  查看规则                                    ${BOLD}3)${PLAIN}"
    echo -e "   ${CYAN}❖${PLAIN}  重载规则                                    ${BOLD}4)${PLAIN}"
    echo -e "   ${CYAN}❖${PLAIN}  返回                                        ${BOLD}0)${PLAIN}"
    echo ""
    echo -ne " ${BOLD}└─ 请选择 [ 0-4 ]：${PLAIN}"
    
    local choice
    read -r choice

    case "$choice" in
        1)
            local port=$(input "端口号" "如: 80 或 8080-8090")
            if [ -n "$port" ]; then
                echo -e "\n ${BOLD}选择协议：${PLAIN}"
                echo -e "   ${CYAN}❖${PLAIN}  tcp       ${BOLD}1)${PLAIN}"
                echo -e "   ${CYAN}❖${PLAIN}  udp       ${BOLD}2)${PLAIN}"
                echo -e "   ${CYAN}❖${PLAIN}  tcp/udp   ${BOLD}3)${PLAIN}"
                echo -ne " ${BOLD}└─ 请选择 [ 1-3 ]：${PLAIN}"
                local proto_choice
                read -r proto_choice
                local protocol="tcp"
                case "$proto_choice" in
                    2) protocol="udp" ;;
                    3) protocol="tcp/udp" ;;
                esac
                allow_port "$port" "$protocol"
                print_success "已开放端口: $port/$protocol"
            fi
            ;;
        2)
            local port=$(input "端口号" "如: 80")
            if [ -n "$port" ]; then
                echo -e "\n ${BOLD}选择协议：${PLAIN}"
                echo -e "   ${CYAN}❖${PLAIN}  tcp       ${BOLD}1)${PLAIN}"
                echo -e "   ${CYAN}❖${PLAIN}  udp       ${BOLD}2)${PLAIN}"
                echo -ne " ${BOLD}└─ 请选择 [ 1-2 ]：${PLAIN}"
                local proto_choice
                read -r proto_choice
                local protocol="tcp"
                [ "$proto_choice" = "2" ] && protocol="udp"
                deny_port "$port" "$protocol"
                print_success "已关闭端口: $port/$protocol"
            fi
            ;;
        3)
            show_firewall_rules "$fw_type"
            ;;
        4)
            reload_firewall "$fw_type"
            print_success "防火墙规则已重载"
            ;;
        0|"")
            return 0
            ;;
    esac

    pause
}

# 开放端口
allow_port() {
    local port="$1"
    local protocol="${2:-tcp}"

    if command_exists firewall-cmd; then
        firewall-cmd --permanent --add-port="${port}/${protocol}" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command_exists ufw; then
        ufw allow "${port}/${protocol}" >/dev/null 2>&1
    elif command_exists iptables; then
        iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT
        if command_exists netfilter-persistent; then
            netfilter-persistent save >/dev/null 2>&1
        elif [ -f /etc/sysconfig/iptables ]; then
            iptables-save > /etc/sysconfig/iptables
        fi
    fi

    log_info "开放端口: $port/$protocol"
}

# 关闭端口
deny_port() {
    local port="$1"
    local protocol="${2:-tcp}"

    if command_exists firewall-cmd; then
        firewall-cmd --permanent --remove-port="${port}/${protocol}" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command_exists ufw; then
        ufw deny "${port}/${protocol}" >/dev/null 2>&1
    elif command_exists iptables; then
        iptables -D INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null
    fi

    log_info "关闭端口: $port/$protocol"
}

# 显示防火墙规则
show_firewall_rules() {
    local fw_type="$1"

    print_subtitle "防火墙规则"
    case "$fw_type" in
        firewalld)
            firewall-cmd --list-all
            ;;
        ufw)
            ufw status verbose
            ;;
        iptables)
            iptables -L -n --line-numbers
            ;;
    esac
    echo ""
}

# 重载防火墙
reload_firewall() {
    local fw_type="$1"

    case "$fw_type" in
        firewalld)
            firewall-cmd --reload
            ;;
        ufw)
            ufw reload
            ;;
        iptables)
            # iptables 不需要重载
            ;;
    esac
}

# 显示网络信息
show_network_info() {
    print_title "网络信息"

    local local_ip=$(get_local_ip)
    local public_ip=$(get_public_ip)
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns=$(cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2}' | head -3 | tr '\n' ' ')

    echo ""
    echo -e " ${BOLD}${BLUE}┌─────────────────────────────────────────────────────────────┐${PLAIN}"
    echo -e " ${BOLD}${BLUE}│${PLAIN}                        网络信息                             ${BOLD}${BLUE}│${PLAIN}"
    echo -e " ${BOLD}${BLUE}├─────────────────────────────────────────────────────────────┤${PLAIN}"
    printf " ${BOLD}${BLUE}│${PLAIN}  本机 IP:    ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$local_ip"
    printf " ${BOLD}${BLUE}│${PLAIN}  公网 IP:    ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$public_ip"
    printf " ${BOLD}${BLUE}│${PLAIN}  默认网关:   ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$gateway"
    printf " ${BOLD}${BLUE}│${PLAIN}  DNS 服务器: ${GREEN}%-47s${PLAIN}${BOLD}${BLUE}│${PLAIN}\n" "$dns"
    echo -e " ${BOLD}${BLUE}└─────────────────────────────────────────────────────────────┘${PLAIN}"

    print_subtitle "网络接口"
    ip -br addr 2>/dev/null || ifconfig -a 2>/dev/null | grep -E "^[a-z]|inet "

    print_subtitle "监听端口 (前20)"
    ss -tuln 2>/dev/null | head -20 || netstat -tuln | head -20

    pause
}

# 执行插件
plugin_main
