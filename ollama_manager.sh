#!/bin/bash

# 通用Linux Ollama综合管理工具
# 整合功能：安装/卸载Ollama、模型管理、系统优化、问题诊断、OpenWebUI管理
# 适用平台：所有主流Linux发行版（Debian/Ubuntu、Fedora、CentOS、Arch等）
# 作者：shaoyanxing

# ==============================================
# 颜色定义 - 用于终端输出的格式化显示
# ==============================================
RED='\033[0;31m'      # 错误信息红色
GREEN='\033[0;32m'    # 成功信息绿色
YELLOW='\033[1;33m'   # 警告信息黄色
BLUE='\033[0;34m'     # 信息提示蓝色
NC='\033[0m'          # 无颜色（重置）

# ==============================================
# 定义镜像源 - 解决国内访问GitHub等资源的问题
# ==============================================
# GitHub镜像源 - 用于加速Ollama安装包下载
MIRROR_1="https://gh-proxy.com/https://github.com/ollama/ollama/releases/latest/download"
MIRROR_2="https://hk.gh-proxy.com/https://github.com/ollama/ollama/releases/latest/download"
MIRROR_3="https://edgeone.gh-proxy.com/https://github.com/ollama/ollama/releases/latest/download"
MIRROR_4="https://gh-proxy.net/github.com/ollama/ollama/releases/latest/download"
GITHUB_ORIGIN="https://github.com/ollama/ollama/releases/latest/download"  # 官方源

# OpenWebUI镜像源 - 用于加速Web界面相关资源下载
OPENWEBUI_GHCR_ORIGIN="ghcr.io/open-webui/open-webui:main"  # 官方容器镜像
OPENWEBUI_GHCR_MIRROR="ghcr.nju.edu.cn/open-webui/open-webui:main"  # 国内镜像
OPENWEBUI_REPO_ORIGIN="https://github.com/open-webui/open-webui.git"  # 官方代码仓库
OPENWEBUI_REPO_MIRROR="https://hk.gh-proxy.com/https://github.com/open-webui/open-webui.git"  # 国内仓库镜像

# Ollama模型镜像源 - 加速大模型下载
OLLAMA_MODEL_MIRROR="https://ollama.mirrors.cernet.edu.cn"

# Docker镜像源
DOCKER_MIRRORS=(
    "https://docker.xuanyuan.me"
    "https://docker.1panel.live"
    "https://docker.1ms.run"
    "https://docker.m.daocloud.io"
    "https://docker-0.unsee.tech/"
    "https://proxy.vvvv.ee/"
)
DOCKER_DAEMON_FILE="/etc/docker/daemon.json"

# ==============================================
# 全局变量 - 存储系统状态和配置信息
# ==============================================
SYSTEM_TYPE=""           # 系统类型（debian/redhat/arch/other）
HW_ARCH=""               # 硬件架构（x86_64/arm64/armv7l等）
PI_MODEL=""              # 树莓派型号（4/5/other，非树莓派则为空）
MEM_GB=0                 # 内存大小（GB）
OLLAMA_INSTALL_TYPE="none" # Ollama安装类型（docker/script/none）
OLLAMA_VERSION=""        # Ollama版本信息
OPENWEBUI_INSTALL_TYPE="none" # OpenWebUI安装类型（docker/source/none）
OPENWEBUI_VERSION=""     # OpenWebUI版本信息
INSTALLED_MODELS=""      # 已安装模型列表
SUDO_USER=""             # 执行sudo的原用户
SUDO_USER_HOME=""        # 原用户的家目录
USE_GITHUB_MIRROR=true   # 是否使用GitHub镜像（默认true）
USE_GHCR_MIRROR=true     # 是否使用GHCR镜像（默认true）
IS_CHINESE_USER=false    # 是否为国内用户
PKG_MANAGER=""           # 包管理器（apt/dnf/yum/pacman）
INSTALL_CMD=""           # 安装命令
UPDATE_CMD=""            # 更新命令
UPGRADE_CMD=""           # 升级命令
PKG_CLEAN_CMD=""         # 清理包缓存命令

