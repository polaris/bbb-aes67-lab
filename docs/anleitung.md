# Yocto-Image für den BeagleBone Black

Nov 3, 2026 · @Jan Deinhard

Ziel: ein `core-image-minimal` mit Yocto 6.0 „Wrynose“ (LTS bis April 2030) für die Maschine `beaglebone-yocto`, gebaut unter WSL2 und gebootet von microSD.

Seit 6.0 richtet man Builds mit `bitbake-setup` ein. Das alte Sammel-Repository `poky` ist abgelöst. Die Maschine `beaglebone-yocto` liegt weiterhin im Layer `meta-yocto-bsp` und braucht keinen Hersteller-Layer.

## 1. WSL2 vorbereiten

Ubuntu in WSL2 installieren (PowerShell). Ist schon Ubuntu 24.04 oder 26.04 vorhanden (prüfen mit `wsl -l -v`), diesen Schritt überspringen:

```powershell
wsl --install -d Ubuntu-24.04
```

WSL mehr RAM und Swap geben. Datei `%UserProfile%\.wslconfig` anlegen, Werte an den PC anpassen:

```ini
[wsl2]
memory=24GB
swap=16GB
```

Danach WSL neu starten:

```powershell
wsl --shutdown
```

Wichtig: Alles im Linux-Dateisystem (`~`) bauen, nie unter `/mnt/c`. Yocto 6.0 nennt 32 GB RAM und 140 GB Platten­platz als Richtwert.

## 2. Host-Pakete installieren

In der Ubuntu-Shell:

```bash
sudo apt update
sudo apt install -y build-essential chrpath cpio debianutils diffstat file \
  gawk gcc git iputils-ping libacl1 locales lz4 python3 python3-git \
  python3-jinja2 python3-pexpect python3-pip python3-subunit python3-venv \
  python3-websockets socat texinfo unzip wget xz-utils zstd bmap-tools
```

Yocto braucht eine UTF-8-Locale:

```bash
sudo locale-gen en_US.UTF-8
```

## 3. bitbake-setup installieren und Setup anlegen

`bitbake-setup` holt die Layer und legt das Build-Verzeichnis an. Installation in einer Python-Umgebung (venv):

```bash
cd ~
python3 -m venv --clear ~/bitbake-setup-venv
. ~/bitbake-setup-venv/bin/activate
pip install bitbake-setup
```

Alle Builds unter `~/bitbake-builds` ablegen:

```bash
bitbake-setup settings set --global default top-dir-prefix $HOME
```

Setup für die LTS-Version anlegen. Die Maschine stellen wir in Schritt 4 um:

```bash
bitbake-setup init --non-interactive poky-wrynose poky distro/poky machine/qemux86-64
```

Namen des angelegten Setups prüfen (im Folgenden `poky-wrynose`):

```bash
ls ~/bitbake-builds
```

venv wieder verlassen. Sonst findet BitBake die System-Python-Module nicht (Fehler z. B. `No module named 'websockets'`):

```bash
deactivate
```

## 4. Maschine und Image konfigurieren

Build-Umgebung laden (in jeder neuen Shell nötig):

```bash
source ~/bitbake-builds/poky-wrynose/build/init-build-env
```

Maschine auf den BeagleBone umstellen. Konfigurations-Fragmente sind seit 6.0 der Ersatz für viele `local.conf`-Zeilen:

```bash
bitbake-config-build enable-fragment machine/beaglebone-yocto
bitbake-config-build list-fragments
```

Root-Login ohne Passwort erlauben (nur für Entwicklung):

```bash
bitbake-config-build enable-fragment core/yocto/root-login-with-empty-password
```

Optional: vorgebaute Zwischenergebnisse aus dem Netz nutzen (Shared-State-Mirror). Spart Bauzeit bei guter Leitung:

```bash
bitbake-config-build enable-fragment core/yocto/sstate-mirror-cdn
```

Zusätzliche Pakete und Begrenzung der Parallelität in `conf/local.conf` eintragen. Weniger Threads verhindern, dass WSL der Speicher ausgeht:

```bash
cat >> conf/local.conf <<'EOF'
IMAGE_INSTALL:append = " ethtool"
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"
EOF
```

## 5. Bauen

Der erste Build dauert je nach Rechner mehrere Stunden. Weitere Builds gehen dank Cache deutlich schneller.

