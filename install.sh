#!/bin/bash

# 定义输出颜色
RED='\033[0;31m'    # 红色
GREEN='\033[0;32m'  # 绿色
YELLOW='\033[0;33m' # 黄色
NC='\033[0m'        # 无颜色

# --- 变量定义 ---
INSTALL_DIR="$(pwd)" # 安装目录，即当前脚本所在目录
BURP_VERSION="2025"  # Burp Suite 版本号，此脚本中固定为2025，若要获取最新版需修改下载逻辑
BURP_JAR="burpsuite_pro_v${BURP_VERSION}.jar" # Burp Suite JAR 文件名
BURP_DOWNLOAD_URL="https://portswigger-cdn.net/burp/releases/download?product=pro&type=Jar" # Burp Suite 下载链接
BURP_EXEC_SCRIPT="burpsuitepro" # 执行Burp Suite的启动脚本名
DESKTOP_ENTRY_NAME="BurpSuite_Professional.desktop" # 桌面快捷方式文件名
DESKTOP_ENTRY_PATH="${HOME}/.local/share/applications/${DESKTOP_ENTRY_NAME}" # 桌面快捷方式存放路径
BURP_ICON_PATH="${INSTALL_DIR}/burp_suite.ico" # Burp Suite 图标路径

# --- 辅助函数 ---

# 打印信息日志
log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

# 打印警告日志
log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 打印错误日志
log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "部分操作（如：安装依赖、创建软链接）需要root权限。请使用 sudo 运行此脚本。"
        exit 1
    fi
}

# 检查软件包是否已安装
package_installed() {
    pacman -Qq "$1" &> /dev/null
}

# 安装依赖项
install_dependencies() {
    log_info "正在处理依赖项..."
    
    # 检查并安装 git
    if ! command -v git &> /dev/null; then
        log_info "正在使用 pacman 安装 git..."
        sudo pacman -Syu --noconfirm git
        if [ $? -ne 0 ]; then
            log_error "通过 pacman 安装 git 失败。请检查您的网络连接或 pacman 配置。"
            exit 1
        fi
    else
        log_info "git 已经安装。"
    fi

    # 检查并安装 jre-openjdk (优先考虑最新的 LTS 或常用版本，这里为了简洁和兼容性，只检查jre-openjdk)
    if ! package_installed "jre-openjdk"; then
        log_info "正在使用 pacman 安装 jre-openjdk..."
        # 尝试安装一个通用的 jre-openjdk 包。ArchLinux 通常会提供默认的JRE。
        # 如果需要特定版本，例如 openjdk-17-jre，可以替换这里的包名。
        sudo pacman -Syu --noconfirm jre-openjdk
        if [ $? -ne 0 ]; then
            log_error "通过 pacman 安装 jre-openjdk 失败。请检查您的网络连接或 pacman 配置。"
            log_error "您可能需要手动安装一个适合的 jre-openjdk 版本，例如 'openjdk-17-jre' 或 'openjdk-21-jre'。"
            exit 1
        fi
    else
        log_info "jre-openjdk 已经安装。"
    fi

    # 接着处理 axel，它通常在 AUR 中
    if ! command -v axel &> /dev/null; then
        log_warn "'axel' 未安装。它通常用于加速下载，且在 Arch Linux 上位于 AUR (Arch User Repository)。"
        log_info "尝试使用 paru 或 yay 安装 axel..."
        if command -v paru &> /dev/null; then
            sudo paru -S --noconfirm axel
        elif command -v yay &> /dev/null; then
            sudo yay -S --noconfirm axel
        else
            log_warn "未检测到 paru 或 yay。您需要手动从 AUR 安装 'axel'，例如："
            log_warn "  git clone https://aur.archlinux.org/axel.git"
            log_warn "  cd axel"
            log_warn "  makepkg -si"
            log_warn "${YELLOW}（如果您选择不安装 axel，下载速度可能会较慢，但不影响功能。）${NC}"
            read -p "是否继续安装，即使没有安装 axel？ (Y/n): " confirm_continue
            if [[ "$confirm_continue" =~ ^[Nn]$ ]]; then
                log_info "用户选择终止安装。"
                exit 0
            fi
        fi
        
        # 再次检查 axel 是否安装成功，如果仍未安装则使用 wget 回退
        if ! command -v axel &> /dev/null; then
            log_warn "axel 安装失败或用户选择不安装。将使用 wget 进行下载（速度可能较慢）。"
            USE_WGET_FALLBACK=true # 标记以备后续下载函数使用 wget
        fi
    else
        log_info "axel 已经安装。"
    fi

    # 最终检查核心命令是否可用
    if ! command -v java &> /dev/null || ! command -v git &> /dev/null; then
        log_error "核心依赖 (Java 或 Git) 仍然缺失。请手动解决依赖问题后重试。"
        exit 1
    fi

    log_info "所有必需依赖（或替代方案）已处理。"
}

