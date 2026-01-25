#!/bin/bash
# ============================================================
# ui.sh - UI 渲染函数库
# 封装所有颜色、Banner、Gum 组件
# 所有交互必须使用 gum/fzf，禁止 echo 菜单
# ============================================================

# ============================================================
# Tokyo Night 风格配色
# ============================================================
PRIMARY_COLOR="#7aa2f7"    # 柔和蓝紫 - 主色调
SECONDARY_COLOR="#bb9af7"  # 淡紫色 - 次要色调
ACCENT_COLOR="#9ece6a"     # 清新绿 - 成功/强调
WARNING_COLOR="#e0af68"    # 暖橙色 - 警告
ERROR_COLOR="#f7768e"      # 柔红色 - 错误
INFO_COLOR="#7dcfff"       # 天蓝色 - 信息
DIM_COLOR="#565f89"        # 暗灰色 - 次要文字
BG_HIGHLIGHT="#24283b"     # 高亮背景

# 渐变色数组（用于Logo等）
GRADIENT_COLORS=(
    "#bb9af7"  # 紫
    "#7aa2f7"  # 蓝紫
    "#7dcfff"  # 天蓝
    "#7dcfff"  # 天蓝
    "#2ac3de"  # 青
    "#2ac3de"  # 青
)

# gum 路径
GUM="${ROOT_DIR}/bin/gum"
FZF="${ROOT_DIR}/bin/fzf"

# ============================================================
# Banner 和标题
# ============================================================

# 显示标题 Banner（紧凑版）
hg_banner() {
    clear

    # ANSI Shadow风格 ASCII Art Logo
    local logo='██╗  ██╗ ██████╗ ████████╗ ██████╗  ██████╗ ██╗
██║  ██║██╔════╝ ╚══██╔══╝██╔═══██╗██╔═══██╗██║
███████║██║  ███╗   ██║   ██║   ██║██║   ██║██║
██╔══██║██║   ██║   ██║   ██║   ██║██║   ██║██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝╚██████╔╝███████╗
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝
───────────── by HGIDC ─────────────'

    echo ""
    # 先渲染Logo为左对齐块（保持ASCII对齐），再整体居中
    local logo_block=$("$GUM" style --foreground "$PRIMARY_COLOR" --bold --align left "$logo")
    "$GUM" style --align center "$logo_block"

    # 显示系统信息栏
    hg_show_sysinfo
}

# 显示系统信息栏（含资源进度条）
hg_show_sysinfo() {
    local hostname=$(hostname 2>/dev/null || echo "N/A")
    local os_info=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 | cut -d' ' -f1-2 || echo "N/A")
    local local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
    local cpu_cores=$(nproc 2>/dev/null || echo "?")

    # 获取内存使用情况
    local mem_info=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%d %d", $3, $2}')
    local mem_used=$(echo "$mem_info" | cut -d' ' -f1)
    local mem_total=$(echo "$mem_info" | cut -d' ' -f2)
    local mem_percent=$((mem_used * 100 / mem_total))

    # 获取磁盘使用情况（根分区）
    local disk_info=$(df -m / 2>/dev/null | awk 'NR==2{printf "%d %d", $3, $2}')
    local disk_used=$(echo "$disk_info" | cut -d' ' -f1)
    local disk_total=$(echo "$disk_info" | cut -d' ' -f2)
    local disk_percent=$((disk_used * 100 / disk_total))

    # 固定信息行
    "$GUM" style --foreground "$DIM_COLOR" \
        "┌─────────────────────────────────────────────────────────────────┐"
    "$GUM" style --foreground "$DIM_COLOR" \
        "│ $hostname @ $os_info │ IP: $local_ip │ CPU: ${cpu_cores}c"
    "$GUM" style --foreground "$DIM_COLOR" \
        "├─────────────────────────────────────────────────────────────────┤"

    # 内存进度条
    local mem_bar=$(draw_progress_bar $mem_percent 30)
    local mem_color=$(get_usage_color $mem_percent)
    printf "│ MEM: %s %3d%% [%dM/%dM]\n" "$("$GUM" style --foreground "$mem_color" "$mem_bar")" "$mem_percent" "$mem_used" "$mem_total"

    # 磁盘进度条
    local disk_bar=$(draw_progress_bar $disk_percent 30)
    local disk_color=$(get_usage_color $disk_percent)
    printf "│ DISK:%s %3d%% [%dM/%dM]\n" "$("$GUM" style --foreground "$disk_color" "$disk_bar")" "$disk_percent" "$disk_used" "$disk_total"

    "$GUM" style --foreground "$DIM_COLOR" \
        "└─────────────────────────────────────────────────────────────────┘"
    echo ""
}

