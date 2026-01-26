#!/bin/bash
# ============================================================
# 软件源管理插件
# ============================================================

PLUGIN_NAME="软件源管理·····更换国内镜像源"
PLUGIN_DESC="更换系统软件源为国内镜像"

plugin_main() {
    while true; do
        print_title "软件源管理"

        # 检测当前系统
        local os_id=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
        local os_version=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
        local os_codename=$(grep -oP '(?<=^VERSION_CODENAME=).+' /etc/os-release 2>/dev/null || lsb_release -cs 2>/dev/null)

        print_info "系统: $os_id $os_version ($os_codename)"

        interactive_menu "中科大源·····中国科学技术大学" "清华源·····清华大学TUNA" "阿里云源·····阿里云镜像" "华为云源·····华为云镜像" "腾讯云源·····腾讯云镜像" "官方源·····恢复默认源" "查看当前源·····显示源配置" "返回主菜单"

        case "$MENU_RESULT" in
            "中科大源·····中国科学技术大学") change_mirror "ustc" ;;
            "清华源·····清华大学TUNA") change_mirror "tuna" ;;
            "阿里云源·····阿里云镜像") change_mirror "aliyun" ;;
            "华为云源·····华为云镜像") change_mirror "huawei" ;;
            "腾讯云源·····腾讯云镜像") change_mirror "tencent" ;;
            "官方源·····恢复默认源") change_mirror "official" ;;
            "查看当前源·····显示源配置") show_current_mirror ;;
            "返回主菜单"|"") return 0 ;;
        esac
    done
}

change_mirror() {
    require_root || return 1
    local mirror_type="$1"

    local os_id=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')

    case "$os_id" in
        ubuntu|debian)
            change_apt_mirror "$mirror_type"
            ;;
        centos|rhel|rocky|almalinux)
            change_yum_mirror "$mirror_type"
            ;;
        fedora)
            change_dnf_mirror "$mirror_type"
            ;;
        *)
            print_error "暂不支持当前系统: $os_id"
            pause
            return 1
            ;;
    esac
}

change_apt_mirror() {
    local mirror_type="$1"
    local sources_file="/etc/apt/sources.list"
    local os_codename=$(grep -oP '(?<=^VERSION_CODENAME=).+' /etc/os-release 2>/dev/null || lsb_release -cs 2>/dev/null)
    local os_id=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')

    # 备份原配置
    backup_file "$sources_file"

    local mirror_url=""
    local mirror_name=""

    case "$mirror_type" in
        ustc)
            mirror_url="mirrors.ustc.edu.cn"
            mirror_name="中科大"
            ;;
        tuna)
            mirror_url="mirrors.tuna.tsinghua.edu.cn"
            mirror_name="清华"
            ;;
        aliyun)
            mirror_url="mirrors.aliyun.com"
            mirror_name="阿里云"
            ;;
        huawei)
            mirror_url="repo.huaweicloud.com"
            mirror_name="华为云"
            ;;
        tencent)
            mirror_url="mirrors.cloud.tencent.com"
            mirror_name="腾讯云"
            ;;
        official)
            if [ "$os_id" = "ubuntu" ]; then
                mirror_url="archive.ubuntu.com"
            else
                mirror_url="deb.debian.org"
            fi
            mirror_name="官方"
            ;;
    esac

    print_info "正在更换为${mirror_name}源..."

    if [ "$os_id" = "ubuntu" ]; then
        cat > "$sources_file" <<EOF
deb https://${mirror_url}/ubuntu/ ${os_codename} main restricted universe multiverse
deb https://${mirror_url}/ubuntu/ ${os_codename}-updates main restricted universe multiverse
deb https://${mirror_url}/ubuntu/ ${os_codename}-backports main restricted universe multiverse
deb https://${mirror_url}/ubuntu/ ${os_codename}-security main restricted universe multiverse
EOF
    else
        cat > "$sources_file" <<EOF
deb https://${mirror_url}/debian/ ${os_codename} main contrib non-free
deb https://${mirror_url}/debian/ ${os_codename}-updates main contrib non-free
deb https://${mirror_url}/debian/ ${os_codename}-backports main contrib non-free
deb https://${mirror_url}/debian-security/ ${os_codename}-security main contrib non-free
EOF
    fi

    spinner "更新软件包列表..." apt-get update -qq

    print_success "已更换为${mirror_name}源"
    pause
}

