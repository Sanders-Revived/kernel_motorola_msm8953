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

TC_REPO="${TC_REPO:-https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone}"
TC_REF="${TC_REF:-18}"
TC_DIR="${TC_DIR:-$ROOT_DIR/tc/clang-r522817}"

DTBTOOL_REPO="${DTBTOOL_REPO:-https://github.com/LineageOS/android_system_tools_dtbtool.git}"
DTBTOOL_REF="${DTBTOOL_REF:-lineage-18.1}"
DTBTOOL_DIR="${DTBTOOL_DIR:-$ROOT_DIR/tools/dtbtool}"
DTBTOOL_BIN="${DTBTOOL_BIN:-$OUT_DIR/host/dtbToolLineage}"

AK3_REPO="${AK3_REPO:-https://github.com/Sanders-Revived/AnyKernel3.git}"
AK3_BRANCH="${AK3_BRANCH:-sanders}"

KSU_SETUP_URL="${KSU_SETUP_URL:-https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh}"
KSU_DIR="$ROOT_DIR/KernelSU"
WITH_KSU="${WITH_KSU:-0}"
KSU_REF="${KSU_REF:-}"

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
Uso: ./build.sh [opções]

  --ksu             Compila com KernelSU
  --no-ksu          Compila sem KernelSU (padrão)
  --clean           Remove out/ antes da compilação
  --jobs=N          Usa N tarefas paralelas
  --regen           Regenera a defconfig mínima
  --regen-full      Regenera a defconfig completa
  -h, --help        Mostra esta ajuda

Variáveis úteis: TC_DIR, DTBTOOL_DIR, DTBTOOL_BIN, DTC_BIN,
DTBTOOL_REF, KSU_REF, KSU_SETUP_URL e JOBS.
EOF
}

parse_args() {
    local arg

    for arg in "$@"; do
        case "$arg" in
            --ksu) WITH_KSU=1 ;;
            --no-ksu) WITH_KSU=0 ;;
            --clean|-c) CLEAN=1 ;;
            --jobs=*) JOBS="${arg#*=}" ;;
            --regen|-r) ACTION=regen ;;
            --regen-full|-rf) ACTION=regen-full ;;
            --help|-h) usage; exit 0 ;;
            *) die "Opção desconhecida: $arg" ;;
        esac
    done

    [[ "$WITH_KSU" == 0 || "$WITH_KSU" == 1 ]] || die "WITH_KSU deve ser 0 ou 1"
    [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS deve ser um número positivo"
}

setup_toolchain() {
    if [[ ! -x "$TC_DIR/bin/clang" ]]; then
        [[ ! -e "$TC_DIR" ]] || die "Toolchain inválida: $TC_DIR"
        printf '[*] Clonando LLVM %s\n' "$TC_REF"
        mkdir -p "$(dirname "$TC_DIR")"
        git clone --depth=1 --single-branch --branch "$TC_REF" \
            "$TC_REPO" "$TC_DIR"
    fi

    [[ -x "$TC_DIR/bin/clang" ]] || die "clang não encontrado em $TC_DIR/bin"
    export PATH="$TC_DIR/bin:$PATH"
}

setup_ksu() {
    local remote ref

    command -v curl >/dev/null || die "curl não encontrado"
    if [[ -d "$KSU_DIR/.git" ]]; then
        remote="$(git -C "$KSU_DIR" remote get-url origin 2>/dev/null || true)"
        if [[ "$remote" != *"github.com/backslashxx/KernelSU"* ]]; then
            printf '[*] Removendo checkout antigo do KernelSU\n'
            rm -rf "$KSU_DIR"
        fi
    fi

    ref="${KSU_REF:-latest-tag}"
    printf '[*] Configurando KernelSU (%s)\n' "$ref"
    if [[ -n "$KSU_REF" ]]; then
        curl -fsSL "$KSU_SETUP_URL" | bash -s -- "$KSU_REF"
    else
        curl -fsSL "$KSU_SETUP_URL" | bash
    fi
    [[ -d "$KSU_DIR/kernel" ]] || die "O setup do KernelSU não criou $KSU_DIR/kernel"
}

setup_dtbtool() {
    if [[ ! -f "$DTBTOOL_DIR/dtbtool.c" && ! -x "$DTBTOOL_BIN" ]]; then
        [[ ! -e "$DTBTOOL_DIR" ]] || die "Diretório dtbtool inválido: $DTBTOOL_DIR"
        printf '[*] Clonando dtbToolLineage (%s)\n' "$DTBTOOL_REF"
        mkdir -p "$(dirname "$DTBTOOL_DIR")"
        git clone --depth=1 --single-branch --branch "$DTBTOOL_REF" \
            "$DTBTOOL_REPO" "$DTBTOOL_DIR"
    fi

    if [[ ! -x "$DTBTOOL_BIN" ]]; then
        [[ -f "$DTBTOOL_DIR/dtbtool.c" ]] ||
            die "dtbtool.c não encontrado em $DTBTOOL_DIR"
        mkdir -p "$(dirname "$DTBTOOL_BIN")"
        if [[ ! -e "$DTBTOOL_BIN" || "$DTBTOOL_DIR/dtbtool.c" -nt "$DTBTOOL_BIN" ]]; then
            printf '[*] Compilando dtbToolLineage\n'
            "$HOSTCC" -O2 -Wall -Wextra -o "$DTBTOOL_BIN" \
                "$DTBTOOL_DIR/dtbtool.c"
        fi
    fi

    [[ -x "$DTBTOOL_BIN" ]] || die "dtbToolLineage não foi gerado"
}