# ==============================================
# 日志函数 - 统一输出格式，便于识别不同类型信息
# ==============================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==============================================
# 检测用户地理位置 - 判断是否为国内用户
# ==============================================
detect_user_location() {
    log_info "检测网络位置..."
    
    # 尝试多种方式检测IP和地理位置
    local ip country
    local services=(
        "https://ip.cn/ip/"          # 国内IP查询服务
        "https://api.ip.sb/geoip"    # 国际IP查询服务
        "https://ipinfo.io/country"  # 国际IP查询服务
    )
    
    # 检查curl是否安装
    if ! command -v curl &> /dev/null; then
        log_info "未检测到curl，尝试安装..."
        $INSTALL_CMD curl -y
    fi
    
    for service in "${services[@]}"; do
        if [[ $service == *"ip.cn"* ]]; then
            # 解析ip.cn的响应
            response=$(curl -s "$service")
            country=$(echo "$response" | grep -oE "国家：[^\<]+" | cut -d':' -f2)
            ip=$(echo "$response" | grep -oE "IP：[0-9.]+" | cut -d':' -f2)
            if [[ "$country" == "中国" ]]; then
                IS_CHINESE_USER=true
                break
            fi
        elif [[ $service == *"ipinfo.io"* ]]; then
            # 解析ipinfo.io的响应
            country=$(curl -s "$service")
            ip=$(curl -s https://ipinfo.io/ip)
            if [[ "$country" == "CN" ]]; then
                IS_CHINESE_USER=true
                break
            fi
        fi
        
        # 如果成功获取IP但未确定国家，继续尝试
        if [[ -n "$ip" ]]; then
            break
        fi
    done
    
    # 如果无法获取IP，使用默认值
    if [[ -z "$ip" ]]; then
        ip="未知"
    fi
    
    log_info "检测到IP地址: $ip"
    if $IS_CHINESE_USER; then
        log_info "检测到国内网络环境，推荐使用镜像源提高下载速度"
    else
        log_info "检测到海外网络环境，可使用官方源"
    fi
}

# ==============================================
# 配置Docker镜像源
# ==============================================
configure_docker_mirrors() {
    log_info "配置Docker镜像源..."
    
    # 创建docker目录（如果不存在）
    mkdir -p "$(dirname "$DOCKER_DAEMON_FILE")"
    
    # 备份现有配置（如果存在）
    if [ -f "$DOCKER_DAEMON_FILE" ]; then
        cp "$DOCKER_DAEMON_FILE" "${DOCKER_DAEMON_FILE}.bak"
        log_info "已备份现有Docker配置到 ${DOCKER_DAEMON_FILE}.bak"
    fi
    
    # 生成新的配置文件
    cat > "$DOCKER_DAEMON_FILE" << EOF
{
    "registry-mirrors": [
EOF

    # 添加镜像源
    local mirror_count=${#DOCKER_MIRRORS[@]}
    for ((i=0; i<mirror_count; i++)); do
        if [ $i -eq $((mirror_count - 1)) ]; then
            echo "        \"${DOCKER_MIRRORS[$i]}\"" >> "$DOCKER_DAEMON_FILE"
        else
            echo "        \"${DOCKER_MIRRORS[$i]}\"," >> "$DOCKER_DAEMON_FILE"
        fi
    done

    # 完成配置文件
    cat >> "$DOCKER_DAEMON_FILE" << EOF
    ]
}
EOF

    log_success "Docker镜像源配置完成，使用的镜像源:"
    for mirror in "${DOCKER_MIRRORS[@]}"; do
        echo "  - $mirror"
    done
    
    # 如果Docker已安装，重启服务使配置生效
    if command -v docker &> /dev/null; then
        log_info "重启Docker服务以应用配置..."
        systemctl restart docker
        if [ $? -eq 0 ]; then
            log_success "Docker服务已重启"
        else
            log_warning "Docker服务重启失败，可能需要手动重启"
        fi
    fi
}

# ==============================================
# 权限检查 - 确保脚本以root权限运行
# ==============================================
check_root() {
    if [ "$EUID" -ne 0 ]; then  # EUID为0表示root用户
        log_error "请使用root权限运行此脚本 (sudo ./ollama_manager.sh)"
        exit 1  # 非root权限则退出
    fi
}

# ==============================================
# 检测包管理器 - 适配不同Linux发行版
# ==============================================
detect_package_manager() {
    log_info "检测系统包管理器..."
    
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt install"
        UPDATE_CMD="apt update"
        UPGRADE_CMD="apt upgrade -y"
        PKG_CLEAN_CMD="apt clean && apt autoremove -y"
        SYSTEM_TYPE="debian"
        log_info "检测到Debian/Ubuntu系统，使用apt包管理器"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        UPDATE_CMD="dnf check-update"
        UPGRADE_CMD="dnf upgrade -y"
        PKG_CLEAN_CMD="dnf clean all && dnf autoremove -y"
        SYSTEM_TYPE="redhat"
        log_info "检测到Fedora/RHEL系统，使用dnf包管理器"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
        UPDATE_CMD="yum check-update"
        UPGRADE_CMD="yum update -y"
        PKG_CLEAN_CMD="yum clean all && yum autoremove -y"
        SYSTEM_TYPE="redhat"
        log_info "检测到CentOS系统，使用yum包管理器"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
        UPDATE_CMD="pacman -Sy"
        UPGRADE_CMD="pacman -Syu --noconfirm"
        PKG_CLEAN_CMD="pacman -Sc --noconfirm"
        SYSTEM_TYPE="arch"
        log_info "检测到Arch Linux系统，使用pacman包管理器"
    else
        log_error "未检测到支持的包管理器（apt/dnf/yum/pacman）"
        exit 1
    fi
}

# ==============================================
# 硬件检测 - 识别系统架构和设备类型，用于推荐合适配置
# ==============================================
detect_hardware() {
    log_info "检测硬件信息..."
    
    # 检测CPU架构
    HW_ARCH=$(uname -m)
    log_info "检测到CPU架构: $HW_ARCH"
    
    # 检测是否为树莓派
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(tr -d '\0' < /proc/device-tree/model)  # 读取并去除空字符
        log_info "检测到设备型号: $MODEL"
        
        # 根据型号字符串判断具体型号
        if [[ "$MODEL" == *"Raspberry Pi 5"* ]]; then
            PI_MODEL="5"
        elif [[ "$MODEL" == *"Raspberry Pi 4"* ]]; then
            PI_MODEL="4"
        else
            PI_MODEL="other"
        fi
    else
        PI_MODEL=""
        log_info "未检测到树莓派专用信息"
    fi
}

# ==============================================
# 内存检测 - 获取系统内存大小，用于推荐模型和配置
# ==============================================
detect_memory() {
    log_info "检测内存大小..."
    
    # 内存信息存储在/proc/meminfo中
    if [ -f /proc/meminfo ]; then
        MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')  # 总内存(KB)
        MEM_GB=$((MEM_KB / 1024 / 1024))  # 转换为GB
        log_info "检测到内存大小: ${MEM_GB}GB"
    else
        log_error "无法检测内存大小"
        MEM_GB=0
        exit 1  # 无法检测内存时退出
    fi
}

# ==============================================
# 镜像源设置 - 配置GitHub镜像使用选项
# ==============================================
select_github_mirror() {
    log_info "===== GitHub镜像源设置 ====="
    log_info "国内用户推荐使用镜像源以提高下载速度"
    
    # 根据地理位置推荐默认选项
    local default_option="y"
    if ! $IS_CHINESE_USER; then
        default_option="n"
    fi
    
    read -p "是否使用GitHub镜像源? (推荐国内用户使用) [y/n] (默认: $default_option): " -n 1 -r
    echo  # 换行
    
    # 如果用户直接回车，使用默认选项
    if [ -z "$REPLY" ]; then
        REPLY=$default_option
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_GITHUB_MIRROR=true
        log_success "将使用GitHub镜像源"
    else
        USE_GITHUB_MIRROR=false
        log_warning "将使用GitHub官方源，国内用户可能下载缓慢或失败"
    fi
}

# ==============================================
# 镜像源设置 - 配置GHCR镜像使用选项
# ==============================================
select_ghcr_mirror() {
    log_info "===== GHCR镜像源设置 ====="
    log_info "国内用户推荐使用镜像源以提高下载速度"
    
    # 根据地理位置推荐默认选项
    local default_option="y"
    if ! $IS_CHINESE_USER; then
        default_option="n"
    fi
    
    read -p "是否使用GHCR镜像源? (推荐国内用户使用) [y/n] (默认: $default_option): " -n 1 -r
    echo  # 换行
    
    # 如果用户直接回车，使用默认选项
    if [ -z "$REPLY" ]; then
        REPLY=$default_option
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_GHCR_MIRROR=true
        log_success "将使用GHCR镜像源"
    else
        USE_GHCR_MIRROR=false
        log_warning "将使用GHCR官方源，国内用户可能下载缓慢或失败"
    fi
}

# ==============================================
# 镜像源选择 - 选择具体的Ollama安装镜像源
# ==============================================
select_ollama_mirror() {
    log_info "===== 请选择Ollama安装镜像源 ====="
    
    # 根据之前的设置决定显示哪些镜像源
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        echo "1. 主站镜像: $MIRROR_1"
        echo "2. 香港镜像: $MIRROR_2"
        echo "3. edgeone镜像: $MIRROR_3"
        echo "4. gh-proxy.net镜像: $MIRROR_4"
        
        read -p "请输入选项 [1/2/3/4]: " -n 1 -r
        echo  # 换行
        
        # 根据用户选择设置镜像源
        case "$REPLY" in
            "1")
                OLLAMA_MIRROR="$MIRROR_1"
                log_success "已选择主站镜像源"
                ;;
            "2")
                OLLAMA_MIRROR="$MIRROR_2"
                log_success "已选择香港镜像源"
                ;;
            "3")
                OLLAMA_MIRROR="$MIRROR_3"
                log_success "已选择edgeone镜像源"
                ;;
            "4")
                OLLAMA_MIRROR="$MIRROR_4"
                log_success "已选择gh-proxy.net镜像源"
                ;;
            *)
                log_error "无效选项，默认使用edgeone镜像源"
                OLLAMA_MIRROR="$MIRROR_3"
                ;;
        esac
    else
        OLLAMA_MIRROR="$GITHUB_ORIGIN"
        log_info "使用GitHub官方源: $OLLAMA_MIRROR"
    fi
}

