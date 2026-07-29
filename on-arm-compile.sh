#!/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$BASE_DIR/san-kernel-4.19"
TOOLCHAIN_DIR="$BASE_DIR/toolchains/san-gcc/bin"
DEFCONFIG="arch/arm64/configs/vendor/lavender-perf_defconfig"
OUT_DIR="build-lavender"

echo "[on-arm-compile] Checking SAN-GCC toolchain..."
if [[ ! -f "$TOOLCHAIN_DIR/aarch64-linux-gcc" ]]; then
    echo "ERROR: SAN-GCC toolchain not found at $TOOLCHAIN_DIR"
    echo "Expected binary: $TOOLCHAIN_DIR/aarch64-linux-gcc"
    exit 1
fi
export PATH="$TOOLCHAIN_DIR:$PATH"

echo "[on-arm-compile] Kernel source: $KERNEL_DIR"
if [[ ! -d "$KERNEL_DIR" ]]; then
    echo "ERROR: Kernel source directory not found: $KERNEL_DIR"
    exit 1
fi

echo "[on-arm-compile] Defconfig: $DEFCONFIG"
if [[ ! -f "$KERNEL_DIR/$DEFCONFIG" ]]; then
    echo "ERROR: Defconfig not found: $DEFCONFIG"
    exit 1
fi

cd "$KERNEL_DIR"

echo "[on-arm-compile] Starting non-interactive build..."
echo "  ARCH=arm64"
echo "  CC=aarch64-linux-gcc"
echo "  CROSS_COMPILE=aarch64-linux-"
echo "  CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
echo "  DEFCONFIG=$DEFCONFIG"
echo "  OUTPUT_DIR=$OUT_DIR"

make -j$(nproc) ARCH=arm64 CC=aarch64-linux-gcc CROSS_COMPILE=aarch64-linux- CROSS_COMPILE_ARM32=arm-linux-gnueabi- "$DEFCONFIG" O="$OUT_DIR"

make -j$(nproc) ARCH=arm64 CC=aarch64-linux-gcc CROSS_COMPILE=aarch64-linux- CROSS_COMPILE_ARM32=arm-linux-gnueabi- O="$OUT_DIR"

echo "[on-arm-compile] Build completed successfully."
echo "[on-arm-compile] Kernel Image: $KERNEL_DIR/$OUT_DIR/arch/arm64/boot/Image"
