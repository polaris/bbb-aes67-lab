FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://hash.cfg file://20-no-markers"

do_install:append() {
    install -m 0644 ${UNPACKDIR}/20-no-markers ${D}${libdir}/swupdate/conf.d/
}
