#!/bin/bash
# ============================================================
# hgtool - 黑果云运维工具箱
# 模仿 LinuxMirrors 风格重构
#
# 特性:
#   - 零依赖：无需外部工具
#   - 模块化：插件式架构
#   - 美观：纯 ANSI 终端 UI
# ============================================================

# 版本号
VERSION="1.0.0"

# 1. 定义工作目录
ROOT_DIR=$(cd "$(dirname "$0")"; pwd)
export ROOT_DIR
export VERSION

# 2. 引用核心库
source "$ROOT_DIR/lib/deps.sh"
source "$ROOT_DIR/lib/utils.sh"

# 3. 环境自检
check_and_install_dependencies

# 4. 加载 UI 库
source "$ROOT_DIR/lib/ui.sh"

# 5. 权限检查
check_root_privileges

# ============================================================
# 主菜单逻辑
# ============================================================

# 生成插件列表
generate_plugin_list() {
    local -a names=()
    local -a descs=()
    local -a files=()
    
    # 扫描插件目录
    for category_dir in "$ROOT_DIR/plugins"/*; do
        if [ -d "$category_dir" ]; then
            for plugin_file in "$category_dir"/*.sh; do
                if [ -f "$plugin_file" ]; then
                    local name=$(grep -m1 "^PLUGIN_NAME=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
                    local desc=$(grep -m1 "^PLUGIN_DESC=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
                    
                    if [ -n "$name" ]; then
                        names+=("$name")
                        descs+=("$desc")
                        files+=("$plugin_file")
                    fi
                fi
            done
        fi
    done
    
    # 返回结果（使用全局变量）
    PLUGIN_NAMES=("${names[@]}")
    PLUGIN_DESCS=("${descs[@]}")
    PLUGIN_FILES=("${files[@]}")
}

# 主菜单
main_menu() {
    # 生成插件列表
    generate_plugin_list
    
    local count=${#PLUGIN_NAMES[@]}
    
    while true; do
        # 显示 Banner
        print_banner
        
        # 构建菜单项
        local -a menu_items=()
        for i in "${!PLUGIN_NAMES[@]}"; do
            menu_items+=("${PLUGIN_NAMES[$i]}")
        done
        menu_items+=("退出程序")
        
        # 使用交互式菜单
        interactive_menu "${menu_items[@]}"
        
        # 如果取消返回空，刷新菜单
        if [[ -z "$MENU_RESULT" ]]; then
            continue
        fi
        
        # 处理选择
        if [[ "$MENU_RESULT" == "退出程序" ]]; then
            clear
            echo ""
            echo -e " ${GREEN}${BOLD}👋 感谢使用 hgtool！再见！${PLAIN}"
            echo ""
            exit 0
        else
            # 查找对应的插件文件
            for i in "${!PLUGIN_NAMES[@]}"; do
                if [[ "${PLUGIN_NAMES[$i]}" == "$MENU_RESULT" ]]; then
                    local plugin_file="${PLUGIN_FILES[$i]}"
                    if [ -f "$plugin_file" ]; then
                        source "$plugin_file"
                    fi
                    break
                fi
            done
        fi
    done
}

# ============================================================
# 命令行参数处理
# ============================================================

show_help() {
    echo ""
    echo -e " ${BOLD}hgtool - 黑果云运维工具箱 v${VERSION}${PLAIN}"
    echo ""
    echo " 用法:"
    echo "   ./hgtool.sh [选项]"
    echo ""
    echo " 选项:"
    echo "   -h, --help      显示帮助信息"
    echo "   -v, --version   显示版本信息"
    echo "   -l, --list      列出所有可用插件"
    echo ""
    echo " 示例:"
    echo "   ./hgtool.sh           # 启动交互式菜单"
    echo "   sudo ./hgtool.sh      # 以 root 权限运行（推荐）"
    echo ""
}

show_version() {
    echo "hgtool v${VERSION}"
}

list_plugins() {
    generate_plugin_list
    
    echo ""
    echo -e " ${BOLD}可用插件列表：${PLAIN}"
    echo ""
    
    for i in "${!PLUGIN_NAMES[@]}"; do
        echo -e "   ${CYAN}❖${PLAIN}  ${PLUGIN_NAMES[$i]} - ${DIM}${PLUGIN_DESCS[$i]}${PLAIN}"
    done
    echo ""
}

# 解析命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -v|--version)
        show_version
        exit 0
        ;;
    -l|--list)
        list_plugins
        exit 0
        ;;
    "")
        # 无参数，启动主菜单
        ;;
    *)
        print_error "未知选项: $1"
        echo "使用 ./hgtool.sh --help 查看帮助"
        exit 1
        ;;
esac

# 6. 进入主循环
main_menu
