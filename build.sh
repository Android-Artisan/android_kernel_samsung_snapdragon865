#!/bin/bash

set -e

# =============================
# Parse Arguments
# =============================

while getopts "m:" opt; do
  case "$opt" in
    m) DEVICE_CODENAME="$OPTARG" ;;
    *) echo "Usage: $0 -m x1q"; exit 1 ;;
  esac
done

if [ -z "$DEVICE_CODENAME" ]; then
  echo "Error: Device codename not specified."
  echo "Usage: $0 -m x1q"
  exit 1
fi

if [ "$DEVICE_CODENAME" != "x1q" ]; then
  echo "Error: Invalid device codename. Only 'x1q' is supported."
  exit 1
fi

# =============================
# Toolchain Setup
# =============================

TOOLCHAIN_DIR="$(pwd)/toolchains"
GCC_DIR="$TOOLCHAIN_DIR/gcc"
CLANG_DIR="$TOOLCHAIN_DIR/clang"

GCC_URL="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/heads/master.tar.gz"
CLANG_URL="https://releases.llvm.org/10.0.0/clang+llvm-10.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz"

echo "[INFO] Checking and downloading toolchains if needed..."
mkdir -p "$TOOLCHAIN_DIR"

if [ ! -d "$GCC_DIR/bin" ]; then
  echo "[INFO] Downloading GCC toolchain..."
  mkdir -p "$GCC_DIR"
  curl -L "$GCC_URL" | tar -xz -C "$GCC_DIR"
fi

if [ ! -d "$CLANG_DIR/bin" ]; then
  echo "[INFO] Downloading Clang 10.0 toolchain..."
  curl -LO "$CLANG_URL"
  tar -xf clang+llvm-10.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
  mv clang+llvm-10.0.0-x86_64-linux-gnu-ubuntu-18.04 "$CLANG_DIR"
  rm clang+llvm-10.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
fi

GCC_TOOLCHAIN="$GCC_DIR/bin/aarch64-linux-android-"
CLANG_PATH="$CLANG_DIR/bin/clang"
CLANG_TRIPLE="aarch64-linux-gnu-"

# =============================
# Output Setup
# =============================

OUTPUT_DIR="$(pwd)/out"
mkdir -p "$OUTPUT_DIR"
export ARCH=arm64

# =============================
# Kernel Build
# =============================

echo "[INFO] Starting build for device: $DEVICE_CODENAME"

make -C "$(pwd)" \
  O="$OUTPUT_DIR" \
  DTC_EXT="$(pwd)/tools/dtc" \
  CONFIG_BUILD_ARM64_DT_OVERLAY=y \
  CLANG_TRIPLE="$CLANG_TRIPLE" \
  CROSS_COMPILE="$GCC_TOOLCHAIN" \
  CC="$CLANG_PATH" \
  vendor/"${DEVICE_CODENAME}"_chn_hkx_defconfig

make -C "$(pwd)" \
  O="$OUTPUT_DIR" \
  DTC_EXT="$(pwd)/tools/dtc" \
  CONFIG_BUILD_ARM64_DT_OVERLAY=y \
  CLANG_TRIPLE="$CLANG_TRIPLE" \
  CROSS_COMPILE="$GCC_TOOLCHAIN" \
  CC="$CLANG_PATH" -j$(nproc)

echo "[INFO] Kernel build complete."

# =============================
# ZIP Build
# =============================

echo "[INFO] Building flashable zip..."
MODEL="$DEVICE_CODENAME"
ZIP_DIR="build/out/$MODEL/zip"
FILES_DIR="$ZIP_DIR/files"
META_DIR="$ZIP_DIR/META-INF/com/google/android"

mkdir -p "$FILES_DIR"
mkdir -p "$META_DIR"

cp "$OUTPUT_DIR/arch/arm64/boot/Image" "$FILES_DIR/boot.img" || echo "[WARN] boot.img not found"
cp "$OUTPUT_DIR/dtbo.img" "$FILES_DIR/dtbo.img" || echo "[WARN] dtbo.img not found"
cp build/update-binary "$META_DIR/update-binary"
cp build/updater-script "$META_DIR/updater-script"

DEFCONFIG_PATH="arch/arm64/configs/vendor/x1q_chn_hkx_defconfig"
version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' "$DEFCONFIG_PATH" | cut -d '"' -f 2)
version=${version:1}
DATE=$(date +"%d-%m-%Y_%H-%M-%S")

NAME="${version}_${DEVICE_CODENAME}_${DATE}_UNOFFICIAL.zip"

pushd "$ZIP_DIR" > /dev/null
zip -r -qq "../$NAME" .
popd > /dev/null

echo "[INFO] ZIP created: build/out/$MODEL/$NAME"
