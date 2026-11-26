SUMMARY = "Script to confirm the update of the A/B partition for SWUpdate"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://update-confirm file://10-login"

# Keine Quellen zum Auspacken, nur einzelne Dateien
S = "${UNPACKDIR}"

inherit allarch update-rc.d

# Als letzter Dienst starten, nach rmnologin.sh (S99, alphabetisch davor)
INITSCRIPT_NAME = "update-confirm"
INITSCRIPT_PARAMS = "start 99 2 3 4 5 ."

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${UNPACKDIR}/update-confirm ${D}${sysconfdir}/init.d/

    install -d ${D}${libdir}/${BPN}/checks.d
    install -m 0755 ${UNPACKDIR}/10-login ${D}${libdir}/${BPN}/checks.d/
}

RDEPENDS:${PN} += "libubootenv-bin"
