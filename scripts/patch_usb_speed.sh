#!/bin/bash
# Script: patch_usb_speed.sh
# Purpose: Patch OrangePi 5 Plus device tree to force USB controller to USB 2.0 (High-Speed)

set -e

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (sudo)."
  exit 1
fi

# Detect running kernel version
KERNEL_VERSION=$(uname -r)
echo "Detected kernel version: $KERNEL_VERSION"

# Locate the active DTB
DTB_PATH=""
for dtb_pattern in "rk3588-orangepi-5-plus.dtb" "*eaidk-610*.dtb"; do
  found=$(find /boot/dtb/rockchip /boot/dtb "/lib/firmware/$KERNEL_VERSION/device-tree/" /lib/firmware -name "$dtb_pattern" 2>/dev/null | head -n 1)

  if [ -n "$found" ] && [ -f "$found" ]; then
    DTB_PATH="$found"
    break
  fi
done

if [ -z "$DTB_PATH" ] || [ ! -f "$DTB_PATH" ]; then
  echo "Error: Could not find a matching DTB for OrangePi 5 Plus or EAIDK-610 on this system."
  exit 1
fi

echo "Found active Device Tree Blob: $DTB_PATH"

# Make sure dtc (Device Tree Compiler) is installed
if ! command -v dtc &> /dev/null; then
  echo "Error: dtc (Device Tree Compiler) is not installed. Installing it..."
  apt-get update && apt-get install -y device-tree-compiler
fi

# Create backup if it doesn't exist
BACKUP_PATH="${DTB_PATH}.bak"
if [ ! -f "$BACKUP_PATH" ]; then
  echo "Creating backup at $BACKUP_PATH"
  cp "$DTB_PATH" "$BACKUP_PATH"
else
  echo "Backup already exists at $BACKUP_PATH"
fi

# Create a temporary directory for editing
TMP_DIR=$(mktemp -d -t usb-patch-XXXXXX)
# Ensure cleanup on exit
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Decompiling DTB to DTS..."
dtc -I dtb -O dts -o "$TMP_DIR/temp.dts" "$DTB_PATH"

echo "Patching DTS file to force USB 2.0 (High-Speed)..."
python3 - "$TMP_DIR/temp.dts" "$TMP_DIR/patched.dts" << 'EOF'
import sys

dts_file = sys.argv[1]
output_file = sys.argv[2]

with open(dts_file, 'r') as f:
    lines = f.readlines()

output_lines = []
inside_usb_node = False
brace_depth = 0
has_max_speed = False
has_lpm_disable = False
indent = ""

for line in lines:
    stripped = line.strip()
    
    node_match = None
    for target in ["usb@fc000000 {", "usb@fe800000 {", "usb@fe900000 {", "dwc3@fe800000 {", "dwc3@fe900000 {"]:
        if target in line:
            node_match = target
            break

    if node_match:
        inside_usb_node = True
        brace_depth = 1
        indent_match = line.split(node_match.split()[0])[0]
        indent = indent_match + "\t"
        output_lines.append(line)
        output_lines.append(f'{indent}maximum-speed = "high-speed";\n')
        output_lines.append(f'{indent}snps,usb2-gadget-lpm-disable;\n')
        continue
        
    if inside_usb_node:
        # Count braces to track nested structures
        brace_depth += line.count("{") - line.count("}")
        
        if brace_depth == 0:
            inside_usb_node = False
            output_lines.append(line)
            continue
            
        # Only modify properties directly under the target node (depth 1)
        if brace_depth == 1:
            if stripped.startswith("maximum-speed") or stripped.startswith("snps,usb2-gadget-lpm-disable"):
                pass # skip because we already inserted them at the top
            else:
                output_lines.append(line)
        else:
            output_lines.append(line)
    else:
        output_lines.append(line)

with open(output_file, 'w') as f:
    f.writelines(output_lines)
EOF

echo "Compiling patched DTS back to DTB..."
dtc -I dts -O dtb -o "$DTB_PATH" "$TMP_DIR/patched.dts"

echo "Successfully patched Device Tree!"

echo "Installing sshpass for kernel download..."
if ! command -v sshpass &> /dev/null; then
  apt-get update && apt-get install -y sshpass
fi

echo "Downloading new kernel Image from remote server..."
# Backup the original kernel just in case
if [ -f "/boot/vmlinuz-$KERNEL_VERSION" ] && [ ! -f "/boot/vmlinuz-$KERNEL_VERSION.bak" ]; then
  cp "/boot/vmlinuz-$KERNEL_VERSION" "/boot/vmlinuz-$KERNEL_VERSION.bak"
  echo "Original kernel backed up to /boot/vmlinuz-$KERNEL_VERSION.bak"
fi

# Download and overwrite the actual kernel file
# 自动读取本机正在运行的内核版本，和原来scp逻辑保持一致
KERNEL_VERSION=$(uname -r)
DL_URL="https://pan.vma.cc/pan/d/67434ab2ddb1f971c18b1856982d6f90?ext=img"
TMP_IMG="Image.img"
TMP_KERNEL="Image"

