IMAGE_INSTALL:append = " swupdate swupdate-www u-boot-env libubootenv-bin hwrevision swupdate-ab-select update-confirm"

WKS_FILE = "bbb-image.wks"

create_directories() {
    install -d ${IMAGE_ROOTFS}/uboot
    install -d ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_directories"

BBB_BROKEN ?= "0"
break_image() {
    if [ "${BBB_BROKEN}" = "1" ]; then
        rm -f ${IMAGE_ROOTFS}/sbin/init
        printf '#!/bin/sh\n# Absichtlich kaputt: endet sofort, der Kernel gerät in Panic\nexit 1\n' \
            > ${IMAGE_ROOTFS}/sbin/init
        chmod 755 ${IMAGE_ROOTFS}/sbin/init
    fi
}
ROOTFS_POSTPROCESS_COMMAND += "break_image"

IMAGE_BOOT_FILES:append = " boot.scr"

IMAGE_FSTYPES += "ext4.gz"

# ext4 immer 256 MiB, wie auf der frischen Karte (Werte in KiB)
IMAGE_ROOTFS_SIZE = "262144"
# Bau bricht ab, wenn das Image nicht mehr in die Partition passt
IMAGE_ROOTFS_MAXSIZE = "262144"
