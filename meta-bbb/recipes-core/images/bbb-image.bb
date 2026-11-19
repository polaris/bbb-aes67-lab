SUMMARY = "Image für das AES67-Labor"
require recipes-core/images/core-image-minimal.bb

IMAGE_INSTALL:append = " ethtool linuxptp"