# 下载 Burp Suite Professional
download_burpsuite() {
    log_info "正在下载 Burp Suite Professional v${BURP_VERSION}..."
    
    if [ "$USE_WGET_FALLBACK" = true ]; then
        log_info "使用 wget 下载 Burp Suite (因为 axel 不可用)..."
        wget -O "${INSTALL_DIR}/${BURP_JAR}" "${BURP_DOWNLOAD_URL}"
    else
        log_info "使用 axel 下载 Burp Suite..."
        axel "${BURP_DOWNLOAD_URL}" -o "${INSTALL_DIR}/${BURP_JAR}"
    fi

    if [ $? -ne 0 ]; then
        log_error "下载 Burp Suite Professional 失败。请检查下载链接和您的网络连接。"
        log_error "您可以尝试手动下载 '${BURP_DOWNLOAD_URL}' 并将其重命名为 '${BURP_JAR}' 放到当前目录，然后重新运行脚本。"
        exit 1
    fi
    log_info "Burp Suite Professional 已下载到 ${INSTALL_DIR}/${BURP_JAR}"
}

# 创建 Burp Suite 启动脚本
create_burp_exec_script() {
    log_info "正在创建 Burp Suite Professional 启动脚本..."
    echo "#!/bin/bash" > "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    echo "cd \"${INSTALL_DIR}\"" >> "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}" # 确保脚本在正确的目录中运行
    echo "java --add-opens=java.desktop/javax.swing=ALL-UNNAMED \\" >> "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    echo "     --add-opens=java.base/java.lang=ALL-UNNAMED \\" >> "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    echo "     --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \\" >> "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    echo "     --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED \\" >> "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    echo "     --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED \\" >> "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    echo "     -javaagent:\"${INSTALL_DIR}/loader.jar\" -noverify -jar \"${INSTALL_DIR}/${BURP_JAR}\" \"\$@\"" >> "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    chmod +x "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    
    # 可选：创建到 /usr/local/bin 的软链接，以便全局访问
    if [ -w /usr/local/bin ]; then
        log_info "正在 /usr/local/bin 中创建软链接..."
        sudo ln -sf "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}" /usr/local/bin/burpsuitepro
    else
        log_warn "无法在 /usr/local/bin 中创建软链接（权限不足）。您需要从 ${INSTALL_DIR}/${BURP_EXEC_SCRIPT} 运行 Burp Suite。"
    fi
    log_info "Burp Suite Professional 启动脚本已创建到 ${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
}

