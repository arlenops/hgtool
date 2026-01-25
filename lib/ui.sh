#!/bin/bash
# ============================================================
# ui.sh - UI 渲染函数库
# 封装所有颜色、Banner、Gum 组件
# 所有交互必须使用 gum/fzf，禁止 echo 菜单
# ============================================================

# 标准配色
PRIMARY_COLOR="#7D56F4"   # 黑果云品牌紫
ACCENT_COLOR="#04B575"    # 成功/安全绿色
WARNING_COLOR="#FFB86C"   # 警告橙色
ERROR_COLOR="#FF5555"     # 错误红色
INFO_COLOR="#8BE9FD"      # 信息蓝色

# gum 路径
GUM="${ROOT_DIR}/bin/gum"
FZF="${ROOT_DIR}/bin/fzf"

# ============================================================
# Banner 和标题
# ============================================================

# 显示标题 Banner
hg_banner() {
    clear

    # ASCII Art Logo - 统一每行宽度
    local logo
    logo='██╗  ██╗ ██████╗ ████████╗ ██████╗  ██████╗ ██╗    
██║  ██║██╔════╝ ╚══██╔══╝██╔═══██╗██╔═══██╗██║    
███████║██║  ███╗   ██║   ██║   ██║██║   ██║██║    
██╔══██║██║   ██║   ██║   ██║   ██║██║   ██║██║    
██║  ██║╚██████╔╝   ██║   ╚██████╔╝╚██████╔╝███████╗
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝'

    # 使用 gum style 渲染 ASCII Art Banner
    "$GUM" style \
        --foreground "$PRIMARY_COLOR" \
        --border "rounded" \
        --border-foreground "$PRIMARY_COLOR" \
        --padding "1 2" \
        --margin "1" \
        --align "center" \
        "$logo"

    # 显示系统信息栏
    hg_show_sysinfo
}

# 显示系统信息栏
hg_show_sysinfo() {
    local hostname=$(hostname 2>/dev/null || echo "未知")
    local os_info=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "未知")
    local kernel=$(uname -r 2>/dev/null || echo "未知")
    local local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "未知")
    local cpu_cores=$(nproc 2>/dev/null || echo "?")
    local mem_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "?")

    "$GUM" style \
        --foreground "$INFO_COLOR" \
        --italic \
        "  主机: $hostname | 系统: $os_info | 内核: $kernel
  IP: $local_ip | CPU: ${cpu_cores}核 | 内存: $mem_total"

    echo ""
}

# 显示小标题
hg_title() {
    local title="${1:-操作}"
    echo ""
    "$GUM" style \
        --foreground "$PRIMARY_COLOR" \
        --bold \
        --border "rounded" \
        --border-foreground "$PRIMARY_COLOR" \
        --padding "0 2" \
        "▶ $title"
    echo ""
}

# ============================================================
# 交互组件
# ============================================================

# 确认操作（危险操作用红色）
hg_confirm() {
    local msg="${1:-确认执行此操作？}"
    local is_danger="${2:-false}"

    local color="$PRIMARY_COLOR"
    if [ "$is_danger" = "true" ]; then
        color="$ERROR_COLOR"
    fi

    "$GUM" confirm \
        --prompt.foreground "$color" \
        --selected.background "$color" \
        "$msg"
    return $?
}

# 危险确认（红色警告）
hg_confirm_danger() {
    local msg="${1:-⚠️ 危险操作！确认继续？}"
    "$GUM" confirm \
        --prompt.foreground "$ERROR_COLOR" \
        --selected.background "$ERROR_COLOR" \
        --affirmative "是的，我确认" \
        --negative "取消" \
        "$msg"
    return $?
}

# 获取用户输入
hg_input() {
    local prompt="${1:-请输入}"
    local placeholder="${2:-}"
    local default="${3:-}"

    "$GUM" input \
        --placeholder "$placeholder" \
        --prompt "$prompt: " \
        --prompt.foreground "$PRIMARY_COLOR" \
        --value "$default"
}

# 获取密码输入
hg_password() {
    local prompt="${1:-请输入密码}"

    "$GUM" input \
        --password \
        --prompt "$prompt: " \
        --prompt.foreground "$PRIMARY_COLOR"
}

# 多行文本输入
hg_write() {
    local placeholder="${1:-输入内容...}"

    "$GUM" write \
        --placeholder "$placeholder" \
        --header.foreground "$PRIMARY_COLOR"
}

# 单选菜单
hg_choose() {
    local header="${1:-请选择}"
    shift

    "$GUM" choose \
        --header "$header" \
        --header.foreground "$PRIMARY_COLOR" \
        --cursor.foreground "$PRIMARY_COLOR" \
        --selected.foreground "$ACCENT_COLOR" \
        "$@" || true
}