```bash
bitbake core-image-minimal
```

Ergebnis ansehen:

```bash
ls tmp/deploy/images/beaglebone-yocto/*.wic*
```

Du brauchst die komprimierte `.wic.zst`-Datei (Speicherkarten-Abbild) und die passende `.wic.bmap`-Datei (Blockliste für schnelles Schreiben).

## 6. SD-Karte beschreiben

WSL sieht den Kartenleser nicht direkt. Deshalb das Abbild entpackt nach Windows kopieren:

```bash
# <WindowsUser> durch deinen Windows-Benutzernamen ersetzen
# Das Abbild ist zstd-komprimiert. Die Umleitung < folgt dem symbolischen Link,
# zstd selbst würde ihn ignorieren.
zstd -dc < tmp/deploy/images/beaglebone-yocto/core-image-minimal-beaglebone-yocto.rootfs.wic.zst \
  > /mnt/c/Users/<WindowsUser>/Downloads/bbb.img
```

In Windows `Downloads\bbb.img` mit balenaEtcher oder Rufus auf die microSD-Karte schreiben. Die Endung `.img` sorgt dafür, dass beide Programme die Datei akzeptieren.

Alternative an einem nativen Linux-Rechner (Gerätenamen vorher mit `lsblk` prüfen):

```bash
# bmaptool entpackt .zst selbst
sudo bmaptool copy core-image-minimal-beaglebone-yocto.rootfs.wic.zst /dev/sdX
```

## 7. Booten und serielle Konsole

Seriell-Kabel mit **3,3-V-Pegel** an den 6-poligen Stecker J1 anschließen, z. B. FTDI TTL-232R-3V3 oder das 3-adrige UART8000-U. Bei unbekannter Belegung TX mit dem Multimeter finden: TX liegt im Ruhezustand auf ca. 3,3 V. Eine Ader mit 5 V nicht anschließen.

| J1-Pin | Signal am Board | Kabel |
| --- | --- | --- |
| 1 (am weißen Punkt) | GND | GND (schwarz) |
| 2, 3, 6 | – | frei |
| 4 | RX | TX des Kabels |
| 5 | TX | RX des Kabels |

PuTTY einrichten:

1. COM-Port des Kabels im Geräte-Manager unter „Anschlüsse (COM & LPT)“ suchen. Er verschwindet beim Abziehen des Kabels.
2. PuTTY: Connection type **Serial**, Serial line **COMx**, Speed **115200**.
3. Unter „Connection → Serial“: 8 Datenbits, 1 Stoppbit, keine Parität, Flow control **None**.
4. Sitzung unter „Session“ speichern, z. B. als „BeagleBone“.

Vorsicht: Ein Debian ab Werk stellt über Mini-USB zusätzlich einen virtuellen COM-Port bereit. Der zeigt keine Boot-Meldungen und verschwindet beim Neustart.

Von der SD-Karte booten:

1. PuTTY zuerst öffnen, damit die Boot-Meldungen sichtbar sind.
2. Board stromlos machen und Karte einstecken.
3. Strom über ein **5-V-Netzteil** anschließen (Hohlstecker 5,5/2,1 mm, Plus innen, mind. 1 A).

Mit aktualisiertem U-Boot im internen Speicher (Abschnitt 10) startet das Board ohne Taster von der Karte.

Nur beim Erststart mit dem alten U-Boot von 2014: Vor dem Einschalten Taster **S2** gedrückt halten und loslassen, sobald die USR-LEDs leuchten. S2 sitzt oben links neben dem microSD-Slot. S1 (RESET) und S3 (POWER) sitzen unten links. Bei Versorgung über Mini-USB am PC startete das Board mit S2 nicht von der Karte, PuTTY blieb leer. Mit Netzteil klappte es sofort.

Während des Starts flackert USR1 (SD-Karte). Flackert USR3, liest das Board den internen Speicher. Am Prompt mit `root` ohne Passwort anmelden. Die Begrüßung lautet „Poky (Yocto Project Reference Distro) 6.0.x beaglebone-yocto“.

## 8. Prüfen

Auf dem Board:

```bash
cat /etc/os-release      # Yocto-Version
uname -r                 # Kernel-Version
ip addr show eth0        # Netzwerk
ethtool -T eth0          # Hardware-Zeitstempel für PTP
```

