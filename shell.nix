# Build environment for Wonderful Kernel.
#
#   nix-shell                  # interactive shell, then run ./run.sh
#   nix-shell --run ./run.sh   # one-shot build
#
# Android's prebuilt clang (downloaded by ./build.sh) is a normal Linux
# binary, so builds run inside an FHS environment ("wonderful-fhs") where it
# works unchanged. build.sh re-enters that environment by itself, so you
# never have to call it directly.
{ pkgs ? import <nixpkgs> { } }:

let
  fhs = pkgs.buildFHSEnv {
    name = "wonderful-fhs";

    targetPkgs = p: with p; [
      # kernel build
      bc bison flex gnumake perl python3 openssl openssl.dev elfutils
      ncurses ncurses.dev zlib zlib.dev libxml2 cpio lz4 kmod
      gcc binutils glibc glibc.dev
      # scripts and packaging
      git curl wget gnutar gzip xz zip unzip which file rsync
    ];

    profile = ''
      export WONDERFUL_FHS=1
    '';

    runScript = "bash";
  };
in
pkgs.mkShell {
  packages = [ fhs ];
  shellHook = ''
    export WONDERFUL_FHS_CMD=${fhs}/bin/wonderful-fhs
    if [[ $- == *i* ]]; then
      echo "Wonderful Kernel build shell. Run ./run.sh to start."
    fi
  '';
}
