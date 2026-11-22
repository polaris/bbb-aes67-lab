# Plan: SWUpdate auf dem BeagleBone Black

Ziel: Das Board bekommt neue Images über das Netzwerk statt über eine neu beschriebene SD-Karte. Am Ende liegt ein A/B-System im eMMC. Ein fehlerhaftes Update fällt automatisch auf die alte Version zurück.

Der Weg führt über die SD-Karte. Dort kann nichts kaputtgehen, was sich nicht mit einer frisch beschriebenen Karte beheben lässt. Erst wenn alles läuft, wandert das System ins eMMC.

## Spielregeln

- Arbeit im Git-Branch `swupdate`. Der Stand auf `master` mit PTP bleibt lauffähig.
- Eigener Layer `meta-bbb-swupdate` neben `meta-bbb`. So bleibt sichtbar, was nur für SWUpdate nötig ist.
- Das Image heißt `bbb-image` und liegt in `meta-bbb`. Alles, was nur SWUpdate braucht (Pakete, `IMAGE_FEATURES`), kommt über `meta-bbb-swupdate/recipes-core/images/bbb-image.bbappend` dazu. `conf/local.inc` enthält nur Einstellungen für den Build-Rechner und die Entwicklung.
- Jeder Schritt endet mit „Prüfen“. Erst weitergehen, wenn die Prüfung klappt.
- Jeder Schritt hat Lernfragen. Beantworte sie schriftlich in eigenen Worten, bevor du weitergehst. Kannst du eine nicht beantworten, ist das der Hinweis, wo du nachlesen solltest.
- Nach jedem Schritt das Ergebnis in `docs/anleitung.md` übernehmen (siehe letzter Abschnitt). Nicht alles erst am Ende.
- Rettungsweg immer bereithalten: eine SD-Karte mit dem bisherigen Image, deren Boot-Partition `MLO` und `u-boot.img` enthält. Damit startet das Board mit **S2** auch dann, wenn das U-Boot im eMMC kaputt ist.
- Gelesen wird schrittweise. Jeder Schritt nennt unter „Lesen“ nur die Kapitel, die du dafür brauchst. Lies sie vor den Aufgaben. Gemeint ist die SWUpdate-Dokumentation unter sbabic.github.io/swupdate, sonst ist die Quelle angegeben. Weichen die Kapitelnamen in deiner Version ab, im Inhaltsverzeichnis nach dem Stichwort suchen.

## Schritt 1: Layer einbinden, SWUpdate ins Image

Lesen:
- Einleitung „SWUpdate: software update for embedded system“, nur den Überblick bis zur Liste der Funktionen.
- „meta-SWUpdate: building with Yocto“.
- Im Kapitel zum Bauen den Teil zur Konfiguration (Kconfig, `menuconfig`).

Aufgaben:
1. Branch `swupdate` anlegen.
2. `meta-swupdate` (Branch `wrynose`) nach `../layers/` klonen und einbinden. Abhängigkeiten in `meta-swupdate/conf/layer.conf` nachsehen (`LAYERDEPENDS`) und fehlende Layer ergänzen. `meta-oe` ist schon da.
3. Layer `meta-bbb-swupdate` mit `bitbake-layers create-layer` im Repo anlegen, per symbolischem Link nach `../layers/` holen (wie `meta-bbb`) und einbinden. `LAYERDEPENDS` auf `core meta-bbb swupdate` setzen.
4. Eigenes Image `bbb-image.bb` in `meta-bbb` anlegen (auf Basis von `core-image-minimal`, mit `ethtool` und `linuxptp`). `IMAGE_INSTALL` aus `conf/local.inc` entfernen. In `meta-bbb` `LAYERDEPENDS` um `openembedded-layer` ergänzen.
5. `swupdate` über `bbb-image.bbappend` in `meta-bbb-swupdate` ins Image aufnehmen. Mit `bitbake -e bbb-image | grep ^IMAGE_INSTALL=` prüfen, dann `bitbake bbb-image`. Karte beschreiben (Dateiname jetzt `bbb-image-beaglebone-yocto.rootfs.wic.zst`), booten.
6. Nachsehen, wie SWUpdate konfiguriert ist: `bitbake -c menuconfig swupdate`. Merken, welche Handler aktiv sind. Die Konfiguration später über eine eigene `defconfig` im `.bbappend` festlegen, nicht nur im Menü.

