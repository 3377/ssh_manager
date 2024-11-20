#!/bin/bash

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_MANAGER_DIR="$HOME/.ssh_manager"
SSH_DIR="$SSH_MANAGER_DIR"
KEY_NAME="drfykey"
HOSTS_FILE="$SSH_MANAGER_DIR/hosts"
CURRENT_USER="$(whoami)"
CURRENT_HOST="$(hostname)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
CONFIG_FILE="$SSH_MANAGER_DIR/config.sh"

# WebDAV配置
WEBDAV_BASE_URL="https://pan.hstz.com"
WEBDAV_PATH="/dav/ssh_manager"
WEBDAV_FULL_URL="${WEBDAV_BASE_URL}${WEBDAV_PATH}"

# ANSI颜色代码
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 测试WebDAV连接
test_webdav() {
    local user="$1"
    local pass="$2"
    
    info "测试WebDAV连接..."
    
    # 创建一个临时文件
    local temp_file="test_${TIMESTAMP}.tmp"
    echo "test" > "$temp_file"
    
    # 尝试上传临时文件
    if ! curl -s -f -T "$temp_file" -u "$user:$pass" "$WEBDAV_FULL_URL/$temp_file"; then
        error "无法连接到WebDAV服务器"
        rm -f "$temp_file"
        return 1
    fi
    
    # 检查文件是否存在
    if ! curl -s -f -X PROPFIND --header "Depth: 1" -u "$user:$pass" "$WEBDAV_FULL_URL/$temp_file" >/dev/null 2>&1; then
        error "无法验证WebDAV上传"
        rm -f "$temp_file"
        return 1
    fi
    
    # 删除临时文件
    curl -s -f -X DELETE -u "$user:$pass" "$WEBDAV_FULL_URL/$temp_file"
    rm -f "$temp_file"
    
    info "WebDAV连接测试成功"
    return 0
}

# 清理现有配置
clean_local_config() {
    info "清理本地配置..."
    rm -rf "$SSH_MANAGER_DIR"
    mkdir -p "$SSH_MANAGER_DIR"
    chmod 700 "$SSH_MANAGER_DIR"
}

# 初始化配置
init_config() {
    info "初始化配置目录..."
    
    # 创建必要的目录
    mkdir -p "$SSH_MANAGER_DIR"
    chmod 700 "$SSH_MANAGER_DIR"
    
    # 确保hosts文件存在
    touch "$HOSTS_FILE"
    chmod 600 "$HOSTS_FILE"
}

# 初始化环境
init_env() {
    info "初始化环境..."
    
    # 创建必要的目录
    mkdir -p "$SSH_MANAGER_DIR"
    chmod 700 "$SSH_MANAGER_DIR"
    
    # 确保hosts文件存在
    touch "$HOSTS_FILE"
    chmod 600 "$HOSTS_FILE"
}

# 生成新的SSH密钥对
generate_keys() {
    info "生成新的SSH密钥对..."
    
    # 确保.ssh目录存在
    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi

    # 删除可能存在的旧密钥
    rm -f "$SSH_DIR/$KEY_NAME" "$SSH_DIR/${KEY_NAME}.pub"
    
    # 生成新的SSH密钥对
    if ! ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/$KEY_NAME" -N ""; then
        error "生成SSH密钥对失败"
        return 1
    fi
    
    # 设置正确的权限
    chmod 600 "$SSH_DIR/$KEY_NAME"
    chmod 644 "$SSH_DIR/${KEY_NAME}.pub"
    
    # 确保authorized_keys文件存在
    local auth_keys="$SSH_DIR/authorized_keys"
    touch "$auth_keys"
    chmod 600 "$auth_keys"
    
    # 将新生成的公钥添加到authorized_keys
    cat "$SSH_DIR/${KEY_NAME}.pub" >> "$auth_keys"
    
    success "SSH密钥对生成成功，并已添加到本机的authorized_keys"
    return 0
}

