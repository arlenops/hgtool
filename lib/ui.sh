#!/bin/bash
# ============================================================
# ui.sh - UI 渲染函数库
# 封装所有颜色、Banner、Gum 组件
# ============================================================

# 标准配色
PRIMARY_COLOR="#7D56F4"   # 黑果云品牌紫
ACCENT_COLOR="#04B575"    # 成功/安全绿色
WARNING_COLOR="#FFB86C"   # 警告橙色
ERROR_COLOR="#FF5555"     # 错误红色

# 显示标题 Banner
# 用途: 清屏 + ASCII Art + 系统信息栏
hg_banner() {
    clear
    echo ""
    # TODO: 添加 ASCII Art Logo
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║       黑果云运维工具箱 (hgtool)           ║"
    echo "  ║       颜值即正义，效率即生命              ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo ""
}

# 确认操作
# 用途: 弹出 Yes/No 对话框
# 参数: $1 - 提示消息
hg_confirm() {
    local msg="${1:-确认执行此操作？}"
    "$ROOT_DIR/bin/gum" confirm "$msg"
    return $?
}

# 获取用户输入
# 用途: 弹出带占位符的输入框，结果存入变量
# 参数: $1 - 提示信息
hg_input() {
    local prompt="${1:-请输入}"
    "$ROOT_DIR/bin/gum" input --placeholder "$prompt"
}

# 主菜单
# 用途: 调用 fzf 搜索 plugins/ 下的所有脚本并执行
hg_menu() {
    find "$ROOT_DIR/plugins" -name "*.sh" | fzf_menu_wrapper
}

# fzf 菜单包装器
fzf_menu_wrapper() {
    "$ROOT_DIR/bin/fzf" --height=40% --reverse --border
}

# 执行任务（带 Spinner）
# 用途: 显示 Spinner 动画，后台执行命令，完成后打钩
# 参数: $1 - 提示消息, $2 - 要执行的命令
hg_process() {
    local msg="${1:-处理中...}"
    local cmd="${2}"
    "$ROOT_DIR/bin/gum" spin --spinner dot --title "$msg" -- bash -c "$cmd"
}

# 成功提示
# 用途: 绿色大号字体提示
# 参数: $1 - 提示消息
hg_success() {
    local msg="${1:-操作成功！}"
    "$ROOT_DIR/bin/gum" style --foreground "$ACCENT_COLOR" --bold "$msg"
}

# 错误提示
# 用途: 红色边框提示
# 参数: $1 - 提示消息
hg_error() {
    local msg="${1:-操作失败！}"
    "$ROOT_DIR/bin/gum" style --foreground "$ERROR_COLOR" --border "rounded" "$msg"
}

# 暂停等待用户按键
# 参数: $1 - 提示消息
hg_pause() {
    local msg="${1:-按任意键继续...}"
    echo ""
    read -n 1 -s -r -p "$msg"
    echo ""
}
