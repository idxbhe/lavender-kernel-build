#!/bin/bash
# ============================================================================
# get-device-info.sh
# Collect all AnyKernel3 device info from Android (root required)
# Run this in Termux/ADB shell, then share the output
# ============================================================================

echo "============================================"
echo "  ANYKERNEL3 DEVICE INFO COLLECTOR"
echo "  (Root required) - Redmi Note 7 (lavender)"
echo "============================================"
echo ""

# ---------- 1. BOOT PARTITION PATH ----------
echo "--- [1] BOOT PARTITION PATH ---"
echo "Finding boot partition block device..."
echo ""

# Method 1: /proc/mounts
echo "  From /proc/mounts:"
grep -E "^/dev/block.* /boot " /proc/mounts 2>/dev/null || echo "  (not found in /proc/mounts)"

# Method 2: /dev/block/by-name/ symlink
echo ""
echo "  From /dev/block/by-name/:"
ls -la /dev/block/by-name/boot 2>/dev/null || echo "  (symlink not found)"

# Method 3: /dev/block/bootdevice/by-name/
echo ""
echo "  From /dev/block/bootdevice/by-name/:"
ls -la /dev/block/bootdevice/by-name/boot 2>/dev/null || echo "  (not found in bootdevice/by-name)"

# Method 4: Partitions list
echo ""
echo "  Available by-name partitions:"
ls /dev/block/by-name/ 2>/dev/null || echo "  (no by-name directory)"

# Method 5: All block devices
echo ""
echo "  All block devices:"
ls /dev/block/ 2>/dev/null || echo "  (no /dev/block)"

# Method 6: cat /proc/partitions
echo ""
echo "  From /proc/partitions:"
cat /proc/partitions 2>/dev/null || echo "  (not found)"

echo ""

# ---------- 2. A/B SLOTS ----------
echo "--- [2] A/B SLOTS STATUS ---"
echo ""

echo "  ro.boot.slot_suffix:"
getprop ro.boot.slot_suffix 2>/dev/null || echo "  (getprop not available)"

echo "  ro.boot.slot:"
getprop ro.boot.slot 2>/dev/null || echo "  (getprop not available)"

echo "  From /proc/cmdline:"
cat /proc/cmdline 2>/dev/null | tr ' ' '\n' | grep -i slot || echo "  (no slot info in cmdline)"

echo ""
echo "  Available slot partitions:"
ls /dev/block/by-name/ 2>/dev/null | grep -E "_a$|_b$" || echo "  (no A/B partitions found)"

echo ""

# ---------- 3. FSTAB FILE ----------
echo "--- [3] FSTAB FILE ---"
echo ""

echo "  Searching for fstab files in /system..."
echo ""

echo "  Common fstab locations:"
for path in \
    /system/etc/fstab.qcom \
    /system/etc/fstab \
    /system/etc/fstab.miui.xml \
    /system/etc/fstab.{$product,system}/etc/fstab.qcom \
    /vendor/etc/fstab.qcom \
    /vendor/etc/fstab.vendor \
    /etc/fstab.qcom \
    /etc/fstab.miui.xml; do
    if [ -f "$path" ]; then
        echo "  FOUND: $path"
    fi
done

echo ""
echo "  All fstab files:"
find /system /vendor /etc -name "fstab*" -type f 2>/dev/null | head -20

echo ""
echo "  Most likely fstab file path:"
for path in \
    /system/etc/fstab.qcom \
    /system/etc/fstab \
    /vendor/etc/fstab.qcom \
    /vendor/etc/fstab.vendor \
    /system/etc/fstab.miui.xml; do
    if [ -f "$path" ]; then
        echo "  >>> $path <<<"
        break
    fi
done

echo ""

# ---------- 4. FSTAB CONTENT (CRITICAL) ----------
echo "--- [4] FSTAB CONTENT ---"
echo "  (This shows mount options for /system, /data, /cache)"
echo ""

# Find the actual fstab file
FSTAB_PATH=""
for path in \
    /system/etc/fstab.qcom \
    /system/etc/fstab \
    /vendor/etc/fstab.qcom \
    /vendor/etc/fstab.vendor \
    /system/etc/fstab.miui.xml \
    /etc/fstab.qcom; do
    if [ -f "$path" ]; then
        FSTAB_PATH="$path"
        break
    fi