# 绘制进度条
draw_progress_bar() {
    local percent=$1
    local width=$2
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

# 根据使用率返回颜色
get_usage_color() {
    local percent=$1
    if [ "$percent" -lt 60 ]; then
        echo "$ACCENT_COLOR"  # 绿色
    elif [ "$percent" -lt 80 ]; then
        echo "$WARNING_COLOR"  # 黄色
    else
        echo "$ERROR_COLOR"  # 红色
    fi
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
        "$title"
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
    local select_color="$ACCENT_COLOR"
    if [ "$is_danger" = "true" ]; then
        color="$ERROR_COLOR"
        select_color="$ERROR_COLOR"
    fi

    # 使用 choose 替代 confirm，实现上下选择
    echo ""
    "$GUM" style --foreground "$color" --bold "$msg"
    
    local choice
    choice=$("$GUM" choose \
        --cursor="> " \
        --cursor.foreground "$select_color" \
        --selected.foreground "$select_color" \
        "是" \
        "否")
        
    if [ "$choice" == "是" ]; then
        return 0
    else
        return 1
    fi
}

# 危险确认（红色警告）
hg_confirm_danger() {
    local msg="${1:-危险操作！确认继续？}"
    hg_confirm "$msg" "true"
    return $?
}

# 成功提示
hg_success() {
    local msg="${1:-操作成功！}"
    echo ""
    "$GUM" style \
        --foreground "$ACCENT_COLOR" \
        --bold \
        "[成功] $msg"
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
        "[失败] $msg"
}

# 警告提示
hg_warn() {
    local msg="${1:-警告}"
    echo ""
    "$GUM" style \
        --foreground "$WARNING_COLOR" \
        --bold \
        "[注意] $msg"
}

# 信息提示
hg_info() {
    local msg="${1:-提示}"
    "$GUM" style \
        --foreground "$INFO_COLOR" \
        "[信息] $msg"
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

# ============================================================
# 视觉增强组件
# ============================================================

# 分隔线（可选标题）
hg_divider() {
    local title="${1:-}"
    local width=60
    local line=""
    
    # 生成分隔线字符
    for ((i=0; i<width; i++)); do
        line+="─"
    done
    
    if [ -n "$title" ]; then
        # 带标题的分隔线
        local title_len=${#title}
        local side_len=$(( (width - title_len - 4) / 2 ))
        local left_line=""
        local right_line=""
        for ((i=0; i<side_len; i++)); do
            left_line+="─"
            right_line+="─"
        done
        "$GUM" style --foreground "$DIM_COLOR" "$left_line┤ $title ├$right_line"
    else
        # 纯分隔线
        "$GUM" style --foreground "$DIM_COLOR" "$line"
    fi
}

# 页脚信息（版本、快捷键提示）
hg_footer() {
    local version="${1:-1.0.0}"
    echo ""
    "$GUM" style \
        --foreground "$DIM_COLOR" \
        --italic \
        --align "center" \
        "─────────────────────────────────────────────────────────────
  HGTool v$version  │  ↑↓ 选择  │  Enter 确认  │  ESC 返回  │  q 退出"
}