Prüfen: Auf dem Board läuft `swupdate -h`. Die Liste der Handler steht in der Ausgabe von `swupdate -v -i /dev/null` oder in den Startmeldungen.

Lernfragen:
1. Wo landet die SWUpdate-Konfiguration im Build, und wie überschreibst du sie dauerhaft?
2. Welche Pakete hat `meta-swupdate` zusätzlich ins Image gezogen und warum?

## Schritt 2: Das erste Update – nur eine Datei

Noch keine Partitionen. Ein Update, das eine einzige Datei installiert, zeigt das `.swu`-Format ohne Risiko.

Lesen:
- Kapitel zur Syntax von `sw-description` (Default-Parser): Aufbau, Abschnitte `images` und `files`, `hardware-compatibility`. Collections und `bootenv` noch überspringen.
- „Handlers“: nur die Einleitung und die Übersicht, welche Handler es gibt.
- In „meta-SWUpdate“ den Teil zur Klasse `swupdate` und wie sie die `.swu` baut.

Aufgaben:
1. In `meta-bbb-swupdate` ein Rezept `update-hello.bb` anlegen, das `inherit swupdate` nutzt und eine `sw-description` mit einem `files`-Eintrag enthält. Die Datei `hello.txt` soll nach `/home/root/hello.txt`.
2. `bitbake update-hello` und die `.swu` unter `tmp/deploy/images/beaglebone-yocto/` suchen.
3. Mit `cpio -it < update-hello-*.swu` den Inhalt ansehen.
4. Per `scp` aufs Board kopieren (Dropbear ist im Image) und mit `swupdate -v -i /tmp/update-hello.swu` installieren.
5. Danach mit einem `sha256`-Fehler in `sw-description` absichtlich ein kaputtes Update bauen und die Fehlermeldung lesen.

Prüfen: `hello.txt` liegt auf dem Board. Das kaputte Update wird abgelehnt, die Datei bleibt unverändert.

Lernfragen:
1. Wie ist eine `.swu`-Datei aufgebaut, und warum muss `sw-description` darin an erster Stelle stehen?
2. Was macht ein Handler? Nenne drei Handler und wofür man sie nimmt.
3. Was erzeugt die Klasse `swupdate` automatisch in `sw-description` (z. B. Prüfsummen)?
4. Was steht in den Feldern `name`, `version` und `hardware-compatibility`, und was passiert, wenn `hardware-compatibility` nicht passt?

## Schritt 3: Updates über das Netzwerk

Lesen:
- Kapitel zum Starten von SWUpdate: Kommandozeilen-Optionen, besonders `-w` für den Webserver.
- Den Abschnitt zum Webserver (Mongoose).
- Suricatta nur überfliegen, um zu wissen, dass es den Weg gibt.

Aufgaben:
1. `swupdate-www` über `bbb-image.bbappend` ins Image aufnehmen. Den Dienst so starten, dass der Webserver auf Port 8080 läuft.
2. Im Browser am PC `http://<Board-IP>:8080` öffnen und `update-hello.swu` hochladen.
3. Herausfinden, wie der Dienst gestartet wird (Init-Skript oder systemd-Unit) und wo die Startoptionen stehen.

Prüfen: Das Update läuft über den Browser, die Fortschrittsanzeige erreicht 100 %, die Datei liegt auf dem Board.

Lernfragen:
1. Welche Startoption aktiviert den Webserver, und welche weiteren Wege gibt es, ein Update einzuspielen (Stichworte: `-d` Download, Suricatta/hawkBit)?
2. Was ist `swupdate-progress` und wofür wäre es nützlich?

## Schritt 4: U-Boot-Umgebung aus Linux lesen und schreiben

