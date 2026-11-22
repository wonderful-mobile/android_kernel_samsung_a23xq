#!/usr/bin/env bash
#
# Friendly front end for build.sh: asks which kernel you want, then builds it.
#
#   ./run.sh                    # ask questions
#   ./run.sh --root ksun ...    # skip the questions, same options as build.sh
#
# On NixOS (or anywhere Nix is installed) it uses shell.nix automatically.

set -Eeuo pipefail
SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$SRC"
. wonderful/device.conf

run_build() {
	# Use the Nix shell when Nix is available and we are not inside it yet.
	if [ -z "${WONDERFUL_FHS_CMD:-}" ] && [ -z "${WONDERFUL_FHS:-}" ] && command -v nix-shell >/dev/null; then
		exec nix-shell "$SRC/shell.nix" --run "$(printf '%q ' "$SRC/build.sh" "$@")"
	fi
	exec "$SRC/build.sh" "$@"
}

# Options given: behave exactly like build.sh.
[ $# -gt 0 ] && run_build "$@"

ask() { # ask <prompt> <default> -> REPLY
	local prompt="$1" def="$2"
	read -r -p "$prompt [$def]: " REPLY || true
	REPLY="${REPLY:-$def}"
}

cat <<EOF

  Wonderful Kernel for the $DEVICE_NAME ($DEVICE)
  -------------------------------------------------

  Which root manager do you want built into the kernel?

    1) None              plain kernel, no root
    2) KernelSU-Next     KernelSU fork, a good default
    3) SukiSU            KernelSU fork
    4) BakaSU            KernelSU fork

  (Official KernelSU only supports GKI 2.0 kernels, Linux 5.10 and newer.)

EOF
ask "Choose 1-4" 2
case "$REPLY" in
1) ROOT=none ;;
2) ROOT=ksun ;;
3) ROOT=sukisu ;;
4) ROOT=bakasu ;;
*) echo "Please choose 1, 2, 3 or 4." >&2; exit 1 ;;
esac

SUSFS=false
if [[ " $SUSFS_SUPPORTED " == *" $ROOT "* ]]; then
	echo
	echo "  SUSFS hides root from apps that refuse to run on rooted phones."
	echo "  It is optional and adds some complexity. Skip it if you are not sure."
	echo
	ask "Add SUSFS? (y/n)" n
	[[ "$REPLY" =~ ^[Yy] ]] && SUSFS=true
fi

echo
ask "Start from a clean build? Slower, but safer after updates (y/n)" n
CLEAN=false
[[ "$REPLY" =~ ^[Yy] ]] && CLEAN=true

ARGS=(--root "$ROOT")
$SUSFS && ARGS+=(--susfs)
$CLEAN && ARGS+=(--clean)

echo
echo "  Running: ./build.sh ${ARGS[*]}"
echo "  The first build downloads the compiler (about 1.4 GB) and takes a while."
echo
run_build "${ARGS[@]}"