# ==============================================
# 系统更新 - 更新系统包到最新版本
# ==============================================
update_system() {
    log_info "更新系统包..."
    # 先更新包列表，再升级所有包
    if $UPDATE_CMD && $UPGRADE_CMD; then
        log_success "系统包更新完成"
    else
        log_warning "系统包更新可能未完成，继续安装但可能有风险"
    fi
}

# ==============================================
# Docker安装 - 安装Docker引擎（用于容器化部署）
# ==============================================
install_docker() {
    log_info "安装Docker..."
    
    # 安装Docker依赖包
    if [ "$SYSTEM_TYPE" = "debian" ]; then
        $INSTALL_CMD apt-transport-https ca-certificates curl software-properties-common
    elif [ "$SYSTEM_TYPE" = "redhat" ]; then
        $INSTALL_CMD curl policycoreutils openssh-server
    elif [ "$SYSTEM_TYPE" = "arch" ]; then
        $INSTALL_CMD curl ca-certificates
    fi
    
    # 使用官方脚本安装Docker（通用方法）
    if curl -fsSL https://get.docker.com -o get-docker.sh; then
        sh get-docker.sh
        rm get-docker.sh
    else
        log_error "Docker官方安装脚本下载失败"
        exit 1
    fi
    
    # 将当前用户添加到docker组（避免每次使用docker都需要sudo）
    usermod -aG docker $SUDO_USER
    
    # 启动并启用Docker服务
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker安装完成"
}

# ==============================================
# 模型镜像配置 - 配置Ollama使用国内模型镜像源
# ==============================================
configure_ollama_model_mirror() {
    log_info "配置Ollama模型拉取镜像源..."
    
    # 根据安装方式不同，配置方法不同
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        # Docker方式：在容器内配置环境变量
        docker exec ollama sh -c "echo 'export OLLAMA_HOST=0.0.0.0' > /root/.bashrc"
        docker exec ollama sh -c "echo 'export OLLAMA_MODEL_MIRROR=$OLLAMA_MODEL_MIRROR' >> /root/.bashrc"
    else
        # 直接安装方式：配置系统服务或环境变量
        if [ -f /etc/systemd/system/ollama.service ]; then
            # 修改服务文件添加环境变量
            sed -i "/ExecStart=/c\ExecStart=/usr/local/bin/ollama serve" /etc/systemd/system/ollama.service
            echo "Environment=\"OLLAMA_MODEL_MIRROR=$OLLAMA_MODEL_MIRROR\"" >> /etc/systemd/system/ollama.service
            systemctl daemon-reload  # 重新加载系统服务配置
        else
            # 创建环境变量文件
            echo "OLLAMA_MODEL_MIRROR=$OLLAMA_MODEL_MIRROR" | tee /etc/profile.d/ollama.sh
            chmod +x /etc/profile.d/ollama.sh
        fi
    fi
    
    # 重启Ollama使配置生效
    log_info "重启Ollama服务以应用镜像源配置..."
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        docker restart ollama
    else
        systemctl restart ollama
    fi
    
    log_success "Ollama模型拉取镜像源配置完成，当前镜像源: $OLLAMA_MODEL_MIRROR"
}

# ==============================================
# Ollama安装 - Docker容器方式
# ==============================================
install_ollama_docker() {
    log_info "使用Docker安装Ollama..."
    
    # 检查Docker是否已安装，未安装则自动安装
    if ! command -v docker &> /dev/null; then
        log_info "未检测到Docker，开始安装Docker..."
        install_docker
    fi
    
    # 拉取并运行Ollama容器
    # 参数说明：
    # -d: 后台运行
    # -v: 挂载数据卷（持久化存储模型）
    # -p: 端口映射（11434是Ollama默认端口）
    # --name: 容器名称
    # --restart always: 开机自动启动
    docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama --restart always ollama/ollama:latest
    
    # 等待容器启动完成
    sleep 10
    
    # 检查容器是否启动成功
    if docker ps | grep -q ollama; then
        log_success "Ollama Docker容器启动成功"
        OLLAMA_INSTALL_TYPE="docker"
    else
        log_error "Ollama Docker容器启动失败"
        exit 1
    fi
}

# ==============================================
# Ollama安装 - 官方脚本方式（直接安装到系统）
# ==============================================
install_ollama_script() {
    log_info "使用官方脚本安装Ollama..."
    log_info "当前使用的源: $OLLAMA_MIRROR"
    
    # 通过镜像源替换官方下载地址，加速安装
    # 使用sed替换脚本中的官方地址为镜像地址
    if export OLLAMA_MIRROR="$OLLAMA_MIRROR" && \
       curl -fsSL https://ollama.com/install.sh | \
       sed "s|https://ollama.com/download|$OLLAMA_MIRROR|g" | sh; then
        log_success "官方脚本安装成功"
    else
        log_warning "官方脚本安装失败，尝试备用方法..."
        # 备用方案：直接下载安装脚本并修改
        if wget "$OLLAMA_MIRROR/../install.sh" -O install.sh; then
            chmod +x install.sh  # 赋予执行权限
            sed -i "s|https://ollama.com/download|$OLLAMA_MIRROR|g" install.sh  # 替换地址
            if ./install.sh; then
                log_success "备用方法安装成功"
            else
                log_error "备用方法安装也失败"
                exit 1
            fi
        else
            log_error "无法下载安装脚本"
            exit 1
        fi
    fi
    
    # 启动Ollama服务并设置开机自启
    systemctl start ollama
    systemctl enable ollama
    
    # 将用户添加到ollama组（获取访问权限）
    usermod -aG ollama $SUDO_USER
    
    OLLAMA_INSTALL_TYPE="script"
    log_success "Ollama官方脚本安装完成"
}

# ==============================================
# 安装方式推荐 - 根据硬件配置推荐合适的安装方式
# ==============================================
recommend_install_method() {
    log_info "根据您的硬件配置推荐安装方式..."
    
    # 内存大于等于8GB推荐Docker方式（便于管理）
    # 内存小于8GB推荐官方脚本（更节省资源）
    if [ $MEM_GB -ge 8 ]; then
        log_info "您的系统内存为${MEM_GB}GB，推荐使用Docker安装方式（便于管理）"
    else
        log_info "您的系统内存为${MEM_GB}GB，推荐使用官方脚本直接安装（更节省资源）"
    fi
    
    # 提示用户当前系统是否已安装Docker
    if command -v docker &> /dev/null; then
        log_info "检测到已安装Docker"
    fi
    
    # 让用户选择安装方式
    read -p "请选择安装方式 (1=Docker, 2=官方脚本): " -n 1 -r
    echo
    if [[ $REPLY == "1" ]]; then
        INSTALL_METHOD="docker"
    else
        INSTALL_METHOD="script"
    fi
}

