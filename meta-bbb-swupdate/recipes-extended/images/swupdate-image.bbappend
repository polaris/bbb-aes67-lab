IMAGE_FSTYPES = "cpio.gz.u-boot"
IMAGE_INSTALL:append = " init-ifupdown hwrevision libgcc libubootenv-bin u-boot-env"

create_uboot_dir() {
    install -d ${IMAGE_ROOTFS}/uboot
}
ROOTFS_POSTPROCESS_COMMAND += "create_uboot_dir"