SWUpdate schaltet beim A/B-Update die Bootpartition über eine Variable in der U-Boot-Umgebung um. Dafür muss Linux wissen, wo U-Boot sie speichert.

Lesen:
- „Bootloader Interface“, den Teil zu U-Boot.
- README von `libubootenv` (github.com/sbabic/libubootenv): Aufbau von `fw_env.config`.
- U-Boot-Dokumentation (docs.u-boot.org): Kapitel „Environment Variables“, dort die Abschnitte zum Speicherort.

Aufgaben:
1. In U-Boot (Leertaste beim Start) `env info` und `printenv` ausführen. Einmal `saveenv` ausführen und notieren, wohin gespeichert wird (FAT-Datei oder Rohbereich im MMC, welches Gerät). Mit dem neuen U-Boot ist `saveenv` erlaubt, die Warnung in Abschnitt 9 der Anleitung gilt nur für das alte.
2. Passende `/etc/fw_env.config` schreiben und über ein `.bbappend` für `libubootenv` ins Image bringen.
3. Auf dem Board `fw_printenv` und `fw_setenv test 123` ausführen, neu starten und in U-Boot `printenv test` prüfen.

Prüfen: Eine Variable, die Linux setzt, ist in U-Boot sichtbar und umgekehrt.

Lernfragen:
1. Wozu braucht SWUpdate Zugriff auf die U-Boot-Umgebung, und welche Bibliothek nutzt es dafür?
2. Was passiert, wenn `fw_env.config` auf die falsche Stelle zeigt? Warum ist das gefährlich?
3. Warum speichert man die Umgebung oft doppelt (redundante Umgebung)?

## Schritt 5: A/B-Layout auf der SD-Karte

Ziel-Layout (gilt später genauso im eMMC):

| Partition | Inhalt | Ändert sich beim Update? |
| --- | --- | --- |
| 1 `boot` (FAT) | `MLO`, `u-boot.img`, `boot.scr`, ggf. `uboot.env` (siehe Schritt 4) | nein |
| 2 `rootfsA` (ext4) | Linux A mit Kernel und Device Tree in `/boot` | ja, wenn B läuft |
| 3 `rootfsB` (ext4) | Linux B, ebenso | ja, wenn A läuft |
| 4 `data` (ext4) | Daten, die ein Update überleben | nein |

Die Boot-Partition gehört weder zu A noch zu B. SWUpdate tauscht nur Kernel und Root-Dateisystem, nicht das U-Boot. Ein kaputtes U-Boot würde weder A noch B starten. Dagegen hilft nur der Rettungsweg mit S2 und SD-Karte.

Lesen:
- Kapitel zu Update-Strategien („Software Management on embedded systems“ bzw. „Update strategy examples“): single copy und double copy.
- Yocto-Dokumentation, „OpenEmbedded Kickstart (.wks) Reference“.
- U-Boot-Dokumentation: „Standard Boot“ (bootstd), dort die Bootmethoden `extlinux` und `script` und ihre Reihenfolge.

Aufgaben:
1. Eigene `.wks`-Datei im Layer anlegen: Boot-Partition (FAT, mit `MLO` und `u-boot.img` als Rettungsweg), `rootfsA`, `rootfsB`, `data`. Mit `WKS_FILE` aktivieren.
2. Kernel und Device Tree in das Root-Dateisystem legen (`/boot` im rootfs), damit ein Update von rootfs auch den Kernel mitnimmt.
3. Statt `extlinux.conf` ein U-Boot-Bootskript `boot.scr` erzeugen. Es liest eine Variable (z. B. `rootpart`), lädt Kernel und Device Tree von dieser Partition und setzt `root=` passend. Klären, in welcher Reihenfolge U-Boot `extlinux.conf` und `boot.scr` sucht, und sicherstellen, dass das Skript gefunden wird.
4. `data` als `/data` einhängen. Hier landen später Dinge, die ein Update überleben sollen (z. B. `ptp4l`-Konfiguration).

