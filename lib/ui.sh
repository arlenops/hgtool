#!/bin/bash
# ============================================================
# ui.sh - UI 渲染函数库（纯 ANSI 版本）
# 模仿 LinuxMirrors 代码风格
# 无外部依赖，使用纯 ANSI 转义码
# ============================================================

# ============================================================
# 颜色定义（ANSI 转义码）
# ============================================================
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PURPLE='\033[35m'
CYAN='\033[36m'
WHITE='\033[37m'
PLAIN='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# 状态图标
SUCCESS="${GREEN}✔${PLAIN}"
ERROR="${RED}✘${PLAIN}"
WARN="${YELLOW}!${PLAIN}"
INFO="${CYAN}ℹ${PLAIN}"
WORKING="${CYAN}◉${PLAIN}"

# ============================================================
# 基础输出函数
# ============================================================

# 打印成功消息
print_success() {
    echo -e " ${SUCCESS} ${GREEN}$1${PLAIN}"
}

# 打印错误消息
print_error() {
    echo -e " ${ERROR} ${RED}$1${PLAIN}"
}

# 打印警告消息
print_warn() {
    echo -e " ${WARN} ${YELLOW}$1${PLAIN}"
}

# 打印信息消息
print_info() {
    echo -e " ${INFO} ${CYAN}$1${PLAIN}"
}

# 打印工作中状态
print_working() {
    echo -e " ${WORKING} $1"
}

# ============================================================
# 分隔线和边框
# ============================================================

# 打印分隔线
separator() {
    local width=${1:-65}
    local char=${2:-─}
    local line=""
    for ((i=0; i<width; i++)); do
        line+="$char"
    done
    echo -e "${DIM}${line}${PLAIN}"
}

# 打印标题（带边框）
print_title() {
    local title="$1"
    local width=65
    
    clear
    echo ""
    echo -e "${BLUE}╔$(separator $((width-2)) ═)╗${PLAIN}"
    
    # 计算标题居中
    local title_len=${#title}
    local padding=$(( (width - 2 - title_len) / 2 ))
    local left_pad=""
    local right_pad=""
    for ((i=0; i<padding; i++)); do
        left_pad+=" "
        right_pad+=" "
    done
    # 补齐奇数长度
    if (( (width - 2 - title_len) % 2 == 1 )); then
        right_pad+=" "
    fi
    
    echo -e "${BLUE}║${PLAIN}${left_pad}${BOLD}${title}${PLAIN}${right_pad}${BLUE}║${PLAIN}"
    echo -e "${BLUE}╚$(separator $((width-2)) ═)╝${PLAIN}"
    echo ""
}

# 打印子标题
print_subtitle() {
    local title="$1"
    echo ""
    echo -e " ${BOLD}${BLUE}[ ${title} ]${PLAIN}"
    echo ""
}

# ============================================================
# Banner
# ============================================================

print_banner() {
    clear
    echo ""
    echo -e "${CYAN}  ██╗  ██╗ ██████╗ ████████╗ ██████╗  ██████╗ ██╗${PLAIN}"
    echo -e "${CYAN}  ██║  ██║██╔════╝ ╚══██╔══╝██╔═══██╗██╔═══██╗██║${PLAIN}"
    echo -e "${CYAN}  ███████║██║  ███╗   ██║   ██║   ██║██║   ██║██║${PLAIN}"
    echo -e "${CYAN}  ██╔══██║██║   ██║   ██║   ██║   ██║██║   ██║██║${PLAIN}"
    echo -e "${CYAN}  ██║  ██║╚██████╔╝   ██║   ╚██████╔╝╚██████╔╝███████╗${PLAIN}"
    echo -e "${CYAN}  ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝${PLAIN}"
    echo ""
    echo -e "  ${DIM}黑果云运维工具箱 v${VERSION:-1.0.0}${PLAIN}"
    echo ""
}

# ============================================================
# 菜单函数
# ============================================================
# ============================================================
# 交互式选择菜单（上下键移动选择）
# ============================================================

# 全局变量存储菜单选择结果
MENU_RESULT=""

# 交互式选择菜单
# 用法: interactive_menu "选项1" "选项2" ...
# 支持格式: "名称·····描述" 会自动对齐描述部分
# 结果存储在 MENU_RESULT 变量中
interactive_menu() {
    local -a items=("$@")
    local count=${#items[@]}
    local selected=0
    local key=""
    local max_name_len=0
    
    MENU_RESULT=""
    
    # 计算最大名称长度（用于对齐）
    for item in "${items[@]}"; do
        local name="${item%%·····*}"
        local name_len=${#name}
        [ $name_len -gt $max_name_len ] && max_name_len=$name_len
    done
    
    # 隐藏光标
    tput civis 2>/dev/null
    
    while true; do
        # 显示菜单
        for i in "${!items[@]}"; do
            local item="${items[$i]}"
            local display_text=""
            
            # 分离名称和描述
            if [[ "$item" == *"·····"* ]]; then
                local name="${item%%·····*}"
                local desc="${item##*·····}"
                local name_len=${#name}
                local padding=$((max_name_len - name_len + 5))
                local dots=""
                for ((j=0; j<padding; j++)); do
                    dots+="·"
                done
                display_text="${name}${dots}${desc}"
            else
                display_text="$item"
            fi
            
            if [ $i -eq $selected ]; then
                echo -e "${GREEN}▶${PLAIN} ${GREEN}${BOLD}${display_text}${PLAIN}"
            else
                echo -e "  ${display_text}"
            fi
        done
        
        # 读取按键
        IFS= read -rsn1 key
        
        case "$key" in
            $'\x1b')  # ESC 序列开始（方向键）
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A')  # 上键
                        ((selected--))
                        [ $selected -lt 0 ] && selected=$((count - 1))
                        ;;
                    '[B')  # 下键
                        ((selected++))
                        [ $selected -ge $count ] && selected=0
                        ;;
                esac
                ;;
            'k'|'K')  # vim 风格上移
                ((selected--))
                [ $selected -lt 0 ] && selected=$((count - 1))
                ;;
            'j'|'J')  # vim 风格下移
                ((selected++))
                [ $selected -ge $count ] && selected=0
                ;;
            '')  # Enter 键
                tput cnorm 2>/dev/null
                MENU_RESULT="${items[$selected]}"
                return 0
                ;;
            'q'|'Q')  # q 取消
                tput cnorm 2>/dev/null
                MENU_RESULT=""
                return 1
                ;;
        esac
        
        # 移动光标回到菜单开始位置
        echo -ne "\033[${count}A"
    done
}