done

if [ -n "$FSTAB_PATH" ]; then
    echo "  Reading: $FSTAB_PATH"
    echo "  --- START ---"
    cat "$FSTAB_PATH" 2>/dev/null
    echo "  --- END ---"
else
    echo "  ERROR: No fstab file found!"
fi

echo ""

# ---------- 5. DEVICE INFO ----------
echo "--- [5] DEVICE INFO ---"
echo ""

echo "  ro.product.device:"
getprop ro.product.device 2>/dev/null || echo "  (not available)"

echo "  ro.product.model:"
getprop ro.product.model 2>/dev/null || echo "  (not available)"

echo "  ro.board.platform:"
getprop ro.board.platform 2>/dev/null || echo "  (not available)"

echo "  ro.build.product:"
getprop ro.build.product 2>/dev/null || echo "  (not available)"

echo ""

# ---------- 6. KERNEL INFO ----------
echo "--- [6] CURRENT KERNEL ---"
echo ""

echo "  uname -r:"
uname -r 2>/dev/null || echo "  (not available)"

echo ""
echo "  uname -a:"
uname -a 2>/dev/null || echo "  (not available)"

echo ""

# ---------- 7. RAMDISK FILES ----------
echo "--- [7] RAMDISK FILES ---"
echo "  (Files in root of ramdisk)"
echo ""

echo "  / directory contents:"
ls -la / 2>/dev/null | head -30

echo ""

# Check for init.rc variants
echo "  init.rc files:"
find / -name "init.rc" -type f 2>/dev/null | head -10

echo ""

# Check for device-specific init files
echo "  Device-specific init files (lavender/um575*):"
for pattern in "lavender" "um575" "konka" "sdm660" "sm6125"; do
    files=$(find / -name "init.*.rc" -type f 2>/dev/null | grep -i "$pattern" | head -5)
    if [ -n "$files" ]; then
        echo "  Pattern '$pattern':"
        echo "$files"
    fi
done

echo ""

# ---------- 8. INIT.RC SNIPPETS ----------
echo "--- [8] INIT.RC MOUNT OPTIONS ---"
echo ""

if [ -f /init.rc ]; then
    echo "  From /init.rc (mount commands):"
    grep -A2 "^mount " /init.rc 2>/dev/null | head -30
elif [ -f /system/etc/fstab.qcom ]; then
    echo "  (mount info from fstab is more important)"
fi

echo ""

# ---------- 9. BOOT IMAGE INFO ----------
echo "--- [9] BOOT IMAGE INFO ---"
echo ""

echo "  Boot partition size:"
blockdev --getsize64 /dev/block/bootdevice/by-name/boot 2>/dev/null || \
blockdev --getsize64 /dev/block/mmcblk0p21 2>/dev/null || \
echo "  (could not determine)"

echo ""
echo "  Boot image magic:"
dd if=/dev/block/bootdevice/by-name/boot bs=64 skip=0 count=1 2>/dev/null | strings | head -5 || \
echo "  (could not read boot image)"

echo ""

# ---------- 10. RECOVERY INFO ----------
echo "--- [10] RECOVERY INFO ---"
echo ""

echo "  Recovery version (if available):"
getprop ro.lineage.releasetype 2>/dev/null || \
getprop ro.lineage.build.type 2>/dev/null || \
echo "  (TWRP or unknown)"

echo ""

# ---------- DONE ----------
echo "============================================"
echo "  COLLECTION COMPLETE"
echo "============================================"
echo ""
echo "Copy ALL output above and send to your kernel"
echo "developer / paste into anykernel.sh editor."
echo ""
echo "ESSENTIAL ITEMS TO PROVIDE:"
echo "  ✓ Boot partition path  (from section 1)"
echo "  ✓ A/B slot status      (from section 2)"
echo "  ✓ Fstab file path      (from section 3)"
echo "  ✓ Fstab content        (from section 4)"
echo "  ✓ Device name          (from section 5)"