Prüfen: Bootet mit `rootpart=2`. Nach `fw_setenv rootpart 3` und Neustart läuft das System von B. `cat /proc/cmdline` und `mount` zeigen es.

Lernfragen:
1. Was ist der Unterschied zwischen „single copy“ (mit Rescue-System) und „double copy“ (A/B)? Welche Vor- und Nachteile hat jede Variante bei 4 GB eMMC?
2. Warum gehört der Kernel ins rootfs und nicht in die gemeinsame Boot-Partition?
3. Was liegt in `/data`, und was darf dort nicht liegen?

## Schritt 6: Echtes A/B-Update

Lesen:
- In der Syntax von `sw-description` jetzt die übersprungenen Teile: Collections und Auswahl mit `-e`, Abschnitt `bootenv`, Verweise mit `ref`.
- Handler `raw` (bzw. Image-Handler für Partitionen) im Kapitel „Handlers“.
- Abschnitt zur Update-Transaktion und zur Variable `recovery_status` bzw. `ustate`.
- In „meta-SWUpdate“ die Variablen `SWUPDATE_IMAGES` und `SWUPDATE_IMAGES_FSTYPES`.

Aufgaben:
1. Rezept `update-image.bb` mit `inherit swupdate`. `SWUPDATE_IMAGES` enthält `bbb-image` als `.ext4.gz`.
2. `sw-description` mit zwei Collections `copy1` und `copy2`. Jede schreibt das Image auf die jeweils andere Partition und setzt im Abschnitt `bootenv` die Variable `rootpart`.
3. Kleines Skript auf dem Board, das aus `/proc/cmdline` die laufende Partition ermittelt und `swupdate` mit dem richtigen `-e` aufruft. Für den Webserver das gleiche über die Startoptionen des Dienstes lösen.
4. Eine sichtbare Versionsangabe ins Image bringen, z. B. eine Datei `/etc/bbb-version` mit Build-Datum.
5. Die Hardware-Revision nur an einer Stelle festlegen: `HW_REVISION` aus `hwrevision.bb` nach `meta-bbb-swupdate/conf/layer.conf` verschieben, damit alle Rezepte sie sehen. In `sw-description` von `update-hello` und `update-image` `hardware-compatibility: [ "@@HW_REVISION@@" ];` eintragen. In der ausgepackten `.swu` prüfen, dass dort `1.0` steht.
6. Update einspielen, neu starten, Version prüfen. Danach zurück auf die andere Seite.

Prüfen: Zweimal hintereinander ein Update. Das Board wechselt A → B → A, die Version steigt jedes Mal. Das laufende System wird nie überschrieben.

Lernfragen:
1. Was sind „software collections“ und was bewirkt `swupdate -e stable,copy2`?
2. Was passiert, wenn während des Schreibens der Strom ausfällt? Probiere es aus.
3. Warum setzt SWUpdate die Umgebungsvariablen erst am Ende des Updates?
4. Was verhindert, dass ein halb geschriebenes Update gebootet wird?

## Schritt 7: Automatischer Rückfall (Bootzähler)

Lesen:
- U-Boot-Dokumentation: „Boot Count Limit“ (bootcount, `bootlimit`, `altbootcmd`).
- „Bootloader Interface“ noch einmal, den Teil zu `upgrade_available` und `ustate`.
- Kernel-Dokumentation zum Watchdog (`Documentation/watchdog/watchdog-api.rst`), nur den Anfang bis zur „magic close“-Funktion.

Aufgaben:
1. Prüfen, ob das U-Boot einen Bootzähler hat (`CONFIG_BOOTCOUNT_LIMIT`, Speicherort `CONFIG_BOOTCOUNT_ENV`). Falls nicht: Konfigurations-Fragment für U-Boot im Layer, neu bauen, `MLO` und `u-boot.img` wie in Abschnitt 10 der Anleitung ins eMMC kopieren. Vorher prüfen, dass der Rettungsweg mit S2 funktioniert.
2. `bootlimit`, `upgrade_available` und `altbootcmd` so setzen, dass nach drei misslungenen Starts die alte Partition bootet.
3. Nach einem erfolgreichen Start bestätigt ein Dienst auf dem Board das Update (`upgrade_available=0`, `bootcount=0`). Überlegen, was „erfolgreich“ heißt, z. B. `ptp4l` erreicht `SLAVE`.
4. Absichtlich ein kaputtes Update bauen (z. B. Kernel mit `init=/bin/false`) und einspielen.