# 多选菜单
hg_choose_multi() {
    local header="${1:-请选择（空格选中，回车确认）}"
    shift

    "$GUM" choose \
        --no-limit \
        --header "$header" \
        --header.foreground "$PRIMARY_COLOR" \
        --cursor.foreground "$PRIMARY_COLOR" \
        --selected.foreground "$ACCENT_COLOR" \
        "$@"
}

# ============================================================
# fzf 菜单
# ============================================================

# fzf 菜单包装器
fzf_menu_wrapper() {
    "$FZF" \
        --height=60% \
        --layout=reverse \
        --border=rounded \
        --prompt="🔍 搜索: " \
        --pointer="▶" \
        --marker="✓" \
        --header="↑↓选择 / 输入搜索 / ESC退出" \
        --color="fg:#f8f8f2,bg:#282a36,hl:#bd93f9" \
        --color="fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9" \
        --color="info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6" \
        --color="marker:#ff79c6,spinner:#ffb86c,header:#6272a4"
}

# 带预览的 fzf 菜单
fzf_menu_preview() {
    local preview_cmd="${1:-}"

    "$FZF" \
        --height=80% \
        --layout=reverse \
        --border=rounded \
        --prompt="🔍 搜索: " \
        --pointer="▶" \
        --preview="$preview_cmd" \
        --preview-window="right:50%:wrap" \
        --color="fg:#f8f8f2,bg:#282a36,hl:#bd93f9" \
        --color="fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9" \
        --color="info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6"
}

# ============================================================
# 进度和状态
# ============================================================

# 执行任务（带 Spinner）
hg_spin() {
    local msg="${1:-处理中...}"
    shift

    "$GUM" spin \
        --spinner "dot" \
        --spinner.foreground "$PRIMARY_COLOR" \
        --title "$msg" \
        --title.foreground "$PRIMARY_COLOR" \
        -- "$@"
}

# 执行命令并显示进度
hg_process() {
    local msg="${1:-处理中...}"
    local cmd="${2}"

    "$GUM" spin \
        --spinner "dot" \
        --spinner.foreground "$PRIMARY_COLOR" \
        --title "$msg" \
        -- bash -c "$cmd"
}

# ============================================================
# 消息提示
# ============================================================

# 成功提示
hg_success() {
    local msg="${1:-操作成功！}"
    echo ""
    "$GUM" style \
        --foreground "$ACCENT_COLOR" \
        --bold \
        "✓ $msg"
}

# 错误提示
hg_error() {
    local msg="${1:-操作失败！}"
    echo ""
    "$GUM" style \
        --foreground "$ERROR_COLOR" \
        --bold \
        --border "rounded" \
        --border-foreground "$ERROR_COLOR" \
        --padding "0 1" \
        "✗ $msg"
}

# 警告提示
hg_warn() {
    local msg="${1:-警告}"
    echo ""
    "$GUM" style \
        --foreground "$WARNING_COLOR" \
        --bold \
        "⚠ $msg"
}

# 信息提示
hg_info() {
    local msg="${1:-提示}"
    "$GUM" style \
        --foreground "$INFO_COLOR" \
        "ℹ $msg"
}

# 格式化输出表格
hg_table() {
    "$GUM" table \
        --border.foreground "$PRIMARY_COLOR" \
        --header.foreground "$PRIMARY_COLOR" \
        --cell.foreground "#f8f8f2"
}

# ============================================================
# 其他工具
# ============================================================

# 暂停等待用户按键
hg_pause() {
    local msg="${1:-按任意键继续...}"
    echo ""
    "$GUM" style --foreground "$INFO_COLOR" --italic "$msg"
    read -n 1 -s -r
    echo ""
}

# 显示帮助信息
hg_help() {
    local title="${1:-帮助}"
    local content="${2:-}"

    "$GUM" style \
        --border "rounded" \
        --border-foreground "$INFO_COLOR" \
        --padding "1" \
        --margin "1" \
        "$title

$content"
}

# 过滤输入（实时搜索）
hg_filter() {
    local placeholder="${1:-输入关键词过滤...}"

    "$GUM" filter \
        --placeholder "$placeholder" \
        --prompt.foreground "$PRIMARY_COLOR" \
        --indicator.foreground "$ACCENT_COLOR"
}

# 加入多个文本
hg_join() {
    "$GUM" join --vertical "$@"
}

# 格式化 Markdown
hg_format() {
    "$GUM" format -t markdown
}
