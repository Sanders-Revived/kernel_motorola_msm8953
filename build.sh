#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DEVICE="sanders"
DEVICE_NAME="Moto G5s Plus"
DEFCONFIG="sanders_defconfig"

OUT_DIR="$ROOT_DIR/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
DTB_DIR="$BOOT_DIR/dts/qcom"
KERNEL_IMG="$BOOT_DIR/Image.gz"
QCDT_IMG="$OUT_DIR/dt.img"
AK3_DIR="$OUT_DIR/AnyKernel3"

TC_REPO="${TC_REPO:-https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r596125}"
TC_REF="${TC_REF:-16.0}"
TC_DIR="${TC_DIR:-$ROOT_DIR/tc/clang-r596125}"

DTBTOOL_REPO="${DTBTOOL_REPO:-https://github.com/LineageOS/android_system_tools_dtbtool.git}"
DTBTOOL_REF="${DTBTOOL_REF:-lineage-18.1}"
DTBTOOL_DIR="${DTBTOOL_DIR:-$ROOT_DIR/tools/dtbtool}"
DTBTOOL_BIN="${DTBTOOL_BIN:-$OUT_DIR/host/dtbToolLineage}"

AK3_REPO="${AK3_REPO:-https://github.com/Sanders-Revived/AnyKernel3.git}"
AK3_BRANCH="${AK3_BRANCH:-sanders}"

KSU_SETUP_URL="${KSU_SETUP_URL:-https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh}"
KSU_DIR="$ROOT_DIR/KernelSU"
WITH_KSU="${WITH_KSU:-0}"
KSU_REF="${KSU_REF:-master}"
WITH_OC="${WITH_OC:-0}"

HOSTCC="${HOSTCC:-cc}"
JOBS="${JOBS:-$(command -v nproc >/dev/null && nproc --all || printf '1')}"
CLEAN=0
ACTION=build

die() {
    printf '[!] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: ./build.sh [options]

  --ksu             Build with Backslash KernelSU
  --no-ksu          Build without KernelSU (default)
  --oc              Build with the 725MHz GPU operating point
  --no-oc           Build with the stock GPU frequency table (default)
  --clean           Remove out/ before building
  --jobs=N          Use N parallel jobs
  --regen           Regenerate the minimal defconfig
  --regen-full      Regenerate the full defconfig
  -h, --help        Show this help

Useful variables: TC_DIR, DTBTOOL_DIR, DTBTOOL_BIN, DTC_BIN,
DTBTOOL_REF, KSU_REF, KSU_SETUP_URL and JOBS.
EOF
}

parse_args() {
    local arg

    for arg in "$@"; do
        case "$arg" in
            --ksu) WITH_KSU=1 ;;
            --no-ksu) WITH_KSU=0 ;;
            --oc) WITH_OC=1 ;;
            --no-oc) WITH_OC=0 ;;
            --clean|-c) CLEAN=1 ;;
            --jobs=*) JOBS="${arg#*=}" ;;
            --regen|-r) ACTION=regen ;;
            --regen-full|-rf) ACTION=regen-full ;;
            --help|-h) usage; exit 0 ;;
            *) die "Unknown option: $arg" ;;
        esac
    done

    [[ "$WITH_KSU" == 0 || "$WITH_KSU" == 1 ]] || die "WITH_KSU must be 0 or 1"
    [[ "$WITH_OC" == 0 || "$WITH_OC" == 1 ]] || die "WITH_OC must be 0 or 1"
    [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"
}

setup_toolchain() {
    if [[ ! -x "$TC_DIR/bin/clang" ]]; then
        [[ ! -e "$TC_DIR" ]] || die "Invalid toolchain directory: $TC_DIR"
        printf '[*] Cloning LLVM %s\n' "$TC_REF"
        mkdir -p "$(dirname "$TC_DIR")"
        git clone --depth=1 --single-branch --branch "$TC_REF" \
            "$TC_REPO" "$TC_DIR"
    fi

    [[ -x "$TC_DIR/bin/clang" ]] || die "clang not found in $TC_DIR/bin"
    export PATH="$TC_DIR/bin:$PATH"
}