# 下载文件
download_file() {
    local url="$1"
    local output_file="$2"
    local user="$3"
    local pass="$4"

    # 使用curl下载文件，添加-L参数处理重定向
    local response
    response=$(curl -s -k -L -w "%{http_code}" -u "$user:$pass" -o "$output_file" "$url")
    
    # 检查HTTP状态码
    if [ "$response" = "200" ] || [ "$response" = "201" ]; then
        # 验证文件是否下载成功
        if [ -s "$output_file" ]; then
            # 检查文件内容是否是HTML（可能是错误页面）
            if ! grep -q "^<!DOCTYPE\|^<html\|^<a href=" "$output_file"; then
                return 0
            else
                warn "下载的文件包含HTML内容，可能是错误页面"
                rm -f "$output_file"
                return 1
            fi
        else
            warn "下载的文件为空"
            rm -f "$output_file"
            return 1
        fi
    else
        warn "下载失败，HTTP状态码: $response"
        return 1
    fi
}

# 从WebDAV下载文件
download_from_webdav() {
    local user="$1"
    local pass="$2"
    local need_upload=false
    local key_exists=false
    
    info "正在从WebDAV下载文件..."
    
    # 检查目录是否存在，使用-L参数处理重定向
    if ! curl -s -k -L -I -u "$user:$pass" "$WEBDAV_FULL_URL" | grep -q "HTTP/.*[[:space:]]2"; then
        info "WebDAV目录不存在，将在上传时创建"
        need_upload=true
    fi
    
    # 创建临时目录用于验证下载的文件
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # 下载私钥到临时目录
    if download_file "$WEBDAV_FULL_URL/$KEY_NAME" "${temp_dir}/${KEY_NAME}" "$user" "$pass"; then
        info "WebDAV上存在密钥，正在下载..."
        
        # 下载公钥到临时目录
        if download_file "$WEBDAV_FULL_URL/${KEY_NAME}.pub" "${temp_dir}/${KEY_NAME}.pub" "$user" "$pass"; then
            # 验证密钥对
            chmod 600 "${temp_dir}/${KEY_NAME}"
            if ssh-keygen -l -f "${temp_dir}/${KEY_NAME}" > /dev/null 2>&1; then
                info "成功下载有效的密钥对"
                info "使用WebDAV上的现有密钥"
                # 移动验证过的密钥到最终位置
                mv "${temp_dir}/${KEY_NAME}" "$SSH_DIR/$KEY_NAME"
                mv "${temp_dir}/${KEY_NAME}.pub" "$SSH_DIR/${KEY_NAME}.pub"
                chmod 600 "$SSH_DIR/$KEY_NAME"
                chmod 644 "$SSH_DIR/${KEY_NAME}.pub"
                key_exists=true
            else
                warn "下载的密钥对无效，需要生成新的密钥对"
                need_upload=true
            fi
        else
            warn "公钥下载失败，需要生成新的密钥对"
            need_upload=true
        fi
    else
        info "WebDAV上不存在密钥，需要生成新的密钥对"
        need_upload=true
    fi

    # 清理临时目录
    rm -rf "$temp_dir"

    # 获取本地主机名和时间戳
    local current_hostname
    current_hostname=$(hostname)
    local timestamp
    timestamp=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')
    
    # 创建临时文件用于合并
    local temp_merged
    temp_merged=$(mktemp)
    local temp_remote
    temp_remote=$(mktemp)
    
    # 确保本地主机列表文件存在
    touch "$HOSTS_FILE"
    
    # 下载远程主机列表
    if download_file "$WEBDAV_FULL_URL/hosts" "$temp_remote" "$user" "$pass"; then
        info "下载到现有主机列表，进行处理..."
        
        if [ -s "$temp_remote" ]; then
            info "当前远程主机列表："
            cat "$temp_remote"
            
            # 合并远程和本地列表（如果本地列表存在）
            if [ -s "$HOSTS_FILE" ]; then
                cat "$HOSTS_FILE" "$temp_remote" > "$temp_merged"
            else
                cat "$temp_remote" > "$temp_merged"
            fi
        else
            info "远程主机列表为空，使用本地列表"
            if [ -s "$HOSTS_FILE" ]; then
                cat "$HOSTS_FILE" > "$temp_merged"
            fi
        fi
    else
        warn "主机列表下载失败，使用本地列表"
        if [ -s "$HOSTS_FILE" ]; then
            cat "$HOSTS_FILE" > "$temp_merged"
        fi
    fi
    
    # 检查当前主机是否需要添加到列表中
    if ! grep -q "^${current_hostname}|" "$temp_merged" 2>/dev/null; then
        info "添加当前主机到列表: ${current_hostname}"
        echo "${current_hostname}|${timestamp}" >> "$temp_merged"
        need_upload=true
    else
        # 更新现有主机的时间戳
        sed -i "s/^${current_hostname}|.*$/${current_hostname}|${timestamp}/" "$temp_merged"
        info "更新当前主机的时间戳: ${current_hostname}"
        need_upload=true
    fi
    
    # 确保列表不为空且格式正确
    if [ ! -s "$temp_merged" ]; then
        info "创建新的主机列表，添加当前主机"
        echo "${current_hostname}|${timestamp}" > "$temp_merged"
        need_upload=true
    fi
    
    # 对合并后的列表进行排序和去重，保留最新的时间戳
    sort -t'|' -k1,1 -u "$temp_merged" > "$HOSTS_FILE"
    chmod 600 "$HOSTS_FILE"
    
    info "当前主机列表内容："
    cat "$HOSTS_FILE"
    
    # 清理临时文件
    rm -f "$temp_merged" "$temp_remote"
    
    # 如果没有有效的密钥，生成新的
    if [ "$key_exists" = false ]; then
        info "生成新的密钥对..."
        if ! generate_keys; then
            error "生成密钥对失败"
            return 1
        fi
        need_upload=true
    fi
    
    # 如果需要上传，执行上传操作
    if [ "$need_upload" = true ]; then
        info "上传新生成的配置到WebDAV..."
        if ! upload_to_webdav "$user" "$pass"; then
            error "配置上传失败"
            return 1
        fi
    fi
    
    return 0
}

