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

## 18. Updates über den Browser

SWUpdate läuft seit Abschnitt 16 als Dienst, bisher ohne Webserver. Mit dem Webserver lässt sich eine `.swu` im Browser hochladen.

### Wie der Dienst startet

Alles kommt aus dem Rezept `swupdate` in `meta-swupdate`:

1. `/etc/init.d/swupdate` ist per `update-rc.d` angemeldet (`INITSCRIPT_PARAMS = "defaults 70"`). Daher die Meldung `Starting swupdate ...` beim Booten.
2. Das Init-Skript startet `/usr/lib/swupdate/swupdate.sh`.
3. `swupdate.sh` setzt Vorgaben, liest alle Dateien aus `/usr/lib/swupdate/conf.d/` und `/etc/swupdate/conf.d/` nach Namen sortiert ein und startet `swupdate` mit den Variablen `SWUPDATE_ARGS`, `SWUPDATE_WEBSERVER_ARGS` (für `-w`) und `SWUPDATE_SURICATTA_ARGS` (für `-u`).

Eine Datei in `/etc/swupdate/conf.d/` ersetzt die gleichnamige in `/usr/lib/swupdate/conf.d/`. Vorgaben aus Paketen gehören nach `/usr/lib`, Änderungen von Hand auf dem Board nach `/etc`.

Die Pakete teilen sich so auf:

| Paket | Inhalt |
| --- | --- |
| `swupdate` | Programm, Init-Skript, `swupdate.sh`, alles unter `/usr/lib/swupdate/` |
| `swupdate-www` | Webseite unter `/www` und `/usr/lib/swupdate/conf.d/10-mongoose-args` |

`10-mongoose-args` setzt `SWUPDATE_WEBSERVER_ARGS="-r /www"`. Ist `swupdate-www` im Image, startet der Webserver also von selbst. Die Datei passt auch auf das Muster `${libdir}/swupdate/*` von `swupdate`. Sie landet trotzdem in `swupdate-www`, weil das Rezept die Teilpakete per `PACKAGES =+` vor das Hauptpaket stellt und jede Datei an das erste passende Paket geht.

### Webserver ins Image

`meta-bbb-swupdate/recipes-core/images/bbb-image.bbappend`:

```
IMAGE_INSTALL:append = " swupdate swupdate-www hwrevision"
```

### Startoptionen ergänzen

Ohne Zugriff auf die U-Boot-Umgebung braucht auch der Dienst `-M -m` (Abschnitt 17). Dafür eine eigene Datei in `conf.d`. Achtung: `swupdate.sh` setzt `SWUPDATE_ARGS="-v ${SWUPDATE_EXTRA_ARGS}"` **vor** dem Einlesen von `conf.d`. `SWUPDATE_EXTRA_ARGS` in einer `conf.d`-Datei wirkt deshalb nicht mehr. `SWUPDATE_ARGS` selbst erweitern.

`meta-bbb-swupdate/recipes-support/swupdate/files/20-no-markers`:

```sh
# Bis Schritt 4: keine Markierungen in der U-Boot-Umgebung, fw_env.config fehlt noch
SWUPDATE_ARGS="${SWUPDATE_ARGS} -M -m"
```

Das `.bbappend` aus Abschnitt 16 erweitern, `meta-bbb-swupdate/recipes-support/swupdate/swupdate_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://hash.cfg file://20-no-markers"

do_install:append() {
    install -m 0644 ${UNPACKDIR}/20-no-markers ${D}${libdir}/swupdate/conf.d/
}
```

`FILES` ist nicht nötig, `${libdir}/swupdate/*` gehört schon zum Paket `swupdate`. Zum schnellen Ausprobieren ohne Neubau geht dieselbe Zeile auch von Hand nach `/etc/swupdate/conf.d/20-no-markers`, dann `reboot`.

Image bauen, Karte beschreiben. Auf dem Board prüfen:

```bash
ls /usr/lib/swupdate/conf.d/     # 10-mongoose-args  20-no-markers
ps | grep swupdate
#  304 root     51048 S    /usr/bin/swupdate -v -M -m -w -r /www
#  324 root     67440 S    /usr/bin/swupdate -v -M -m -w -r /www
```

Zwei Prozesse sind normal. SWUpdate startet Schnittstellen wie den Webserver als Kindprozesse mit derselben Befehlszeile.

### Update im Browser

Im Browser `http://<Board-IP>:8080` öffnen und die `.swu` hochladen. Die Meldungen von SWUpdate erscheinen in PuTTY. Zum Erkennen den Text in `hello.txt` vorher ändern und `update-hello` neu bauen. Danach auf dem Board:

```bash
cat /home/root/hello.txt     # neuer Text
```

Andere Wege, ein Update einzuspielen:

| Option | Weg |
| --- | --- |
| `-i <datei>` | Datei auf dem Board (Abschnitt 17) |
| `-w` | Upload über den Webserver |
| `-d` | SWUpdate lädt die `.swu` selbst von einer URL |
| `-u` | Suricatta: SWUpdate fragt regelmäßig einen Update-Server ab, z. B. hawkBit |