# ==============================================
# 安装验证 - 检查Ollama是否安装成功
# ==============================================
verify_installation() {
    log_info "验证Ollama安装..."
    sleep 5  # 等待服务启动
    
    # 根据安装方式不同，验证方法不同
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        if docker exec ollama ollama --version &> /dev/null; then
            OLLAMA_VERSION=$(docker exec ollama ollama --version)
            log_success "Ollama验证成功: $OLLAMA_VERSION"
        else
            log_error "Ollama验证失败"
        fi
    else
        if command -v ollama &> /dev/null; then
            OLLAMA_VERSION=$(ollama --version)
            log_success "Ollama验证成功: $OLLAMA_VERSION"
        else
            log_error "Ollama验证失败"
        fi
    fi
}

# ==============================================
# 示例模型安装 - 提供一个轻量级模型的快速安装选项
# ==============================================
install_deepseek_model() {
    log_info "推荐安装轻量级模型Deepseek-Coder-6B-Instruct-Q4..."
    read -p "是否安装此模型? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 根据安装方式不同，执行不同的命令
        if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
            docker exec -it ollama ollama run deepseek-coder:6b-instruct-q4_0
        else
            ollama run deepseek-coder:6b-instruct-q4_0
        fi
    fi
}

# ==============================================
# 模型推荐 - 根据硬件配置推荐合适的模型
# ==============================================
recommend_models() {
    log_info "根据您的硬件配置推荐合适的模型..."
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${GREEN}推荐模型列表:${NC}"
    
    # 针对不同架构和内存推荐不同模型
    if [ "$HW_ARCH" = "x86_64" ]; then
        # x86架构推荐
        if [ $MEM_GB -ge 16 ]; then
            echo "  - Qwen2.5 7B (q4_0量化版本)"
            echo "  - Llama3 8B (q4_0量化版本)"
        elif [ $MEM_GB -ge 8 ]; then
            echo "  - Qwen2.5 3B (q4_0量化版本)"
            echo "  - Llama3 3B (q4_0量化版本)"
        else
            echo "  - Qwen2.5 1.5B (q4_0量化版本)"
            echo "  - Deepseek-Coder 6B (q4_0量化版本)"
        fi
    elif [[ "$HW_ARCH" == *"arm"* ]]; then
        # ARM架构推荐
        if [ "$PI_MODEL" = "5" ]; then
            if [ $MEM_GB -ge 16 ]; then
                echo "  - Qwen2.5 7B (q4_0量化版本)"
                echo "  - Llama3 8B (q4_0量化版本)"
            elif [ $MEM_GB -ge 8 ]; then
                echo "  - Qwen2.5 3B (q4_0量化版本)"
                echo "  - Llama3 3B (q4_0量化版本)"
            else
                echo "  - Qwen2.5 1.5B (q4_0量化版本)"
                echo "  - Deepseek-Coder 6B (q4_0量化版本)"
            fi
        elif [ "$PI_MODEL" = "4" ]; then
            if [ $MEM_GB -ge 8 ]; then
                echo "  - Qwen2.5 1.5B (q4_0量化版本)"
                echo "  - Deepseek-Coder 6B (q4_0量化版本)"
            else
                echo "  - Qwen2.5 0.5B (q4_0量化版本)"
                echo "  - Gemma 2B (q4_0量化版本)"
            fi
        else
            echo "  - 推荐使用小于1B参数的模型"
            echo "  - Qwen2.5 0.5B (q4_0量化版本)"
        fi
    else
        # 未知架构推荐
        echo "  - 推荐使用小于3B参数的模型"
        echo "  - Qwen2.5 1.5B (q4_0量化版本)"
    fi
    echo -e "${BLUE}===========================================${NC}"
}

# ==============================================
# 使用帮助 - 显示Ollama基本使用命令
# ==============================================
show_usage() {
    log_info "Ollama基本使用方法:"
    echo "  1. 运行模型: ollama run <模型名>"
    echo "  2. 查看模型列表: ollama list"
    echo "  3. 拉取新模型: ollama pull <模型名>"
    echo "  4. 删除模型: ollama rm <模型名>"
    echo "  5. 查看帮助: ollama help"
}

# ==============================================
# Ollama卸载 - 完全移除Ollama及其相关文件
# ==============================================
uninstall_ollama() {
    log_info "开始卸载Ollama..."
    
    # 根据安装方式不同，卸载方法不同
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        # Docker方式卸载
        if docker ps -a | grep -q ollama; then
            log_info "停止并删除Ollama容器..."
            docker stop ollama
            docker rm ollama
        fi
        
        # 询问是否删除镜像
        read -p "是否删除Ollama镜像? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if docker images | grep -q ollama/ollama; then
                docker rmi ollama/ollama:latest
                log_success "镜像删除完成"
            fi
        fi
    elif [ "$OLLAMA_INSTALL_TYPE" = "script" ]; then
        # 脚本安装方式卸载
        if systemctl is-active --quiet ollama; then
            log_info "停止Ollama服务..."
            systemctl stop ollama
        fi
        if systemctl is-enabled --quiet ollama; then
            log_info "禁用Ollama服务..."
            systemctl disable ollama
        fi
        
        # 删除服务文件
        if [ -f "/etc/systemd/system/ollama.service" ]; then
            log_info "删除Ollama服务文件..."
            rm -f /etc/systemd/system/ollama.service
            systemctl daemon-reload
        fi
        
        # 删除二进制文件
        if [ -f "/usr/local/bin/ollama" ]; then
            log_info "删除Ollama二进制文件..."
            rm -f /usr/local/bin/ollama
        fi
        
        # 询问是否删除模型数据
        read -p "是否删除Ollama模型数据？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ -d "/usr/share/ollama" ]; then
                rm -rf /usr/share/ollama
            fi
            if [ -d "$SUDO_USER_HOME/.ollama" ]; then
                rm -rf "$SUDO_USER_HOME/.ollama"
            fi
            log_success "数据目录删除完成"
        fi
        
        # 删除用户和用户组
        if id "ollama" &> /dev/null; then
            log_info "删除ollama用户..."
            userdel -r ollama
        fi
        if getent group "ollama" &> /dev/null; then
            log_info "删除ollama用户组..."
            groupdel ollama
        fi
    fi
    
    log_success "Ollama卸载完成"
}

