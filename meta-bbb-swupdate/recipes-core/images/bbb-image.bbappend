IMAGE_INSTALL:append = " swupdate swupdate-www u-boot-env libubootenv-bin hwrevision swupdate-ab-select"

WKS_FILE = "bbb-image.wks"

create_directories() {
    install -d ${IMAGE_ROOTFS}/uboot
    install -d ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_directories"

IMAGE_BOOT_FILES:append = " boot.scr"

IMAGE_FSTYPES += "ext4.gz"

# ext4 immer 256 MiB, wie auf der frischen Karte (Werte in KiB)
IMAGE_ROOTFS_SIZE = "262144"
# Bau bricht ab, wenn das Image nicht mehr in die Partition passt
IMAGE_ROOTFS_MAXSIZE = "262144"
