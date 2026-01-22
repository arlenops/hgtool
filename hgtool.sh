#!/bin/bash
# ============================================================
# hgtool - 黑果云运维工具箱
# 核心理念：颜值即正义，效率即生命
# ============================================================

# 1. 定义工作目录
ROOT_DIR=$(cd "$(dirname "$0")"; pwd)

# 2. 引用核心库
source "$ROOT_DIR/lib/utils.sh"
source "$ROOT_DIR/lib/ui.sh"

# 3. 环境自检 (第一次运行时的关键)
# 检查 bin/ 下是否有 gum/fzf，没有则自动从 GitHub/Gitee 下载
check_and_install_dependencies

# 4. 权限检查
check_root_privileges

# 5. 显示欢迎界面
hg_banner

# 6. 进入主循环
while true; do
    # 自动扫描 plugins 目录下的脚本生成菜单
    SCRIPT_TO_RUN=$(find "$ROOT_DIR/plugins" -name "*.sh" | fzf_menu_wrapper)
    
    if [ -n "$SCRIPT_TO_RUN" ]; then
        source "$SCRIPT_TO_RUN"
        # 执行完脚本后暂停，让用户看清结果
        hg_pause "按任意键返回主菜单..."
    else
        echo "再见！"
        exit 0
    fi
done
