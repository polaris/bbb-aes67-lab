# Yocto-Image für den BeagleBone Black

Nov 3, 2026 · @Jan Deinhard

Ziel: ein eigenes Image `bbb-image` auf Basis von `core-image-minimal` mit Yocto 6.0 „Wrynose“ (LTS bis April 2030) für die Maschine `beaglebone-yocto`, gebaut unter WSL2 und gebootet von microSD.

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

Eigene Dateien liegen in einem Git-Repository, hier `~/src/bbb-aes67-lab`. Die eigenen Einstellungen kommen dort in `conf/local.inc`. Die `conf/local.conf` im Build-Verzeichnis bindet sie nur per `require` ein. So stehen die Einstellungen unter Versionskontrolle:

```bash
mkdir -p ~/src/bbb-aes67-lab/conf && git -C ~/src/bbb-aes67-lab init
cat > ~/src/bbb-aes67-lab/conf/local.inc <<'EOF'
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"
EXTRA_IMAGE_FEATURES += "ssh-server-dropbear tools-debug"
EOF
echo "require $HOME/src/bbb-aes67-lab/conf/local.inc" >> conf/local.conf
```

Weniger Threads verhindern, dass WSL der Speicher ausgeht. `ssh-server-dropbear` erlaubt `ssh` und `scp` aufs Board, `tools-debug` bringt Werkzeuge wie `gdb` und `strace` mit.

In `local.inc` gehören nur Einstellungen für den Build-Rechner und die Entwicklung. Pakete für das Board kommen in ein eigenes Image. Per `IMAGE_INSTALL` in `local.inc` würden sie in jedem gebauten Image landen.

### Eigener Layer und eigenes Image

Eigene Rezepte kommen in den Layer `meta-bbb`. Er liegt ebenfalls im Repository. Unter `../layers` steht nur ein symbolischer Link darauf. So gibt es nur eine Kopie, und Änderungen im Repository wirken sofort im Build:

```bash
bitbake-layers create-layer ~/src/bbb-aes67-lab/meta-bbb
rm -r ~/src/bbb-aes67-lab/meta-bbb/recipes-example
ln -s ~/src/bbb-aes67-lab/meta-bbb ../layers/meta-bbb
bitbake-layers add-layer ../layers/meta-bbb
```

Der Link liegt nicht im Repository. Auf einem neuen Rechner muss er neu angelegt werden.

Image `bbb-image` auf Basis von `core-image-minimal` anlegen:

```bash
mkdir -p ~/src/bbb-aes67-lab/meta-bbb/recipes-core/images
cat > ~/src/bbb-aes67-lab/meta-bbb/recipes-core/images/bbb-image.bb <<'EOF'
SUMMARY = "Image für das AES67-Labor"
require recipes-core/images/core-image-minimal.bb

IMAGE_INSTALL:append = " ethtool"
EOF
```

Prüfen, was im Image landet:

```bash
bitbake -e bbb-image | grep ^IMAGE_INSTALL=
# IMAGE_INSTALL="packagegroup-core-boot  ethtool"
```

## 5. Bauen

Der erste Build dauert je nach Rechner mehrere Stunden. Weitere Builds gehen dank Cache deutlich schneller.

```bash
bitbake bbb-image
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
zstd -dc < tmp/deploy/images/beaglebone-yocto/bbb-image-beaglebone-yocto.rootfs.wic.zst \
  > /mnt/c/Users/<WindowsUser>/Downloads/bbb.img
```

In Windows `Downloads\bbb.img` mit balenaEtcher oder Rufus auf die microSD-Karte schreiben. Die Endung `.img` sorgt dafür, dass beide Programme die Datei akzeptieren.

Alternative an einem nativen Linux-Rechner (Gerätenamen vorher mit `lsblk` prüfen):

```bash
# bmaptool entpackt .zst selbst
sudo bmaptool copy bbb-image-beaglebone-yocto.rootfs.wic.zst /dev/sdX
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

Auf dem Build-PC im Layer `meta-bbb` (Abschnitt 4) ein Kernel-Konfigurations-Fragment anlegen:

```bash
cd ~/src/bbb-aes67-lab/meta-bbb
mkdir -p recipes-kernel/linux/files
cat > recipes-kernel/linux/files/cpts.cfg <<'EOF'
CONFIG_PTP_1588_CLOCK=y
CONFIG_TI_CPTS=y
EOF