# 快捷菜单函数
menu_select() {
    interactive_menu "$@"
    echo "$MENU_RESULT"
}

# ============================================================
# 输入函数
# ============================================================

# 读取用户输入
# 用法: result=$(input "提示" "默认值")
input() {
    local prompt="${1:-请输入}"
    local default="${2:-}"
    local result
    
    if [[ -n "$default" ]]; then
        echo -ne " ${BOLD}└─ ${prompt} [${default}]：${PLAIN}"
    else
        echo -ne " ${BOLD}└─ ${prompt}：${PLAIN}"
    fi
    
    read -r result
    
    if [[ -z "$result" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}

# 确认对话框
# 用法: if confirm "确认操作?"; then ... fi
confirm() {
    local prompt="${1:-确认执行此操作？}"
    local default="${2:-y}"  # y 或 n
    local choice
    
    if [[ "$default" == "y" ]]; then
        echo -ne " ${BOLD}└─ ${prompt} [Y/n]：${PLAIN}"
    else
        echo -ne " ${BOLD}└─ ${prompt} [y/N]：${PLAIN}"
    fi
    
    read -r choice
    
    if [[ -z "$choice" ]]; then
        choice="$default"
    fi
    
    case "$choice" in
        [Yy] | [Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 危险确认（需要输入 YES）
confirm_danger() {
    local prompt="${1:-危险操作！确认继续？}"
    
    echo ""
    echo -e " ${RED}${BOLD}⚠ 警告：${prompt}${PLAIN}"
    echo -ne " ${BOLD}└─ 请输入 ${RED}YES${PLAIN}${BOLD} 确认：${PLAIN}"
    
    local choice
    read -r choice
    
    if [[ "$choice" == "YES" ]]; then
        return 0
    else
        print_warn "已取消"
        return 1
    fi
}

# ============================================================
# 表格输出
# ============================================================

# 打印表格（使用 column 命令对齐）
# 用法: print_table "数据" 
print_table() {
    local data="$1"
    echo "$data" | column -t | while IFS= read -r line; do
        echo -e "   ${CYAN}${line}${PLAIN}"
    done
}

# ============================================================
# 进度和等待
# ============================================================

# 暂停等待按键
pause() {
    local msg="${1:-按任意键继续...}"
    echo ""
    echo -ne " ${DIM}${msg}${PLAIN}"
    read -n 1 -s -r
    echo ""
}

# 简易加载动画（同步执行命令）
# 用法: spinner "提示文字" command arg1 arg2 ...
spinner() {
    local msg="$1"
    shift
    local cmd=("$@")
    
    echo -ne " ${WORKING} ${msg}"
    
    # 执行命令
    if "${cmd[@]}" >/dev/null 2>&1; then
        echo -e "\r ${SUCCESS} ${msg}"
        return 0
    else
        echo -e "\r ${ERROR} ${msg}"
        return 1
    fi
}

# ============================================================
# 兼容性别名（保持旧代码可用）
# ============================================================

# 兼容旧函数名
hg_banner() { print_banner; }
hg_title() { print_title "$1"; }
hg_success() { print_success "$1"; }
hg_error() { print_error "$1"; }
hg_warn() { print_warn "$1"; }
hg_info() { print_info "$1"; }
hg_pause() { pause "$1"; }
hg_confirm() { confirm "$1"; }
hg_confirm_danger() { confirm_danger "$1"; }
hg_spin() { spinner "$@"; }

# 核心兼容函数：hg_choose
# 用法: choice=$(hg_choose "标题" "选项1" "选项2" ...)
hg_choose() {
    local title="$1"
    shift
    menu_select "$title" "$@"
}

# 核心兼容函数：hg_input
hg_input() {
    input "$1" "$2"
}
