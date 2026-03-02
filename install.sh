#!/bin/bash
# ============================================================
# HGTool 私有化安装脚本
# 默认安装在 /opt/hgtool，并创建软链接 /usr/local/bin/hgtool
# 使用: curl -sSL https://api.hgcloud.net/install.sh | sudo bash
# ============================================================

set -e

# --- 配置 ---
DOWNLOAD_URL="file:///dist/hgtool.tar.gz"
INSTALL_DIR="/opt/hgtool"
BIN_LINK="/usr/local/bin/hgtool"
# -----------

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}    欢迎安装 HGTool (黑果云运维工具箱) v1.0.0    ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo ""

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限或 sudo 运行此安装脚本。${NC}"
    exit 1
fi

# 2. 检查必要工具 (curl, tar)
for cmd in curl tar; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}错误: 未找到 $cmd 命令，请先配置好基础环境。${NC}"
        exit 1
    fi
done

# 3. 创建安装目录
echo -e "▶ ${YELLOW}准备安装环境...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    echo -e "  备份已存在的旧版本..."
    mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%s)"
fi
mkdir -p "$INSTALL_DIR"

# 4. 下载发布包并解压
echo -e "▶ ${YELLOW}正在下载核心程序包...${NC}"
# 创建临时文件
TMP_FILE=$(mktemp)
if ! curl -sSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_FILE"; then
    echo -e "${RED}下载失败，请检查网络连接或发布包 URL ($DOWNLOAD_URL)。${NC}"
    rm -f "$TMP_FILE"
    exit 1
fi

echo -e "▶ ${YELLOW}正在解压及安装...${NC}"
tar -xzf "$TMP_FILE" -C "/opt"
rm -f "$TMP_FILE"

# 5. 设置权限
chmod -R 755 "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/hgtool.sh"

# 6. 创建软链接
echo -e "▶ ${YELLOW}配置全局命令...${NC}"
if [ -L "$BIN_LINK" ] || [ -e "$BIN_LINK" ]; then
    rm -f "$BIN_LINK"
fi
ln -s "$INSTALL_DIR/hgtool.sh" "$BIN_LINK"

echo ""
echo -e "${GREEN}✔ HGTool 已成功安装！${NC}"
echo ""
echo -e "安装路径: ${CYAN}$INSTALL_DIR${NC}"
echo -e "全局命令: ${CYAN}hgtool${NC}"
echo ""
echo -e "您可以直接输入 ${GREEN}hgtool${NC} 启动交互式菜单。"
echo -e "${CYAN}=================================================${NC}"

# 如果有交互终端，自动启动（可选）
if [ -t 0 ]; then
    read -p "是否立即启动工具箱？(y/n) [y]: " START_NOW
    START_NOW=${START_NOW:-y}
    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        exec hgtool
    fi
fi
