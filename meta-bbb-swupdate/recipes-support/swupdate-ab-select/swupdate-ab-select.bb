SUMMARY = "Automatische Auswahl der A/B-Seite für SWUpdate"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://updatepartdetect file://30-ab-select"

# Keine Quellen zum Auspacken, nur einzelne Dateien
S = "${UNPACKDIR}"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/updatepartdetect ${D}${bindir}

    install -d ${D}${libdir}/swupdate/conf.d
    install -m 0644 ${UNPACKDIR}/30-ab-select ${D}${libdir}/swupdate/conf.d/
}

FILES:${PN} += "${libdir}/swupdate/conf.d/30-ab-select"
RDEPENDS:${PN} += "swupdate"