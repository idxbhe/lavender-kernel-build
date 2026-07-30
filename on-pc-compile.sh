#!/bin/bash
set -euo pipefail

# ============================================
# on-pc-compile.sh - Kernel Build Script for x86_64 Host
# ============================================
# Script ini digunakan untuk build kernel ARM64 dari komputer x86_64
# dengan menggunakan cross-compiler (SAN-GCC).
#
# Target: sonix-kernel (lavender_defconfig)
# Architecture: arm64 (aarch64)
# ============================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$BASE_DIR/san-kernel"
TOOLCHAIN_DIR="$BASE_DIR/toolchains/san-gcc/bin"
DEFCONFIG="vendor/lavender-perf_defconfig"  # relative to arch/arm64/configs/
OUT_DIR="out"

# ============================================
# Toolchain Configuration
# ============================================
# SAN-GCC adalah cross-compiler x86_64 -> aarch64
# Binary: aarch64-linux-gcc (untuk ARM64)
#         arm-linux-gnueabi-gcc (untuk ARM32 compat)
# ============================================

echo "[on-pc-compile] Host architecture: $(uname -m)"
echo "[on-pc-compile] CPU cores: $(nproc)"
echo ""

echo "[on-pc-compile] Checking SAN-GCC toolchain..."
if [[ ! -f "$TOOLCHAIN_DIR/aarch64-linux-gcc" ]]; then
    echo "ERROR: SAN-GCC toolchain not found at $TOOLCHAIN_DIR"
    echo "Expected binary: $TOOLCHAIN_DIR/aarch64-linux-gcc"
    exit 1
fi

if [[ ! -f "$TOOLCHAIN_DIR/arm-linux-gnueabi-gcc" ]]; then
    echo "ERROR: ARM32 compat toolchain not found at $TOOLCHAIN_DIR"
    echo "Expected binary: $TOOLCHAIN_DIR/arm-linux-gnueabi-gcc"
    exit 1
fi

export PATH="$TOOLCHAIN_DIR:$PATH"
echo "[on-pc-compile] Toolchain version:"
aarch64-linux-gcc --version | head -1

echo ""
echo "[on-pc-compile] Kernel source: $KERNEL_DIR"
if [[ ! -d "$KERNEL_DIR" ]]; then
    echo "ERROR: Kernel source directory not found: $KERNEL_DIR"
    exit 1
fi

echo "[on-pc-compile] Defconfig: $DEFCONFIG"
if [[ ! -f "$KERNEL_DIR/arch/arm64/configs/$DEFCONFIG" ]]; then
    echo "ERROR: Defconfig not found: $KERNEL_DIR/arch/arm64/configs/$DEFCONFIG"
    exit 1
fi

cd "$KERNEL_DIR"

echo ""
echo "[on-pc-compile] Checking build dependencies..."
DEPS_MISSING=0
for dep in cpio flex bison bc gcc make; do
  if ! command -v $dep >/dev/null 2>&1; then
    echo "  WARNING: $dep missing"
    DEPS_MISSING=1
  else
    echo "  OK: $dep ($(command -v $dep))"
  fi
done

if [[ $DEPS_MISSING -eq 1 ]]; then
    echo ""
    echo "WARNING: Some dependencies are missing. Build may fail."
    echo "Install missing packages:"
    echo "  Ubuntu/Debian: sudo apt install cpio flex bison bc build-essential"
    echo "  Fedora: sudo dnf install cpio flex bison bc gcc make"
    echo ""
fi

echo ""
echo "[on-pc-compile] Starting non-interactive build..."
echo "  ARCH=arm64"
echo "  CC=aarch64-linux-gcc"
echo "  CROSS_COMPILE=aarch64-linux-"
echo "  CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
echo "  DEFCONFIG=$DEFCONFIG"
echo "  OUTPUT_DIR=$OUT_DIR"
echo "  JOBS=$(nproc)"
echo ""

# Clean previous build (optional - comment out if you want incremental build)
# rm -rf "$OUT_DIR"

# Configure kernel
echo "[on-pc-compile] Configuring kernel..."
make -j$(nproc) \
    ARCH=arm64 \
    CC=aarch64-linux-gcc \
    CROSS_COMPILE=aarch64-linux- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    "$DEFCONFIG" \
    O="$OUT_DIR"

echo ""
echo "[on-pc-compile] Building kernel image..."
make -j$(nproc) \
    ARCH=arm64 \
    CC=aarch64-linux-gcc \
    CROSS_COMPILE=aarch64-linux- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    O="$OUT_DIR"

echo ""
echo "[on-pc-compile] Build completed successfully."
echo "[on-pc-compile] Output directory: $KERNEL_DIR/$OUT_DIR"
echo "[on-pc-compile] Kernel Image: $KERNEL_DIR/$OUT_DIR/arch/arm64/boot/Image"
echo "[on-pc-compile] Compressed: $KERNEL_DIR/$OUT_DIR/arch/arm64/boot/Image.gz"
echo "[on-pc-compile] Device Tree Blobs: $KERNEL_DIR/$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/xiaomi/"
echo ""

# Show output files
if [[ -f "$OUT_DIR/arch/arm64/boot/Image" ]]; then
    ls -lh "$OUT_DIR/arch/arm64/boot/Image"
fi

if [[ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]]; then
    ls -lh "$OUT_DIR/arch/arm64/boot/Image.gz"
fi

if [[ -f "$OUT_DIR/System.map" ]]; then
    ls -lh "$OUT_DIR/System.map"
fi

if [[ -f "$OUT_DIR/vmlinux" ]]; then
    ls -lh "$OUT_DIR/vmlinux"
fi

echo ""
echo "[on-pc-compile] Next steps:"
echo "  1. Copy Image.gz-dtb to AnyKernel3/"
echo "  2. Run build-flashable-zip.sh to create flashable zip"
echo "  3. Flash via TWRP/OrangeFox recovery"