# 上传文件到WebDAV
upload_to_webdav() {
    local user="$1"
    local pass="$2"
    
    info "正在上传文件到WebDAV..."
    
    # 确保目标目录存在
    if ! curl -s -k -X MKCOL -u "$user:$pass" "$WEBDAV_FULL_URL" > /dev/null 2>&1; then
        warn "创建WebDAV目录失败，目录可能已存在"
    fi
    
    local upload_failed=false
    
    # 检查WebDAV上是否已存在密钥文件
    if ! curl -s -k -I -u "$user:$pass" "$WEBDAV_FULL_URL/$KEY_NAME" | grep -q "HTTP/.*[[:space:]]2"; then
        info "WebDAV上不存在密钥，准备上传..."
        # 上传密钥文件
        if [ -f "$SSH_DIR/$KEY_NAME" ]; then
            info "上传SSH密钥..."
            if ! curl -s -k -T "$SSH_DIR/$KEY_NAME" -u "$user:$pass" "$WEBDAV_FULL_URL/$KEY_NAME" || \
               ! curl -s -k -T "$SSH_DIR/${KEY_NAME}.pub" -u "$user:$pass" "$WEBDAV_FULL_URL/${KEY_NAME}.pub"; then
                error "SSH密钥上传失败"
                upload_failed=true
            else
                success "SSH密钥上传成功"
            fi
        fi
    else
        info "WebDAV上已存在密钥，跳过上传"
    fi
    
    # 上传主机列表前先删除现有文件
    if [ -f "$HOSTS_FILE" ]; then
        info "删除WebDAV上的现有hosts文件..."
        curl -s -k -X DELETE -u "$user:$pass" "$WEBDAV_FULL_URL/hosts" > /dev/null 2>&1
        
        info "上传新的主机列表..."
        if ! curl -s -k -T "$HOSTS_FILE" -u "$user:$pass" "$WEBDAV_FULL_URL/hosts"; then
            error "主机列表上传失败"
            upload_failed=true
        else
            success "主机列表上传成功"
        fi
    fi
    
    if [ "$upload_failed" = true ]; then
        return 1
    fi
    
    return 0
}