change_yum_mirror() {
    local mirror_type="$1"
    local os_id=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
    local os_version=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"' | cut -d. -f1)

    local mirror_url=""
    local mirror_name=""

    case "$mirror_type" in
        ustc)
            mirror_url="https://mirrors.ustc.edu.cn"
            mirror_name="中科大"
            ;;
        tuna)
            mirror_url="https://mirrors.tuna.tsinghua.edu.cn"
            mirror_name="清华"
            ;;
        aliyun)
            mirror_url="https://mirrors.aliyun.com"
            mirror_name="阿里云"
            ;;
        huawei)
            mirror_url="https://repo.huaweicloud.com"
            mirror_name="华为云"
            ;;
        tencent)
            mirror_url="https://mirrors.cloud.tencent.com"
            mirror_name="腾讯云"
            ;;
        official)
            print_info "正在恢复官方源..."
            if [ "$os_id" = "centos" ]; then
                if [ -f /etc/yum.repos.d/CentOS-Base.repo.bak ]; then
                    mv /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo
                fi
            fi
            spinner "清理缓存..." yum clean all
            spinner "重建缓存..." yum makecache
            print_success "已恢复官方源"
            pause
            return 0
            ;;
    esac

    print_info "正在更换为${mirror_name}源..."

    # 备份原配置
    [ -f /etc/yum.repos.d/CentOS-Base.repo ] && cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak

    if [ "$os_id" = "centos" ]; then
        if [ "$os_version" = "7" ]; then
            cat > /etc/yum.repos.d/CentOS-Base.repo <<EOF
[base]
name=CentOS-\$releasever - Base
baseurl=${mirror_url}/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-\$releasever - Updates
baseurl=${mirror_url}/centos/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-\$releasever - Extras
baseurl=${mirror_url}/centos/\$releasever/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
        elif [ "$os_version" = "8" ] || [ "$os_version" = "9" ]; then
            sed -i.bak \
                -e "s|^mirrorlist=|#mirrorlist=|g" \
                -e "s|^#baseurl=http://mirror.centos.org|baseurl=${mirror_url}|g" \
                /etc/yum.repos.d/CentOS-*.repo
        fi
    elif [ "$os_id" = "rocky" ] || [ "$os_id" = "almalinux" ]; then
        sed -i.bak \
            -e "s|^mirrorlist=|#mirrorlist=|g" \
            -e "s|^#baseurl=http://dl.rockylinux.org|baseurl=${mirror_url}/rocky|g" \
            -e "s|^#baseurl=https://repo.almalinux.org|baseurl=${mirror_url}/almalinux|g" \
            /etc/yum.repos.d/*.repo
    fi

    spinner "清理缓存..." yum clean all
    spinner "重建缓存..." yum makecache

    print_success "已更换为${mirror_name}源"
    pause
}

change_dnf_mirror() {
    local mirror_type="$1"
    local os_version=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"')

    local mirror_url=""
    local mirror_name=""

    case "$mirror_type" in
        ustc)
            mirror_url="https://mirrors.ustc.edu.cn"
            mirror_name="中科大"
            ;;
        tuna)
            mirror_url="https://mirrors.tuna.tsinghua.edu.cn"
            mirror_name="清华"
            ;;
        aliyun)
            mirror_url="https://mirrors.aliyun.com"
            mirror_name="阿里云"
            ;;
        huawei)
            mirror_url="https://repo.huaweicloud.com"
            mirror_name="华为云"
            ;;
        tencent)
            mirror_url="https://mirrors.cloud.tencent.com"
            mirror_name="腾讯云"
            ;;
        official)
            print_info "正在恢复官方源..."
            for repo in /etc/yum.repos.d/*.repo.bak; do
                [ -f "$repo" ] && mv "$repo" "${repo%.bak}"
            done
            spinner "清理缓存..." dnf clean all
            spinner "重建缓存..." dnf makecache
            print_success "已恢复官方源"
            pause
            return 0
            ;;
    esac

    print_info "正在更换为${mirror_name}源..."

    # 备份并修改配置
    for repo in /etc/yum.repos.d/fedora*.repo; do
        [ -f "$repo" ] && sed -i.bak \
            -e "s|^metalink=|#metalink=|g" \
            -e "s|^#baseurl=http://download.example/pub/fedora|baseurl=${mirror_url}/fedora|g" \
            "$repo"
    done

    spinner "清理缓存..." dnf clean all
    spinner "重建缓存..." dnf makecache

    print_success "已更换为${mirror_name}源"
    pause
}

show_current_mirror() {
    print_title "当前软件源配置"

    local os_id=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"')

    case "$os_id" in
        ubuntu|debian)
            echo ""
            print_info "/etc/apt/sources.list:"
            echo ""
            cat /etc/apt/sources.list 2>/dev/null | grep -v "^#" | grep -v "^$" | head -10
            ;;
        centos|rhel|rocky|almalinux|fedora)
            echo ""
            print_info "YUM/DNF 源配置:"
            echo ""
            grep -h "baseurl" /etc/yum.repos.d/*.repo 2>/dev/null | head -10
            ;;
    esac

    echo ""
    pause
}

plugin_main
