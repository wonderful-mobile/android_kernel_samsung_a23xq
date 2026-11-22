#!/usr/bin/env bash
#
# Wonderful Kernel build script.
#
#   ./build.sh                       # vanilla kernel
#   ./build.sh --root ksun           # with KernelSU-Next
#   ./build.sh --root sukisu --susfs # with SukiSU and SUSFS
#
# Run "./build.sh --help" for every option. New to this? Use ./run.sh, which
# asks a few questions and calls this script for you.
#
# Root drivers and SUSFS are added only for the duration of the build: the
# script applies them to the source tree, builds, and removes them again, so
# the git tree stays clean.

set -Eeuo pipefail

SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$SRC"

# shellcheck source=wonderful/device.conf
. wonderful/device.conf

# ---------------------------------------------------------------- settings --

CLANG_NAME="clang-r416183b1" # Android clang 12.0.7, same as CI
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12L-security-release/${CLANG_NAME}.tar.gz"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$HOME/.cache/wonderful/toolchains}"

AK3_REPO="https://github.com/osm0sis/AnyKernel3"
AK3_REF="${AK3_REF:-41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1}"

# Root drivers, pinned to reviewed commits. Override with e.g. KSUN_REF=legacy.
KSUN_REPO="https://github.com/KernelSU-Next/KernelSU-Next"
KSUN_REF="${KSUN_REF:-e5f5ec998de88b9fc43c62cff8f7ae12d3f4800a}" # legacy branch
BAKASU_REPO="https://github.com/Baka-SU/BakaSU"
BAKASU_REF="${BAKASU_REF:-2734e0bc155759955880f5fb99be640fc5b92156}" # main, SUSFS built in
SUKISU_REPO="https://github.com/SukiSU-Nova/SukiSU-Nova"
SUKISU_REF="${SUKISU_REF:-4bec532dd447e2852aa8932afa768255350c103a}" # builtin, v3.0.0
# SUSFS-enabled KernelSU-Next driver, used with --susfs. SukiSU and BakaSU
# have SUSFS built in.
KSUN_SUSFS_REPO="https://github.com/sidex15/KernelSU-Next"
KSUN_SUSFS_REF="${KSUN_SUSFS_REF:-d999a2aff11575c6e2f520129ecffb7c6058fb02}" # legacy-susfs-v2

SUSFS_CONFIGS="KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT
KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_ENABLE_LOG KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_SUS_MAP"

OUT="$SRC/out"
DIST="$SRC/dist"
WORK="$SRC/.wonderful" # git-ignored cache for drivers and AnyKernel3

ROOT="none"
SUSFS=false
LTO="${LTO:-none}"
JOBS="$(nproc)"
CLEAN=false
PACKAGE=true
CLEANUP_ONLY=false

# ----------------------------------------------------------------- helpers --

if [ -t 1 ]; then
	C_INFO=$'\e[1;34m' C_OK=$'\e[1;32m' C_ERR=$'\e[1;31m' C_OFF=$'\e[0m'
else
	C_INFO="" C_OK="" C_ERR="" C_OFF=""
fi
info() { echo "${C_INFO}==>${C_OFF} $*"; }
ok() { echo "${C_OK}==>${C_OFF} $*"; }
die() { echo "${C_ERR}error:${C_OFF} $*" >&2; exit 1; }

usage() {
	cat <<EOF
Wonderful Kernel build script for the $DEVICE_NAME ($DEVICE)

Usage: ./build.sh [options]

  -r, --root NAME     root manager built into the kernel:
                        none    no root (default)
                        ksun    KernelSU-Next
                        sukisu  SukiSU
                        bakasu  BakaSU
  -s, --susfs         add SUSFS (only with: $SUSFS_SUPPORTED)
  -j, --jobs N        parallel jobs (default: $(nproc))
      --lto MODE      none, thin or full (default: none)
      --clean         delete out/ before building
      --no-zip        build the kernel only, skip the flashable zip
      --cleanup       only remove a root driver left by an interrupted build
  -h, --help          show this help

The flashable zip is written to dist/.

Environment overrides: KSUN_REF, SUKISU_REF, AK3_REF, TOOLCHAIN_DIR,
KBUILD_BUILD_USER, KBUILD_BUILD_HOST.
EOF
}

has_word() { [[ " $1 " == *" $2 "* ]]; }