# ==============================================
# 安装/卸载菜单处理 - 处理用户选择的安装相关操作
# ==============================================
handle_install_menu() {
    log_info "===== Ollama安装/卸载 ====="
    echo "1. 全新安装 Ollama"
    echo "2. 重新安装（修复） Ollama"
    echo "3. 卸载 Ollama"
    echo "4. 返回主菜单"
    read -p "请输入选项 [1-4]: " -n 1 -r
    echo
    
    case "$REPLY" in
        "1")
            log_info "您选择了【全新安装】"
            OPERATION="install"
            ;;
        "2")
            log_info "您选择了【重新安装（修复）】"
            OPERATION="reinstall"
            uninstall_ollama  # 先卸载再安装
            ;;
        "3")
            log_info "您选择了【卸载】"
            OPERATION="uninstall"
            uninstall_ollama
            return
            ;;
        "4")
            return  # 返回主菜单
            ;;
        *)
            log_error "无效选项，请重新输入"
            return
            ;;
    esac
    
    # 执行安装或重新安装操作
    if [ "$OPERATION" = "install" ] || [ "$OPERATION" = "reinstall" ]; then
        # 选择镜像源设置
        select_github_mirror
        select_ollama_mirror
        detect_hardware
        detect_memory
        
        # 询问是否更新系统
        read -p "是否要更新系统包? (推荐) (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_system
        fi
        
        # 推荐并选择安装方式
        recommend_install_method
        
        # 执行安装
        if [ "$INSTALL_METHOD" = "docker" ]; then
            install_ollama_docker
        else
            install_ollama_script
        fi
        
        # 后续配置
        configure_ollama_model_mirror
        verify_installation
        install_deepseek_model
        recommend_models
        show_usage
        
        log_success "Ollama ${OPERATION}完成"
        log_info "请注销并重新登录以应用用户组权限变更"
    fi
}

# ==============================================
# 模型管理模块
# ==============================================

# 刷新已安装模型列表
refresh_model_list() {
    log_info "刷新模型列表..."
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        INSTALLED_MODELS=$(docker exec ollama ollama list | grep -v "NAME" | awk '{print $1}')
    else
        INSTALLED_MODELS=$(ollama list | grep -v "NAME" | awk '{print $1}')
    fi
}

# 查看已安装模型
list_installed_models() {
    refresh_model_list
    log_info "===== 已安装模型列表 ====="
    
    if [ -z "$INSTALLED_MODELS" ]; then
        log_info "未安装任何模型"
        return
    fi
    
    local index=1
    while IFS= read -r model; do
        if [ -n "$model" ]; then
            echo "  $index. $model"
            index=$((index + 1))
        fi
    done <<< "$INSTALLED_MODELS"
}

# 拉取新模型
pull_new_model() {
    log_info "===== 拉取新模型 ====="
    read -p "请输入模型名称 (例如: llama3:8b): " model_name
    echo
    
    if [ -z "$model_name" ]; then
        log_error "模型名称不能为空"
        return
    fi
    
    log_info "开始拉取模型: $model_name"
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        docker exec -it ollama ollama pull "$model_name"
    else
        ollama pull "$model_name"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "模型 $model_name 拉取成功"
        refresh_model_list
    else
        log_error "模型 $model_name 拉取失败"
    fi
}

# 删除模型
delete_model() {
    log_info "===== 删除模型 ====="
    list_installed_models
    
    if [ -z "$INSTALLED_MODELS" ]; then
        return
    fi
    
    read -p "请输入要删除的模型序号: " index
    echo
    
    # 验证输入是否为数字
    if ! [[ "$index" =~ ^[0-9]+$ ]]; then
        log_error "无效输入，请输入数字"
        return
    fi
    
    # 获取选中的模型名称
    local model_name
    model_name=$(echo "$INSTALLED_MODELS" | sed -n "${index}p")
    
    if [ -z "$model_name" ]; then
        log_error "无效的序号"
        return
    fi
    
    read -p "确定要删除模型 $model_name 吗? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
            docker exec ollama ollama rm "$model_name"
        else
            ollama rm "$model_name"
        fi
        
        if [ $? -eq 0 ]; then
            log_success "模型 $model_name 删除成功"
            refresh_model_list
        else
            log_error "模型 $model_name 删除失败"
        fi
    fi
}

# 导出模型
export_model() {
    log_info "===== 导出模型 ====="
    list_installed_models
    
    if [ -z "$INSTALLED_MODELS" ]; then
        return
    fi
    
    read -p "请输入要导出的模型序号: " index
    echo
    
    # 验证输入是否为数字
    if ! [[ "$index" =~ ^[0-9]+$ ]]; then
        log_error "无效输入，请输入数字"
        return
    fi
    
    # 获取选中的模型名称
    local model_name
    model_name=$(echo "$INSTALLED_MODELS" | sed -n "${index}p")
    
    if [ -z "$model_name" ]; then
        log_error "无效的序号"
        return
    fi
    
    read -p "请输入导出路径 (默认: $SUDO_USER_HOME/): " export_path
    if [ -z "$export_path" ]; then
        export_path="$SUDO_USER_HOME/${model_name//:/_}.bin"
    fi
    
    log_info "开始导出模型 $model_name 到 $export_path"
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        # Docker方式需要先导出到容器内再复制到宿主
        docker exec ollama ollama export "$model_name" "/tmp/${model_name//:/_}.bin"
        docker cp "ollama:/tmp/${model_name//:/_}.bin" "$export_path"
        docker exec ollama rm "/tmp/${model_name//:/_}.bin"
    else
        ollama export "$model_name" "$export_path"
    fi
    
    if [ $? -eq 0 ]; then
        # 修改文件权限为原用户
        chown "$SUDO_USER:$SUDO_USER" "$export_path"
        log_success "模型已导出到: $export_path"
    else
        log_error "模型导出失败"
    fi
}

# 导入模型
import_model() {
    log_info "===== 导入模型 ====="
    read -p "请输入模型文件路径: " import_path
    echo
    
    if [ -z "$import_path" ] || [ ! -f "$import_path" ]; then
        log_error "文件不存在: $import_path"
        return
    fi
    
    read -p "请输入导入后的模型名称 (例如: mymodel:v1): " model_name
    echo
    
    if [ -z "$model_name" ]; then
        log_error "模型名称不能为空"
        return
    fi
    
    log_info "开始从 $import_path 导入模型为 $model_name"
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        # Docker方式需要先复制到容器内再导入
        docker cp "$import_path" "ollama:/tmp/"
        local filename=$(basename "$import_path")
        docker exec ollama ollama import "$model_name" "/tmp/$filename"
        docker exec ollama rm "/tmp/$filename"
    else
        ollama import "$model_name" "$import_path"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "模型 $model_name 导入成功"
        refresh_model_list
    else
        log_error "模型导入失败"
    fi
}

# 模型管理菜单
handle_model_menu() {
    if ! check_ollama_installed; then
        log_error "未检测到Ollama安装，请先安装Ollama"
        read -p "按Enter键继续..."
        return
    fi
    
    while true; do
        clear
        log_info "===== 模型管理 ====="
        echo "1. 查看已安装模型"
        echo "2. 拉取新模型"
        echo "3. 删除模型"
        echo "4. 导出模型"
        echo "5. 导入模型"
        echo "6. 模型推荐"
        echo "7. 返回主菜单"
        read -p "请输入选项 [1-7]: " -n 1 -r
        echo
        
        case "$REPLY" in
            "1")
                list_installed_models
                ;;
            "2")
                pull_new_model
                ;;
            "3")
                delete_model
                ;;
            "4")
                export_model
                ;;
            "5")
                import_model
                ;;
            "6")
                recommend_models
                ;;
            "7")
                return
                ;;
            *)
                log_error "无效选项，请重新输入"
                ;;
        esac
        read -p "按Enter键继续..."
    done
}

