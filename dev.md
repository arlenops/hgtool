# hgtool 交互与美化实施方案

**项目名称：** hgtool (黑果云运维工具箱)
**核心理念：** 颜值即正义，效率即生命。

## 1. 技术栈选型 (轻量化)

* **核心逻辑**：Bash Shell (通用)
* **UI 渲染**：`gum` (负责弹窗、输入框、确认框、Spinner)
* **菜单检索**：`fzf` (负责功能快速模糊搜索)
* **依赖策略**：**便携化 (Portable)**。脚本首次运行时，自动检测系统架构 (x86/ARM)，自动下载 `gum` 和 `fzf` 的二进制文件到本地 `bin/` 目录，**不污染** 系统 `/usr/bin`。

---

## 2. 目录结构设计 (修订版)

为了方便后续增加功能，我们将结构改为 **“主程序 + 核心库 + 插件化”** 的模式。

```text
hgtool/
├── hgtool.sh           # [入口] 主启动脚本 (用户只执行这个)
├── bin/                # [依赖] 存放自动下载的 gum 和 fzf，保持目录整洁
├── lib/                # [核心] 核心函数库
│   ├── ui.sh           #    -> 封装所有颜色、Banner、Gum 组件
│   └── utils.sh        #    -> 封装系统检测、IP获取、Root权限检查等通用功能
├── plugins/            # [功能] 所有的业务逻辑都在这里，按分类存放
│   ├── 00_system/      #    -> 系统初始化、内核优化
│   ├── 01_security/    #    -> 病毒扫描、防火墙
│   ├── 02_web/         #    -> Nginx/Caddy 配置
│   └── 99_extra/       #    -> 杂项工具
└── config/             # [配置] (可选) 存放用户偏好或API Key
    └── settings.conf

```

---

## 3. 交互规范 (UI Standard)

我们要封装一套标准函数，以后写新脚本时直接调用，不需要重复写复杂的 gum 命令。

### 3.1 标准配色

* **主色 (Primary)**: `#7D56F4` (黑果云品牌紫，暂定)
* **强调色 (Accent)**: `#04B575` (成功/安全绿色)
* **警告色 (Warning)**: `#FFB86C` (橙色)

### 3.2 封装函数定义 (在 `lib/ui.sh` 中实现)

以后写脚本只用下面这些命令：

| 函数名 | 用途 | 视觉效果 |
| --- | --- | --- |
| `hg_banner` | 显示标题 | 清屏 + ASCII Art + 系统信息栏 |
| `hg_confirm "Msg"` | 确认操作 | 弹出 Yes/No 对话框 |
| `hg_input "Prompt"` | 获取输入 | 弹出带占位符的输入框，结果存入变量 |
| `hg_menu` | 主菜单 | 调用 fzf 搜索 `plugins/` 下的所有脚本并执行 |
| `hg_process "Msg" "Cmd"` | 执行任务 | 显示 Spinner 动画，后台执行命令，完成后打钩 |
| `hg_success "Msg"` | 成功提示 | 绿色大号字体提示 |
| `hg_error "Msg"` | 错误提示 | 红色边框提示 |

---

## 4. 核心逻辑伪代码 (执行流程)

### 4.1 入口文件 `hgtool.sh` 逻辑

```bash
#!/bin/bash
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

```