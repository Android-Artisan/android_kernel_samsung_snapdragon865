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

if [[ "$DEVICE_CODENAME" != "x1q" ]]; then
    echo "Error: Invalid or missing device model. Only 'x1q' is supported."
    exit 1
fi

# ===================================
# Paths & Directories
# ===================================

ROOT_DIR="$(pwd)"
OUTPUT_DIR="$ROOT_DIR/out"
TOOLCHAIN_DIR="$ROOT_DIR/toolchains"
CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC_DIR="$TOOLCHAIN_DIR/gcc"
CLANG_BIN="$CLANG_DIR/bin"
GCC_BIN="$GCC_DIR/bin"

mkdir -p "$OUTPUT_DIR"

# ===================================
# Toolchain Download (Clang)
# ===================================

if [ ! -f "$CLANG_BIN/clang-14" ]; then
    echo "[INFO] Clang toolchain not found, downloading..."
    rm -rf "$CLANG_DIR"
    mkdir -p "$CLANG_DIR"
    pushd "$CLANG_DIR" > /dev/null
    curl -LJO https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-13.0.0_r13/clang-r450784d.tar.gz
    tar xf android-13.0.0_r13-clang-r450784d.tar.gz
    rm -f android-13.0.0_r13-clang-r450784d.tar.gz
    popd > /dev/null
fi

# ===================================
# Toolchain Download (GCC)
# ===================================

if [ ! -f "$GCC_BIN/aarch64-linux-android-ld" ]; then
    echo "[INFO] GCC toolchain not found, downloading..."
    rm -rf "$GCC_DIR"
    mkdir -p "$GCC_DIR"
    curl -L https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/heads/master.tar.gz | tar -xz -C "$GCC_DIR"
fi

# ===================================
# Export Build Environment
# ===================================

export ARCH=arm64
export CROSS_COMPILE="$GCC_BIN/aarch64-linux-android-"
export CLANG_TRIPLE="aarch64-linux-android-"
export CC="$CLANG_BIN/clang"
export AR="${CROSS_COMPILE}ar"
export NM="${CROSS_COMPILE}nm"
export OBJCOPY="${CROSS_COMPILE}objcopy"
export STRIP="${CROSS_COMPILE}strip"
export LD="${CROSS_COMPILE}ld"

# ===================================
# Kernel Build
# ===================================

echo "[INFO] Building kernel for $DEVICE_CODENAME..."

make -C "$ROOT_DIR" \
    O="$OUTPUT_DIR" \
    DTC_EXT="$ROOT_DIR/tools/dtc" \
    CONFIG_BUILD_ARM64_DT_OVERLAY=y \
    vendor/"$DEVICE_CODENAME"_chn_hkx_defconfig || { echo "[ERROR] defconfig failed"; exit 1; }

make -C "$ROOT_DIR" \
    O="$OUTPUT_DIR" \
    DTC_EXT="$ROOT_DIR/tools/dtc" \
    CONFIG_BUILD_ARM64_DT_OVERLAY=y \
    -j$(nproc) || { echo "[ERROR] Kernel build failed"; exit 1; }

echo "[INFO] Kernel build complete."

# ===================================
# Flashable ZIP Creation
# ===================================

echo "[INFO] Packaging flashable zip..."

MODEL="$DEVICE_CODENAME"
ZIP_OUT_DIR="$ROOT_DIR/build/out/$MODEL"
ZIP_DIR="$ZIP_OUT_DIR/zip"
FILES_DIR="$ZIP_DIR/files"
META_DIR="$ZIP_DIR/META-INF/com/google/android"

mkdir -p "$FILES_DIR" "$META_DIR"

# Copy built files
cp "$OUTPUT_DIR/arch/arm64/boot/Image" "$FILES_DIR/boot.img" || { echo "[ERROR] boot.img not found. Cannot create zip."; exit 1; }
cp "$OUTPUT_DIR/dtbo.img" "$FILES_DIR/dtbo.img" || echo "[WARNING] dtbo.img not found."

# Copy zip meta
cp "$ROOT_DIR/build/update-binary" "$META_DIR/update-binary" || { echo "[ERROR] update-binary missing."; exit 1; }
cp "$ROOT_DIR/build/updater-script" "$META_DIR/updater-script" || { echo "[ERROR] updater-script missing."; exit 1; }

# Extract version from defconfig
DEFCONFIG_PATH="$ROOT_DIR/arch/arm64/configs/vendor/${DEVICE_CODENAME}_chn_hkx_defconfig"
version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' "$DEFCONFIG_PATH" | cut -d '"' -f 2)
version="${version:1}"
DATE=$(date +"%d-%m-%Y_%H-%M-%S")
ZIP_NAME="${version}_${DEVICE_CODENAME}_UNOFFICIAL.zip"

# Build zip
pushd "$ZIP_DIR" > /dev/null
zip -r -qq "../$ZIP_NAME" .
popd > /dev/null

echo "[INFO] Flashable zip created at: build/out/$MODEL/$ZIP_NAME"
