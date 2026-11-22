SUMMARY = "Update-Image für das AES67-Labor"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://sw-description"

IMAGE_DEPENDS = "bbb-image"

SWUPDATE_IMAGES = "bbb-image"
SWUPDATE_IMAGES_FSTYPES[bbb-image] = ".rootfs.ext4.gz"

inherit swupdate

# swupdate.bbclass macht die @@…@@-Variablen in sw-description nicht zu
# Abhängigkeiten von do_swuimage (swupdate-image.bbclass tut es)
do_swuimage[vardeps] += "${@swupdate_find_bitbake_variables(d)}"
