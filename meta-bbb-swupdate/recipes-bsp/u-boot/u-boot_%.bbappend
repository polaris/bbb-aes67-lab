FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://fw_env.config file://boot.cmd"

UBOOT_ENV = "boot"
UBOOT_ENV_SUFFIX = "scr"