# ==============================================
# 检查Ollama是否已安装
# ==============================================
check_ollama_installed() {
    # 检查Docker安装方式
    if command -v docker &> /dev/null && docker ps -a | grep -q ollama; then
        OLLAMA_INSTALL_TYPE="docker"
        return 0
    # 检查直接安装方式
    elif command -v ollama &> /dev/null; then
        OLLAMA_INSTALL_TYPE="script"
        return 0
    else
        OLLAMA_INSTALL_TYPE="none"
        return 1
    fi
}

# ==============================================
# 检查OpenWebUI是否已安装
# ==============================================
check_openwebui_installed() {
    # 检查Docker安装方式
    if command -v docker &> /dev/null && docker ps -a | grep -q open-webui; then
        OPENWEBUI_INSTALL_TYPE="docker"
        return 0
    # 检查源码安装方式
    elif [ -d "/opt/open-webui" ]; then
        OPENWEBUI_INSTALL_TYPE="source"
        return 0
    else
        OPENWEBUI_INSTALL_TYPE="none"
        return 1
    fi
}

# ==============================================
# 检查npm是否安装并处理错误
# ==============================================
check_npm_installed() {
    log_info "检查npm是否安装..."
    if ! command -v npm &> /dev/null; then
        log_warning "未检测到npm，尝试安装..."
        
        # 根据不同系统安装Node.js和npm
        if [ "$SYSTEM_TYPE" = "debian" ]; then
            $INSTALL_CMD curl software-properties-common
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            $INSTALL_CMD nodejs
        elif [ "$SYSTEM_TYPE" = "redhat" ]; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
            $INSTALL_CMD nodejs
        elif [ "$SYSTEM_TYPE" = "arch" ]; then
            $INSTALL_CMD nodejs npm
        fi
        
        # 再次检查npm是否安装成功
        if ! command -v npm &> /dev/null; then
            log_error "npm安装失败，请手动安装Node.js和npm后重试"
            return 1
        fi
    fi
    
    log_info "npm已安装: $(npm --version)"
    return 0
}

# ==============================================
# 执行npm命令并处理错误
# ==============================================
run_npm_command() {
    local command=$1
    local description=$2
    
    log_info "执行: $description"
    if eval $command; then
        log_success "$description 成功"
        return 0
    else
        log_error "$description 失败，错误代码: $?"
        log_error "npm错误详情:"
        # 重新执行命令以显示详细错误输出
        eval $command
        return 1
    fi
}

# ==============================================
# OpenWebUI安装 - 源码方式
# ==============================================
install_openwebui_source() {
    log_info "使用源码安装OpenWebUI..."
    
    # 检查npm是否安装
    if ! check_npm_installed; then
        log_error "npm安装失败，无法继续OpenWebUI源码安装"
        return 1
    fi
    
    # 安装必要依赖
    log_info "安装必要依赖..."
    if [ "$SYSTEM_TYPE" = "debian" ]; then
        $INSTALL_CMD git python3 python3-pip
    elif [ "$SYSTEM_TYPE" = "redhat" ]; then
        $INSTALL_CMD git python3 python3-pip
    elif [ "$SYSTEM_TYPE" = "arch" ]; then
        $INSTALL_CMD git python3
    fi
    
    # 选择代码仓库
    local repo_url
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        repo_url="$OPENWEBUI_REPO_MIRROR"
    else
        repo_url="$OPENWEBUI_REPO_ORIGIN"
    fi
    
    # 克隆代码仓库
    log_info "从 $repo_url 克隆代码仓库..."
    if [ -d "/opt/open-webui" ]; then
        log_info "检测到已有OpenWebUI目录，删除旧版本..."
        rm -rf /opt/open-webui
    fi
    
    if ! git clone "$repo_url" /opt/open-webui; then
        log_error "代码仓库克隆失败"
        return 1
    fi
    
    # 进入项目目录
    cd /opt/open-webui || {
        log_error "无法进入/opt/open-webui目录"
        return 1
    }
    
    # 安装依赖 - 带错误处理
    if ! run_npm_command "npm install" "安装npm依赖"; then
        log_error "依赖安装失败，尝试清理npm缓存后重试..."
        if ! run_npm_command "npm cache clean --force" "清理npm缓存"; then
            return 1
        fi
        if ! run_npm_command "npm install" "重新安装npm依赖"; then
            return 1
        fi
    fi
    
    # 构建项目 - 带错误处理
    if ! run_npm_command "npm run build" "构建项目"; then
        return 1
    fi
    
    # 创建系统服务
    log_info "创建系统服务..."
    cat > /etc/systemd/system/open-webui.service << EOF
[Unit]
Description=OpenWebUI Service
After=network.target ollama.service

[Service]
Type=simple
User=$SUDO_USER
WorkingDirectory=/opt/open-webui
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置权限
    chown -R "$SUDO_USER:$SUDO_USER" /opt/open-webui
    
    # 启动并启用服务
    systemctl daemon-reload
    systemctl start open-webui
    systemctl enable open-webui
    
    # 检查服务状态
    if systemctl is-active --quiet open-webui; then
        log_success "OpenWebUI源码安装成功"
        OPENWEBUI_INSTALL_TYPE="source"
        return 0
    else
        log_error "OpenWebUI服务启动失败"
        log_info "查看日志获取更多信息: journalctl -u open-webui -f"
        return 1
    fi
}

# ==============================================
# OpenWebUI安装 - Docker方式
# ==============================================
install_openwebui_docker() {
    log_info "使用Docker安装OpenWebUI..."
    
    # 检查Docker是否已安装
    if ! command -v docker &> /dev/null; then
        log_info "未检测到Docker，开始安装Docker..."
        install_docker || {
            log_error "Docker安装失败，无法继续OpenWebUI安装"
            return 1
        }
    fi
    
    # 选择镜像源
    local image
    if [ "$USE_GHCR_MIRROR" = true ]; then
        image="$OPENWEBUI_GHCR_MIRROR"
    else
        image="$OPENWEBUI_GHCR_ORIGIN"
    fi
    
    # 拉取并运行容器
    log_info "使用镜像: $image"
    docker run -d \
        -p 3000:8080 \
        -e OLLAMA_API_BASE_URL=http://localhost:11434/api \
        -v open-webui:/app/backend/data \
        --name open-webui \
        --restart always \
        "$image"
    
    # 等待容器启动
    sleep 10
    
    # 检查容器状态
    if docker ps | grep -q open-webui; then
        log_success "OpenWebUI Docker容器启动成功"
        OPENWEBUI_INSTALL_TYPE="docker"
        return 0
    else
        log_error "OpenWebUI Docker容器启动失败"
        log_info "查看日志获取更多信息: docker logs open-webui"
        return 1
    fi
}