Prüfen: Das kaputte Update startet nicht, nach dem Bootlimit läuft wieder die alte Version. Ein gutes Update wird bestätigt und bleibt.

Lernfragen:
1. Wer zählt beim Start hoch, und wer setzt zurück?
2. Warum muss der Watchdog aktiv sein, damit das auch bei einem hängenden Kernel funktioniert?

## Schritt 8: Update-System mit USB-Stick (single copy)

Ergänzt A/B um ein kleines Linux mit SWUpdate, das als initramfs aus dem RAM läuft. Es ist dieselbe Technik wie bei einem reinen „single copy“-Aufbau, bei dem jedes Update über dieses System läuft. Hier ist es der Ausnahmeweg: Normale Updates schreibt weiter das laufende System in die andere Partition. Das Update-System wird gebraucht, wenn A und B beide nicht starten, kein Netzwerk da ist oder ein Werksreset gewünscht ist.

Kernel, Device Tree und initramfs liegen in der Boot-Partition, die kein Update verändert. U-Boot startet das Update-System statt A oder B, wenn ein Auslöser vorliegt. Erst angehen, wenn Schritt 5 bis 7 laufen, weil Bootskript, U-Boot-Umgebung und `recovery_status` gebraucht werden.

Lesen:
- In der Übersicht „Single copy – running as standalone image“ und „Double copy with fall-back“ vergleichen.
- In `meta-swupdate` das Rezept `recipes-extended/images/swupdate-image.bb` mit `swupdate-image.inc`.
- U-Boot-Dokumentation: Befehle `usb` und `bootz` (Aufruf mit initrd: `bootz <kernel> <initrd>:<größe> <fdt>`).
- In `swupdate.inc` die Pakete `swupdate-usb` und `swupdate-client` (udev-Regel für USB-Sticks).

Aufgaben:
1. `swupdate-image` bauen. Format und Größe des Ergebnisses prüfen. Klären, ob das Update-System einen eigenen Kernel braucht oder denselben `zImage` nutzen kann.
2. Kernel, Device Tree und initramfs für das Update-System in die Boot-Partition bringen (`IMAGE_BOOT_FILES` bzw. `.wks`). Prüfen, ob die Boot-Partition groß genug ist.
3. Bootskript erweitern: Bei einem Auslöser das Update-System laden und mit `bootz` samt initrd starten. Auslöser:
   - Variable `rescue=1`, gesetzt aus Linux mit `fw_setenv` (z. B. für einen Werksreset)
   - USB-Stick mit einer Datei `update.swu` (in U-Boot `usb start` und `test -e usb 0:1 update.swu`)
   - `recovery_status=in_progress`, also ein abgebrochenes Update
4. Im Update-System den Stick einhängen und `update.swu` installieren, automatisch über ein Skript oder die udev-Regel von `swupdate-usb`. Danach die Auslöser zurücksetzen und neu starten.
5. `sw-description` um eine Variante für das Update-System ergänzen, die **A und B** schreibt und `rootpart` auf A setzt. Danach sind beide Seiten gleich und gültig, wie nach einem Werksreset. Würde nur A geschrieben, bliebe ein kaputtes B zurück, und der Rückfall aus Schritt 7 würde später auf dieses B führen.
6. A und B absichtlich zerstören (z. B. das erste MB mit `dd if=/dev/zero` überschreiben) und das Board nur mit dem USB-Stick wiederherstellen.

Prüfen: Mit zerstörtem A und B startet das Board mit Stick ins Update-System, installiert das Update und startet danach normal aus A. Nach `fw_setenv rootpart 3` startet es auch aus B. Ohne Stick und ohne Auslöser startet es wie bisher A oder B.

