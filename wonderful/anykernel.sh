### AnyKernel3 script for Wonderful Kernel (Samsung Galaxy A23 5G, a23xq)
## For stock One UI, GSIs and One UI ports on the Android 14 vendor. Not for
## device-specific AOSP ROMs (e.g. LineageOS for a23xq).
## No Android version check: GSIs can report a newer Android version than the vendor.
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
supported.versions=
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

ui_print " " "Wonderful Kernel is made for stock One UI, GSIs and One UI ports."
ui_print "Do not use it on device-specific AOSP ROMs such as LineageOS:" "they will not boot." " ";

# Only the kernel Image is replaced. The ramdisk (and any root already
# patched into it) is left exactly as it is.
split_boot;
flash_boot;
## end boot install