setup_ksu() {
    command -v curl >/dev/null || die "curl not found"
    printf '[*] Setting up Backslash KernelSU (%s)\n' "$KSU_REF"
    curl -fsSL "$KSU_SETUP_URL" | bash -s -- "$KSU_REF"
    [[ -d "$KSU_DIR/kernel" ]] || die "KernelSU setup did not create $KSU_DIR/kernel"
}

setup_dtbtool() {
    if [[ ! -f "$DTBTOOL_DIR/dtbtool.c" && ! -x "$DTBTOOL_BIN" ]]; then
        [[ ! -e "$DTBTOOL_DIR" ]] || die "Invalid dtbtool directory: $DTBTOOL_DIR"
        printf '[*] Cloning dtbToolLineage (%s)\n' "$DTBTOOL_REF"
        mkdir -p "$(dirname "$DTBTOOL_DIR")"
        git clone --depth=1 --single-branch --branch "$DTBTOOL_REF" \
            "$DTBTOOL_REPO" "$DTBTOOL_DIR"
    fi

    if [[ ! -x "$DTBTOOL_BIN" ]]; then
        [[ -f "$DTBTOOL_DIR/dtbtool.c" ]] ||
            die "dtbtool.c not found in $DTBTOOL_DIR"
        mkdir -p "$(dirname "$DTBTOOL_BIN")"
        if [[ ! -e "$DTBTOOL_BIN" || "$DTBTOOL_DIR/dtbtool.c" -nt "$DTBTOOL_BIN" ]]; then
            printf '[*] Building dtbToolLineage\n'
            "$HOSTCC" -O2 -Wall -Wextra -o "$DTBTOOL_BIN" \
                "$DTBTOOL_DIR/dtbtool.c"
        fi
    fi

    [[ -x "$DTBTOOL_BIN" ]] || die "dtbToolLineage was not generated"
}

setup_dtc() {
    DTC_BIN="${DTC_BIN:-$(command -v dtc || true)}"
    [[ -x "$DTC_BIN" ]] || die "dtc not found; install device-tree-compiler or set DTC_BIN"
    DTC_PATH="$(dirname "$DTC_BIN")/"
}

kernel_make() {
    make O="$OUT_DIR" ARCH=arm64 "$@"
}

regen_defconfig() {
    mkdir -p "$OUT_DIR"
    if [[ "$ACTION" == regen ]]; then
        kernel_make "$DEFCONFIG" savedefconfig
        cp "$OUT_DIR/defconfig" "arch/arm64/configs/$DEFCONFIG"
        printf '[+] Minimal defconfig regenerated\n'
    else
        kernel_make "$DEFCONFIG"
        cp "$OUT_DIR/.config" "arch/arm64/configs/$DEFCONFIG"
        printf '[+] Full defconfig regenerated\n'
    fi
}

configure_kernel() {
    kernel_make "$DEFCONFIG"

    if [[ "$WITH_KSU" == 1 ]]; then
        ./scripts/config --file "$OUT_DIR/.config" \
            --enable CONFIG_KSU \
            --enable CONFIG_KSU_TAMPER_SYSCALL_TABLE \
            --enable CONFIG_KSU_LSM_SECURITY_HOOKS \
            --disable CONFIG_KSU_HACK_ARM64_BRANCH_LINK \
            --disable CONFIG_KSU_KPROBES_KSUD
    else
        ./scripts/config --file "$OUT_DIR/.config" --disable CONFIG_KSU
    fi

    if [[ "$WITH_OC" == 1 ]]; then
        ./scripts/config --file "$OUT_DIR/.config" --enable CONFIG_MSM8953_GPU_725MHZ
    else
        ./scripts/config --file "$OUT_DIR/.config" --disable CONFIG_MSM8953_GPU_725MHZ
    fi

    kernel_make olddefconfig
}

