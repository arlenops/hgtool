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
        hg_title "网络安全"

        local choice=$(hg_choose "请选择操作" \
            "🔐 修改 SSH 端口" \
            "🛡️ 防火墙管理" \
            "🌐 网络信息" \
            "🔙 返回主菜单")

        case "$choice" in
            "🔐 修改 SSH 端口")
                change_ssh_port
                ;;
            "🛡️ 防火墙管理")
                firewall_manager
                ;;
            "🌐 网络信息")
                show_network_info
                ;;
            "🔙 返回主菜单"|"")
                return 0
                ;;
        esac
    done
}

# 修改 SSH 端口
change_ssh_port() {
    require_root || return 1

    hg_title "修改 SSH 端口"

    local sshd_config="/etc/ssh/sshd_config"

    if [ ! -f "$sshd_config" ]; then
        hg_error "SSH 配置文件不存在"
        return 1
    fi

    # 获取当前端口
    local current_port=$(grep -E "^Port|^#Port" "$sshd_config" | head -1 | awk '{print $2}')
    current_port=${current_port:-22}

    hg_info "当前 SSH 端口: $current_port"

    # 输入新端口
    local new_port=$(hg_input "新 SSH 端口" "1024-65535" "$current_port")

    # 验证端口
    if [ -z "$new_port" ]; then
        hg_warn "已取消"
        return 0
    fi

    if ! is_valid_port "$new_port"; then
        hg_error "无效的端口号: $new_port (有效范围: 1-65535)"
        return 1
    fi

    if [ "$new_port" -lt 1024 ] && [ "$new_port" -ne 22 ]; then
        hg_warn "端口 $new_port 是特权端口，建议使用 1024 以上的端口"
        if ! hg_confirm "确认继续？"; then
            return 0
        fi
    fi

    # 检查端口占用
    if port_in_use "$new_port"; then
        hg_error "端口 $new_port 已被占用"
        return 1
    fi

    if ! hg_confirm "确认将 SSH 端口从 $current_port 修改为 $new_port ？"; then
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
    hg_info "配置防火墙规则..."
    allow_port "$new_port" "tcp"

    # 重启 SSH
    hg_spin "重启 SSH 服务..." systemctl restart sshd || service sshd restart

    hg_success "SSH 端口已修改为: $new_port"

    "$GUM" style \
        --foreground "$WARNING_COLOR" \
        --bold \
        --border "rounded" \
        --padding "1" \
        "⚠️  重要提醒：

  1. 新的连接命令: ssh -p $new_port user@host
  2. 请保持当前会话，新开终端测试连接
  3. 确认可以连接后再关闭当前会话"

    log_info "SSH 端口修改: $current_port -> $new_port"

    hg_pause
}

# 防火墙管理
firewall_manager() {
    require_root || return 1

    hg_title "防火墙管理"

    # 检测防火墙类型
    local fw_type=""
    if command_exists firewall-cmd; then
        fw_type="firewalld"
    elif command_exists ufw; then
        fw_type="ufw"
    elif command_exists iptables; then
        fw_type="iptables"
    else
        hg_error "未检测到防火墙"
        return 1
    fi

    hg_info "防火墙类型: $fw_type"

    local choice=$(hg_choose "选择操作" \
        "➕ 开放端口" \
        "➖ 关闭端口" \
        "📋 查看规则" \
        "🔄 重载规则" \
        "🔙 返回")

    case "$choice" in
        "➕ 开放端口")
            local port=$(hg_input "端口号" "如: 80 或 8080-8090")
            local protocol=$(hg_choose "协议" "tcp" "udp" "tcp/udp")

            if [ -n "$port" ]; then
                allow_port "$port" "$protocol"
                hg_success "已开放端口: $port/$protocol"
            fi
            ;;
        "➖ 关闭端口")
            local port=$(hg_input "端口号" "如: 80")
            local protocol=$(hg_choose "协议" "tcp" "udp")

            if [ -n "$port" ]; then
                deny_port "$port" "$protocol"
                hg_success "已关闭端口: $port/$protocol"
            fi
            ;;
        "📋 查看规则")
            show_firewall_rules "$fw_type"
            ;;
        "🔄 重载规则")
            reload_firewall "$fw_type"
            hg_success "防火墙规则已重载"
            ;;
        "🔙 返回"|"")
            return 0
            ;;
    esac

    hg_pause
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
        # 保存规则
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

    echo ""
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
    hg_title "网络信息"

    local local_ip=$(get_local_ip)
    local public_ip=$(get_public_ip)
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns=$(cat /etc/resolv.conf 2>/dev/null | grep nameserver | awk '{print $2}' | head -3 | tr '\n' ' ')

    "$GUM" style \
        --border "rounded" \
        --border-foreground "$PRIMARY_COLOR" \
        --padding "1" \
        "🌐 网络信息

  本机 IP:    $local_ip
  公网 IP:    $public_ip
  默认网关:   $gateway
  DNS 服务器: $dns"

    echo ""
    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "网络接口:"
    ip -br addr 2>/dev/null || ifconfig -a 2>/dev/null | grep -E "^[a-z]|inet "

    echo ""
    "$GUM" style --foreground "$PRIMARY_COLOR" --bold "监听端口:"
    ss -tuln 2>/dev/null | head -20 || netstat -tuln | head -20

    hg_pause
}

# 执行插件
plugin_main
