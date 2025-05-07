#!/bin/bash

set -e

# ===================================
# Help / Usage Function
# ===================================
show_usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    -m, --model [value]    Specify the device model (only 'x1q' is supported)
    -h, --help             Show this help message

Example:
    ./$(basename "$0") -m x1q
EOF
    exit 1
}

# ===================================
# Argument Parsing
# ===================================
DEVICE_CODENAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model)
            DEVICE_CODENAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            show_usage
            ;;
    esac
done

# Validate codename
if [[ -z "$DEVICE_CODENAME" ]]; then
    echo "Error: No device model specified."
    show_usage
fi

if [[ "$DEVICE_CODENAME" != "x1q" ]]; then
    echo "Error: Invalid device model. Only 'x1q' is supported."
    exit 1
fi

# ===================================
# Directory & Toolchain Setup
# ===================================

ROOT_DIR="$(pwd)"
OUTPUT_DIR="$ROOT_DIR/out"
TOOLCHAIN_DIR="$ROOT_DIR/toolchains"
CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC_DIR="$TOOLCHAIN_DIR/gcc"

CLANG_BIN="$CLANG_DIR/bin"
CLANG_PATH="$CLANG_BIN/clang"
CLANG_TRIPLE="aarch64-linux-gnu-"
GCC_TOOLCHAIN="$GCC_DIR/bin/aarch64-linux-android-"

mkdir -p "$OUTPUT_DIR"

# ===================================
# Download Clang if Missing
# ===================================

if [ ! -f "$CLANG_BIN/clang-14" ]; then
    echo "-----------------------------------------------"
    echo "[INFO] Clang toolchain not found! Downloading..."
    echo "-----------------------------------------------"
    rm -rf "$CLANG_DIR"
    mkdir -p "$CLANG_DIR"
    pushd "$CLANG_DIR" > /dev/null

    curl -LJO https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-13.0.0_r13/clang-r450784d.tar.gz
    tar -xf android-13.0.0_r13-clang-r450784d.tar.gz
    rm -f android-13.0.0_r13-clang-r450784d.tar.gz

    echo "[INFO] Clang toolchain setup complete."
    echo "-----------------------------------------------"
    popd > /dev/null
fi

# ===================================
# Export Environment
# ===================================
export ARCH=arm64

# ===================================
# Kernel Build
# ===================================

echo "[INFO] Starting kernel build for $DEVICE_CODENAME..."

make -C "$ROOT_DIR" \
    O="$OUTPUT_DIR" \
    DTC_EXT="$ROOT_DIR/tools/dtc" \
    CONFIG_BUILD_ARM64_DT_OVERLAY=y \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$GCC_TOOLCHAIN" \
    CC="$CLANG_PATH" \
    vendor/"$DEVICE_CODENAME"_chn_hkx_defconfig

make -C "$ROOT_DIR" \
    O="$OUTPUT_DIR" \
    DTC_EXT="$ROOT_DIR/tools/dtc" \
    CONFIG_BUILD_ARM64_DT_OVERLAY=y \
    CLANG_TRIPLE="$CLANG_TRIPLE" \
    CROSS_COMPILE="$GCC_TOOLCHAIN" \
    CC="$CLANG_PATH" -j$(nproc)

echo "[INFO] Kernel build complete."

# ===================================
# Build Flashable ZIP
# ===================================

echo "[INFO] Packaging flashable zip..."

MODEL="$DEVICE_CODENAME"
ZIP_OUT_DIR="$ROOT_DIR/build/out/$MODEL"
ZIP_DIR="$ZIP_OUT_DIR/zip"
FILES_DIR="$ZIP_DIR/files"
META_DIR="$ZIP_DIR/META-INF/com/google/android"

mkdir -p "$FILES_DIR"
mkdir -p "$META_DIR"

cp "$OUTPUT_DIR/arch/arm64/boot/Image" "$FILES_DIR/boot.img" || echo "[WARN] boot.img not found"
cp "$OUTPUT_DIR/dtbo.img" "$FILES_DIR/dtbo.img" || echo "[WARN] dtbo.img not found"
cp "$ROOT_DIR/build/update-binary" "$META_DIR/update-binary"
cp "$ROOT_DIR/build/updater-script" "$META_DIR/updater-script"

DEFCONFIG_PATH="$ROOT_DIR/arch/arm64/configs/vendor/x1q_chn_hkx_defconfig"
version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' "$DEFCONFIG_PATH" | cut -d '"' -f 2)
version="${version:1}"
DATE=$(date +"%d-%m-%Y_%H-%M-%S")
ZIP_NAME="${version}_${DEVICE_CODENAME}_UNOFFICIAL.zip"

pushd "$ZIP_DIR" > /dev/null
zip -r -qq "../$ZIP_NAME" .
popd > /dev/null

echo "[INFO] Flashable zip created at: build/out/$MODEL/$ZIP_NAME"