# 授权当前主机
authorize_current_host() {
    local hostname
    hostname=$(hostname)
    local timestamp
    timestamp=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')
    
    # 首先检查并修复SSH配置
    info "检查当前主机的SSH配置..."
    if ! check_and_fix_ssh_config; then
        warn "SSH配置检查/修复失败，但将继续尝试授权过程"
    fi
    
    # 检查主机是否已经在列表中
    if grep -q "^${hostname}|" "$HOSTS_FILE"; then
        info "主机 ${hostname} 已在授权列表中"
    else
        echo "${hostname}|${timestamp}" >> "$HOSTS_FILE"
        sort -t'|' -k1,1 -u "$HOSTS_FILE" -o "$HOSTS_FILE"
        success "已授权当前主机: ${hostname} (${timestamp})"
    fi
    
    # 确保.ssh目录和authorized_keys文件存在且权限正确
    local ssh_dir="$HOME/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"
    
    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi
    
    if [ ! -f "$auth_keys" ]; then
        touch "$auth_keys"
    fi
    
    chmod 600 "$auth_keys"
    
    # 将公钥添加到authorized_keys
    if [ -f "$SSH_DIR/${KEY_NAME}.pub" ]; then
        cat "$SSH_DIR/${KEY_NAME}.pub" >> "$auth_keys"
        sort -u "$auth_keys" -o "$auth_keys"
        success "公钥已添加到authorized_keys"
    else
        error "找不到公钥文件：$SSH_DIR/${KEY_NAME}.pub"
        return 1
    fi
    
    return 0
}

# 检查并修复SSH配置
check_and_fix_ssh_config() {
    info "检查SSH配置..."
    local sshd_config="/etc/ssh/sshd_config"
    local needs_restart=false
    
    # 检查是否有root权限
    if [ "$(id -u)" -ne 0 ]; then
        warn "需要root权限来修改SSH配置"
        if command -v sudo >/dev/null 2>&1; then
            info "尝试使用sudo获取权限..."
        else
            error "无法修改SSH配置：需要root权限且系统未安装sudo"
            return 1
        fi
    fi
    
    # 检查sshd_config是否存在
    if [ ! -f "$sshd_config" ]; then
        error "找不到SSH配置文件：$sshd_config"
        return 1
    fi
    
    # 备份配置文件
    local backup_file="${sshd_config}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! sudo cp "$sshd_config" "$backup_file"; then
        error "无法创建配置文件备份"
        return 1
    fi
    info "已创建SSH配置备份：$backup_file"
    
    # 检查并启用PubkeyAuthentication
    if ! sudo grep -q "^PubkeyAuthentication yes" "$sshd_config"; then
        info "启用PubkeyAuthentication..."
        # 注释掉所有PubkeyAuthentication行
        sudo sed -i 's/^[#]*PubkeyAuthentication.*//' "$sshd_config"
        # 添加新的配置
        echo "PubkeyAuthentication yes" | sudo tee -a "$sshd_config" > /dev/null
        needs_restart=true
    fi
    
    # 检查AuthorizedKeysFile配置
    if ! sudo grep -q "^AuthorizedKeysFile" "$sshd_config"; then
        info "配置AuthorizedKeysFile..."
        echo "AuthorizedKeysFile .ssh/authorized_keys" | sudo tee -a "$sshd_config" > /dev/null
        needs_restart=true
    fi
    
    # 如果配置有改动，重启SSH服务
    if [ "$needs_restart" = true ]; then
        info "SSH配置已修改，重启SSH服务..."
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl restart sshd
        elif command -v service >/dev/null 2>&1; then
            sudo service sshd restart
        else
            error "无法重启SSH服务：未找到systemctl或service命令"
            return 1
        fi
        success "SSH服务已重启，配置生效"
    else
        info "SSH配置正确，无需修改"
    fi
    
    return 0
}