Lernfragen:
1. Warum läuft das Update-System aus dem RAM und nicht von einer eigenen Partition?
2. Was schützt das Update-System selbst davor, kaputtzugehen?
3. Wann nimmt man „single copy“ als Regelweg, wann A/B, und warum kombiniert man beides?
4. Woran erkennt U-Boot ein abgebrochenes Update, und was sollte es dann tun?
5. Warum schreibt das Update-System A und B, das normale Update aber nur die jeweils andere Seite?

## Schritt 9: Schreibgeschütztes Root-Dateisystem mit Overlay für /etc

Bei einem A/B-System soll das laufende Root-Dateisystem unverändert bleiben. Sonst gehen Änderungen beim Wechsel auf die andere Seite verloren, oder A und B unterscheiden sich unbemerkt. Erst angehen, wenn Schritt 6 und 7 stabil laufen.

Lesen:
- Yocto-Dokumentation, Development Tasks Manual: „Creating a Read-Only Root Filesystem“.
- Yocto-Dokumentation, Reference Manual: Klassen `overlayfs` und `overlayfs-etc`.
- Kernel-Dokumentation `Documentation/filesystems/overlayfs.rst`: Abschnitte zu upper/lower und „Changes to underlying filesystems“.

Aufgaben:
1. `read-only-rootfs` in `bbb-image.bbappend` zu `IMAGE_FEATURES` hinzufügen. Booten und notieren, was nicht mehr geht: Dienste, die nach `/etc` oder `/var` schreiben wollen, SSH-Hostschlüssel, `fw_setenv` (Sperrdatei), SWUpdate selbst.
2. `overlayfs-etc` ebenfalls dort zu `IMAGE_FEATURES` hinzufügen, sodass `/etc` als Overlay auf der `data`-Partition liegt. Die Variablen `OVERLAYFS_ETC_*` in der Klasse `overlayfs-etc` von OE-Core nachlesen und setzen.
3. Prüfen, ob die Bestätigung aus Schritt 7 noch funktioniert. Sie schreibt in die U-Boot-Umgebung, nicht ins Root-Dateisystem.
4. Die typische Falle selbst erleben: Auf dem Board `/etc/ptp4l.conf` ändern. Dann ein Update mit einer neuen `ptp4l.conf` einspielen. Ergebnis: Die geänderte Datei im Overlay verdeckt die neue aus dem Update.
5. Eine Strategie dafür festlegen und umsetzen, z. B. Gerätekonfiguration nicht in `/etc`, sondern nach `/data/config`, oder ein Post-Install-Skript in `sw-description`, das bestimmte Dateien aus dem Overlay entfernt.

Prüfen: `touch /usr/test` scheitert mit „Read-only file system“. `mount` zeigt ein Overlay auf `/etc`. Eine Änderung in `/etc` überlebt Neustart und Wechsel von A nach B. Der SSH-Hostschlüssel bleibt nach einem Neustart gleich.

Lernfragen:
1. Was liegt im `lowerdir`, im `upperdir` und im `workdir`?
2. Warum verdeckt eine geänderte Datei im Overlay die neue Version aus dem Update, und welche Strategien gibt es dagegen?
3. Wann reicht ein Overlay auf `/etc` nicht aus? Was würde dm-verity zusätzlich leisten?

## Schritt 10: Signierte Updates

Lesen:
- „Update images from verified source“.
- In „meta-SWUpdate“ den Teil zum Signieren (`SWUPDATE_SIGNING`).

Aufgaben:
1. RSA-Schlüsselpaar erzeugen. Privaten Schlüssel nicht ins Repo legen (`.gitignore`).
2. `SWUPDATE_SIGNING` und den Schlüssel im Build setzen, `CONFIG_SIGNED_IMAGES` in der SWUpdate-Konfiguration aktivieren, öffentlichen Schlüssel ins Image bringen und SWUpdate mit `-k` starten.
3. Ein unsigniertes und ein mit falschem Schlüssel signiertes Update versuchen.

