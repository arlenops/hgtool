#!/bin/bash
# ============================================================
# 宝塔面板管理插件
# ============================================================

PLUGIN_NAME="宝塔管理·····安装、卸载、密码重置"
PLUGIN_DESC="宝塔面板安装、卸载、管理"

plugin_main() {
    while true; do
        print_title "宝塔面板管理"

        local status="未安装"
        [ -f /usr/bin/bt ] && status="已安装"
        print_info "宝塔面板: $status"

        interactive_menu "安装宝塔·····一键安装宝塔面板" "卸载宝塔·····完全卸载宝塔面板" "忘记密码·····重置面板密码" "修改端口·····更改面板访问端口" "面板信息·····查看面板详情" "返回主菜单"

        case "$MENU_RESULT" in
            "安装宝塔·····一键安装宝塔面板") install_bt ;;
            "卸载宝塔·····完全卸载宝塔面板") uninstall_bt ;;
            "忘记密码·····重置面板密码") reset_bt_password ;;
            "修改端口·····更改面板访问端口") change_bt_port ;;
            "面板信息·····查看面板详情") show_bt_info ;;
            "返回主菜单"|"") return 0 ;;
        esac
    done
}

install_bt() {
    require_root || return 1
    print_title "安装宝塔面板"

    if [ -f /usr/bin/bt ]; then
        print_warn "宝塔面板已安装"
        pause
        return 0
    fi

    interactive_menu "正式版·····稳定版本推荐" "开心版·····解锁专业版功能" "返回"
    [[ -z "$MENU_RESULT" ]] || [[ "$MENU_RESULT" == "返回" ]] && return 0

    local install_url=""
    case "$MENU_RESULT" in
        "正式版·····稳定版本推荐")
            install_url="https://download.bt.cn/install/install_lts.sh"
            ;;
        "开心版·····解锁专业版功能")
            install_url="https://io.bt.sb/install/install_panel.sh"
            ;;
    esac

    confirm "确认安装宝塔面板？" || { pause; return 0; }

    print_info "正在下载安装脚本..."
    if curl -sSO "$install_url"; then
        local script_name=$(basename "$install_url")
        chmod +x "$script_name"
        print_info "开始安装，请按提示操作..."
        bash "$script_name"
        rm -f "$script_name"
    else
        print_error "下载安装脚本失败"
    fi
    pause
}

uninstall_bt() {
    require_root || return 1
    print_title "卸载宝塔面板"

    if [ ! -f /usr/bin/bt ]; then
        print_error "宝塔面板未安装"
        pause
        return 1
    fi

    confirm_danger "确认完全卸载宝塔面板？所有数据将被删除！" || { pause; return 0; }

    print_info "正在卸载宝塔面板..."

    # 停止宝塔服务
    spinner "停止宝塔服务..." bt stop

    # 下载并执行官方卸载脚本
    if curl -sSO https://download.bt.cn/install/bt-uninstall.sh; then
        chmod +x bt-uninstall.sh
        bash bt-uninstall.sh
        rm -f bt-uninstall.sh
        print_success "宝塔面板已卸载"
    else
        # 手动卸载
        print_info "使用手动方式卸载..."
        rm -rf /www/server/panel
        rm -rf /www/server/data
        rm -f /usr/bin/bt
        rm -f /etc/init.d/bt
        print_success "宝塔面板已卸载"
    fi
    pause
}

reset_bt_password() {
    require_root || return 1
    print_title "重置宝塔密码"

    if [ ! -f /usr/bin/bt ]; then
        print_error "宝塔面板未安装"
        pause
        return 1
    fi

    interactive_menu "重置为随机密码·····系统生成新密码" "自定义密码·····设置指定密码" "查看当前账号·····显示用户名密码" "返回"

    case "$MENU_RESULT" in
        "重置为随机密码·····系统生成新密码")
            print_info "正在重置密码..."
            bt default
            ;;
        "自定义密码·····设置指定密码")
            local new_pass=$(input "请输入新密码")
            if [ -n "$new_pass" ]; then
                echo "$new_pass" | bt 6
                print_success "密码已修改"
            fi
            ;;
        "查看当前账号·····显示用户名密码")
            bt default
            ;;
    esac
    pause
}

change_bt_port() {
    require_root || return 1
    print_title "修改宝塔端口"

    if [ ! -f /usr/bin/bt ]; then
        print_error "宝塔面板未安装"
        pause
        return 1
    fi

    # 获取当前端口
    local current_port=$(cat /www/server/panel/data/port.pl 2>/dev/null || echo "8888")
    print_info "当前端口: $current_port"

    local new_port=$(input "新端口" "$current_port")
    [ -z "$new_port" ] && { pause; return 0; }

    # 验证端口
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        print_error "无效端口号"
        pause
        return 1
    fi

    confirm "确认修改端口为 $new_port ？" || { pause; return 0; }

    echo "$new_port" | bt 8

    # 开放防火墙端口
    allow_port "$new_port" "tcp"

    print_success "端口已修改为: $new_port"
    echo -e " ${YELLOW}新访问地址: http://服务器IP:$new_port${PLAIN}"
    pause
}

show_bt_info() {
    print_title "宝塔面板信息"

    if [ ! -f /usr/bin/bt ]; then
        print_error "宝塔面板未安装"
        pause
        return 1
    fi

    bt default
    echo ""
    print_subtitle "面板状态"
    bt status
    pause
}

plugin_main
