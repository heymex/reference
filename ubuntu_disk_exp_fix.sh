#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Detecting the physical volume backing the root LV..."

# Step 1: Get the physical volume backing the root VG
PV_PATH=$(sudo pvs --noheadings -o pv_name | awk '{$1=$1;print}' | head -n1)

# Step 2: Resolve any symlinks (mapper -> actual partition like /dev/sda3)
PV_PATH=$(readlink -f "$PV_PATH")

# Step 3: Extract the underlying disk and partition number
DISK=$(lsblk -no pkname "$PV_PATH" | head -n1)
DISK="/dev/${DISK}"
PART_NUM=$(echo "$PV_PATH" | grep -o '[0-9]*$')

VG_NAME="ubuntu-vg"
LV_PATH="/dev/mapper/ubuntu--vg-ubuntu--lv"

echo "[INFO] Physical PV: ${PV_PATH}"
echo "[INFO] Base disk: ${DISK}"
echo "[INFO] Partition number: ${PART_NUM}"

# 1. Rescan the disk so kernel sees the new size
echo "[INFO] Rescanning disk size..."
echo 1 | sudo tee "/sys/class/block/$(basename $DISK)/device/rescan" >/dev/null

# 2. Always ensure GPT uses the full disk
echo "[INFO] Ensuring GPT uses full disk (sgdisk -e)..."
sudo sgdisk -e "$DISK" || true

# 3. Resize the last partition to fill the disk
echo "[INFO] Resizing partition ${DISK}${PART_NUM} to use all available space..."
sudo parted --script "$DISK" resizepart "$PART_NUM" 100%

# 4. Show updated partition layout
echo "[INFO] Updated partition table:"
sudo fdisk -l "$DISK" | grep "^$DISK" || true

# 5. Resize the PV to recognize the expanded partition
echo "[INFO] Resizing physical volume on ${PV_PATH}..."
sudo pvresize "$PV_PATH"

# 6. Extend the LV to use all free space in the VG
echo "[INFO] Extending logical volume ${LV_PATH} to all available free space..."
sudo lvextend -l +100%FREE "$LV_PATH"

# 7. Detect filesystem type and grow filesystem accordingly
FS_TYPE=$(lsblk -no FSTYPE "$LV_PATH")
echo "[INFO] Filesystem type detected: $FS_TYPE"

case "$FS_TYPE" in
  ext4)
    echo "[INFO] Resizing ext4 filesystem..."
    sudo resize2fs "$LV_PATH"
    ;;
  xfs)
    echo "[INFO] Resizing XFS filesystem..."
    sudo xfs_growfs /
    ;;
  *)
    echo "[ERROR] Unsupported filesystem type: $FS_TYPE"
    exit 1
    ;;
esac

echo "[INFO] Expansion complete! Final sizes:"
lsblk
df -h /