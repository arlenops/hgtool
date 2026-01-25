#!/bin/bash
# ============================================================
# hgtool - 黑果云运维工具箱
# 核心理念：颜值即正义，效率即生命
#
# 特性:
#   - 零依赖：首次运行自动下载 gum/fzf
#   - 模块化：插件式架构，易于扩展
#   - 美观：全程使用 gum/fzf 渲染 UI
# ============================================================

set -e

# 版本信息
VERSION="1.0.0"

# 1. 定义工作目录
ROOT_DIR=$(cd "$(dirname "$0")"; pwd)
export ROOT_DIR

# 2. 引用核心库
source "$ROOT_DIR/lib/deps.sh"
source "$ROOT_DIR/lib/utils.sh"

# 3. 环境自检 - 检查并下载 gum/fzf
check_and_install_dependencies

# 4. 现在可以加载 UI 库了（依赖 gum）
source "$ROOT_DIR/lib/ui.sh"

# 5. 权限检查
check_root_privileges

# 6. 显示欢迎界面
hg_banner

# ============================================================
# 主菜单逻辑
# ============================================================

# 生成插件菜单项
generate_menu_items() {
    local items=()

    # 扫描插件目录
    for category_dir in "$ROOT_DIR/plugins"/*; do
        if [ -d "$category_dir" ]; then
            local category_name=$(basename "$category_dir")

            for plugin_file in "$category_dir"/*.sh; do
                if [ -f "$plugin_file" ]; then
                    # 读取插件名称
                    local plugin_name=$(grep -m1 "^PLUGIN_NAME=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)
                    local plugin_desc=$(grep -m1 "^PLUGIN_DESC=" "$plugin_file" 2>/dev/null | cut -d'"' -f2)

                    if [ -n "$plugin_name" ]; then
                        echo "$plugin_name|$plugin_desc|$plugin_file"
                    fi
                fi
            done
        fi
    done
}

# 格式化菜单显示（表格化对齐）
format_menu_item() {
    local name="$1"
    local desc="$2"

    # 固定列宽的表格化格式：名称(20宽) │ 描述
    printf "  %-14s │ %-s" "$name" "$desc"
}

# 主菜单
main_menu() {
    while true; do
        hg_banner

        # 生成菜单
        local menu_data=$(generate_menu_items)
        local menu_items=()
        local plugin_map=()

        while IFS='|' read -r name desc file; do
            if [ -n "$name" ]; then
                local formatted=$(format_menu_item "$name" "$desc")
                menu_items+=("$formatted")
                plugin_map+=("$file")
            fi
        done <<< "$menu_data"

        # 添加退出选项
        menu_items+=("退出程序")

        # 使用 fzf 显示菜单
        local selected=$(printf '%s\n' "${menu_items[@]}" | fzf_menu_wrapper)

        # 处理选择
        if [ -z "$selected" ] || [ "$selected" = "退出程序" ]; then
            hg_banner
            "$GUM" style \
                --foreground "$ACCENT_COLOR" \
                --bold \
                --border "rounded" \
                --border-foreground "$ACCENT_COLOR" \
                --padding "1 2" \
                --margin "1" \
                --align "center" \
                "👋 感谢使用 hgtool！

再见！"
            exit 0
        fi

        # 查找对应的插件文件
        local idx=0
        for item in "${menu_items[@]}"; do
            if [ "$item" = "$selected" ]; then
                if [ $idx -lt ${#plugin_map[@]} ]; then
                    local plugin_file="${plugin_map[$idx]}"
                    if [ -f "$plugin_file" ]; then
                        # 执行插件
                        source "$plugin_file"
                    fi
                fi
                break
            fi
            ((idx++))
        done
    done
}

# ============================================================
# 命令行参数处理
# ============================================================

show_help() {
    "$GUM" style \
        --border "rounded" \
        --border-foreground "$PRIMARY_COLOR" \
        --padding "1" \
        "hgtool - 黑果云运维工具箱 v$VERSION

用法:
  ./hgtool.sh [选项]

选项:
  -h, --help      显示帮助信息
  -v, --version   显示版本信息
  -l, --list      列出所有可用插件

示例:
  ./hgtool.sh           # 启动交互式菜单
  sudo ./hgtool.sh      # 以 root 权限运行（推荐）"
}

show_version() {
    "$GUM" style \
        --foreground "$PRIMARY_COLOR" \
        --bold \
        "hgtool v$VERSION"
}

list_plugins() {
    "$GUM" style \
        --foreground "$PRIMARY_COLOR" \
        --bold \
        "可用插件列表:"

    echo ""
    generate_menu_items | while IFS='|' read -r name desc file; do
        if [ -n "$name" ]; then
            echo "  • $name - $desc"
        fi
    done
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
        hg_error "未知选项: $1"
        echo "使用 ./hgtool.sh --help 查看帮助"
        exit 1
        ;;
esac

# 7. 进入主循环
main_menu