cat > recipes-kernel/linux/linux-yocto_%.bbappend <<'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://cpts.cfg"
EOF
```

## 12. linuxptp ins Image aufnehmen

`linuxptp` (mit `ptp4l` und `phc2sys`) liegt im Layer `meta-oe` von meta-openembedded:

```bash
cd ~/bitbake-builds/poky-wrynose/build
git clone -b wrynose https://git.openembedded.org/meta-openembedded ../layers/meta-openembedded
bitbake-layers add-layer ../layers/meta-openembedded/meta-oe
```

In `meta-bbb/recipes-core/images/bbb-image.bb` die Paketzeile erweitern:

```
IMAGE_INSTALL:append = " ethtool linuxptp"
```

`meta-bbb` hängt damit von `meta-oe` ab. In `meta-bbb/conf/layer.conf` eintragen, dann meldet BitBake gleich beim Start, wenn der Layer fehlt:

```
LAYERDEPENDS_meta-bbb = "core openembedded-layer"
```

```bash
bitbake bbb-image
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

## 16. SWUpdate einbinden

SWUpdate spielt später neue Images über das Netzwerk ein. In diesem Schritt kommt es nur ins Image. Das Rezept liefert der Layer `meta-swupdate`. Seine einzige Abhängigkeit (`LAYERDEPENDS_swupdate = "openembedded-layer"`) ist `meta-oe` aus Abschnitt 12.

```bash
cd ~/bitbake-builds/poky-wrynose/build
git clone -b wrynose https://github.com/sbabic/meta-swupdate ../layers/meta-swupdate
git -C ../layers/meta-swupdate log -1 --oneline    # Stand notieren
bitbake-layers add-layer ../layers/meta-swupdate
```

`bitbake-setup update` aktualisiert nur die Layer, die es selbst angelegt hat. `meta-openembedded` und `meta-swupdate` mit `git pull` selbst aktualisieren.

### Eigener Layer für SWUpdate

Alles, was nur SWUpdate betrifft, kommt in einen zweiten eigenen Layer `meta-bbb-swupdate`. Er liegt wie `meta-bbb` im Repository und ist per symbolischem Link eingebunden (Abschnitt 4):

```bash
bitbake-layers create-layer ~/src/bbb-aes67-lab/meta-bbb-swupdate
rm -r ~/src/bbb-aes67-lab/meta-bbb-swupdate/recipes-example
ln -s ~/src/bbb-aes67-lab/meta-bbb-swupdate ../layers/meta-bbb-swupdate
bitbake-layers add-layer ../layers/meta-bbb-swupdate
```

Abhängigkeiten in `meta-bbb-swupdate/conf/layer.conf` eintragen. Der Layer ergänzt das Image aus `meta-bbb` und braucht SWUpdate:

```
LAYERDEPENDS_meta-bbb-swupdate = "core meta-bbb swupdate"
```

### SWUpdate ins Image

SWUpdate kommt über ein `.bbappend` zu `bbb-image` dazu. Ohne den SWUpdate-Layer entsteht dasselbe Image ohne SWUpdate.

`meta-bbb-swupdate/recipes-core/images/bbb-image.bbappend`:

```
IMAGE_INSTALL:append = " swupdate"
```

Vor dem Bauen prüfen, was im Image landet:

```bash
bitbake -e bbb-image | grep ^IMAGE_INSTALL=
# IMAGE_INSTALL="packagegroup-core-boot  ethtool linuxptp swupdate"
bitbake bbb-image
```

Karte wie in Abschnitt 6 beschreiben.

### Prüfen

SWUpdate startet beim Booten als Dienst. In PuTTY erscheinen nach Dropbear die Meldungen `Starting swupdate ...` und `SWUpdate v2026.05.1`. Auf dem Board:

```bash
swupdate -h
```

Beobachtungen beim ersten Start:

| Meldung | Bedeutung |
| --- | --- |
| `Using default bootloader interface: uboot` | Zugriff auf die U-Boot-Umgebung ist eingebaut |
| Handler `dummy`, `executor`, `flash`, `lua`, `raw`, `rawfile`, `shellscript`, `preinstall`, `postinstall` | `rawfile` installiert einzelne Dateien, `raw` schreibt ganze Partitionen |
| `Registered Crypto Providers:` ohne Eintrag | Hash-Prüfung, Signatur und Verschlüsselung sind aus, siehe unten |
| Lua-Fehler `module 'swupdate_handlers' not found` | harmlos, es gibt nur keine eigenen Handler in Lua |

