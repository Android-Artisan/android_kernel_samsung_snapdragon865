#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────
KERNEL_DIR="$(pwd)"
OUT_DIR="$KERNEL_DIR/out"
IMAGE_DIR="$KERNEL_DIR/SM-G9880"
TOOLCHAIN_DIR="$KERNEL_DIR/toolchain"
DEFCONFIG="vendor/z3q_chn_hkx_defconfig"

# Correct LineageOS Clang repo:
CLANG_REPO="https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git"  # :contentReference[oaicite:0]{index=0}
GCC64_REPO="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git"
GCC32_REPO="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git"

# ─── Fetch Toolchains ─────────────────────────────────────────
echo "[*] Cloning toolchains into $TOOLCHAIN_DIR…"
mkdir -p "$TOOLCHAIN_DIR"

# Clang for kernel builds
if [ ! -d "$TOOLCHAIN_DIR/clang" ]; then
  git clone --depth=1 "$CLANG_REPO" "$TOOLCHAIN_DIR/clang"
else
  echo "  → clang already present"
fi

# AOSP GCC (64‑bit)
if [ ! -d "$TOOLCHAIN_DIR/gcc64" ]; then
  git clone --depth=1 "$GCC64_REPO" "$TOOLCHAIN_DIR/gcc64"
else
  echo "  → gcc64 already present"
fi

# AOSP GCC (32‑bit)
if [ ! -d "$TOOLCHAIN_DIR/gcc32" ]; then
  git clone --depth=1 "$GCC32_REPO" "$TOOLCHAIN_DIR/gcc32"
else
  echo "  → gcc32 already present"
fi

# ─── Export Environment ────────────────────────────────────────
export PATH="$TOOLCHAIN_DIR/clang/bin:$TOOLCHAIN_DIR/gcc64/bin:$TOOLCHAIN_DIR/gcc32/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-android-
export CROSS_COMPILE_ARM32=arm-linux-androideabi-
export CLANG_TRIPLE=aarch64-linux-gnu-
export KBUILD_BUILD_USER=artisan
export KBUILD_BUILD_HOST=boyan-scripts

# ─── Fallback for missing perflog.h ───────────────────────────
PERFLOG="$KERNEL_DIR/system/core/liblog/include/log/perflog.h"
if [ ! -f "$PERFLOG" ]; then
  echo "[*] Creating dummy perflog.h…"
  mkdir -p "$(dirname "$PERFLOG")"
  echo "// dummy perflog.h" > "$PERFLOG"
fi

# ─── Clean & Configure ────────────────────────────────────────
echo "[*] Cleaning previous output…"
make O="$OUT_DIR" clean

echo "[*] Applying defconfig ($DEFCONFIG)…"
make O="$OUT_DIR" "$DEFCONFIG"

# ─── Build Kernel ─────────────────────────────────────────────
echo "[*] Building Image.gz-dtb, DTBs, dtbo.img…"
make -j"$(nproc)" O="$OUT_DIR" \
     CC=clang \
     CLANG_TRIPLE="$CLANG_TRIPLE" \
     CROSS_COMPILE="$CROSS_COMPILE" \
     CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
     Image.gz-dtb dtbs dtboimg

# ─── Collect Artifacts ────────────────────────────────────────
echo "[*] Copying artifacts into $IMAGE_DIR…"
mkdir -p "$IMAGE_DIR"

cp "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" "$IMAGE_DIR/" 2>/dev/null \
  && echo "  ✓ Image.gz-dtb" || echo "  – Image.gz-dtb missing"

cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$IMAGE_DIR/" 2>/dev/null \
  && echo "  ✓ dtbo.img"     || echo "  – dtbo.img missing"

find "$OUT_DIR" -name '*.dtb' -exec cp {} "$IMAGE_DIR/" \; \
  && echo "  ✓ all .dtb files"

echo "[✓] Build complete. Files in $IMAGE_DIR."