# --------------------------------------------------------------- arguments --

while [ $# -gt 0 ]; do
	case "$1" in
	-r | --root) ROOT="${2:-}"; shift 2 ;;
	--root=*) ROOT="${1#*=}"; shift ;;
	-s | --susfs) SUSFS=true; shift ;;
	-j | --jobs) JOBS="${2:-}"; shift 2 ;;
	--lto) LTO="${2:-}"; shift 2 ;;
	--clean) CLEAN=true; shift ;;
	--no-zip) PACKAGE=false; shift ;;
	--cleanup) CLEANUP_ONLY=true; shift ;;
	-h | --help) usage; exit 0 ;;
	*) usage; die "unknown option: $1" ;;
	esac
done

has_word "$ROOT_SUPPORTED" "$ROOT" || die "unknown root manager '$ROOT' (choose: $ROOT_SUPPORTED)"
if $SUSFS && ! has_word "$SUSFS_SUPPORTED" "$ROOT"; then
	die "SUSFS needs one of these root managers: $SUSFS_SUPPORTED"
fi
[[ "$JOBS" =~ ^[0-9]+$ ]] || die "--jobs needs a number"
has_word "none thin full" "$LTO" || die "--lto must be none, thin or full"

case "$ROOT" in
none) VARIANT="Vanilla" ;;
ksun) VARIANT="KernelSU-Next" ;;
sukisu) VARIANT="SukiSU" ;;
bakasu) VARIANT="BakaSU" ;;
esac
$SUSFS && VARIANT="$VARIANT-SUSFS"

# ------------------------------------------------------------- environment --

# On NixOS, re-run inside the FHS environment from shell.nix so Android's
# prebuilt clang works.
if ! $CLEANUP_ONLY && [ -z "${WONDERFUL_FHS:-}" ] && [ -e /etc/NIXOS ]; then
	if [ -n "${WONDERFUL_FHS_CMD:-}" ]; then
		exec "$WONDERFUL_FHS_CMD" -c "$(printf '%q ' "$SRC/build.sh" "$@" \
			--root "$ROOT" $($SUSFS && echo --susfs) --jobs "$JOBS" --lto "$LTO" \
			$($CLEAN && echo --clean) $($PACKAGE || echo --no-zip))"
	fi
	die "on NixOS, run this from the Nix shell: nix-shell --run './build.sh ...'"
fi

$CLEANUP_ONLY || for tool in bc bison flex make perl python3 git curl zip cpio; do
	command -v "$tool" >/dev/null || die "missing '$tool'. Install the build dependencies (see README) or use nix-shell."
done

fetch_toolchain() {
	local dir="$TOOLCHAIN_DIR/$CLANG_NAME"
	if [ ! -x "$dir/bin/clang" ]; then
		info "Downloading Android clang ($CLANG_NAME, about 1.4 GB once)"
		mkdir -p "$dir.tmp"
		curl -fL --retry 3 "$CLANG_URL" | tar -xz -C "$dir.tmp"
		rm -rf "$dir" && mv "$dir.tmp" "$dir"
	fi
	export PATH="$dir/bin:$PATH"
}

# Clone (or update) a git repo into the cache and check out a pinned ref.
# A full (blobless) clone is used because the root drivers compute their
# version number from the commit count.
fetch_repo() { # fetch_repo <url> <ref> <dir>
	local url="$1" ref="$2" dir="$3"
	if [ ! -d "$dir/.git" ]; then
		git clone --quiet --filter=blob:none "$url" "$dir"
	fi
	# Drop fixes applied by an earlier build (see patches/driver/).
	git -C "$dir" reset --quiet --hard
	git -C "$dir" clean --quiet -fd
	if ! git -C "$dir" checkout --quiet --detach "$ref" 2>/dev/null; then
		git -C "$dir" fetch --quiet --tags origin
		git -C "$dir" checkout --quiet --detach "$ref" ||
			git -C "$dir" checkout --quiet --detach "origin/$ref"
	fi
}

# ------------------------------------------------- temporary tree changes --

APPLIED_PATCHES=()
DRIVER_LINKED=false
DRIVER_REF=""