# ==============================================
# OpenWebUI卸载
# ==============================================
uninstall_openwebui() {
    log_info "开始卸载OpenWebUI..."
    
    if [ "$OPENWEBUI_INSTALL_TYPE" = "docker" ]; then
        # Docker方式卸载
        if docker ps -a | grep -q open-webui; then
            log_info "停止并删除OpenWebUI容器..."
            docker stop open-webui
            docker rm open-webui
        fi
        
        # 询问是否删除数据卷
        read -p "是否删除OpenWebUI数据? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if docker volume ls | grep -q open-webui; then
                docker volume rm open-webui
                log_success "数据卷删除完成"
            fi
        fi
        
    elif [ "$OPENWEBUI_INSTALL_TYPE" = "source" ]; then
        # 源码方式卸载
        if systemctl is-active --quiet open-webui; then
            log_info "停止OpenWebUI服务..."
            systemctl stop open-webui
        fi
        
        if systemctl is-enabled --quiet open-webui; then
            log_info "禁用OpenWebUI服务..."
            systemctl disable open-webui
        fi
        
        # 删除服务文件
        if [ -f "/etc/systemd/system/open-webui.service" ]; then
            rm -f /etc/systemd/system/open-webui.service
            systemctl daemon-reload
        fi
        
        # 询问是否删除安装目录
        read -p "是否删除OpenWebUI安装目录? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ -d "/opt/open-webui" ]; then
                rm -rf /opt/open-webui
                log_success "安装目录删除完成"
            fi
        fi
    fi
    
    OPENWEBUI_INSTALL_TYPE="none"
    log_success "OpenWebUI卸载完成"
}

# ==============================================
# OpenWebUI管理菜单
# ==============================================
handle_openwebui_menu() {
    log_info "===== OpenWebUI管理 ====="
    echo "1. 安装 OpenWebUI"
    echo "2. 卸载 OpenWebUI"
    echo "3. 查看 OpenWebUI 日志"
    echo "4. 返回主菜单"
    read -p "请输入选项 [1-4]: " -n 1 -r
    echo
    
    case "$REPLY" in
        "1")
            log_info "您选择了安装OpenWebUI"
            
            # 检查Ollama是否已安装
            if ! check_ollama_installed; then
                log_error "请先安装Ollama，OpenWebUI需要依赖Ollama运行"
                read -p "按Enter键继续..."
                return
            fi
            
            # 选择安装方式
            log_info "请选择安装方式:"
            echo "1. Docker方式（推荐）"
            echo "2. 源码方式（适合开发或定制）"
            read -p "请输入选项 [1/2]: " -n 1 -r
            echo
            
            if [[ $REPLY == "1" ]]; then
                install_openwebui_docker
            else
                install_openwebui_source
            fi
            ;;
        "2")
            log_info "您选择了卸载OpenWebUI"
            if check_openwebui_installed; then
                uninstall_openwebui
            else
                log_info "未检测到OpenWebUI安装"
            fi
            ;;
        "3")
            log_info "您选择了查看OpenWebUI日志"
            if check_openwebui_installed; then
                view_openwebui_logs
            else
                log_info "未检测到OpenWebUI安装"
            fi
            ;;
        "4")
            return
            ;;
        *)
            log_error "无效选项，请重新输入"
            ;;
    esac
    read -p "按Enter键继续..."
}

# ==============================================
# 系统优化模块
# ==============================================

# 配置系统swap交换分区
configure_swap() {
    log_info "===== 配置Swap交换分区 ====="
    
    # 检查当前swap状态
    log_info "当前Swap状态:"
    free -h | grep Swap
    
    # 推荐swap大小（根据内存大小）
    local recommended_swap
    if [ $MEM_GB -lt 8 ]; then
        recommended_swap=$((MEM_GB * 2))  # 内存小于8GB，推荐2倍内存的swap
    else
        recommended_swap=$MEM_GB  # 内存大于等于8GB，推荐等于内存的swap
    fi
    
    log_info "根据您的内存大小(${MEM_GB}GB)，推荐Swap大小为${recommended_swap}GB"
    read -p "是否配置Swap分区? (y/n): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "取消配置Swap"
        return
    fi
    
    read -p "请输入Swap大小(GB) [默认: ${recommended_swap}]: " swap_size
    if [ -z "$swap_size" ]; then
        swap_size=$recommended_swap
    fi
    
    # 检查数字有效性
    if ! [[ "$swap_size" =~ ^[0-9]+$ ]]; then
        log_error "无效的大小输入，必须是数字"
        return
    fi
    
    # 检查swap文件是否已存在
    if [ -f "/swapfile" ]; then
        log_warning "检测到已存在swapfile，将替换它"
        swapoff /swapfile
        rm -f /swapfile
    fi
    
    # 创建swap文件
    log_info "创建${swap_size}GB的swap文件..."
    if ! fallocate -l "${swap_size}G" /swapfile; then
        log_warning "fallocate失败，尝试使用dd命令..."
        dd if=/dev/zero of=/swapfile bs=1G count=$swap_size status=progress
    fi
    
    # 设置权限
    chmod 600 /swapfile
    
    # 格式化swap
    mkswap /swapfile
    
    # 启用swap
    swapon /swapfile
    
    # 设置开机自动挂载
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log_info "已配置开机自动挂载swap"
    fi
    
    log_success "Swap配置完成，新的Swap状态:"
    free -h | grep Swap
}

# 优化系统网络设置
optimize_network() {
    log_info "===== 优化网络设置 ====="
    
    # 备份现有配置
    if [ -f "/etc/sysctl.conf" ]; then
        cp /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%Y%m%d)"
        log_info "已备份sysctl配置"
    fi
    
    # 添加网络优化参数
    cat >> /etc/sysctl.conf << EOF

# Ollama网络优化参数
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.core.netdev_max_backlog=5000
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_syncookies=1
EOF
    
    # 应用配置
    sysctl -p
    
    log_success "网络优化配置已应用，这些设置将提高大模型下载和网络传输性能"
}

# 优化Ollama服务性能
optimize_ollama_performance() {
    log_info "===== 优化Ollama服务性能 ====="
    
    if ! check_ollama_installed; then
        log_error "未检测到Ollama安装，请先安装Ollama"
        return
    fi
    
    # 根据安装类型进行不同的优化配置
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        log_info "Docker安装方式优化..."
        
        # 停止当前容器
        docker stop ollama
        
        # 推荐内存限制（总内存的75%）
        local mem_limit=$((MEM_GB * 75 / 100))G
        log_info "推荐Ollama内存限制: $mem_limit (系统总内存的75%)"
        
        # 删除旧容器
        docker rm ollama
        
        # 用新参数重新创建容器
        docker run -d \
            -v ollama:/root/.ollama \
            -p 11434:11434 \
            --name ollama \
            --restart always \
            --memory=$mem_limit \
            --cpus="0.75" \
            ollama/ollama:latest
        
        log_success "Ollama Docker容器已重新启动并应用优化参数"
    else
        log_info "直接安装方式优化..."
        
        # 停止服务
        systemctl stop ollama
        
        # 修改服务文件添加优化参数
        if [ -f /etc/systemd/system/ollama.service ]; then
            # 添加内存限制（总内存的75%）
            local mem_limit=$((MEM_GB * 750))M  # 转换为MB
            sed -i "/\[Service\]/a LimitMEMLOCK=infinity" /etc/systemd/system/ollama.service
            sed -i "/\[Service\]/a LimitAS=$mem_limit" /etc/systemd/system/ollama.service
            sed -i "/\[Service\]/a CPUQuota=75%" /etc/systemd/system/ollama.service
            
            # 重新加载并启动服务
            systemctl daemon-reload
            systemctl start ollama
            log_success "Ollama服务已应用优化参数"
        else
            log_error "未找到Ollama服务文件，无法应用优化"
        fi
    fi
}

