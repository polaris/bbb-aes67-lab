IMAGE_INSTALL:append = " swupdate swupdate-www u-boot-env libubootenv-bin hwrevision"

WKS_FILE = "bbb-image.wks"

create_directories() {
    install -d ${IMAGE_ROOTFS}/uboot
    install -d ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_directories"

IMAGE_BOOT_FILES:append = " boot.scr"
