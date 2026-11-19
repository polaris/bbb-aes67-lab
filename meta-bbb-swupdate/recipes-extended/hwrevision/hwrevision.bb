SUMMARY = "Hardware-Revision für die Kompatibilitätsprüfung von SWUpdate"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Inhalt hängt von MACHINE ab, daher maschinenspezifisches Paket
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Revision der Platine, muss in hardware-compatibility von sw-description stehen
HW_REVISION ?= "1.0"

# Keine Quellen, kein Compiler nötig
S = "${UNPACKDIR}"
INHIBIT_DEFAULT_DEPS = "1"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}
    echo "${MACHINE} ${HW_REVISION}" > ${D}${sysconfdir}/hwrevision
}
