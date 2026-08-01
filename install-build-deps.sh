#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/deps"
PACKAGES_DEBIAN="cpio flex bison bc libarchive-tools zstd wget curl git make libssl-dev openssl"
PACKAGES_ARCH="cpio flex bison bc libarchive zstd wget curl git make openssl"

mkdir -p "$DEPS_DIR"

echo "$PACKAGES_DEBIAN" > "$DEPS_DIR/debian.txt"
echo "$PACKAGES_ARCH"  > "$DEPS_DIR/arch.txt"
echo "$PACKAGES_DEBIAN" > "$DEPS_DIR/ubuntu.txt"
echo "$PACKAGES_ARCH"  > "$DEPS_DIR/fedora.txt"
echo "$PACKAGES_ARCH"  > "$DEPS_DIR/voidlinux.txt"

echo "Dependency manifests saved to $DEPS_DIR/"
ls "$DEPS_DIR/"

if [[ $EUID -ne 0 ]]; then
  echo "Not running as root; skipping package installation."
  echo "Run with sudo/root to install dependencies."
fi

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

install_debian() {
  echo "Installing dependencies on Debian/Ubuntu-based system..."
  apt-get update
  apt-get install -y $PACKAGES_DEBIAN
}

install_arch() {
  echo "Installing dependencies on Arch-based system..."
  pacman -Sy
  pacman -S --needed --noconfirm $PACKAGES_ARCH
}

install_fedora() {
  echo "Installing dependencies on Fedora-based system..."
  dnf install -y $PACKAGES_ARCH
}

install_voidlinux() {
  echo "Installing dependencies on Void Linux..."
  xbps-install -S $PACKAGES_ARCH
}

echo ""
read -p "Detect and install for your current distro automatically? (y/n): " auto
install_choice() {
  if [[ $EUID -ne 0 ]]; then
    echo "Not running as root; skipping package installation."
    echo "Run with sudo/root to install dependencies."
    return
  fi
  case "$1" in
    debian|ubuntu) install_debian ;;
    arch) install_arch ;;
    fedora) install_fedora ;;
    voidlinux) install_voidlinux ;;
    *) echo "Invalid distro"; return 1 ;;
  esac
}
case "$auto" in
  y|Y)
    distro=$(detect_distro)
    echo "Detected: $distro"
    install_choice "$distro"
    ;;
  *)
    read -p "Enter which distro to install deps for (debian/ubuntu/arch/fedora/voidlinux): " target
    install_choice "$target"
    ;;
esac

echo "Done."