Das Paket `swupdate-progress` verbindet sich mit dem laufenden SWUpdate und zeigt den Fortschritt an, z. B. per psplash auf einem Display. Nach einem erfolgreichen Update kann es ein Skript ausführen oder neu starten.

## 19. U-Boot-Umgebung aus Linux

U-Boot und Linux laufen nie gleichzeitig. Die einzige Stelle, über die beide Informationen austauschen, ist die U-Boot-Umgebung. SWUpdate schreibt dort den Stand eines Updates hinein und schaltet später darüber zwischen den Partitionen A und B um. Dafür muss Linux die Umgebung lesen und schreiben können.

### Wo U-Boot die Umgebung speichert

Die Startmeldung verrät den Ort:

```
Loading Environment from FAT... Unable to read "uboot.env" from mmc0:1...
```

U-Boot hat eine eingebaute Standard-Umgebung. Fehlt `uboot.env`, startet es damit ganz normal. Die Datei speichert nur Änderungen. Angelegt wird sie in U-Boot (Leertaste beim Start) mit:

```
=> saveenv
Saving Environment to FAT... OK
```

`env info` ist in diesem U-Boot nicht eingebaut. Die Größe steht am Ende von `printenv`:

```
Environment size: 9034/131068 bytes
```

131 068 Byte für Variablen plus 4 Byte CRC32 ergeben 131 072 = `0x20000`. Bei einer redundanten Umgebung käme ein Byte für einen Zähler dazu (131 067).

U-Boot kam bisher fertig aus dem Shared-State-Mirror (Abschnitt 4), lokal gibt es keine `.config`. Konfigurieren lassen und nachsehen:

```bash
bitbake -c configure u-boot
B=$(bitbake -e u-boot | sed -n 's/^B="\(.*\)"/\1/p')
grep -rE "^CONFIG_ENV_(SIZE|IS_IN_FAT|FAT_)|^CONFIG_SYS_REDUNDAND|^CONFIG_BOOTCOUNT" "$B" --include=.config
```

| Option | Wert | Bedeutung |
| --- | --- | --- |
| `CONFIG_ENV_SIZE` | `0x20000` | 128 KiB |
| `CONFIG_ENV_IS_IN_FAT` | `y` | Umgebung als Datei in einer FAT-Partition |
| `CONFIG_ENV_FAT_INTERFACE`, `CONFIG_ENV_FAT_DEVICE_AND_PART` | `"mmc"`, `"0:1"` | `mmc 0` Partition 1, fest die SD-Karte |
| `CONFIG_ENV_FAT_FILE` | `"uboot.env"` | Dateiname |
| `CONFIG_SYS_REDUNDAND_ENVIRONMENT` | nicht gesetzt | nur eine Kopie |
| `CONFIG_BOOTCOUNT_LIMIT`, `CONFIG_BOOTCOUNT_AM33XX` | `y` | Bootzähler im Register der Echtzeituhr, übersteht Neustart, aber kein Ausschalten |
| `CONFIG_BOOTCOUNT_BOOTLIMIT` | `0` | kein Grenzwert vorgegeben |

U-Boot nummeriert die Controller: `mmc 0` ist der microSD-Steckplatz (Linux `mmcblk0`), `mmc 1` das eMMC (Linux `mmcblk1`). U-Boot selbst kommt aus dem eMMC, liest seine Umgebung aber fest von der SD-Karte. Ohne Karte startet es mit der eingebauten Umgebung und kann nichts speichern. Für ein System ganz im eMMC muss U-Boot neu gebaut werden.

In Linux ist `mmc 0:1` die Partition `/dev/mmcblk0p1`, eingehängt unter `/uboot` (Abschnitt 20; mit dem Standard-Layout von `beaglebone-yocto` unter `/boot`). Die Umgebung ist also die Datei `/uboot/uboot.env`.

### fw_env.config

`libubootenv` (Bibliothek für SWUpdate, Kommandos `fw_printenv` und `fw_setenv`) liest den Ort aus `/etc/fw_env.config`. Aufbau einer Zeile:

```
<Gerät oder Datei>  <Versatz>  <Größe>  [Sektorgröße]  [Anzahl Sektoren]  [Sperre aus]
```

Sektorgröße und Anzahl gelten nur für rohen NOR- und NAND-Flash. Zwei Zeilen bedeuten eine redundante Umgebung. Hier genügt eine Zeile:

```
/uboot/uboot.env 0x0 0x20000
```

Die Größe muss genau zu `CONFIG_ENV_SIZE` passen, sonst stimmt die CRC nicht.

Das U-Boot-Rezept aus OE-Core installiert `fw_env.config` selbst, sobald die Datei in `${UNPACKDIR}` liegt (`u-boot.inc`). Sie landet im Paket `u-boot-env`, zusammen mit `/etc/u-boot-initial-env`. Ein `.bbappend` muss sie nur in `SRC_URI` aufnehmen.