setup_dtc() {
    DTC_BIN="${DTC_BIN:-$(command -v dtc || true)}"
    [[ -x "$DTC_BIN" ]] || die "dtc não encontrado; instale device-tree-compiler ou defina DTC_BIN"
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
        printf '[+] Defconfig mínima regenerada\n'
    else
        kernel_make "$DEFCONFIG"
        cp "$OUT_DIR/.config" "arch/arm64/configs/$DEFCONFIG"
        printf '[+] Defconfig completa regenerada\n'
    fi
}

configure_kernel() {
    kernel_make "$DEFCONFIG"

    if [[ "$WITH_KSU" == 1 ]]; then
        ./scripts/config --file "$OUT_DIR/.config" \
            --enable CONFIG_KSU \
            --disable CONFIG_KSU_HACK_ARM64_BRANCH_LINK \
            --enable CONFIG_KSU_TAMPER_SYSCALL_TABLE \
            --disable CONFIG_KSU_DEBUG \
            --disable CONFIG_SECURITY_WRITABLE_HOOKS \
            --disable CONFIG_SECURITY_SELINUX_DISABLE
    else
        ./scripts/config --file "$OUT_DIR/.config" --disable CONFIG_KSU
    fi

    kernel_make olddefconfig
}

prepare_arch_headers() {
    local makefile="$ROOT_DIR/scripts/Makefile.asm-generic"
    local generated="$OUT_DIR/arch/arm64/include/generated"

    mkdir -p "$generated/asm" "$generated/uapi/asm"
    make -f "$makefile" srctree="$ROOT_DIR" SRCARCH=arm64 \
        src=asm obj="$generated/asm"
    make -f "$makefile" srctree="$ROOT_DIR" SRCARCH=arm64 \
        src=uapi/asm obj="$generated/uapi/asm"
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

    printf '[*] Compilando com %s tarefas\n' "$JOBS"
    make -j"$JOBS" "${make_args[@]}" Image.gz dtbs
    [[ -s "$KERNEL_IMG" ]] || die "Image.gz não foi gerada"
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
        [[ -s "$DTB_DIR/$dtb" ]] || die "DTB ausente: $DTB_DIR/$dtb"
    done

    rm -rf "$stage"
    mkdir -p "$stage"
    cp "${dtbs[@]/#/$DTB_DIR/}" "$stage/"

    printf '[*] Gerando QCDT\n'
    "$DTBTOOL_BIN" --force-v2 --page-size 2048 \
        --dtc-path "$DTC_PATH" \
        --output-file "$QCDT_IMG" \
        "$stage/"
    [[ "$(head -c 4 "$QCDT_IMG")" == QCDT ]] || die "QCDT inválido"
}

package_kernel() {
    local commit zip_name zip_path
    commit="$(git rev-parse --short=8 HEAD 2>/dev/null || printf 'local')"
    zip_name="Aurora-Kernel-${DEVICE}-$(date '+%Y%m%d-%H%M')-${commit}"
    [[ "$WITH_KSU" == 1 ]] && zip_name+="-KernelSU-$(printf '%s' "${KSU_REF:-latest}" | tr '/ ' '__')"
    [[ "$WITH_KSU" == 0 ]] && zip_name+="-NoKSU"
    zip_path="$ROOT_DIR/$zip_name.zip"

    rm -rf "$AK3_DIR"
    git clone --depth=1 --quiet --single-branch --branch "$AK3_BRANCH" \
        "$AK3_REPO" "$AK3_DIR"
    cp "$KERNEL_IMG" "$AK3_DIR/Image.gz"
    cp "$QCDT_IMG" "$AK3_DIR/dt"

    command -v zip >/dev/null || die "zip não encontrado"
    (
        cd "$AK3_DIR"
        zip -qr9 "$zip_path" . -x './.git/*' './README.md' './*placeholder*'
    )
    rm -rf "$AK3_DIR"
    printf '[+] Pacote: %s\n' "$zip_path"
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
printf '[*] Build %s (%s, KSU=%s)\n' "$DEVICE_NAME" "$DEFCONFIG" "$WITH_KSU"
setup_toolchain
[[ "$WITH_KSU" == 0 ]] || setup_ksu
mkdir -p "$OUT_DIR"
setup_dtbtool
setup_dtc
configure_kernel
prepare_arch_headers
build_kernel
build_qcdt
package_kernel
printf '[+] Concluído em %dm %ds\n' "$((SECONDS / 60))" "$((SECONDS % 60))"