PTP läuft mit dem neuen Image unverändert (Werte wie in Abschnitt 15).

### Konfiguration von SWUpdate ansehen und anpassen

Die Konfiguration kommt aus der `defconfig` in `meta-swupdate/recipes-support/swupdate/swupdate/`. Ansehen geht mit `bitbake -c menuconfig swupdate` (Suche mit `/`) oder direkt in der fertigen `.config` im Build-Verzeichnis des Rezepts:

```bash
B=$(bitbake -e swupdate | sed -n 's/^B="\(.*\)"/\1/p')
grep -E "SSL|HASH|SIGNED|ENCRYPT|UBOOT|WEBSERVER|ARCHIVE|GUNZIP|ZSTD" "$B/.config"
```

`bitbake -e` liefert den Pfad des Build-Verzeichnisses (`B`), `sed` schneidet ihn aus. Stand der Standard-Konfiguration:

| Option | Stand | Bedeutung |
| --- | --- | --- |
| `CONFIG_UBOOT`, `CONFIG_UBOOT_FWENV="/etc/fw_env.config"` | an | U-Boot-Umgebung über `libubootenv` |
| `CONFIG_UBOOT_DEFAULTENV="/etc/u-boot-initial-env"` | – | Ersatz-Umgebung, solange U-Boot keine gespeichert hat |
| `CONFIG_WEBSERVER`, `CONFIG_MONGOOSESSL` | an | Webserver mit HTTPS |
| `CONFIG_SSL_IMPL_OPENSSL` | an | OpenSSL ist eingebaut, wird aber nur vom Webserver genutzt |
| `CONFIG_HASH_VERIFY` | aus | `sha256` in `sw-description` wird nicht geprüft |
| `CONFIG_SIGNED_IMAGES`, `CONFIG_ENCRYPTED_IMAGES` | aus | keine Signatur, keine Verschlüsselung |
| `CONFIG_GUNZIP` | an | `.gz`-Images möglich |
| `CONFIG_ZSTD`, `CONFIG_ARCHIVE` | aus | keine `.zst`-Images, keine tar-Archive |

Weil Hash-Prüfung, Signatur und Verschlüsselung aus sind, meldet sich OpenSSL nicht als Crypto-Provider an. Daher die leere Zeile beim Start.

Änderungen im Menü gehen beim nächsten `bitbake -c clean swupdate` verloren. Dauerhaft geht es über Fragmente: Das Rezept erbt `cml1` und mischt alle `.cfg`-Dateien aus `SRC_URI` mit `merge_config.sh` über die `defconfig`. Dieselben Fragmente wertet es auch beim Parsen aus und ergänzt `DEPENDS` passend, z. B. `libarchive` bei `CONFIG_ARCHIVE=y`. Nach Änderungen im Menü erzeugt `bitbake -c diffconfig swupdate` so ein Fragment.

Hash-Prüfung einschalten:

`meta-bbb-swupdate/recipes-support/swupdate/swupdate_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://hash.cfg"
```

`meta-bbb-swupdate/recipes-support/swupdate/files/hash.cfg`:

```
CONFIG_HASH_VERIFY=y
```

Prüfen. `-f` erzwingt, dass `do_configure` neu läuft:

```bash
bitbake -c configure -f swupdate
grep HASH_VERIFY "$B/.config"     # CONFIG_HASH_VERIFY=y
bitbake bbb-image
```

Karte neu beschreiben. Beim Start erscheint jetzt ein Crypto-Provider:

```
[INFO ] : SWUPDATE running :  [print_registered_cryptolib] : Registered Crypto Providers:
[INFO ] : SWUPDATE running :  [print_registered_cryptolib] :    Provider for hash
[INFO ] : SWUPDATE running :  [print_registered_cryptolib] :            opensslSHA256*
```

OpenSSL stellt nur die Hash-Prüfung (SHA-256) bereit, weil nur sie eingeschaltet ist. Für signierte Updates kommt später ein eigener Eintrag dazu. Der Stern markiert vermutlich den Provider, der als Standard benutzt wird. Die Handler sind unverändert.