`meta-bbb-swupdate/recipes-bsp/u-boot/u-boot_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://fw_env.config"
```

Die Datei liegt in `meta-bbb-swupdate/recipes-bsp/u-boot/files/fw_env.config`. `FILESEXTRAPATHS` ist nötig, weil BitBake sonst nur neben dem ursprünglichen Rezept in OE-Core sucht. Durch die Änderung passt der Shared-State-Mirror für U-Boot nicht mehr, U-Boot wird einmal lokal gebaut.

Ins Image über `meta-bbb-swupdate/recipes-core/images/bbb-image.bbappend`:

```
IMAGE_INSTALL:append = " swupdate swupdate-www u-boot-env libubootenv-bin hwrevision"
```

`libubootenv0` ist schon als Abhängigkeit von SWUpdate im Image. `fw_printenv` und `fw_setenv` stecken in `libubootenv-bin`.

### Prüfen

Image bauen, Karte beschreiben. **Nach jedem Beschreiben der Karte fehlt `uboot.env`**, weil sie nur durch `saveenv` entsteht. `fw_printenv` meldet dann nur `Cannot initialize environment`. Deshalb zuerst in U-Boot `saveenv`, dann booten.

In beide Richtungen testen:

```bash
fw_setenv test 123
reboot
```

```
=> printenv test
test=123
=> setenv test 456
=> saveenv
=> boot
```

```bash
fw_printenv test      # test=456
fw_setenv test        # ohne Wert: Variable löschen
```

### Markierungen von SWUpdate wieder einschalten

Die Notlösung `-M -m` aus Abschnitt 17 und 18 entfällt. `files/20-no-markers` löschen und `swupdate_%.bbappend` auf den Stand aus Abschnitt 16 zurücksetzen:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://hash.cfg"
```

SWUpdate schreibt dann zwei Variablen (`core/stream_interface.c`, `include/state.h`):

| Variable | Option zum Abschalten | Werte |
| --- | --- | --- |
| `recovery_status` | `-M` | `in_progress` während der Installation, gelöscht bei Erfolg, `failed` bei Fehler |
| `ustate` | `-m` | `1` installiert, `3` fehlgeschlagen; außerdem `0` OK, `2` wird getestet |

`recovery_status=in_progress` nach einem Neustart zeigt ein abgebrochenes Update an, etwa durch Stromausfall. `ustate=1` heißt: installiert, aber noch nicht bestätigt. Der Wert bleibt stehen, bis ihn jemand zurücksetzt (Thema Rückfall mit Bootzähler).

Test mit dem Update aus Abschnitt 17, ohne `-M -m`:

```bash
swupdate -v -i /tmp/update-hello-beaglebone-yocto.rootfs.swu
fw_printenv | grep -E "ustate|recovery_status"     # ustate=1
```

Die Fehler `Cannot persistently store … update state` erscheinen nicht mehr.

### Grenzen dieses Aufbaus

- Nur eine Kopie der Umgebung, dazu in einer FAT-Datei. Ein Stromausfall beim Schreiben kann sie zerstören. U-Boot fällt dann auf die eingebaute Umgebung zurück, gesetzte Variablen sind weg.
- Der Bootzähler liegt im Register der Echtzeituhr. Linux kann ihn mit `fw_setenv` nicht zurücksetzen.
- Die Umgebung hängt an der SD-Karte.

## 20. A/B-Layout

Für ein A/B-Update braucht die Karte zwei Root-Partitionen. Eine läuft, die andere wird beim Update beschrieben. U-Boot muss wissen, welche es starten soll. Das entscheidet eine Variable in der U-Boot-Umgebung, die Linux mit `fw_setenv` setzen kann (Abschnitt 19).

### Layout

| Nr. | Label | Typ | Größe | Eingehängt | Inhalt |
| --- | --- | --- | --- | --- | --- |
| 1 | `boot` | FAT, Boot-Flag | 64 MiB | `/uboot` | `MLO`, `u-boot.img`, `boot.scr`, `uboot.env` |
| 2 | `root_a` | ext4 | 256 MiB | `/` wenn A läuft | Linux A, Kernel und Device Tree in `/boot` |
| 3 | `root_b` | ext4 | 256 MiB | `/` wenn B läuft | Linux B, ebenso |
| 4 | `data` | ext4 | 128 MiB | `/data` | Daten, die ein Update überleben |

Vier primäre Partitionen sind das Maximum einer MBR-Partitionstabelle. U-Boot selbst liegt in `boot` und gehört weder zu A noch zu B. Ein Update tauscht nur das Root-Dateisystem samt Kernel.

Kernel und Device Tree müssen im Root-Dateisystem liegen. Sonst würde ein Update von B den Kernel von A weiterverwenden. Bei `beaglebone-yocto` ist das schon so: `MACHINE_ESSENTIAL_EXTRA_RDEPENDS += "kernel-image kernel-devicetree"` in der Maschinenkonfiguration bringt `/boot/zImage` und die `.dtb`-Dateien ins Image.

### wks-Datei

wic sucht `.wks`-Dateien in `<Layer>/files/wic/` (nicht `<Layer>/wic/`). `meta-bbb-swupdate/files/wic/bbb-image.wks`:

```
part /uboot --source bootimg_partition --ondisk mmcblk0 --fstype=vfat --label boot --active --align 4 --fixed-size 64 --use-uuid
part --source rootfs --ondisk mmcblk0 --fstype=ext4 --label root_a --align 4 --fixed-size 256 --use-uuid
part --source rootfs --ondisk mmcblk0 --fstype=ext4 --label root_b --align 4 --fixed-size 256 --use-uuid
part /data --ondisk mmcblk0 --fstype=ext4 --label data --align 4 --size 128 --use-uuid
```

- `bootimg_partition` kopiert die Dateien aus `IMAGE_BOOT_FILES` in die FAT-Partition.
- `--active` setzt das Boot-Flag. U-Boot sucht Bootdateien nur auf Partitionen mit diesem Flag.
- `--source rootfs` ohne Einhängepunkt: A und B bekommen dasselbe Root-Dateisystem. So startet auch B von Anfang an.
- `--fixed-size 256` statt `--size`: Beide Seiten bleiben gleich groß, auch wenn das Image wächst. Ein Update muss später in 256 MiB passen.
- `--use-uuid`: Die Partitionen sind über `PARTUUID` ansprechbar, bei MBR `<Disk-ID>-<Nr.>`, hier `076c4a2a-02` und `076c4a2a-03`.

wic trägt `/uboot` und `/data` in `/etc/fstab` ein, legt die Verzeichnisse aber nicht an. Ohne Verzeichnis hängt Linux die Partition nicht ein. Für Updates reicht das nicht. Abschnitt 21 ersetzt diese Einträge durch eine eigene `fstab`.

Warum `/uboot` und nicht `/boot`: Im Root-Dateisystem liegt der Kernel unter `/boot`. Eine dort eingehängte FAT-Partition würde ihn verdecken. Deshalb zeigt `fw_env.config` jetzt auf `/uboot/uboot.env`:

```
/uboot/uboot.env 0x0 0x20000
```

`meta-bbb-swupdate/recipes-core/images/bbb-image.bbappend`:

```
IMAGE_INSTALL:append = " swupdate swupdate-www u-boot-env libubootenv-bin hwrevision"