# 创建桌面快捷方式 (KDE 桌面环境适用)
create_desktop_entry() {
    log_info "正在创建 KDE 桌面快捷方式..."
    mkdir -p "${HOME}/.local/share/applications" # 确保目录存在
    
    echo "[Desktop Entry]" > "${DESKTOP_ENTRY_PATH}"
    echo "Name=Burp Suite Professional" >> "${DESKTOP_ENTRY_PATH}"
    echo "Comment=Web 渗透测试工具" >> "${DESKTOP_ENTRY_PATH}"
    echo "Exec=${INSTALL_DIR}/${BURP_EXEC_SCRIPT}" >> "${DESKTOP_ENTRY_PATH}"
    
    # 检查图标文件是否存在，如果存在则设置图标
    if [ -f "${BURP_ICON_PATH}" ]; then
        echo "Icon=${BURP_ICON_PATH}" >> "${DESKTOP_ENTRY_PATH}"
    else
        log_warn "Burp Suite 图标文件 ${BURP_ICON_PATH} 未找到，桌面快捷方式将没有自定义图标。"
    fi
    
    echo "Terminal=false" >> "${DESKTOP_ENTRY_PATH}" # 不在终端中运行
    echo "Type=Application" >> "${DESKTOP_ENTRY_PATH}"
    echo "Categories=Development;Security;Network;Utility;" >> "${DESKTOP_ENTRY_PATH}" # 分类，方便在应用菜单中查找
    echo "StartupNotify=true" >> "${DESKTOP_ENTRY_PATH}" # 启动时显示通知
    
    # 更新桌面数据库
    update-desktop-database "${HOME}/.local/share/applications" &> /dev/null || log_warn "无法更新桌面数据库，快捷方式可能需要重启桌面环境才能显示。"
    
    log_info "KDE 桌面快捷方式已创建到 ${DESKTOP_ENTRY_PATH}"
}

# --- 脚本主要功能函数 ---

# 安装 Burp Suite
install_burp() {
    log_info "正在开始安装 Burp Suite Professional..."
    
    # 检查Burp Suite是否已安装
    if [ -f "${INSTALL_DIR}/${BURP_JAR}" ]; then
        log_warn "Burp Suite Professional 似乎已安装在此目录中。"
        read -p "您想重新安装/更新吗？ (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "用户取消了安装。"
            exit 0
        fi
        uninstall_burp_core # 清理现有文件以便重新安装
    fi

    install_dependencies
    download_burpsuite
    create_burp_exec_script
    create_desktop_entry
    log_info "Burp Suite Professional 安装完成！"
    log_info "您现在可以通过应用菜单或运行 '${INSTALL_DIR}/${BURP_EXEC_SCRIPT}' 来启动 Burp Suite Professional。"
}

# 升级 Burp Suite
upgrade_burp() {
    log_info "正在开始升级 Burp Suite Professional..."
    
    if [ ! -f "${INSTALL_DIR}/loader.jar" ] || [ ! -f "${BURP_ICON_PATH}" ]; then
        log_error "Burp Suite Professional 似乎未安装在此目录中，或缺少必要文件。"
        log_info "请先运行 'install' 命令。"
        exit 1
    fi

    # 当前脚本的“升级”仅限于重新下载指定版本的JAR包。
    # 要实现真正的“最新版升级”，需要修改脚本以解析PortSwigger的最新发布信息。
    log_info "当前脚本使用固定版本 (${BURP_VERSION})。将重新下载此版本以进行“升级”。"
    log_info "${YELLOW}警告：此升级并非动态获取最新版本，而是重新下载指定版本。${NC}"
    
    rm -f "${INSTALL_DIR}/${BURP_JAR}" # 删除旧的JAR包
    download_burpsuite
    create_burp_exec_script # 重新创建以防参数变化或确保软链接有效
    
    log_info "Burp Suite Professional 升级完成！"
    log_info "如果 Burp Suite 正在运行，请重启它以应用更新。"
}

# 卸载 Burp Suite 核心文件
uninstall_burp_core() {
    log_info "正在从 ${INSTALL_DIR} 移除 Burp Suite Professional 文件..."
    rm -f "${INSTALL_DIR}/${BURP_JAR}"
    rm -f "${INSTALL_DIR}/${BURP_EXEC_SCRIPT}"
    # 不删除 loader.jar 和 burp_suite.ico，因为它们是原始仓库的一部分。
    log_info "核心 Burp Suite Professional 文件已移除。"
}