restore_tree() {
	local i
	for ((i = ${#APPLIED_PATCHES[@]} - 1; i >= 0; i--)); do
		git apply -R "${APPLIED_PATCHES[i]}" || echo "warning: could not revert ${APPLIED_PATCHES[i]}" >&2
	done
	APPLIED_PATCHES=()
	if $DRIVER_LINKED || [ -L drivers/kernelsu ]; then
		rm -f drivers/kernelsu
		sed -i '/^obj-\$(CONFIG_KSU) += kernelsu\/$/d' drivers/Makefile
		sed -i '/^source "drivers\/kernelsu\/Kconfig"$/d' drivers/Kconfig
		DRIVER_LINKED=false
	fi
}
trap restore_tree EXIT
# Ctrl+C or a kill should clean up too.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

apply_patch_dir() { # apply_patch_dir <dir>
	local p
	[ -d "$1" ] || return 0
	for p in "$1"/*.patch; do
		[ -e "$p" ] || continue
		info "Applying ${p#"$SRC"/}"
		git apply --check "$p" 2>/dev/null ||
			die "${p#"$SRC"/} does not apply cleanly. See the failed files with: git apply --check -v ${p#"$SRC"/}"
		git apply "$p"
		APPLIED_PATCHES+=("$p")
	done
}

setup_root() {
	local url ref drv="$ROOT"
	case "$ROOT" in
	none) return 0 ;;
	ksun) url="$KSUN_REPO" ref="$KSUN_REF" ;;
	sukisu) url="$SUKISU_REPO" ref="$SUKISU_REF" ;;
	bakasu) url="$BAKASU_REPO" ref="$BAKASU_REF" ;;
	esac
	# KernelSU-Next needs a separate SUSFS-enabled driver.
	if $SUSFS; then
		case "$ROOT" in
		ksun) url="$KSUN_SUSFS_REPO" ref="$KSUN_SUSFS_REF" drv="ksun-susfs" ;;
		esac
	fi
	DRIVER_REF="$url@$ref"

	info "Fetching $VARIANT driver ($drv @ ${ref:0:12})"
	fetch_repo "$url" "$ref" "$WORK/root/$drv"

	# Small fixes to the driver itself, e.g. for building on older kernels.
	local p
	for p in "$SRC/wonderful/patches/driver/$drv"/*.patch; do
		[ -e "$p" ] || continue
		info "Applying ${p#"$SRC"/} to the driver"
		git -C "$WORK/root/$drv" apply "$p" || die "${p#"$SRC"/} does not apply to $drv @ ${ref:0:12}"
	done

	ln -sfn "../.wonderful/root/$drv/kernel" drivers/kernelsu
	printf 'obj-$(CONFIG_KSU) += kernelsu/\n' >>drivers/Makefile
	printf 'source "drivers/kernelsu/Kconfig"\n' >>drivers/Kconfig
	DRIVER_LINKED=true

	local kver
	kver="$(make -s kernelversion | cut -d. -f1-2)"
	if $SUSFS; then
		apply_patch_dir "$SRC/wonderful/patches/susfs/$kver"
		apply_patch_dir "$SRC/wonderful/patches/root/$ROOT-susfs"
	else
		apply_patch_dir "$SRC/wonderful/patches/root/$ROOT"
	fi
}

# ------------------------------------------------------------------- build --

MAKE_ARGS=(
	-C "$SRC" O="$OUT" ARCH=arm64
	LLVM=1 LLVM_IAS=1
	CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
	CLANG_TRIPLE=aarch64-linux-gnu-
	KCFLAGS=-w CONFIG_SECTION_MISMATCH_WARN_ONLY=y CONFIG_BUILD_ARM64_DT_OVERLAY=y
	LOCALVERSION="-wonderful-$PROJECT_VERSION-$VARIANT"
)
# Inside the Nix FHS shell, host tools are built with gcc (Android clang
# cannot find the host C runtime there). The kernel itself still uses clang.
[ -n "${WONDERFUL_FHS:-}" ] && MAKE_ARGS+=(HOSTCC=gcc HOSTCXX=g++)

kconfig() { "$SRC/scripts/config" --file "$OUT/.config" "$@"; }

configure() {
	info "Configuring ($DEFCONFIG)"
	make "${MAKE_ARGS[@]}" "$DEFCONFIG" >/dev/null

	case "$ROOT" in
	none) ;;
	ksun) kconfig --enable KSU --enable KSU_MANUAL_HOOK ;;
	sukisu) kconfig --enable KSU --disable KPM ;;
	bakasu)
		# BakaSU picks its hook method in a choice: manual, or SUSFS inline hooks.
		if $SUSFS; then
			kconfig --enable KSU --disable KSU_MANUAL_HOOK --disable KSU_TRACEPOINT_HOOK --enable KSU_SUSFS
		else
			kconfig --enable KSU --disable KSU_TRACEPOINT_HOOK --enable KSU_MANUAL_HOOK
		fi
		;;
	esac

	local c
	if $SUSFS; then
		for c in $SUSFS_CONFIGS; do kconfig --enable "$c"; done
		# SUSFS v2 leaves unmounting to the root driver itself.
		kconfig --disable KSU_SUSFS_TRY_UMOUNT
	elif [ "$ROOT" = sukisu ]; then
		kconfig --disable KSU_SUSFS
	fi

	case "$LTO" in
	thin) kconfig --disable LTO_NONE --enable LTO_CLANG --enable THINLTO ;;
	full) kconfig --disable LTO_NONE --enable LTO_CLANG --disable THINLTO ;;
	esac

	make "${MAKE_ARGS[@]}" olddefconfig >/dev/null

	# Fail early if a requested option did not survive olddefconfig.
	if [ "$ROOT" != none ]; then
		grep -q '^CONFIG_KSU=y' "$OUT/.config" || die "CONFIG_KSU could not be enabled"
	fi
	if $SUSFS; then
		grep -q '^CONFIG_KSU_SUSFS=y' "$OUT/.config" || die "CONFIG_KSU_SUSFS could not be enabled"
	fi
}

package() {
	local ak3="$WORK/AnyKernel3" stage="$OUT/ak3" sha release name
	info "Packing flashable zip"
	fetch_repo "$AK3_REPO" "$AK3_REF" "$ak3"

	rm -rf "$stage" && mkdir -p "$stage" "$DIST"
	cp -r "$ak3"/tools "$ak3"/META-INF "$stage"/
	cp "$ak3"/LICENSE "$stage"/ 2>/dev/null || true
	cp wonderful/anykernel.sh "$stage"/anykernel.sh
	cp "$OUT/arch/arm64/boot/Image" "$stage"/

	release="$(cat "$OUT/include/config/kernel.release")"
	sed -i "s|^kernel.string=.*|kernel.string=Wonderful Kernel $PROJECT_VERSION ($VARIANT) $release|" "$stage"/anykernel.sh

	sha="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
	name="Wonderful-$PROJECT_VERSION-$DEVICE-$VARIANT-$sha.zip"
	rm -f "$DIST/$name"
	(cd "$stage" && zip -qr9 "$DIST/$name" .)

	cat >"$DIST/${name%.zip}.txt" <<EOF
Wonderful Kernel $PROJECT_VERSION for $DEVICE_NAME ($DEVICE)
Variant:  $VARIANT
Kernel:   $release
Source:   $sha
Root:     $ROOT ${DRIVER_REF:-}
SUSFS:    $SUSFS
Built:    $(date -u +'%Y-%m-%d %H:%M UTC')
EOF
	ok "Flashable zip: dist/$name"
}

# -------------------------------------------------------------------- main --

export ARCH=arm64
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-$(whoami)}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-wonderful}"

if [ -L drivers/kernelsu ] || grep -q 'kernelsu' drivers/Makefile; then
	info "Removing a root driver left over from an earlier, interrupted build"
	restore_tree
fi
if $CLEANUP_ONLY; then
	ok "Source tree is clean"
	exit 0
fi

info "Wonderful Kernel $PROJECT_VERSION for $DEVICE_NAME: $VARIANT"
$CLEAN && { info "Cleaning out/"; rm -rf "$OUT"; }

fetch_toolchain
setup_root
configure

info "Building with $JOBS jobs (clang $(clang --version | head -1 | grep -o 'clang version [0-9.]*' | cut -d' ' -f3))"
start=$SECONDS
make "${MAKE_ARGS[@]}" -j"$JOBS"
[ -f "$OUT/arch/arm64/boot/Image" ] || die "build finished but out/arch/arm64/boot/Image is missing"
ok "Kernel built in $(((SECONDS - start) / 60))m $(((SECONDS - start) % 60))s: $(strings "$OUT/arch/arm64/boot/Image" | grep -m1 'Linux version' | cut -d' ' -f1-3)"

$PACKAGE && package
exit 0