## 17. Erstes Update mit einer Datei

Das erste Update installiert nur eine Textdatei. So lässt sich das Format ohne Risiko ausprobieren.

### Update-Rezept

Ablage im Layer `meta-bbb-swupdate`. BitBake sucht `file://`-Dateien unter anderem im Ordner `files/` neben dem Rezept:

```
recipes-extended/update-hello/
├── update-hello.bb
└── files/
    ├── sw-description
    └── hello.txt
```

`update-hello.bb`:

```
SUMMARY = "Erstes Test-Update: installiert eine einzelne Datei"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://sw-description \
    file://hello.txt \
"

inherit swupdate
```

Die Klasse `swupdate` packt alle Dateien aus `SRC_URI` in die `.swu`, `sw-description` an erster Stelle. Images aus dem Deploy-Ordner kämen über `SWUPDATE_IMAGES` dazu, hier nicht nötig.

`files/sw-description`:

```
software =
{
	version = "0.1.0";
	description = "Erstes Test-Update";
	hardware-compatibility: [ "1.0" ];

	files: (
		{
			filename = "hello.txt";
			path = "/home/root/hello.txt";
		}
	);
};
```

`filename` ist der Name in der `.swu`, `path` das Ziel auf dem Board. Einträge unter `files` installiert der Handler `rawfile`. Eine Zeile `sha256` ist nicht nötig, siehe unten.

Bauen und Inhalt ansehen:

```bash
bitbake update-hello
cpio -it < tmp/deploy/images/beaglebone-yocto/update-hello-beaglebone-yocto.rootfs.swu
# sw-description
# hello.txt
# 2 blocks
```

Eine `.swu` ist ein cpio-Archiv. SWUpdate liest es als Datenstrom von vorn. Deshalb muss `sw-description` zuerst kommen: SWUpdate muss wissen, was zu tun ist, bevor die Daten eintreffen.

### Hardware-Revision

Die `defconfig` von `meta-swupdate` schaltet `CONFIG_HW_COMPATIBILITY=y` ein, mit `CONFIG_HW_COMPATIBILITY_FILE="/etc/hwrevision"`. Damit ist `hardware-compatibility` in `sw-description` Pflicht. Ohne den Eintrag bricht SWUpdate ab:

```
[ERROR] : SWUPDATE failed [0] ERROR parser.c : parse_hw_compatibility : 305 : HW compatibility not found
[ERROR] : SWUPDATE failed [0] ERROR parser.c : parser : 1112 : Found nothing to install
```

Die folgenden Meldungen zum JSON-Parser sind nur Folgefehler.

Auf dem Board steht in `/etc/hwrevision` eine Zeile `<Board> <Revision>`. SWUpdate installiert nur, wenn die Revision in `hardware-compatibility` vorkommt. `meta-swupdate` legt die Datei nicht an. Eigenes Rezept `recipes-extended/hwrevision/hwrevision.bb`:

```
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
```

Ins Image über `meta-bbb-swupdate/recipes-core/images/bbb-image.bbappend`:

```
IMAGE_INSTALL:append = " swupdate hwrevision"
```

Image neu bauen, Karte beschreiben. Auf dem Board:

```bash
cat /etc/hwrevision     # beaglebone-yocto 1.0
```

SWUpdate meldet beim Start `Running on beaglebone-yocto Revision 1.0`.

### Auf dem Board installieren

```bash
scp tmp/deploy/images/beaglebone-yocto/update-hello-beaglebone-yocto.rootfs.swu root@<Board-IP>:/tmp/
```

Auf dem Board:

```bash
swupdate -v -M -m -i /tmp/update-hello-beaglebone-yocto.rootfs.swu
cat /home/root/hello.txt
```

`-M` und `-m` schalten die Markierungen in der U-Boot-Umgebung ab (Transaktion „läuft“ und Status „installiert“). Ohne `/etc/fw_env.config` kann SWUpdate sie nicht schreiben. Die Datei wird zwar installiert, das Update gilt aber als fehlgeschlagen:

```
[ERROR] : SWUPDATE failed [0] ERROR uboot.c : bootloader_initialize : 47 : Cannot initialize environment from /etc/fw_env.config
[ERROR] : SWUPDATE failed [0] ERROR stream_interface.c : network_initializer : 789 : Cannot persistently store INSTALLED update state.
```

