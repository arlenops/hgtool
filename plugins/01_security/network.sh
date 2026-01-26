#!/bin/bash
# ============================================================
# 网络安全插件
# ============================================================

PLUGIN_NAME="网络管理·····SSH端口、防火墙"
PLUGIN_DESC="SSH端口、防火墙管理"

plugin_main() {
    while true; do
        print_title "网络管理"

        interactive_menu "修改 SSH 端口·····更改远程连接端口" "防火墙管理·····端口开放与关闭" "网络信息·····查看网络详情" "返回主菜单"

        case "$MENU_RESULT" in
            "修改 SSH 端口·····更改远程连接端口") change_ssh_port ;;
            "防火墙管理·····端口开放与关闭") firewall_manager ;;
            "网络信息·····查看网络详情") show_network_info ;;
            "返回主菜单"|"") return 0 ;;
        esac
    done
}

change_ssh_port() {
    require_root || return 1
    print_title "修改 SSH 端口"
    local sshd_config="/etc/ssh/sshd_config"
    [ ! -f "$sshd_config" ] && { print_error "SSH 配置不存在"; pause; return 1; }

    local current_port=$(grep -E "^Port|^#Port" "$sshd_config" | head -1 | awk '{print $2}')
    print_info "当前端口: ${current_port:-22}"

    local new_port=$(input "新端口" "${current_port:-22}")
    [ -z "$new_port" ] && { pause; return 0; }
    is_valid_port "$new_port" || { print_error "无效端口"; pause; return 1; }
    port_in_use "$new_port" && { print_error "端口已占用"; pause; return 1; }

    confirm "确认修改为 $new_port ？" || { pause; return 0; }

    backup_file "$sshd_config"
    grep -qE "^Port " "$sshd_config" && sed -i "s/^Port .*/Port $new_port/" "$sshd_config" || echo "Port $new_port" >> "$sshd_config"
    allow_port "$new_port" "tcp"
    spinner "重启 SSH..." systemctl restart sshd || service sshd restart

    print_success "SSH 端口已改为: $new_port"
    echo -e " ${YELLOW}新连接命令: ssh -p $new_port user@host${PLAIN}"
    pause
}

firewall_manager() {
    require_root || return 1
    print_title "防火墙管理"

    local fw_type=""
    command_exists firewall-cmd && fw_type="firewalld"
    command_exists ufw && fw_type="ufw"
    command_exists iptables && fw_type="iptables"
    [ -z "$fw_type" ] && { print_error "未检测到防火墙"; pause; return 1; }
    print_info "防火墙: $fw_type"

    interactive_menu "开放端口·····允许端口通信" "关闭端口·····禁止端口通信" "查看规则·····显示防火墙规则" "返回"

    case "$MENU_RESULT" in
        "开放端口·····允许端口通信")
            local port=$(input "端口号")
            [ -n "$port" ] && { allow_port "$port" "tcp"; print_success "已开放: $port"; }
            ;;
        "关闭端口·····禁止端口通信")
            local port=$(input "端口号")
            [ -n "$port" ] && { deny_port "$port" "tcp"; print_success "已关闭: $port"; }
            ;;
        "查看规则·····显示防火墙规则")
            case "$fw_type" in
                firewalld) firewall-cmd --list-all ;;
                ufw) ufw status verbose ;;
                iptables) iptables -L -n ;;
            esac
            ;;
    esac
    pause
}

allow_port() {
    local port="$1" proto="${2:-tcp}"
    command_exists firewall-cmd && { firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1; }
    command_exists ufw && ufw allow "${port}/${proto}" >/dev/null 2>&1
}

deny_port() {
    local port="$1" proto="${2:-tcp}"
    command_exists firewall-cmd && { firewall-cmd --permanent --remove-port="${port}/${proto}" >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1; }
    command_exists ufw && ufw deny "${port}/${proto}" >/dev/null 2>&1
}

show_network_info() {
    print_title "网络信息"
    echo " 本机 IP:  $(get_local_ip)"
    echo " 公网 IP:  $(get_public_ip)"
    echo " 网关:     $(ip route | grep default | awk '{print $3}' | head -1)"
    echo ""
    print_subtitle "监听端口"
    ss -tuln 2>/dev/null | head -15
    pause
}

plugin_main