build_kernel() {
    local make_args=(
        O="$OUT_DIR"
        ARCH=arm64
        CC=clang
        LD=ld.lld
        AS=llvm-as
        AR=llvm-ar
        NM=llvm-nm
        OBJCOPY=llvm-objcopy
        OBJDUMP=llvm-objdump
        STRIP=llvm-strip
        CROSS_COMPILE=aarch64-linux-gnu-
        CROSS_COMPILE_ARM32=arm-linux-gnueabi-
        LLVM=1
        LLVM_IAS=1
    )

    printf '[*] Building with %s parallel jobs\n' "$JOBS"
    make -j"$JOBS" "${make_args[@]}" Image.gz dtbs
    [[ -s "$KERNEL_IMG" ]] || die "Image.gz was not generated"
}

build_qcdt() {
    local dtb
    local dtbs=(
        msm8953-sanders-p1.dtb
        msm8953-sanders-p2.dtb
        msm8953-sanders-p3.dtb
        msm8953-sanders-p4.dtb
    )
    local stage="$OUT_DIR/sanders-dtbs"

    for dtb in "${dtbs[@]}"; do
        [[ -s "$DTB_DIR/$dtb" ]] || die "Missing DTB: $DTB_DIR/$dtb"
    done

    rm -rf "$stage"
    mkdir -p "$stage"
    cp "${dtbs[@]/#/$DTB_DIR/}" "$stage/"

    printf '[*] Generating QCDT\n'
    "$DTBTOOL_BIN" --force-v2 --page-size 2048 \
        --dtc-path "$DTC_PATH" \
        --output-file "$QCDT_IMG" \
        "$stage/"
    [[ "$(head -c 4 "$QCDT_IMG")" == QCDT ]] || die "Invalid QCDT"
}

package_kernel() {
    local commit zip_name zip_path
    commit="$(git rev-parse --short=8 HEAD 2>/dev/null || printf 'local')"
    zip_name="Aurora-Kernel-${DEVICE}-$(date '+%Y%m%d-%H%M')-${commit}"
    [[ "$WITH_KSU" == 1 ]] && zip_name+="-KernelSU-Backslash-$(printf '%s' "$KSU_REF" | tr '/ ' '__')"
    [[ "$WITH_KSU" == 0 ]] && zip_name+="-NoKSU"
    [[ "$WITH_OC" == 1 ]] && zip_name+="-OC"
    [[ "$WITH_OC" == 0 ]] && zip_name+="-NoOC"
    zip_path="$ROOT_DIR/$zip_name.zip"

    rm -rf "$AK3_DIR"
    git clone --depth=1 --quiet --single-branch --branch "$AK3_BRANCH" \
        "$AK3_REPO" "$AK3_DIR"
    cp "$KERNEL_IMG" "$AK3_DIR/Image.gz"
    cp "$QCDT_IMG" "$AK3_DIR/dt"

    command -v zip >/dev/null || die "zip not found"
    (
        cd "$AK3_DIR"
        zip -qr9 "$zip_path" . -x './.git/*' './README.md' './*placeholder*'
    )
    rm -rf "$AK3_DIR"
    printf '[+] Package: %s\n' "$zip_path"
}

cleanup() {
    if [[ "$WITH_KSU" == 1 ]]; then
        rm -f drivers/kernelsu
        sed -i '/obj-$(CONFIG_KSU) += kernelsu\//d' drivers/Makefile
        sed -i '${/^$/d;}' drivers/Makefile
        sed -i '/source "drivers\/kernelsu\/Kconfig"/d' drivers/Kconfig
    fi
    if [[ -d "$AK3_DIR" ]]; then
        rm -rf "$AK3_DIR"
    fi
}

trap cleanup EXIT
parse_args "$@"

if [[ "$CLEAN" == 1 ]]; then
    rm -rf "$OUT_DIR"
fi

if [[ "$ACTION" != build ]]; then
    regen_defconfig
    exit 0
fi

SECONDS=0
printf '[*] Building %s (%s, KSU=%s, OC=%s)\n' \
    "$DEVICE_NAME" "$DEFCONFIG" "$WITH_KSU" "$WITH_OC"
setup_toolchain
[[ "$WITH_KSU" == 0 ]] || setup_ksu
mkdir -p "$OUT_DIR"
setup_dtbtool
setup_dtc
configure_kernel
build_kernel
build_qcdt
package_kernel
printf '[+] Completed in %dm %ds\n' "$((SECONDS / 60))" "$((SECONDS % 60))"
