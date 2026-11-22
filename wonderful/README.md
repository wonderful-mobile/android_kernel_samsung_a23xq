# Wonderful Kernel build tools

Quick start, from the top of the kernel source:

```bash
./run.sh                          # asks which root manager you want, then builds
./run.sh --root ksun              # or skip the questions
./build.sh --help                 # every option
```

The flashable zip ends up in `dist/`. Full guide:
https://wonderful-mobile-docs.techtransthai.org/wonderful-kernel/building/

## Files

| Path | What it is |
|---|---|
| `../build.sh` | Build script: toolchain, root driver, patches, kernel, zip |
| `../run.sh` | Friendly front end, uses Nix automatically when available |
| `../shell.nix` | Build environment (works on NixOS and any distro with Nix) |
| `device.conf` | Device name, defconfig, supported root managers |
| `anykernel.sh` | AnyKernel3 install script for this device |
| `patches/susfs/<kver>/` | SUSFS ported to this kernel |
| `patches/root/<root>/` | Kernel hooks for a root manager (without SUSFS) |
| `patches/root/<root>-susfs/` | Kernel hooks for a root manager with SUSFS |
| `patches/driver/<root>/` | Small fixes to the downloaded root driver |

Root drivers are pinned in `build.sh` (`KSUN_REF`, `SUKISU_REF`). Everything
from `patches/` and the driver itself is applied only during the build and
removed afterwards. If a build was killed, run `./build.sh --cleanup`.