Zeigt `ethtool -T` die Einträge `hardware-transmit` und `hardware-receive`, ist das Board bereit für PTP-Versuche. Dazu später den Layer `meta-openembedded` einbinden, der das Paket `linuxptp` enthält.

## 9. Notlösung: über das alte U-Boot starten

Falls der Start mit S2 nicht klappt, kann das alte U-Boot im internen Speicher den Yocto-Kernel von der SD-Karte laden. Beim Einschalten in PuTTY die Leertaste drücken, bis der Prompt `U-Boot#` erscheint. Der Countdown steht oft auf 0.

Karte prüfen:

```
mmc dev 0
fatls mmc 0:1
```

Kernel und Device Tree laden und starten. Jede Zeile einzeln und vollständig eingeben:

```
setenv bootargs console=ttyS0,115200n8 root=/dev/mmcblk0p2 rootwait
fatload mmc 0:1 0x82000000 zImage
fatload mmc 0:1 0x88000000 am335x-boneblack.dtb
bootz 0x82000000 - 0x88000000
```

Ohne `- 0x88000000` fehlt der Device Tree. Der Kernel bleibt dann stumm, und der Watchdog startet das Board neu.

Dauerhaft geht das über eine `uEnv.txt` auf der SD-Karte. Das alte U-Boot liest sie vor dem internen Speicher. Im laufenden Yocto ist die Boot-Partition der Karte bereits unter `/boot` eingehängt:

```bash
cat > /boot/uEnv.txt <<'EOF'
bootargs=console=ttyS0,115200n8 root=/dev/mmcblk0p2 rootwait
uenvcmd=fatload mmc 0:1 0x82000000 zImage; fatload mmc 0:1 0x88000000 am335x-boneblack.dtb; bootz 0x82000000 - 0x88000000
EOF
sync
```

Nicht `saveenv` im alten U-Boot verwenden. Bei alten Images liegt der Speicherbereich dafür teils in der Boot-Partition des internen Speichers.

## 10. U-Boot im internen Speicher aktualisieren

Voraussetzung: Der Start mit S2 funktioniert. Er ist das Sicherheitsnetz, falls das neue U-Boot nicht startet. Danach sucht das Board automatisch zuerst auf der SD-Karte nach `extlinux.conf`, und S2 ist überflüssig. Das alte Debian startet danach nicht mehr.

Mit S2 in Yocto starten. Im Board heißt die SD-Karte `mmcblk0`, der interne Speicher `mmcblk1`.

```bash
mkdir -p /mnt/emmc
mount -t vfat /dev/mmcblk1p1 /mnt/emmc
ls -l /mnt/emmc            # altes MLO und u-boot.img müssen da sein
mkdir -p /mnt/emmc/backup-2014
cp /mnt/emmc/MLO /mnt/emmc/u-boot.img /mnt/emmc/backup-2014/
cp /boot/MLO /boot/u-boot.img /mnt/emmc/
sync
umount /mnt/emmc
poweroff
```

Test: SD-Karte entfernen, ohne S2 einschalten. PuTTY zeigt jetzt die neue U-Boot-Version statt 2014.04. Steht dort weiterhin die alte Version, liegt eine Rohkopie des alten Bootloaders außerhalb der Partition und muss mit `dd` ersetzt werden.

## 11. PTP-Hardware-Zeitstempel aktivieren

Im Standard-Kernel von `beaglebone-yocto` fehlt der Treiber für die Zeitstempel-Einheit des AM335x (CPTS). Erkennbar an `PTP Hardware Clock: none` bei `ethtool -T eth0` und an:

```bash
zcat /proc/config.gz | grep CPTS     # "# CONFIG_TI_CPTS is not set"
```

Auf dem Build-PC einen eigenen Layer mit Kernel-Konfigurations-Fragment anlegen:

```bash
cd ~/bitbake-builds/poky-wrynose/build
bitbake-layers create-layer ../layers/meta-bbb
bitbake-layers add-layer ../layers/meta-bbb

mkdir -p ../layers/meta-bbb/recipes-kernel/linux/files
cat > ../layers/meta-bbb/recipes-kernel/linux/files/cpts.cfg <<'EOF'
CONFIG_PTP_1588_CLOCK=y
CONFIG_TI_CPTS=y
EOF

cat > ../layers/meta-bbb/recipes-kernel/linux/linux-yocto_%.bbappend <<'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://cpts.cfg"
EOF
```