# 显示授权主机列表
list_hosts() {
    echo
    info "授权主机列表："
    if [ -f "$HOSTS_FILE" ] && [ -s "$HOSTS_FILE" ] && ! grep -q "^<!DOCTYPE\|^<html\|^<a href=" "$HOSTS_FILE"; then
        echo "主机名                  授权时间"
        echo "----------------------------------------"
        while IFS='|' read -r host timestamp; do
            printf "%-22s %s\n" "$host" "$timestamp"
        done < "$HOSTS_FILE"
    else
        echo "暂无授权主机"
        : > "$HOSTS_FILE"
        chmod 600 "$HOSTS_FILE"
    fi
}

# 显示功能帮助信息
show_feature_help() {
    local feature="$1"
    case $feature in
        "sync")
            echo "从WebDAV同步功能说明："
            echo "此功能用于从WebDAV服务器同步SSH密钥和主机授权列表。"
            echo
            echo "主要步骤："
            echo "1. 检查并下载WebDAV上的SSH密钥"
            echo "2. 验证密钥的有效性"
            echo "3. 同步主机授权列表"
            echo
            echo "注意事项："
            echo "- 确保WebDAV服务器可访问"
            echo "- 需要正确的用户名和密码"
            echo "- 同步过程中不会删除本地已有的授权"
            ;;
        "hosts")
            echo "授权主机列表功能说明："
            echo "此功能显示所有已授权的主机及其授权时间。"
            echo
            echo "显示信息："
            echo "- 主机名"
            echo "- 授权时间（北京时间）"
            echo
            echo "注意事项："
            echo "- 时间戳格式：YYYY-MM-DD HH:MM:SS"
            echo "- 列表按主机名排序"
            echo "- 重复授权会更新时间戳"
            ;;
        "help")
            show_help
            ;;
        *)
            error "未知的功能选项"
            ;;
    esac
}

# 处理菜单选择
handle_menu() {
    while true; do
        echo
        echo "=== SSH Manager 菜单 ==="
        echo "1. 查看授权主机列表"
        echo "2. 从WebDAV同步"
        echo "3. 上传授权列表到WebDAV"
        echo "4. 查看帮助信息"
        echo "0. 退出程序并清除配置"
        echo "===================="
        
        read -p "请选择操作 [0-4]: " choice
        
        case $choice in
            1)
                echo
                if ! list_hosts; then
                    error "查看授权主机列表失败"
                    return 1
                fi
                ;;
            2)
                echo
                info "从WebDAV同步..."
                if [ -z "$WEBDAV_USER" ] || [ -z "$WEBDAV_PASS" ]; then
                    error "WebDAV凭据未设置"
                    return 1
                fi
                if download_from_webdav "$WEBDAV_USER" "$WEBDAV_PASS"; then
                    success "文件已成功从WebDAV同步"
                fi
                ;;
            3)
                info "上传授权列表到WebDAV..."
                if [ -z "$WEBDAV_USER" ] || [ -z "$WEBDAV_PASS" ]; then
                    error "WebDAV凭据未设置"
                    return 1
                fi
                if ! upload_to_webdav "$WEBDAV_USER" "$WEBDAV_PASS"; then
                    error "授权列表上传失败"
                    return 1
                fi
                ;;
            4)
                echo
                show_help
                ;;
            0)
                echo "退出程序..."
                # 删除配置文件以保护凭据安全
                if [ -f "$CONFIG_FILE" ]; then
                    rm -f "$CONFIG_FILE"
                    echo "已清除配置文件"
                fi
                exit 0
                ;;
            *)
                error "无效的选择"
                ;;
        esac
    done
}

