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
sshpass -p 'Imtaizi888.' scp -o StrictHostKeyChecking=no root@121.43.187.59:/root/linux/arch/arm64/boot/Image "/boot/vmlinuz-$KERNEL_VERSION"

if [ $? -ne 0 ]; then
  echo "Error: Failed to download the kernel Image. Aborting reboot."
  exit 1
fi

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
After=network.target

[Service]
Type=simple
# =========================================================
# 注意：请确保下方 ExecStart 指向您开发板上实际的二进制文件路径！
# 如果您把它放在了别的地方，请手动修改这个文件或此脚本。
# =========================================================
ExecStart=/root/TC/rust_proxy/target/release/rust_proxy
WorkingDirectory=/root/TC/rust_proxy
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rust_proxy.service

echo "Rebooting system to apply changes..."
reboot