## 12. linuxptp ins Image aufnehmen

`linuxptp` (mit `ptp4l` und `phc2sys`) liegt im Layer `meta-oe` von meta-openembedded:

```bash
git clone -b wrynose https://git.openembedded.org/meta-openembedded ../layers/meta-openembedded
bitbake-layers add-layer ../layers/meta-openembedded/meta-oe
echo 'IMAGE_INSTALL:append = " linuxptp"' >> conf/local.conf
bitbake core-image-minimal
```

Der Kernel wird dabei neu gebaut. Karte neu beschreiben und auf dem Board prüfen:

```bash
ls /sys/class/ptp     # erwartet: ptp0
ethtool -T eth0       # erwartet: hardware-transmit, hardware-receive, Precise (IEEE 1588 quality)
```

## 13. Switch konfigurieren (Cisco SG250-08)

Zugang: PC direkt anschließen, feste IP `192.168.1.10/24`, Browser auf `http://192.168.1.254`, Login `cisco`/`cisco`. Ohne DHCP-Server nimmt der Switch diese Adresse nach etwa einer Minute.

| Menü | Einstellung |
| --- | --- |
| Port Management → Green Ethernet → Properties | Energy Efficient Ethernet und Energy Detect aus |
| Quality of Service → General → QoS Properties | QoS Mode: Basic |
| Quality of Service → General → Queue | alle Queues: Strict Priority |
| Quality of Service → QoS Basic Mode → Global Settings | Trust Mode: DSCP |
| Quality of Service → General → DSCP to Queue | 46 (EF, PTP AES67) → 8, 56 (CS7, PTP Dante) → 8, 34 (AF41, Audio) → 7 |

Queue 8 ist die höchste Priorität. IGMP Snooping für die ersten Tests aus lassen. Später nur zusammen mit IGMP Querier einschalten. Zum Schluss das rote „Save“ oben anklicken.

## 14. Dante AVIO als PTP-Master

AVIO per Ethernet an den Switch, Strom per USB (PC, Ladegerät oder Hub mit Netzteil). Der PC mit Dante Controller hängt ebenfalls am Switch.

1. In Dante Controller das Gerät öffnen, Reiter **RTP-Konfiguration**: AES67-Modus aktivieren.
2. Reiter **Gerätekonfiguration** → **Neustart**.
3. Erst danach sendet der AVIO PTPv2. Ohne AES67-Modus nur PTPv1, das `ptp4l` ignoriert.

## 15. Board synchronisieren

```bash
ptp4l -i eth0 -m -s --priority1=255
```

`-s` macht das Board zum reinen Follower. `--priority1=255` ist nötig, weil der AVIO einen höheren `priority1` als den `ptp4l`-Standard 128 meldet. Ohne die Option hält sich das Board für die bessere Uhr (Warnung `defaultDS.priority1 probably misconfigured`).

Erwarteter Verlauf: `LISTENING` → `UNCALIBRATED` → `SLAVE`, danach eine Zeile pro Sekunde. Gemessen am Aufbau mit SG250 und AVIO:

| Wert | Bedeutung | gemessen |
| --- | --- | --- |
| rms / max | Versatz zum Master in ns | 20–50 / meist < 100 |
| freq | Frequenzkorrektur in ppb | ca. +43 500, stabil |
| delay | Laufzeit in eine Richtung in ns | ca. 7 060 |

Die erste Zeile mit riesigem Wert und „temporal vortex“ ist normal. Das Board hat keine gepufferte Uhr und startet mit falscher Zeit.

Systemuhr an die PTP-Uhr koppeln (zweite Konsole):

```bash
phc2sys -s eth0 -c CLOCK_REALTIME -w -m
```

## Quellen

- [Yocto Project Quick Build (6.0)](https://docs.yoctoproject.org/6.0.3/_sources/brief-yoctoprojectqs/index.rst.txt)
- [BSP Developer’s Guide (6.0)](https://docs.yoctoproject.org/bsp-guide/bsp.html)
- [Yocto Project 6.0 „Wrynose“ – Ankündigung](https://www.yoctoproject.org/?p=102509)
- [CNX Software zu Yocto 6.0](https://www.cnx-software.com/2026/05/14/yocto-project-6-0-wrynose-released-with-linux-6-18-lts/)