# 清理系统缓存和无用包
clean_system() {
    log_info "===== 清理系统 ====="
    
    log_info "清理系统缓存..."
    sync
    echo 3 > /proc/sys/vm/drop_caches
    
    log_info "清理包管理器缓存..."
    $PKG_CLEAN_CMD
    
    log_info "清理旧的日志文件..."
    find /var/log -type f -name "*.log" -size +100M -delete
    find /var/log -type f -name "*.gz" -mtime +30 -delete
    
    log_success "系统清理完成"
}

# 系统优化与配置菜单
handle_optimization_menu() {
    while true; do
        clear
        log_info "===== 系统优化与配置 ====="
        echo "1. 配置Docker镜像源"
        echo "2. 配置Swap交换分区（推荐低内存系统）"
        echo "3. 优化网络设置（提高下载速度）"
        echo "4. 优化Ollama性能（资源分配）"
        echo "5. 清理系统缓存和无用包"
        echo "6. 返回主菜单"
        read -p "请输入选项 [1-6]: " -n 1 -r
        echo
        
        case "$REPLY" in
            "1")
                configure_docker_mirrors
                ;;
            "2")
                configure_swap
                ;;
            "3")
                optimize_network
                ;;
            "4")
                optimize_ollama_performance
                ;;
            "5")
                clean_system
                ;;
            "6")
                return
                ;;
            *)
                log_error "无效选项，请重新输入"
                ;;
        esac
        read -p "按Enter键继续..."
    done
}

# ==============================================
# 问题诊断模块
# ==============================================

# 查看Ollama日志
view_ollama_logs() {
    log_info "===== Ollama日志 (最近50行) ====="
    if [ "$OLLAMA_INSTALL_TYPE" = "docker" ]; then
        docker logs --tail 50 ollama
    else
        journalctl -u ollama --no-pager --tail 50
    fi
}

# 查看OpenWebUI日志
view_openwebui_logs() {
    log_info "===== OpenWebUI日志 (最近50行) ====="
    if [ "$OPENWEBUI_INSTALL_TYPE" = "docker" ]; then
        docker logs --tail 50 open-webui
    else
        journalctl -u open-webui --no-pager --tail 50
    fi
}

# 诊断网络连接
diagnose_network() {
    log_info "===== 网络连接诊断 ====="
    log_info "测试Ollama官方网站连接..."
    if curl -s --head https://ollama.com | grep "200 OK" > /dev/null; then
        log_success "Ollama官方网站连接正常"
    else
        log_error "Ollama官方网站连接失败"
    fi
    
    log_info "测试GitHub连接..."
    if curl -s --head https://github.com | grep "200 OK" > /dev/null; then
        log_success "GitHub连接正常"
    else
        log_error "GitHub连接失败，建议使用镜像源"
    fi
    
    log_info "测试Ollama API连接..."
    if curl -s --head http://localhost:11434/api/tags | grep "200 OK" > /dev/null; then
        log_success "Ollama API连接正常"
    else
        log_error "Ollama API连接失败，请检查Ollama服务是否运行"
    fi
}

# 系统资源检查
check_system_resources() {
    log_info "===== 系统资源检查 ====="
    log_info "CPU使用情况:"
    top -bn1 | grep "Cpu(s)"
    
    log_info "\n内存使用情况:"
    free -h
    
    log_info "\n磁盘空间情况:"
    df -h /
    
    log_info "\n进程状态:"
    if [ "$OLLAMA_INSTALL_TYPE" != "none" ]; then
        log_info "Ollama进程:"
        ps aux | grep ollama | grep -v grep
    fi
    if [ "$OPENWEBUI_INSTALL_TYPE" != "none" ]; then
        log_info "OpenWebUI进程:"
        ps aux | grep -E "node|open-webui" | grep -v grep
    fi
}

# 问题诊断菜单
handle_diagnose_menu() {
    while true; do
        clear
        log_info "===== 问题诊断 ====="
        echo "1. 查看Ollama日志"
        echo "2. 查看OpenWebUI日志"
        echo "3. 网络连接诊断"
        echo "4. 系统资源检查"
        echo "5. 返回主菜单"
        read -p "请输入选项 [1-5]: " -n 1 -r
        echo
        
        case "$REPLY" in
            "1")
                if check_ollama_installed; then
                    view_ollama_logs
                else
                    log_error "未检测到Ollama安装"
                fi
                ;;
            "2")
                if check_openwebui_installed; then
                    view_openwebui_logs
                else
                    log_error "未检测到OpenWebUI安装"
                fi
                ;;
            "3")
                diagnose_network
                ;;
            "4")
                check_system_resources
                ;;
            "5")
                return
                ;;
            *)
                log_error "无效选项，请重新输入"
                ;;
        esac
        read -p "按Enter键继续..."
    done
}

# ==============================================
# 主菜单 - 程序入口点
# ==============================================
main_menu() {
    while true; do
        clear
        log_info "===== Ollama综合管理工具 ====="
        log_info "当前状态: Ollama[$OLLAMA_INSTALL_TYPE] | OpenWebUI[$OPENWEBUI_INSTALL_TYPE]"
        echo "1. Ollama安装/卸载"
        echo "2. 模型管理"
        echo "3. OpenWebUI管理"
        echo "4. 系统优化与配置"
        echo "5. 问题诊断"
        echo "6. 退出"
        read -p "请输入选项 [1-6]: " -n 1 -r
        echo
        
        case "$REPLY" in
            "1")
                handle_install_menu
                ;;
            "2")
                handle_model_menu
                ;;
            "3")
                handle_openwebui_menu
                ;;
            "4")
                handle_optimization_menu
                ;;
            "5")
                handle_diagnose_menu
                ;;
            "6")
                log_info "感谢使用Ollama综合管理工具，再见！"
                exit 0
                ;;
            *)
                log_error "无效选项，请重新输入"
                read -p "按Enter键继续..."
                ;;
        esac
    done
}

# ==============================================
# 程序初始化 - 准备环境并启动主菜单
# ==============================================
initialize() {
    # 检查root权限
    check_root
    
    # 记录原用户信息（执行sudo的用户）
    SUDO_USER=$(logname)
    SUDO_USER_HOME=$(eval echo ~$SUDO_USER)
    log_info "当前操作用户: $SUDO_USER (家目录: $SUDO_USER_HOME)"
    
    # 检测系统环境
    detect_package_manager
    detect_user_location
    detect_hardware
    detect_memory
    
    # 检查现有安装状态
    check_ollama_installed
    check_openwebui_installed
    
    # 显示系统信息摘要
    log_info "系统信息摘要: $SYSTEM_TYPE / $HW_ARCH / ${MEM_GB}GB RAM"
    
    # 启动主菜单
    main_menu
}

# 启动程序
initialize
    
