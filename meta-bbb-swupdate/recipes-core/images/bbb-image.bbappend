IMAGE_INSTALL:append = " swupdate swupdate-www u-boot-env libubootenv-bin hwrevision"

WKS_FILE = "bbb-image.wks"

create_data_dir() {
    install -d ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_data_dir"
