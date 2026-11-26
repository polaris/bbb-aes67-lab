FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://fw_env.config file://boot.cmd file://setexpr.cfg file://bootcount.cfg"

UBOOT_ENV = "boot"
UBOOT_ENV_SUFFIX = "scr"
