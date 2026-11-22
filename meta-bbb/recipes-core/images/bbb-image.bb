SUMMARY = "Image für das AES67-Labor"
require recipes-core/images/core-image-minimal.bb

IMAGE_INSTALL:append = " ethtool linuxptp"

add_bbb_version_to_rootfs() {
    echo "${BBB_VERSION}" > ${IMAGE_ROOTFS}${sysconfdir}/bbb-version
}
ROOTFS_POSTPROCESS_COMMAND += "add_bbb_version_to_rootfs"
