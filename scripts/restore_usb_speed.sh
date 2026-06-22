#!/bin/bash
# Script: restore_usb_speed.sh
# Purpose: Restore original Device Tree Blob (DTB) from backup to revert USB speed limiting

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
DTB_PATH="/lib/firmware/$KERNEL_VERSION/device-tree/rockchip/rk3588-orangepi-5-plus.dtb"
if [ ! -f "$DTB_PATH" ]; then
  echo "DTB not found at default location. Searching /lib/firmware..."
  DTB_PATH=$(find /lib/firmware -name "rk3588-orangepi-5-plus.dtb" | head -n 1)
fi

if [ -z "$DTB_PATH" ] || [ ! -f "$DTB_PATH" ]; then
  echo "Error: Could not find rk3588-orangepi-5-plus.dtb on this system."
  exit 1
fi

BACKUP_PATH="${DTB_PATH}.bak"
if [ ! -f "$BACKUP_PATH" ]; then
  echo "Error: Backup file $BACKUP_PATH does not exist. Cannot restore."
  exit 1
fi

echo "Restoring original DTB from backup: $BACKUP_PATH -> $DTB_PATH"
cp "$BACKUP_PATH" "$DTB_PATH"

echo "Successfully restored original Device Tree!"
echo "Please reboot your system (e.g. run 'reboot') to apply the changes."