Mit `-M -m` endet der Lauf mit `SWUpdate was successful !`. Die Optionen entfallen, sobald die U-Boot-Umgebung aus Linux erreichbar ist.

Der Aufruf mit `-i` legt dieselben Sockets an wie der SWUpdate-Dienst (`/tmp/sockinstctrl`, `/tmp/swupdateprog`) und löscht sie am Ende. Vor Updates über den Dienst das Board neu starten.

### Prüfsummen

Die `.swu` baut `swugenerator`. Es formatiert `sw-description` neu und setzt für jede Datei selbst die SHA-256-Prüfsumme (`swugenerator/generator.py`):

```python
if not self.nohash:
    entry["sha256"] = new.getsha256()
```

Ein eigener Wert für `sha256` in `sw-description` wird überschrieben, ebenso der Platzhalter `$swupdate_get_sha256(...)`. Prüfen durch Auspacken der `.swu`:

```bash
mkdir -p ~/swu-test && cd ~/swu-test
cpio -id < ~/bitbake-builds/poky-wrynose/build/tmp/deploy/images/beaglebone-yocto/update-hello-beaglebone-yocto.rootfs.swu
cat sw-description
sha256sum hello.txt      # gleicher Wert wie in sw-description
```

Aus dem Quellcode von SWUpdate (2026.05.1):

- Eine Prüfsumme aus lauter Nullen gilt als „keine Prüfsumme“ (`IsValidHash` in `core/util.c`). Dann wird nicht verglichen.
- `CONFIG_HASH_VERIFY` prüft vorhandene Prüfsummen, verlangt aber keine. Pflicht werden sie erst mit `CONFIG_SIGNED_IMAGES` (`check_missing_hash` in `core/parser.c`). Ohne Signatur könnte jemand mit der `.swu` auch die Prüfsumme entfernen.

### Kaputtes Update

Um die Prüfung zu testen, muss die fertige `.swu` verändert werden. Das entspricht einer Datei, die nach dem Bauen beschädigt oder manipuliert wurde:

```bash
cd ~/swu-test
echo "manipuliert" > hello.txt
printf '%s\n' sw-description hello.txt | cpio -o -H newc > update-hello-broken.swu
scp update-hello-broken.swu root@<Board-IP>:/tmp/
```

`printf` hält die Reihenfolge ein, `sw-description` zuerst. `-H newc` ist das cpio-Format ohne eigene Prüfsumme, sodass nur SWUpdate den Fehler finden kann.

Auf dem Board:

```bash
swupdate -v -M -m -i /tmp/update-hello-broken.swu
cat /home/root/hello.txt     # unverändert
```

```
[TRACE] : SWUPDATE running :  [extract_files] :         filename hello.txt
[TRACE] : SWUPDATE running :  [extract_files] :         size 12 required
[ERROR] : SWUPDATE failed [0] ERROR cpio_utils.c : hash_compare : 588 : HASH mismatch : 99df166e…101b <--> d8699e30…1f5c
[ERROR] : SWUPDATE failed [1] Image invalid or corrupted. Not installing ...
```

Links steht die Prüfsumme aus `sw-description`, rechts die der gelieferten Daten. Der Fehler kommt beim Auspacken (`extract_files`), vor `Valid image found: copying to FLASH`. SWUpdate arbeitet in zwei Phasen: erst alle Dateien in ein temporäres Verzeichnis auspacken und prüfen, dann installieren. Mit der Eigenschaft `installed-directly = true` schreibt ein Handler direkt aus dem Datenstrom. Dann fällt ein Fehler erst auf, wenn die Daten schon geschrieben sind.

## Quellen

- [Yocto Project Quick Build (6.0)](https://docs.yoctoproject.org/6.0.3/_sources/brief-yoctoprojectqs/index.rst.txt)
- [BSP Developer’s Guide (6.0)](https://docs.yoctoproject.org/bsp-guide/bsp.html)
- [Yocto Project 6.0 „Wrynose“ – Ankündigung](https://www.yoctoproject.org/?p=102509)
- [CNX Software zu Yocto 6.0](https://www.cnx-software.com/2026/05/14/yocto-project-6-0-wrynose-released-with-linux-6-18-lts/)
- [SWUpdate-Dokumentation](https://sbabic.github.io/swupdate/)
- [meta-swupdate](https://github.com/sbabic/meta-swupdate)