WKS_FILE = "bbb-image.wks"

create_directories() {
    install -d ${IMAGE_ROOTFS}/uboot
    install -d ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_directories"

IMAGE_BOOT_FILES:append = " boot.scr"
```

`ROOTFS_POSTPROCESS_COMMAND` wird ohne `;` erweitert. `IMAGE_BOOT_FILES` gehört ins Image, nicht ins U-Boot-Rezept, weil wic die Variable beim Bau des Images liest.

### Bootskript statt extlinux.conf

Bisher hat `bootimg_partition` mit `--sourceparams="loader=u-boot"` eine `extlinux.conf` erzeugt. Darin steht `root=` fest, genommen von der ersten Partition mit dem Einhängepunkt `/`. Für A/B taugt das nicht. Ein U-Boot-Skript entscheidet stattdessen beim Start.

`meta-bbb-swupdate/recipes-bsp/u-boot/files/boot.cmd`:

```
# rootpart: 2 = root_a, 3 = root_b (gesetzt von SWUpdate oder fw_setenv)

if test -z "${rootpart}"; then
    setenv rootpart 2
fi

echo "A/B: booting from ${devtype} ${devnum}:${rootpart}"

load ${devtype} ${devnum}:${rootpart} ${kernel_addr_r} /boot/zImage
load ${devtype} ${devnum}:${rootpart} ${fdt_addr_r} /boot/${fdtfile}

part uuid ${devtype} ${devnum}:${rootpart} rootuuid
setenv bootargs console=ttyS0,115200 root=PARTUUID=${rootuuid} rootwait

bootz ${kernel_addr_r} - ${fdt_addr_r}
```

Die Variablen kommen aus drei Quellen:

| Quelle | Variablen |
| --- | --- |
| eingebaute Standard-Umgebung | `kernel_addr_r`, `fdt_addr_r` |
| zur Laufzeit gesetzt | `devtype`, `devnum` (von `distro_bootcmd` beim Durchsuchen der Geräte), `fdtfile` (von `findfdt` nach der Board-Erkennung), `rootuuid` (vom Skript selbst) |
| gespeichert in `uboot.env` | `rootpart` |

- `load` erkennt das Dateisystem selbst (ext4) und folgt dem symbolischen Link `/boot/zImage`.
- `part uuid` liest die `PARTUUID` der gewählten Partition. Damit stimmt `root=` immer mit der Partition überein, von der der Kernel kam.
- `bootz <Kernel> - <Device Tree>`: Der Bindestrich steht für „keine Initramfs“.
- Fehlt `rootpart`, startet A. Nach dem Beschreiben der Karte ist die Variable nicht gesetzt.

`meta-bbb-swupdate/recipes-bsp/u-boot/u-boot_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://fw_env.config file://boot.cmd"

UBOOT_ENV = "boot"
UBOOT_ENV_SUFFIX = "scr"
```

Mit `UBOOT_ENV_SUFFIX = "scr"` übersetzt das Rezept (`u-boot.inc`) die Datei `boot.cmd` mit `mkimage -T script` in `boot.scr` und legt sie in `tmp/deploy/images/beaglebone-yocto/`. `mkimage` setzt einen 64-Byte-Kopf mit Prüfsumme davor. U-Boot führt nur Skripte mit gültigem Kopf aus. `boot.cmd` direkt auf die Karte zu kopieren, funktioniert also nicht.

### Suchreihenfolge von U-Boot

Dieses U-Boot startet über `distro_bootcmd`. Pro Gerät und Partition mit Boot-Flag sucht es in den Verzeichnissen `/` und `/boot/`:

1. `extlinux/extlinux.conf`
2. `boot.scr.uimg`, dann `boot.scr`

Eine vorhandene `extlinux.conf` gewinnt. Deshalb muss `loader=u-boot` aus der wks-Datei raus, und `root_a` verliert den Einhängepunkt `/`. Ohne `/` würde wic ohnehin kein `root=` in eine `extlinux.conf` schreiben können.

### Skript von Hand testen

Jede Zeile lässt sich vorher am U-Boot-Prompt ausprobieren. `devtype`, `devnum` und `fdtfile` sind dort leer, weil `distro_bootcmd` noch nicht gelaufen ist. Zuerst setzen:

```
=> setenv devtype mmc
=> setenv devnum 0
=> run findfdt
=> printenv fdtfile
fdtfile=am335x-boneblack.dtb
```

Danach die Zeilen aus `boot.cmd` einzeln eingeben. Ohne diese Vorbereitung meldet `load` nur `Bad device specification`.

### Prüfen

Image bauen und Karte beschreiben (Abschnitt 6). Danach fehlt `uboot.env` wieder. Deshalb zuerst in U-Boot `saveenv`, dann `boot`.

Im Bootlog:

```
Found U-Boot script /boot.scr
581 bytes read in 2 ms (283.2 KiB/s)
## Executing script at 80000000
A/B: booting from mmc 0:2
```

Steht dort `Found /extlinux/extlinux.conf`, liegt noch eine alte `extlinux.conf` auf der Karte.

Auf dem Board:

```bash
cat /proc/cmdline        # console=ttyS0,115200 root=PARTUUID=076c4a2a-02 rootwait
ls /uboot                # boot.scr, keine extlinux.conf
mount | grep -E "uboot|data"
fw_printenv rootpart     # nicht gesetzt
```

Auf B umschalten:

```bash
fw_setenv rootpart 3
reboot
```

Im Bootlog steht jetzt `A/B: booting from mmc 0:3`, in `/proc/cmdline` `root=PARTUUID=076c4a2a-03`. Auch in B sind `/uboot` und `/data` eingehängt und `fw_setenv` funktioniert. Zurück mit `fw_setenv rootpart 2` und `reboot`.

### Grenzen dieses Aufbaus

- Ein falscher Wert in `rootpart` (z. B. `4` oder ein kaputtes B) lässt den Start scheitern. Einen automatischen Rückfall gibt es noch nicht (Abschnitt 22).
- `zImage` und die `.dtb`-Dateien liegen weiterhin auch in `boot`, weil die Maschinenkonfiguration sie in `IMAGE_BOOT_FILES` aufführt. Das Skript benutzt sie nicht.
- Die Umgebung liegt weiterhin als einzelne FAT-Datei auf der SD-Karte (Abschnitt 19).

## 21. A/B-Update

Das laufende System schreibt ein neues Root-Dateisystem auf die andere Seite und stellt `rootpart` um. Nach dem Neustart läuft die neue Version. Die alte Seite bleibt unberührt.

### Versionen an einer Stelle

Zwei Werte werden in mehreren Rezepten gebraucht. Eine Variable in einem Rezept gilt nur dort. Werte für alle Rezepte gehören in eine Konfigurationsdatei, hier in `layer.conf`:

| Variable | Datei | Verwendet in |
| --- | --- | --- |
| `BBB_VERSION ?= "0.1.0"` | `meta-bbb/conf/layer.conf` | `/etc/bbb-version`, `version` in `sw-description` |
| `HW_REVISION ?= "1.0"` | `meta-bbb-swupdate/conf/layer.conf` | `/etc/hwrevision`, `hardware-compatibility` in `sw-description` |

`?=` lässt einen Testbau mit anderem Wert über `local.conf` zu. In `hwrevision.bb` entfällt die eigene Zuweisung.

`/etc/bbb-version` gehört zum Image, nicht zu SWUpdate. `meta-bbb/recipes-core/images/bbb-image.bb`:

```
add_bbb_version_to_rootfs() {
    echo "${BBB_VERSION}" > ${IMAGE_ROOTFS}${sysconfdir}/bbb-version
}
ROOTFS_POSTPROCESS_COMMAND += "add_bbb_version_to_rootfs"
```

Weil die Funktion `BBB_VERSION` benutzt, baut BitBake das Root-Dateisystem neu, sobald sich die Version ändert (`image.bbclass` macht die Funktionen in `ROOTFS_POSTPROCESS_COMMAND` zu Abhängigkeiten von `do_rootfs`). In einem Image-Rezept ist das Ziel `${IMAGE_ROOTFS}`, nicht `${D}`.

`/etc/timestamp` und `/etc/version` taugen nicht als Version. Für reproduzierbare Builds enthalten sie den festen Wert `REPRODUCIBLE_TIMESTAMP_ROOTFS` aus `bitbake.conf`, ein Datum im Jahr 2018.

### Das Update-Image

`bbb-image` muss zusätzlich ein einzelnes Root-Dateisystem liefern. `meta-bbb-swupdate/recipes-core/images/bbb-image.bbappend`, ergänzt:

```
IMAGE_FSTYPES += "ext4.gz"

# ext4 immer 256 MiB, wie auf der frischen Karte (Werte in KiB)
IMAGE_ROOTFS_SIZE = "262144"
# Bau bricht ab, wenn das Image nicht mehr in die Partition passt
IMAGE_ROOTFS_MAXSIZE = "262144"
```

Ohne `IMAGE_ROOTFS_SIZE` ist das ext4 nur so groß wie der Inhalt plus Reserve (hier 92 MiB). Nach einem Update wäre die Seite dann kleiner als nach dem Beschreiben der Karte. Leere Blöcke komprimieren gut: Die `.ext4.gz` wächst dadurch nur von 33,8 auf 34,0 MB. `IMAGE_ROOTFS_MAXSIZE` verhindert, dass ein zu großes Image beim Update über das Ende der Partition hinaus nach `data` schreibt. BitBake kennt keine Kommentare am Zeilenende, sie stehen deshalb in eigenen Zeilen.

`meta-bbb-swupdate/recipes-core/images/update-image.bb`:

```
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
```

- `IMAGE_DEPENDS` lässt `do_swuimage` warten, bis `bbb-image` fertig ist.
- Die Klasse sucht in `tmp/deploy/images/beaglebone-yocto/` nach `<Image><IMAGE_MACHINE_SUFFIX><FSTYPES>`. Seit es `IMAGE_NAME_SUFFIX = ".rootfs"` gibt, muss das `.rootfs` in `SWUPDATE_IMAGES_FSTYPES` stehen. Das Beispiel `".ext4.gz"` in der README von meta-swupdate ist veraltet und endet mit `swupdate cannot find image file`.
- Die letzte Zeile schließt eine Lücke in `swupdate.bbclass`: Ohne sie baut BitBake die `.swu` nicht neu, wenn sich nur `HW_REVISION` ändert, und packt eine veraltete `sw-description` ein. Dieselbe Zeile steht auch in `update-hello.bb`. Prüfen mit `bitbake-getvar -r update-image -f vardeps --value do_swuimage`, Ergebnis `HW_REVISION BBB_VERSION MACHINE`.

`meta-bbb-swupdate/recipes-core/images/files/sw-description`:

```
software =
{
    version = "@@BBB_VERSION@@";
    description = "Update";
    hardware-compatibility: [ "@@HW_REVISION@@" ];

    stable:
    {
        root_a:
        {
            images: (
                {
                    filename = "bbb-image-@@MACHINE@@.rootfs.ext4.gz";
                    device = "/dev/mmcblk0p2";
                    type = "raw";
                    compressed = "zlib";
                }
            );
            bootenv: (
                {
                    name = "rootpart";
                    value = "2";
                }
            );
        };
        root_b:
        {
            images: (
                {
                    filename = "bbb-image-@@MACHINE@@.rootfs.ext4.gz";
                    device = "/dev/mmcblk0p3";
                    type = "raw";
                    compressed = "zlib";
                }
            );
            bootenv: (
                {
                    name = "rootpart";
                    value = "3";
                }
            );
        };
    };
};
```

- `stable` ist die Gruppe, `root_a` und `root_b` sind die Collections. Der Name sagt, wohin geschrieben wird. `swupdate -e stable,root_b` installiert nur, was unter `stable.root_b` steht.
- `filename` muss genau dem Namen der Datei in der `.swu` entsprechen. `@@MACHINE@@` ergibt `beaglebone-yocto`.
- Ohne `compressed = "zlib"` schreibt `raw` die gz-Daten unverändert auf die Partition. Die Installation meldet Erfolg, die Seite startet aber nicht. `compressed = true` ist veraltet.
- Das Image ist nur einmal in der `.swu`, beide Collections verweisen darauf.
- `bootenv` setzt `rootpart` erst nach erfolgreichem Schreiben.

Inhalt prüfen, ohne Dateien im Verzeichnis zurückzulassen (eine alte ausgepackte Kopie führt leicht in die Irre):

```bash
cd tmp/deploy/images/beaglebone-yocto
cpio -it < update-image-beaglebone-yocto.rootfs.swu
cpio -i --to-stdout sw-description < update-image-beaglebone-yocto.rootfs.swu
```

### Bootloader-Handler einschalten

Erster Versuch:

```
ERROR parser.c : parse : 209 : bootloader support absent but sw-description has bootloader section!
```

`CONFIG_UBOOT` (Zugriff auf die Umgebung, reicht für `ustate` und `recovery_status`) und `CONFIG_BOOTLOADERHANDLER` (Handler für `bootenv` in `sw-description`) sind zwei Optionen. Die zweite ist in der defconfig aus. Fragment wie `hash.cfg` in Abschnitt 16, `meta-bbb-swupdate/recipes-support/swupdate/files/bootloaderhandler.cfg`:

```
CONFIG_BOOTLOADERHANDLER=y
```

`swupdate_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://hash.cfg file://bootloaderhandler.cfg"
```

Danach listet `swupdate -v` unter „Registered global handlers“ zusätzlich `uboot` und `bootloader`. Der Fehler kam in der ersten Phase, beim Prüfen. Es wurde nichts geschrieben.

### fstab ins Root-Dateisystem

Nach dem ersten Update startete B, aber `fw_printenv` meldete `Cannot initialize environment`. In B waren `/uboot` und `/data` nicht eingehängt.

Grund: wic ergänzt die `fstab` nur in der Kopie des Root-Dateisystems, die es für die `.wic` anlegt (Abschnitt 20). Die `.ext4.gz` entsteht ohne wic und enthält die unveränderte `fstab` aus `base-files`. Solange A und B aus der `.wic` kamen, fiel das nicht auf. **Was im Update-Image steht, muss für sich allein vollständig sein.** Alles, was erst beim Erstellen der Karte dazukommt, fehlt nach dem ersten Update.

Eigene `fstab` über `base-files`. `meta-bbb-swupdate/recipes-core/base-files/base-files_%.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
```

`file://fstab` steht schon in `SRC_URI` des Originalrezepts. `FILESEXTRAPATHS` sorgt nur dafür, dass die eigene Datei zuerst gefunden wird. `meta-bbb-swupdate/recipes-core/base-files/files/fstab` ist die Originaldatei plus zwei Zeilen:

```
/dev/mmcblk0p1       /uboot               vfat       defaults                           0  0
/dev/mmcblk0p4       /data                ext4       defaults                           0  0
```

`LABEL=boot` funktioniert hier nicht: Die alte FAT-Partition im eMMC trägt dasselbe Label, und `mount` hängte zufällig `/dev/mmcblk1p1` ein. Die festen Namen gelten nur für die SD-Karte, Schritt 11 des Plans löst das allgemein.

In der `.wks` bekommen `root_a` und `root_b` zusätzlich `--no-fstab-update`, sonst stünden die Einträge in der `.wic` doppelt:

```
part --source rootfs ... --label root_a ... --use-uuid --no-fstab-update
part --source rootfs ... --label root_b ... --use-uuid --no-fstab-update
```

Die Option fehlt in der Online-Referenz zu Kickstart, steht aber in `wic help kickstart`. Sie gehört an die Partitionen, deren `fstab` wic ändern würde, also an die mit `--source rootfs`.

Prüfen am PC, ohne die Karte zu beschreiben:

```bash
zcat bbb-image-beaglebone-yocto.rootfs.ext4.gz > /tmp/b.ext4
debugfs -R "cat /etc/fstab" /tmp/b.ext4 | tail -2
rm /tmp/b.ext4
```

### Seite automatisch wählen

Die Auswahl hängt von der laufenden Seite ab. Läuft A, muss `-e stable,root_b` gewählt werden. Die laufende Seite steht in `/proc/cmdline` (`root=PARTUUID=…-02`). `rootpart` taugt dafür nicht: Nach dem Beschreiben der Karte ist es nicht gesetzt, und nach einem Update zeigt es schon vor dem Neustart auf die neue Seite.

Eigenes Rezept `meta-bbb-swupdate/recipes-support/swupdate-ab-select/swupdate-ab-select.bb`:

```
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
```

- `allarch`: Shell-Skripte sind für alle Architekturen gleich. Die Klasse setzt auch `INHIBIT_DEFAULT_DEPS`.
- `install -d` ist nötig, weil `${D}` für jedes Rezept leer beginnt.
- `FILES`: Das Standardmuster deckt unter `${libdir}` nur `${libdir}/${BPN}/*` ab, nicht `/usr/lib/swupdate/`.
- `RDEPENDS`: Ohne SWUpdate liest niemand die `conf.d`-Datei. Die Abhängigkeit zeigt von der Erweiterung zu SWUpdate, nicht umgekehrt.

`files/updatepartdetect`, POSIX-sh, weil im Image nur BusyBox `ash` steckt:

```sh
#!/bin/sh

for arg in $(cat /proc/cmdline); do
    case "$arg" in
        root=PARTUUID=*)
            partuuid=${arg#root=PARTUUID=}
            ;;
    esac
done

case "${partuuid##*-}" in
    02) echo "stable,root_b" ;;
    03) echo "stable,root_a" ;;
    *)  echo "updatepartdetect: running partition unknown (${partuuid:-no root=PARTUUID})" >&2
        exit 1 ;;
esac
```

Das Skript gibt die Auswahl aus, statt eine Variable zu setzen. Variablen eines aufgerufenen Skripts sieht der Aufrufer nicht. Ist die Seite unbekannt, endet es mit 1, statt zu raten.

`files/30-ab-select`, eingelesen von `swupdate.sh` (Abschnitt 18):

```sh
if AB_SELECT=$(updatepartdetect); then
    SWUPDATE_ARGS="${SWUPDATE_ARGS} -e ${AB_SELECT}"
fi
```

Ohne das `if` entstünde im Fehlerfall `swupdate -v -e -w "-r /www"`, und `-e` nähme `-w` als Auswahl. So startet der Dienst ohne `-e`, und jedes Update scheitert mit „Found nothing to install“, ohne etwas zu schreiben. Kein `exit` in einer `conf.d`-Datei: Es würde `swupdate.sh` beenden.

`bbb-image.bbappend`:

```
IMAGE_INSTALL:append = " swupdate swupdate-www u-boot-env libubootenv-bin hwrevision swupdate-ab-select"
```

Prüfen:

```bash
ps | grep "[s]wupdate"
```

```
/usr/bin/swupdate -v -e stable root_b -w -r /www
```

Das fehlende Komma ist kein Fehler. SWUpdate ersetzt beim Auswerten das Komma in seinem eigenen `argv` durch ein Nullbyte (`parse_image_selector()` in `core/swupdate.c`), `ps` zeigt Nullbytes als Leerzeichen.

Von Hand:

```bash
swupdate -v -e "$(updatepartdetect)" -i /data/update-image-beaglebone-yocto.rootfs.swu
```

### Prüfen

Karte mit `BBB_VERSION = "0.1.0"` beschreiben, `saveenv`, booten. Dann zweimal hintereinander:

| Schritt | Ergebnis |
| --- | --- |
| Karte beschrieben | A läuft, `/etc/bbb-version` 0.1.0 |
| `BBB_VERSION` 0.2.0, `bitbake update-image`, Update über den Browser, `reboot` | B läuft (`…-03`), 0.2.0, `ustate=1` |
| `BBB_VERSION` 0.3.0, Update über den Browser, `reboot` | A läuft (`…-02`), 0.3.0 |

Beim zweiten Update wird `root_a` zum ersten Mal per Update beschrieben. Erst damit ist gezeigt, dass beide Collections und die Erkennung aus B stimmen und dass das laufende System nie überschrieben wird.

Im Log von SWUpdate:

```
[parse_image_selector] : Parsing selector: stable,root_b
[_parse_images] : Found compressed Image: bbb-image-beaglebone-yocto.rootfs.ext4.gz in device : /dev/mmcblk0p3 for handler raw
[_parse_bootloader] : Bootloader var: rootpart = 3
[check_hw_compatibility] : Hardware compatibility verified
[network_initializer] : Valid image found: copying to FLASH
[INFO ] : SWUPDATE successful !
```

SWUpdate startet nicht selbst neu. Die Zeilen `Lua exception … swupdate_handlers not found` sind harmlos, es gibt nur keine optionalen Handler in Lua.

### Grenzen dieses Aufbaus

- `ustate=1` bleibt nach jedem Update stehen. Niemand bestätigt, dass die neue Seite funktioniert, und es gibt keinen Rückfall (Abschnitt 22).
- `-e` wird nur beim Start des Dienstes berechnet. Ein zweites Update ohne Neustart schreibt dieselbe Seite noch einmal.
- `/dev/mmcblk0p…` steht fest in `fstab` und `sw-description`, `mmc 0` in `boot.cmd`. Für das eMMC muss das in Schritt 11 allgemein gelöst werden.

## Quellen

- [Yocto Project Quick Build (6.0)](https://docs.yoctoproject.org/6.0.3/_sources/brief-yoctoprojectqs/index.rst.txt)
- [BSP Developer’s Guide (6.0)](https://docs.yoctoproject.org/bsp-guide/bsp.html)
- [Yocto Project 6.0 „Wrynose“ – Ankündigung](https://www.yoctoproject.org/?p=102509)
- [CNX Software zu Yocto 6.0](https://www.cnx-software.com/2026/05/14/yocto-project-6-0-wrynose-released-with-linux-6-18-lts/)
- [SWUpdate-Dokumentation](https://sbabic.github.io/swupdate/)
- [meta-swupdate](https://github.com/sbabic/meta-swupdate)