Prüfen: Nur das richtig signierte Update wird installiert.

Lernfragen:
1. Was genau wird signiert: die ganze `.swu` oder nur `sw-description`? Warum reicht das?
2. Wie würdest du einen Schlüssel austauschen, ohne Geräte im Feld zu verlieren?

## Schritt 11: Umzug ins eMMC

Erst wenn Schritt 1 bis 10 auf der SD-Karte laufen.

Lesen:
- Deine eigenen Abschnitte 19 bis 25 in `docs/anleitung.md` noch einmal durchgehen und alle Stellen markieren, an denen `mmcblk0` oder `mmc 0` fest steht.
- U-Boot-Dokumentation: „Environment Variables“, dort Speicherort im MMC (`CONFIG_ENV_IS_IN_MMC`, `CONFIG_ENV_OFFSET`, `CONFIG_ENV_OFFSET_REDUND`, `CONFIG_SYS_MMC_ENV_PART`) und `CONFIG_ENV_WRITEABLE_LIST`.
- README von `libubootenv`: Verhalten bei ungültiger Umgebung und `/etc/u-boot-initial-env`.
- Hilfe von `mkenvimage` (`mkenvimage -h`, aus `u-boot-tools-native`).

Aufgaben:
1. Größe des eMMC prüfen (`cat /proc/partitions`, 3,66 GiB). Partitionsgrößen in der `.wks` anpassen.
2. Gerätenamen unterscheiden: SD-Karte `mmcblk0` / U-Boot `mmc 0`, eMMC `mmcblk1` / U-Boot `mmc 1`. Bootskript, `fw_env.config`, `sw-description`, `/etc/fstab` und das Gerät für das `/etc`-Overlay so schreiben, dass sie das Gerät nicht fest eintragen, oder ein eigenes Image für das eMMC bauen.
   - Labels (`LABEL=boot`) helfen nicht: Stecken SD-Karte und eMMC mit demselben Layout, gibt es jedes Label zweimal, und es wird zufällig eine der beiden Partitionen genommen. Schon in Schritt 6 hängte `LABEL=boot` statt der SD-Karte die alte FAT-Partition im eMMC ein.
   - Stattdessen das Gerät aus dem laufenden System ableiten: Aus `root=PARTUUID=…` in `/proc/cmdline` das Gerät von `/` bestimmen (z. B. über `/dev/disk/by-partuuid/` oder `blkid`) und Partition 1 (`/uboot`) und 4 (`/data`) auf **demselben Gerät** verwenden. Ein Weg: Ein frühes Init-Skript oder eine udev-Regel legt feste Verweise an, z. B. `/dev/bbb/boot`, `/dev/bbb/root_a`, `/dev/bbb/root_b`, `/dev/bbb/data`. `fstab`, `fw_env.config` und `sw-description` benutzen nur noch diese Namen und gelten so für SD-Karte und eMMC.
