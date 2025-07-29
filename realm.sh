#!/bin/bash

# 定义变量
VERSION="v2.7.0"
FILENAME="realm-x86_64-unknown-linux-gnu.tar.gz"
URL="https://github.com/zhboner/realm/releases/download/${VERSION}/${FILENAME}"
INSTALL_DIR="/opt/realm"
SERVICE_NAME="realm.service"
CONFIG_FILE="${INSTALL_DIR}/config.toml"
EXPECTED_BIN="${INSTALL_DIR}/realm"

# 获取脚本当前运行目录（关键修正）
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
LOCAL_FILE="${SCRIPT_DIR}/${FILENAME}"  # 压缩包应在脚本目录检测

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用sudo或root权限运行此脚本"
    exit 1
fi

# 清理旧的损坏文件（仅删除安装目录的残留，不影响脚本目录的压缩包）
if [ ! -f "${EXPECTED_BIN}" ]; then
    echo "清除安装目录的损坏文件..."
    rm -f "${INSTALL_DIR:?}/${FILENAME}"  # 谨慎删除，避免误删目录
fi

# 创建安装目录并确保权限
mkdir -p "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"

# 下载文件（优先检查脚本当前目录的压缩包）
if [ -f "${LOCAL_FILE}" ]; then
    echo "脚本目录中发现 ${FILENAME}，跳过下载"
    # 复制到安装目录（覆盖可能存在的损坏文件）
    cp -f "${LOCAL_FILE}" "${INSTALL_DIR}/${FILENAME}"
else
    echo "下载 Realm ${VERSION}..."
    if ! wget --no-check-certificate "${URL}" -O "${INSTALL_DIR}/${FILENAME}"; then
        echo "下载失败，请检查网络连接"
        exit 1
    fi
fi

# 检查压缩包完整性（大小校验）
if [ $(stat -c %s "${INSTALL_DIR}/${FILENAME}") -lt 1048576 ]; then
    echo "错误：压缩包不完整（小于1MB），可能下载失败"
    rm -f "${INSTALL_DIR}/${FILENAME}"
    exit 1
fi

# 解压文件
echo "解压文件..."
if ! tar -zxvf "${INSTALL_DIR}/${FILENAME}" -C "${INSTALL_DIR}"; then
    echo "解压失败，压缩包可能损坏"
    exit 1
fi

# 验证可执行文件
if [ ! -f "${EXPECTED_BIN}" ]; then
    echo "错误：解压后未找到可执行文件 ${EXPECTED_BIN}"
    exit 1
fi
chmod +x "${EXPECTED_BIN}"

# 生成配置文件（带注释）
echo "生成配置文件..."
cat > "${CONFIG_FILE}" << EOF
[log]
# 日志级别：trace, debug, info, warn, error
#level = "warn"
# 日志输出路径，可指定文件或stdout/stderr
#output = "realm.log"
[network]
# 是否禁用TCP转发
no_tcp = false
# 是否启用UDP转发
use_udp = true
# [[endpoints]] 定义转发规则，可添加多个
# [[endpoints]]
# listen = "本地监听地址:端口"
# remote = "远程目标地址:端口"
[[endpoints]]
listen = "127.0.0.1:5000"
remote = "127.0.0.1:443"
[[endpoints]]
listen = "[::]:11111"
remote = "127.0.0.1:443"
EOF

# 创建系统服务
echo "配置系统服务..."
cat > "/etc/systemd/system/${SERVICE_NAME}" << EOF
[Unit]
Description=realm - 高性能中继服务器
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
ExecStart=${INSTALL_DIR}/realm -c ${CONFIG_FILE}
[Install]
WantedBy=multi-user.target
EOF

# 启动服务并设置开机自启
echo "启动服务..."
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

# 检查服务状态
echo "服务状态检查："
systemctl status "${SERVICE_NAME}" --no-pager

echo "Realm 安装配置完成，可执行文件路径：${INSTALL_DIR}/realm，配置文件路径：${CONFIG_FILE}"