# 上传授权列表到WebDAV
upload_hosts_to_webdav() {
    local user="$1"
    local pass="$2"
    
    info "正在上传授权列表到WebDAV..."
    
    # 检查主机列表文件是否存在
    if [ ! -f "$HOSTS_FILE" ]; then
        error "授权列表文件不存在"
        return 1
    fi
    
    # 确保目标目录存在
    if ! curl -s -k -X MKCOL -u "$user:$pass" "$WEBDAV_FULL_URL" > /dev/null 2>&1; then
        warn "创建WebDAV目录失败，目录可能已存在"
    fi
    
    local upload_failed=false
    
    # 检查WebDAV上是否已存在主机列表文件
    if ! curl -s -k -I -u "$user:$pass" "$WEBDAV_FULL_URL/hosts" | grep -q "HTTP/.*[[:space:]]2"; then
        info "WebDAV上不存在主机列表，准备上传..."
        # 上传主机列表
        if [ -f "$HOSTS_FILE" ]; then
            if ! curl -s -k -T "$HOSTS_FILE" -u "$user:$pass" "$WEBDAV_FULL_URL/hosts"; then
                error "主机列表上传失败"
                upload_failed=true
            else
                success "主机列表上传成功"
            fi
        fi
    else
        info "WebDAV上已存在主机列表，跳过上传"
    fi
    
    if [ "$upload_failed" = true ]; then
        return 1
    fi
    
    return 0
}

# 显示帮助信息
show_help() {
    echo "SSH Manager - SSH密钥管理工具 v2.0.0"
    echo
    echo "使用方法: $0 [WebDAV用户名 WebDAV密码]"
    echo
    echo "功能说明："
    echo "本工具用于管理多台服务器之间的SSH密钥同步和授权，通过WebDAV实现配置集中管理。"
    echo
    echo "主要功能："
    echo "1. 自动同步SSH密钥配置"
    echo "  - 从WebDAV获取统一的SSH密钥"
    echo "  - 自动配置本地SSH环境"
    echo "  - 确保所有服务器使用相同的密钥"
    echo
    echo "2. 自动授权管理"
    echo "  - 自动将当前主机添加到授权列表"
    echo "  - 维护带时间戳的主机授权记录"
    echo "  - 自动配置SSH服务"
    echo
    echo "3. 安全特性"
    echo "  - 自动设置正确的文件权限"
    echo "  - 配置文件自动备份"
    echo "  - 严格的密钥验证"
    echo
    echo "使用注意事项："
    echo "1. 首次使用："
    echo "  - 需要在第一台服务器上运行以初始化密钥"
    echo "  - 之后所有服务器将使用相同的密钥"
    echo
    echo "2. 权限要求："
    echo "  - 配置SSH服务需要root权限"
    echo "  - 建议使用root用户运行"
    echo
    echo "3. 文件位置："
    echo "  - 配置文件存储在: ~/.ssh_manager/"
    echo "  - SSH密钥存储在: ~/.ssh/"
    echo
    echo "4. WebDAV要求："
    echo "  - 需要可用的WebDAV服务器"
    echo "  - WebDAV服务器需要读写权限"
    echo
    echo "示例："
    echo "  $0 webdav_user webdav_password"
    echo
}

# 配置SSHD
configure_sshd() {
    local sshd_config="/etc/ssh/sshd_config"
    local needs_restart=false
    local backup_file="${sshd_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 检查是否有root权限
    if [ "$(id -u)" -ne 0 ]; then
        error "配置SSHD需要root权限"
        return 1
    fi
    
    # 备份原配置文件
    info "备份当前SSH配置..."
    cp "$sshd_config" "$backup_file"
    
    # 配置PubkeyAuthentication
    if ! grep -q "^PubkeyAuthentication yes" "$sshd_config"; then
        info "启用公钥认证..."
        # 注释掉所有PubkeyAuthentication行
        sed -i 's/^PubkeyAuthentication.*/# &/' "$sshd_config"
        # 添加新的配置
        echo "PubkeyAuthentication yes" >> "$sshd_config"
        needs_restart=true
    fi
    
    # 配置AuthorizedKeysFile
    if ! grep -q "^AuthorizedKeysFile.*authorized_keys" "$sshd_config"; then
        info "配置授权密钥文件路径..."
        # 注释掉所有AuthorizedKeysFile行
        sed -i 's/^AuthorizedKeysFile.*/# &/' "$sshd_config"
        # 添加新的配置
        echo "AuthorizedKeysFile .ssh/authorized_keys" >> "$sshd_config"
        needs_restart=true
    fi
    
    # 如果需要，重启SSH服务
    if [ "$needs_restart" = true ]; then
        info "重启SSH服务..."
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart sshd
        else
            service ssh restart
        fi
        if [ $? -eq 0 ]; then
            success "SSH服务已重启"
        else
            error "SSH服务重启失败"
            return 1
        fi
    else
        info "SSH配置已是最新，无需重启"
    fi
    
    return 0
}