3. **Umgebung roh und redundant ins eMMC:** U-Boot per Konfigurations-Fragment von `CONFIG_ENV_IS_IN_FAT` auf `CONFIG_ENV_IS_IN_MMC` umstellen, mit zwei Kopien (`CONFIG_SYS_REDUNDAND_ENVIRONMENT`). Ort festlegen: die Boot-Bereiche des eMMC (`mmcblk1boot0`/`boot1`) oder ein freier Bereich vor der ersten Partition. Darauf achten, dass weder `MLO` noch Partitionen überschrieben werden. `fw_env.config` auf zwei Zeilen mit Gerät und Versatz umstellen. Die FAT-Partition muss Linux danach nicht mehr einhängen.
4. **Erste Umgebung beim Bauen erzeugen:** Mit `mkenvimage` aus `u-boot-initial-env` (erzeugt der U-Boot-Build aus der einkompilierten Umgebung) plus `rootpart=2` eine gültige Umgebung bauen und an die richtige Stelle ins Image bringen. Ziel: Nach dem Beschreiben ist kein `saveenv` mehr nötig.
5. **Ohne gespeicherte Umgebung sicher starten:** Umgebung absichtlich löschen (beide Kopien mit `dd if=/dev/zero`). U-Boot muss mit der eingebauten Umgebung A starten, und das erste `fw_setenv` in Linux muss eine gültige Umgebung anlegen.
6. **Gespeicherte Umgebung einschränken:** Mit `CONFIG_ENV_WRITEABLE_LIST` nur die Variablen aus dem Speicher übernehmen, die Linux setzen darf (`rootpart`, `ustate`, `recovery_status`, Bootzähler, `rescue`). Testen, dass ein von Linux gesetztes `bootargs` wirkungslos bleibt.
7. Von der SD-Karte booten, das `.wic` per `scp` aufs Board kopieren und mit `bmaptool` oder `dd` auf `/dev/mmcblk1` schreiben. Dabei werden auch `MLO` und `u-boot.img` im eMMC ersetzt. Vorher sicherstellen, dass die neue Boot-Partition sie enthält.
8. Das Update-System aus Schritt 8 liegt mit in der Boot-Partition des eMMC. Prüfen, dass U-Boot den USB-Stick auch ohne SD-Karte findet.
9. SD-Karte entfernen und starten.

Prüfen: Board startet ohne Karte aus dem eMMC, ohne dass jemals `saveenv` ausgeführt wurde. Ein A/B-Update über den Browser klappt, der Rückfall aus Schritt 7 klappt, die Rettung per USB-Stick aus Schritt 8 klappt. Nach Löschen der Umgebung startet das Board weiter aus A.

Lernfragen:
1. In welcher Reihenfolge sucht U-Boot jetzt nach Bootmedien, und was passiert, wenn eine alte SD-Karte steckt?
2. Wie würdest du ein Gerät ohne Karte und ohne Netzwerk retten?
3. Warum gehören MAC-Adresse und Seriennummer nicht in die U-Boot-Umgebung?
4. Was könnte ein Angreifer mit Zugriff auf `fw_setenv` ohne `CONFIG_ENV_WRITEABLE_LIST` erreichen?
5. Warum muss `u-boot-initial-env` aus demselben U-Boot-Build stammen wie der Bootloader?

## Schritt 12 (optional): Weiterführend

- Pre- und Post-Install-Skripte (`scripts` in `sw-description`), z. B. Konfiguration nach `/data` migrieren.
- hawkBit-Server in Docker und SWUpdate im Suricatta-Modus: Das Board holt Updates selbst ab.
- Delta-Updates (`delta`-Handler) und Vergleich der Größe.
- Verschlüsselte Images.
- dm-verity: Das Root-Dateisystem wird beim Lesen gegen eine signierte Prüfsumme geprüft. Passt zu Schritt 10.

## Übernahme in die Anleitung

Nach jedem Schritt einen Abschnitt in `docs/anleitung.md` ergänzen, fortlaufend ab Abschnitt 16. Stil wie bisher: kurze Sätze, Befehle in Codeblöcken, gemessene Werte und Stolperstellen festhalten. Was nur dem Lernen dient (Lernfragen, Fehlversuche ohne Erkenntnis), bleibt hier.

| Schritt | Abschnitt in der Anleitung |
| --- | --- |
| 1 | 16. SWUpdate einbinden |
| 2 | 17. Erstes Update mit einer Datei |
| 3 | 18. Updates über den Browser |
| 4 | 19. U-Boot-Umgebung aus Linux |
| 5 | 20. A/B-Layout |
| 6 | 21. A/B-Update |
| 7 | 22. Rückfall mit Bootzähler |
| 8 | 23. Update-System mit USB-Stick |
| 9 | 24. Schreibgeschütztes Root-Dateisystem mit Overlay |
| 10 | 25. Signierte Updates |
| 11 | 26. Umzug ins eMMC |

Nach Schritt 11 außerdem Abschnitt 7 anpassen (Booten ohne Karte) und das Ziel oben in der Anleitung ergänzen.