# 卸载 Burp Suite
uninstall_burp() {
    log_info "正在开始卸载 Burp Suite Professional..."
    
    uninstall_burp_core

    log_info "正在移除桌面快捷方式和软链接（如果存在）..."
    rm -f "${DESKTOP_ENTRY_PATH}"
    sudo rm -f "/usr/local/bin/burpsuitepro" # 移除软链接
    
    # 更新桌面数据库
    update-desktop-database "${HOME}/.local/share/applications" &> /dev/null || log_warn "无法更新桌面数据库，卸载的快捷方式可能需要重启桌面环境才能消失。"
    
    log_info "Burp Suite Professional 卸载完成！"
    log_info "注意：'loader.jar' 和 'burp_suite.ico' 仍然保留在当前目录中，因为它们是原始仓库的一部分。"
}

# 运行注册器
register_burp() {
    log_info "正在启动 Burp Suite Professional 密钥生成器..."
    
    if [ ! -f "${INSTALL_DIR}/loader.jar" ]; then
        log_error "loader.jar 未在 ${INSTALL_DIR} 中找到。无法启动密钥生成器。"
        log_info "请确保您位于 'Burpsuite-Professional' 仓库目录中，并先运行 'install' 命令。"
        exit 1
    fi
    
    log_info "正在启动 loader.jar。请按照密钥生成器窗口中的提示进行操作。"
    log_info ""
    log_info "${YELLOW}***** 注册提示 *****${NC}"
    log_info "${YELLOW}1. 等待密钥生成器窗口弹出。通常会显示一个 'License Request' 文本框。${NC}"
    log_info "${YELLOW}2. 通常，您需要点击密钥生成器中的 'Run' 或 'Generate License Request' 按钮，然后将生成的 'License Request' 内容复制下来。${NC}"
    log_info "${YELLOW}3. 将复制的 'License Request' 粘贴到 PortSwigger 官方提供的激活页面或工具中，以获取 'License Response'。${NC}"
    log_info "${YELLOW}4. 从 PortSwigger 页面获取到 'License Response' 后，将其粘贴回密钥生成器中的相应位置。${NC}"
    log_info "${YELLOW}5. 密钥生成器会根据 'License Response' 为您生成最终的许可证文件或激活码（例如 'License' 文本框中的内容）。${NC}"
    log_info "${YELLOW}6. 首次启动 Burp Suite Professional 时，它会提示您输入或导入许可证。请将步骤5中获取的许可证信息填入。${NC}"
    log_info "${YELLOW}********************${NC}"
    log_info ""
    
    (java -jar "${INSTALL_DIR}/loader.jar") # 在后台运行，不阻塞脚本
    log_info "密钥生成器进程已启动。如果未弹出窗口，请检查您的Java环境配置或查看终端是否有错误信息。"
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install    安装 Burp Suite Professional (依赖、下载、设置启动脚本、桌面快捷方式)。"
    echo "  upgrade    升级/重新下载指定版本的 Burp Suite Professional JAR 包。"
    echo "  uninstall  卸载 Burp Suite Professional 文件和桌面快捷方式。"
    echo "  register   运行 Burp Suite Professional 密钥生成器 (loader.jar)。"
    echo "  help       显示此帮助信息。"
    echo ""
    echo "注意：此脚本假定您在 'Burpsuite-Professional' 目录下运行。"
}

# --- 主脚本逻辑 ---

case "$1" in
    install)
        check_root # 安装依赖和创建软链接可能需要root权限
        install_burp
        ;;
    upgrade)
        check_root # 升级时可能需要root权限更新依赖或创建软链接
        upgrade_burp
        ;;
    uninstall)
        check_root # 卸载软链接需要root权限
        uninstall_burp
        ;;
    register)
        register_burp
        ;;
    help | *)
        show_help
        ;;
esac
