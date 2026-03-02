#!/bin/bash
# ============================================================
# HGTool 构建发布包脚本
# 用于将项目打包为 hgtool.tar.gz 供私有服务器分发
# ============================================================

set -e

# 工作目录
ROOT_DIR=$(cd "$(dirname "$0")"; pwd)
DIST_DIR="${ROOT_DIR}/dist"
PACKAGE_NAME="hgtool.tar.gz"
VERSION=$(grep -m1 '^VERSION="' "${ROOT_DIR}/hgtool.sh" | cut -d'"' -f2)

echo -e "\033[0;36m开始构建 HGTool v${VERSION} 发布包...\033[0m"

# 创建或清空 dist 目录
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/hgtool"

# 拷贝核心文件（排除不需要的文件）
echo "正在整理文件..."
rsync -av \
    --exclude='.git' \
    --exclude='.DS_Store' \
    --exclude='.agent' \
    --exclude='.agents' \
    --exclude='.claude' \
    --exclude='dist' \
    --exclude='tests' \
    --exclude='logs/*' \
    --exclude='deploy_and_test.sh' \
    --exclude='build_release.sh' \
    --exclude='install.sh' \
    --exclude='release.html' \
    --exclude='CLAUDE.md' \
    --exclude='skills-lock.json' \
    "${ROOT_DIR}/" "${DIST_DIR}/hgtool/" > /dev/null

# 确保脚本有执行权限
chmod +x "${DIST_DIR}/hgtool/hgtool.sh"

# 打包为 tar.gz
echo "正在打包 ${PACKAGE_NAME}..."
cd "${DIST_DIR}"
tar -czf "${PACKAGE_NAME}" "hgtool"

# 清理临时目录
rm -rf "${DIST_DIR}/hgtool"

echo -e "\033[0;32m构建完成！\033[0m"
echo -e "包路径: \033[1;33m${DIST_DIR}/${PACKAGE_NAME}\033[0m"
echo -e "大小: $(du -sh "${DIST_DIR}/${PACKAGE_NAME}" | cut -f1)"
echo ""
echo -e "请将此文件与 install.sh 一同上传至您的私有服务器 (例如: api.hgcloud.net)"
