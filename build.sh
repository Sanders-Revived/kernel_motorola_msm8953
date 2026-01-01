#!/usr/bin/env bash
#
# Build script – Aurora Kernel (sanders)
# Moto G5s Plus
#

SECONDS=0

# ===== Device / Kernel =====
DEVICE="sanders"
DEVICE_NAME="Moto G5s Plus"
DEFCONFIG="sanders_defconfig"

# ===== Toolchain =====
TC_DIR="$(pwd)/tc/clang-r522817"
export PATH="$TC_DIR/bin:$PATH"

# ===== AnyKernel3 =====
AK3_REPO="https://github.com/Sanders-Revived/AnyKernel3"
AK3_BRANCH="sanders"
AK3_DIR="$(pwd)/android/AnyKernel3"

# ===== Output =====
OUT_DIR="$(pwd)/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
KERNEL_IMG="$BOOT_DIR/Image.gz"

# ===== Zip =====
ZIPNAME="Aurora-Kernel-KSU-${DEVICE}-$(date '+%Y%m%d-%H%M')"
if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
    ZIPNAME="${ZIPNAME}-$(echo "$head" | cut -c1-8)"
fi
ZIPNAME="${ZIPNAME}.zip"

# ===== Arguments =====
ARG=$1

if [[ "$ARG" == "-c" || "$ARG" == "--clean" ]]; then
    echo "[*] Cleaning output directory"
    rm -rf out
fi

if [[ "$ARG" == "-r" || "$ARG" == "--regen" ]]; then
    mkdir -p out
    make O=out ARCH=arm64 $DEFCONFIG savedefconfig
    cp out/defconfig arch/arm64/configs/$DEFCONFIG
    echo "[+] Defconfig regenerated"
    exit 0
fi

if [[ "$ARG" == "-rf" || "$ARG" == "--regen-full" ]]; then
    mkdir -p out
    make O=out ARCH=arm64 $DEFCONFIG
    cp out/.config arch/arm64/configs/$DEFCONFIG
    echo "[+] Full defconfig regenerated"
    exit 0
fi

# ===== Toolchain check =====
if ! [ -d "$TC_DIR" ]; then
    echo "[*] Cloning AOSP clang..."
    git clone --depth=1 -b 18 \
        https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone \
        "$TC_DIR" || exit 1
fi

curl -LSs "https://raw.githubusercontent.com/backslashxx/KernelSU/refs/heads/master/kernel/setup.sh" | bash -s master

# ===== Build =====
mkdir -p out
echo "[*] Building $DEFCONFIG for $DEVICE_NAME"
make O=out ARCH=arm64 $DEFCONFIG

echo "[*] Starting compilation..."
make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 LLVM_IAS=1 Image.gz

# ===== Check compilation =====
if ! [ -f "$KERNEL_IMG" ]; then
    echo "[!] Compilation failed – Image.gz not found"
    exit 1
fi

echo "[+] Kernel compiled successfully"

# ===== Prepare AnyKernel3 =====
rm -rf AnyKernel3
echo "[*] Cloning AnyKernel3 for $DEVICE"
git clone -q -b "$AK3_BRANCH" "$AK3_REPO" AnyKernel3 || exit 1

# Copy the kernel image to AnyKernel3
cp "$KERNEL_IMG" AnyKernel3

# Remove boot output folder (Supra style)
rm -rf out/arch/arm64/boot

# ===== Zip =====
cd AnyKernel3 || exit 1
zip -r9 "../$ZIPNAME" * -x .git README.md "*placeholder*"
cd ..
rm -rf AnyKernel3

echo
echo "[✓] Done in $((SECONDS / 60))m $((SECONDS % 60))s"
echo "[✓] Zip: $ZIPNAME"
