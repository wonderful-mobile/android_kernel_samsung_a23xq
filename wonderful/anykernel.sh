### AnyKernel3 script for Wonderful Kernel (Samsung Galaxy A23 5G, a23xq)
## Based on AnyKernel3 by osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Wonderful Kernel
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=a23xq
device.name2=
supported.versions=14
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
# boot shell variables
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Only the kernel Image is replaced. The ramdisk (and any root already
# patched into it) is left exactly as it is.
split_boot;
flash_boot;
## end boot install
