#!/bin/bash
set -euo pipefail

# ============================================================================
# build-flashable-zip.sh
# Build flashable AnyKernel3 ZIP for custom kernel
# Usage: ./build-flashable-zip.sh [lavender|konka|...]
# ============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$BASE_DIR/san-kernel-4.19"
ANYKERNEL_DIR="$BASE_DIR/AnyKernel3"
WORK_DIR="$BASE_DIR/anykernel-work"
BUILD_DIR="$BASE_DIR/build-lavender"

# ---------- color helpers ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }
die()   { err "$*"; exit 1; }

# ---------- 1. Validate AnyKernel3 ----------
if [[ ! -d "$ANYKERNEL_DIR" ]]; then
    die "AnyKernel3 not found at: $ANYKERNEL_DIR"
    echo "   Please ensure the AnyKernel3 repo is present before running this script."
fi

if [[ ! -f "$ANYKERNEL_DIR/anykernel.sh" ]]; then
    die "anykernel.sh not found in $ANYKERNEL_DIR"
fi

if [[ ! -f "$ANYKERNEL_DIR/tools/ak3-core.sh" ]]; then
    die "tools/ak3-core.sh not found in $ANYKERNEL_DIR"
fi

ok "AnyKernel3 found."

# ---------- 2. Find kernel image ----------
KERNEL_IMAGE=""
for candidate in \
    "$BUILD_DIR/arch/arm64/boot/Image.gz-dtb" \
    "$BUILD_DIR/arch/arm64/boot/Image" \
    "$BUILD_DIR/arch/arm64/boot/Image.gz"; do

    if [[ -f "$candidate" ]]; then
        KERNEL_IMAGE="$candidate"
        break
    fi
done

if [[ -z "$KERNEL_IMAGE" ]]; then
    die "No kernel image found!"
    echo "   Expected at: $BUILD_DIR/arch/arm64/boot/Image.gz-dtb"
    echo "   Run on-arm-compile.sh first."
fi

ok "Kernel image found: $(basename "$KERNEL_IMAGE")"

# ---------- 3. Clean & create work dir ----------
if [[ -d "$WORK_DIR" ]]; then
    info "Cleaning previous work directory..."
    rm -rf "$WORK_DIR"
fi

info "Creating work directory at $WORK_DIR ..."
cp -r "$ANYKERNEL_DIR" "$WORK_DIR"

# ---------- 4. Copy kernel image ----------
KERNEL_BASENAME="$(basename "$KERNEL_IMAGE")"
info "Copying kernel image → $KERNEL_BASENAME ..."
cp "$KERNEL_IMAGE" "$WORK_DIR/$KERNEL_BASENAME"

# Also copy Image (raw) if it exists
if [[ -f "$BUILD_DIR/arch/arm64/boot/Image" ]]; then
    cp "$BUILD_DIR/arch/arm64/boot/Image" "$WORK_DIR/"
    ok "Copied Image (raw) as well."
fi

# ---------- 5. Write anykernel.sh for lavender ----------
info "Writing anykernel.sh for device 'lavender' ..."

cat > "$WORK_DIR/anykernel.sh" << 'ANYKERNEL_EOF'
### AnyKernel3 Ramdisk Mod Script
## Configured for Redmi Note 7 (lavender) — SDM660/Konkona
## Built by SAN kernel project
## Device info: mmcblk0p60 (64MB boot), Non-A/B, f2fs /data+/cache

### AnyKernel setup
# global properties
properties() { '
kernel.string=SAN Kernel 4.19 by user_why_red (lavender)
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=lavender
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot; # unpack ramdisk

# --- Ramdisk file modifications go here ---
# Device: lavender (Redmi Note 7)
# Fstab: /vendor/etc/fstab.qcom (f2fs for /data and /cache)
#
# Example performance patches (uncomment to enable):
#
# fstab.qcom — /data: f2fs nosuid,nodev,barrier=1 → f2fs nosuid,nodev,barrier=0,background_gc=on
# backup_file fstab.qcom;
# replace_string fstab.qcom "nosuid,nodev,barrier=1" "nosuid,nodev,barrier=0" "nosuid,nodev,barrier=1" "nosuid,nodev,barrier=0" "background_gc=on"
#
# fstab.qcom — /cache: f2fs nosuid,nodev,barrier=1 → nosuid,nodev,barrier=0
# backup_file fstab.qcom;
# replace_string fstab.qcom "cache" "cache"
#
# init.rc — add cgroup mount for CPU control
# backup_file init.rc;
# insert_line init.rc "on init" after "start logd" "\tcgroup cpu /dev/cpuset/cpu"

# --- End ramdisk modifications ---

write_boot;
## end boot install


## init_boot files attributes (lavender does not use init_boot)
#init_boot_attributes() {
#set_perm_recursive 0 0 755 644 $RAMDISK/*;
#set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
#} # end attributes

## vendor_boot files attributes (lavender does not use vendor_boot)
#vendor_boot_attributes() {
#set_perm_recursive 0 0 755 644 $RAMDISK/*;
#set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
#} # end attributes
ANYKERNEL_EOF

ok "anykernel.sh written for device 'lavender' (Redmi Note 7, sdm660, f2fs)."

# ---------- 6. Create flashable ZIP ----------
ZIP_NAME="UPDATE-AnyKernel3-SAN-kernel-lavender-$(date +%Y%m%d).zip"

info "Creating flashable ZIP: $ZIP_NAME ..."
cd "$WORK_DIR"

# Remove placeholder files and unnecessary files before zipping
find . -name "*placeholder*" -delete 2>/dev/null || true
find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

zip -r9 "../$ZIP_NAME" \
    . \
    -x ".git/*" \
    -x "*.git" \
    -x "*placeholder*" \
    -x "*.zip"

cd "$BASE_DIR"

# ---------- 7. Done ----------
ZIP_PATH="$BASE_DIR/$ZIP_NAME"
if [[ -f "$ZIP_PATH" ]]; then
    ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
    ok "============================================"
    ok "  ZIP ready: $ZIP_NAME"
    ok "  Size:      $ZIP_SIZE"
    ok "  Location:  $ZIP_PATH"
    ok "============================================"
    echo ""
    info "Flash steps:"
    echo "   1. Boot into custom recovery (TWRP/LineageOS)"
    echo "   2. Wipe → Dalvik / Cache (recommended)"
    echo "   3. Flash $ZIP_NAME"
    echo "   4. Wipe Dalvik / Cache again"
    echo "   5. Reboot"
    echo ""
    warn "  Do NOT do a factory reset unless necessary!"
    echo ""
    info "If bootloop occurs, re-flash stock boot image via fastboot:"
    echo "   fastboot flash boot <stock-boot.img>"
else
    die "ZIP creation failed!"
fi