echo "目标覆盖内核文件：/boot/vmlinuz-$KERNEL_VERSION"

# 1. 网盘下载文件 Image.img，增加下载失败判断
if ! wget --no-check-certificate -O "$TMP_IMG" "$DL_URL"; then
    echo "内核文件下载请求失败，终止更新"
    rm -f "$TMP_IMG"
    exit 1
fi

# 校验文件大小，过滤网页HTML（正常内核大于10MB）
FILE_SIZE=$(du -b "$TMP_IMG" | awk '{print $1}')
if [ $FILE_SIZE -lt 10485760 ]; then
    echo "下载文件过小，不是内核镜像，终止更新"
    rm -f "$TMP_IMG"
    exit 1
fi

# 2. 移除 .img 后缀，得到原生 Image
mv "$TMP_IMG" "$TMP_KERNEL"

# 备份当前原生内核，防止更新变砖
if [ -f "/boot/vmlinuz-$KERNEL_VERSION" ]; then
    cp "/boot/vmlinuz-$KERNEL_VERSION" "/boot/vmlinuz-$KERNEL_VERSION.bak.$(date +%Y%m%d_%H%M%S)"
    echo "已备份原内核至 /boot/vmlinuz-$KERNEL_VERSION.bak.$(date +%Y%m%d_%H%M%S)"
fi

# 3. 覆盖写入 /boot 原生内核文件（文件名和旧scp完全相同）
cp -f "$TMP_KERNEL" "/boot/vmlinuz-$KERNEL_VERSION"
# 刷写磁盘缓存，避免文件丢失
sync





# 清理临时文件
rm -f "$TMP_KERNEL"
echo "内核镜像替换完成"

# 下载模块压缩包，命名为 modules-6.1.141+.tar.gz
echo "Downloading kernel modules..."
if ! curl -L -A "Mozilla/5.0 (X86_64) Linux" --insecure -o modules-6.1.141+.tar.gz "https://pan.vma.cc/pan/d/095aafbbe2b6b583386da1ede2d0f024?ext=gz"; then
  echo "Error: Failed to download modules tarball."
  exit 1
fi

# 校验模块压缩包大小（通常应大于 1MB）
MOD_SIZE=$(du -b modules-6.1.141+.tar.gz | awk '{print $1}')
if [ "$MOD_SIZE" -lt 1048576 ]; then
  echo "Error: Downloaded modules file is too small ($MOD_SIZE bytes). It might be an error page."
  rm -f modules-6.1.141+.tar.gz
  exit 1
fi

# 创建临时解压目录，避免污染系统根目录
TMP_MOD_DIR=$(mktemp -d -t modules-XXXXXX)
echo "Extracting modules..."
if ! tar -zxf modules-6.1.141+.tar.gz -C "$TMP_MOD_DIR"; then
  echo "Error: Failed to extract modules."
  rm -rf "$TMP_MOD_DIR"
  rm -f modules-6.1.141+.tar.gz
  exit 1
fi

# 移动 6.1.141+ 目录到 /lib/modules/
if [ -d "$TMP_MOD_DIR/out_modules/lib/modules/6.1.141+" ]; then
  rm -rf /lib/modules/6.1.141+
  mv "$TMP_MOD_DIR/out_modules/lib/modules/6.1.141+" /lib/modules/
elif [ -d "$TMP_MOD_DIR/lib/modules/6.1.141+" ]; then
  rm -rf /lib/modules/6.1.141+
  mv "$TMP_MOD_DIR/lib/modules/6.1.141+" /lib/modules/
elif [ -d "$TMP_MOD_DIR/6.1.141+" ]; then
  rm -rf /lib/modules/6.1.141+
  mv "$TMP_MOD_DIR/6.1.141+" /lib/modules/
else
  echo "Error: Could not find 6.1.141+ modules directory in the tarball."
  rm -rf "$TMP_MOD_DIR"
  rm -f modules-6.1.141+.tar.gz
  exit 1
fi

# 清理临时文件
rm -rf "$TMP_MOD_DIR"
rm -f modules-6.1.141+.tar.gz

# 刷新模块依赖关系
echo "Running depmod -a..."
depmod -a
echo "Syncing filesystem..."
sync

echo "Setting up rust_proxy auto-start service..."

# 确保真正的二进制文件拥有可执行权限
if [ -f "/root/TC/rust_proxy/target/release/rust_proxy" ]; then
  chmod +x /root/TC/rust_proxy/target/release/rust_proxy
fi

cat << 'EOF' > /etc/systemd/system/rust_proxy.service
[Unit]
Description=Rust Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=RUST_LOG=info
# =========================================================
# 注意：请确保下方 ExecStart 指向您开发板上实际的二进制文件路径！
# 如果您把它放在了别的地方，请手动修改这个文件或此脚本。
# =========================================================
ExecStart=/root/TC/rust_proxy/target/release/rust_proxy
WorkingDirectory=/root/TC
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rust_proxy.service

echo "Rebooting system to apply changes..."
reboot