# 主程序入口
main() {
    if [ $# -eq 0 ]; then
        # 如果没有参数，直接显示交互式菜单
        if [ -f "$CONFIG_FILE" ]; then
            # 加载已保存的配置
            source "$CONFIG_FILE"
            if [ -n "$WEBDAV_USER" ] && [ -n "$WEBDAV_PASS" ]; then
                info "使用已保存的WebDAV配置"
                # 测试WebDAV连接
                if test_webdav "$WEBDAV_USER" "$WEBDAV_PASS"; then
                    handle_menu
                else
                    error "WebDAV连接测试失败，请检查配置"
                    exit 1
                fi
            else
                error "未找到WebDAV配置信息"
                show_help
                exit 1
            fi
        else
            # 尝试从环境变量读取配置
            if [ -n "$WEBDAV_USER" ] && [ -n "$WEBDAV_PASS" ]; then
                info "使用环境变量中的WebDAV配置"
                # 保存配置到文件
                mkdir -p "$(dirname "$CONFIG_FILE")"
                echo "WEBDAV_USER='$WEBDAV_USER'" > "$CONFIG_FILE"
                echo "WEBDAV_PASS='$WEBDAV_PASS'" >> "$CONFIG_FILE"
                chmod 600 "$CONFIG_FILE"
                
                # 测试WebDAV连接
                if test_webdav "$WEBDAV_USER" "$WEBDAV_PASS"; then
                    handle_menu
                else
                    error "WebDAV连接测试失败，请检查配置"
                    rm -f "$CONFIG_FILE"
                    exit 1
                fi
            else
                error "未找到配置文件，请先使用用户名和密码参数运行脚本进行初始化"
                show_help
                exit 1
            fi
        fi
    elif [ $# -eq 2 ]; then
        WEBDAV_USER="$1"
        WEBDAV_PASS="$2"
        
        # 测试WebDAV连接
        if ! test_webdav "$WEBDAV_USER" "$WEBDAV_PASS"; then
            error "WebDAV连接测试失败，请检查凭据"
            exit 1
        fi
        
        # 保存配置到文件
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "WEBDAV_USER='$WEBDAV_USER'" > "$CONFIG_FILE"
        echo "WEBDAV_PASS='$WEBDAV_PASS'" >> "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        
        # 初始化环境
        init_env
        
        # 从WebDAV下载配置
        info "从WebDAV下载配置..."
        if ! download_from_webdav "$WEBDAV_USER" "$WEBDAV_PASS"; then
            error "配置下载失败"
            exit 1
        fi
        
        # 配置SSHD
        if ! configure_sshd; then
            error "SSHD配置失败"
            exit 1
        fi
        
        # 授权当前主机
        authorize_current_host
        
        # 上传更新后的主机列表到WebDAV
        if [ -f "$HOSTS_FILE" ]; then
            if ! upload_to_webdav "$WEBDAV_USER" "$WEBDAV_PASS"; then
                error "主机列表上传失败"
                exit 1
            fi
        fi
        
        success "初始配置完成"
        
        # 显示交互式菜单
        handle_menu
    else
        show_help
        exit 1
    fi
}

# 执行主程序
main "$@"
