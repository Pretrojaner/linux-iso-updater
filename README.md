# Linux ISO Auto-Updater & Ventoy Sync Tool (v2.6.0)

**Autor:** Ingo  
**Repository:** [Pretrojaner/linux-iso-updater](https://github.com/Pretrojaner/linux-iso-updater)  
**Version:** `2.6.0`

Ein PowerShell- und Python-basiertes All-in-One Automatisierungswerkzeug zum Herunterladen, Aktualisieren und Verifizieren von Linux-, Server-, BSD-, Windows-PE- und Rescue-ISOs sowie zur automatischen Synchronisation und Theme-Einrichtung auf bootfähigen Ventoy-USB-Laufwerken.

> [!IMPORTANT]
> **Wichtiger Hinweis zu Speicherort & benötigtem Speicherplatz:**
> - **Speicherort:** Alle ISO- und Boot-Image-Dateien werden standardmäßig direkt im **selben Verzeichnis abgelegt, in dem sich die Skripte befinden** (strukturiert in Unterordnern von `01_Desktop-Linux` bis `06_Windows-PE_Rescue`).
> - **Speicherplatzbedarf:** Platziere das Skriptpaket daher unbedingt auf einem Laufwerk mit ausreichend freiem Speicherplatz! Für den vollständigen Download aller 80 vorkonfigurierten Distributionen werden ca. **235 GB** freier Speicherplatz empfohlen.
> - **Flexible Auswahl:** Beim Start öffnet sich automatisch das interaktive Auswahlmenü. Du kannst mit `[ENTER]` direkt alle Distros laden (`all`) oder gezielt einzelne Gruppen (z. B. `G1, G4, G6`) bzw. Nummern auswählen, um nur die gewünschten Systeme zu beziehen und Speicherplatz zu sparen.

---

## 🚀 Funktionen

- **Versions- & Release-Scraping:** Prüft online automatisch die neuesten Releases für 80 Linux-Distributionen, Enterprise-Server, Rettungssysteme, BSD-Derivate und Windows-PE-Notfallumgebungen.
- **Interaktive Distributions-Auswahl (`-SelectDistros`):**
  - Übersichtliche Darstellung in 6 Gruppen (`G1` bis `G6`).
  - Mehrfachauswahl via Ziffern (`1, 3, 5-8`), Gruppen (`G1, G4, G6`) oder `all`.
  - Bei Neu- oder Umkonfiguration werden abgewählte ISOs auf Wunsch lokal und auf dem Ventoy-Laufwerk bereinigt.
- **Multi-Format Boot-Support:**
  - Unterstützt standardmäßige Boot-Images im Format `.iso` sowie `.img` (z. B. ShredOS Disk Sanitizer).
- **Integritätsprüfung:**
  - Berechnet und verifiziert automatisch SHA256-, SHA512- und MD5-Prüfsummen direkt nach dem Download.
  - Erkennt dateispezifische Hashes auch in Multi-File-Prüfsummendateien präzise.
  - Überspringt bereits vorhandene, aktuelle ISOs für blitzschnelle Durchläufe.
- **Automatische Ventoy-Installation (`-InstallVentoy`):**
  - Installiert oder aktualisiert Ventoy direkt per Kommandozeile (CLI) ohne grafische Dialoge (GUI).
  - Erkennt Ventoy lokal oder installiert es vollautomatisch via Windows Package Manager (`winget`) bzw. direkt von GitHub Releases.
  - Sichere Laufwerksauswahl mit Bestätigungsabfrage vor dem Formatieren (`/I` mit GPT und NTFS).
  - Erkennt vorhandene Ventoy-Sticks und bietet zerstörungsfreie Bootcode-Aktualisierungen (`/U`) unter Beibehaltung aller vorhandenen Dateien an.
- **Ventoy Themes (7 Styles zur Auswahl & `-ChangeTheme`):**
  - Generiert automatisch hochauflösende 1080p RGB-Hintergründe und Menügrafiken.
  - **7 Themes enthalten:**
    1. `moderndark` – Modern Dark (Slate Blue & Cyan Accent) [Standard]
    2. `matrix` – Matrix Hacker Terminal (Nerdig, tiefschwarz & leuchtendes Phosphorgruen)
    3. `cybertech` – Cyber Tech & Network (Deep Navy & Electric Blue Infrastruktur)
    4. `tuxamber` – Tux Classic Linux (Anthrazit-Carbon & warmes Tux-Gold)
    5. `crimson` – Crimson Security & Audit (Dark Carbon & Blood Crimson Red)
    6. `synthwave` – Synthwave Neon Retro (Midnight Purple & 80s Hot Pink/Cyan)
    7. `darkglass42` – Dark Glass 42 (Edles transluzentes 9-Slice Rahmen-Design, Deep Charcoal & Cyan-Akzente ohne Wallpaper)
  - Kann beim Kopieren interaktiv ausgewählt werden oder eigenständig per Schalter `-ChangeTheme` bzw. `-Theme <name/nr>` gewechselt werden.
- **Intelligente Vorab-Speicherplatzprüfung:**
  - Berechnet vor dem Kopieren den exakten Speicherbedarf aller aktivierten ISOs.
  - Bereits auf dem Ziel-Laufwerk vorhandene, identische Dateien werden vom Bedarf abgezogen.
  - Zeigt bei der Laufwerksauswahl farblich an, ob ausreichend freier Speicher vorhanden ist.
  - Bricht bei Speichermangel auf Wunsch sicher ab und weist den genauen Fehlbetrag in GB aus.
- **Automatische Archivierung & Bereinigung:**
  - Ältere lokale ISO-Versionen werden automatisch in den Ordner `Archiv/` verschoben.
  - Abgewählte und veraltete ISOs werden auf dem Ventoy-Ziellaufwerk endgültig gelöscht.
- **PowerShell 7 Auto-Bootstrap:**
  - Die Starter-Batchdatei prüft auf `pwsh.exe`. Fehlt PowerShell 7 auf einem Fremdrechner, bietet sie die vollautomatische Installation via `winget` oder MSI-Download an.

---

## 📂 Unterstützte Distributionen & Systeme (80 Betriebssysteme & Tools)

### 🖥️ 01_Desktop-Linux (36 Distros)
- **Alpine Linux** – Extrem ressourcenschonende, hochsichere Mini-Distribution auf musl-libc- und busybox-Basis.
- **antiX** – Extrem schnelles, leichtgewichtiges Debian-basiertes Live-System ohne systemd für ältere und moderne Hardware.
- **Arch Linux** – Puristische, flexible Rolling-Release-Distribution nach dem KISS-Prinzip („Keep It Simple, Stupid“).
- **CachyOS** – Performance- und Gaming-optimierte Arch-Linux-Distribution mit angepassten x86-64-v3/v4-Kerneln.
- **Calculate Linux** – Schnelle, benutzerfreundliche Gentoo-basierte Rolling-Release-Distribution mit KDE-Desktop.
- **CRUX** – Schlanke, quellcode- und ports-basierte x86-64-optimierte Distribution nach dem KISS-Prinzip.
- **Debian** – Das universelle, extrem stabile Betriebssystem und Basis unzähliger moderner Linux-Distributionen.
- **Devuan** – Solider Debian-Fork ohne systemd für Liebhaber klassischer Init-Systeme (SysVinit/OpenRC).
- **elementary OS** – Design-fokussiertes, elegantes Betriebssystem auf Ubuntu-LTS-Basis mit intuitivem Pantheon-Desktop.
- **EndeavourOS** – Benutzerfreundlicher Arch-Linux-Installer mit aktiver Community und schlanker Standardkonfiguration.
- **Fedora Workstation** – Innovative, wegweisende Distribution des Red-Hat-Ökosystems mit neuesten Linux-Technologien.
- **Garuda Linux** – Visuell ansprechendes, Arch-basiertes Desktop-System mit BTRFS-Snapshots und Gaming-Fokus ("dr460nized").
- **Gentoo LiveGUI** – Quellcode-basierte Meta-Distribution als sofort bootfähiges Live-System mit grafischer Oberfläche.
- **Linux Lite** – Einsteigerfreundliche, ressourcenschonende Ubuntu-LTS-Distribution mit vertrautem XFCE-Desktop für ältere Hardware.
- **Linux Mint Cinnamon** – Äußerst anwenderfreundliche, elegante Desktop-Distribution auf Ubuntu-Basis mit vertrautem Desktop-Layout.
- **Lubuntu** – Offizieller, extrem schlanker und ressourcenschonender Ubuntu-Flavor mit dem modernen, schnellen LXQt-Desktop.
- **Mageia** – Community-gestützter Mandriva-Nachfolger mit komfortablem Kontrollzentrum und hoher Stabilität.
- **Manjaro Linux** – Zugängliches, hochgradig vorkonfiguriertes Arch-Derivat mit benutzerfreundlichem XFCE-Desktop.
- **MX Linux** – Extrem populäre, hocheffiziente Desktop-Distribution auf Debian-Stable-Basis mit benutzerfreundlichen MX Tools.
- **NixOS** – Revolutionäre, rein deklarative Linux-Distribution mit reproduzierbaren Konfigurationen und atomaren Rollbacks.
- **Omarchy** – Schlankes, modernes Arch-Derivat mit leichtgewichtiger Basis und schnellem Installer.
- **openSUSE Tumbleweed** – Zuverlässige, kontinuierlich getestete Rolling-Release-Distribution mit YaST-Kontrollzentrum.
- **Pop!_OS** – Von System76 entwickelte Ubuntu-basierte Distribution für Kreative und Entwickler mit automatischem Tiling (Pop Shell).
- **Slackware** – Die traditionsreichste aktive Linux-Distribution mit Unix-artiger Stabilität und maximaler Transparenz.
- **Solus** – Unabhängige, eigenständig entwickelte Rolling-Release-Desktop-Distribution mit dem modernen Budgie-Desktop.
- **Ubuntu Desktop** – Die weltweit meistgenutzte Standard-Linux-Desktop-Distribution mit GNOME-Arbeitsumgebung.
- **Ubuntu Cinnamon** – Offizieller Ubuntu-Flavor mit dem modernen, flexiblen Cinnamon-Desktop.
- **Void Linux** – Unabhängige Rolling-Release-Distribution mit dem blitzschnellen XBPS-Paketmanager und runit-Init.
- **Bazzite** – Moderner SteamOS-Klon auf Fedora-Atomic-Basis (Universal Blue) für Handhelds, Konsolen und Desktop-Gaming.
- **KDE neon** – Kontinuierlich aktualisierte Plattform von KDE auf Ubuntu-LTS-Basis mit neuester KDE-Plasma-Desktop-Software.
- **Kubuntu** – Offizieller, eleganter Ubuntu-Flavor mit dem modernen KDE-Plasma-Desktop.
- **Nobara Project** – Performance- und Gaming-optimierte Fedora-Distribution von GloriousEggroll mit Kernel-Patches und vorkonfiguriertem Treiber-Stack.
- **Q4OS** – Extrem schnelles, ressourcenschonendes Desktop-System auf Debian-Basis mit wahlweise Trinity- (TDE) oder KDE-Plasma-Desktop.
- **TUXEDO OS** – Optimiertes Ubuntu-Derivat mit aktuellem Mainline-Kernel, KDE Plasma 6 und umfassendem Hardware-Tuning.
- **Winux** – Auf Ubuntu 24.04 LTS basierende Distribution mit modernem Windows-11-Look (KDE Plasma), vorkonfiguriertem Wine/Proton und hoher Einsteigerfreundlichkeit.
- **Zorin OS Education** – Speziell für Schulen, Schüler und Bildung konzipierte Zorin-OS-Version mit vorinstallierter Lernsoftware.

### 🏢 02_Enterprise-Server & NAS (13 Distros)
- **Azure Linux** – Microsofts gehärtete Linux-Distribution (vormals CBL-Mariner) für Cloud-Infrastruktur, Edge-Devices und Container-Hosts.
- **CentOS Stream 9** – Die kontinuierlich aktualisierte Upstream-Entwicklungsplattform für Red Hat Enterprise Linux (RHEL).
- **Proxmox VE** – Führende Open-Source-Virtualisierungsplattform für KVM-VMs, LXC-Container und Software-Defined Storage.
- **OpenMediaVault** – Modulare, webbasierte Network Attached Storage (NAS)-Lösung auf Debian-Basis.
- **Oracle Linux** – Kostenloses, hochstabiles 100% RHEL-kompatibles Enterprise-Betriebssystem mit dem Unbreakable Enterprise Kernel (UEK).
- **Proxmox Backup Server (PBS)** – Dedizierte Bare-Metal-Backup-Appliance zur unternehmensweiten Deduplizierung und inkrementellen VM/Container-Sicherung.
- **XCP-ng** – Leistungsfähiger Open-Source Enterprise-Hypervisor auf Xen-Basis als führende Alternative zu VMware und Proxmox.
- **ZimaOS** – Modernes, einsteigerfreundliches Cloud- & NAS-Betriebssystem für Home-Server und Personal-Cloud.
- **FreeNAS (TrueNAS SCALE)** – Leistungsstarkes Enterprise-Storage- und NAS-System mit ZFS-Dateisystem und Docker/Apps-Support.
- **Ubuntu Server LTS** – Die bewährte Long-Term-Support-Plattform für Cloud-, Rechenzentrums- und Server-Workloads.
- **Rockstor** – BTRFS-fokussierte NAS- und Speicher-Distribution mit flexiblen „Rock-ons“ (Docker-Apps) und Web-Verwaltung.

### 🛡️ 03_Security- & Penetration-Testing (7 Distros)
- **Kali Linux** – Die weltweite Standard-Distribution für professionelle Penetrationstests, Ethical Hacking und Security-Audits.
- **BackBox Linux** – Führende Ubuntu-basierte Sicherheits- und Penetrationstest-Distribution mit vorkonfiguriertem Toolkit für Ethical Hacking, Forensik und Netzwerkanalysen.
- **Parrot Security** – All-in-One-Umgebung für Cyber-Security, Penetration-Testing, Reverse Engineering und digitale Privatsphäre.
- **Kodachi OS** – Extrem fokussiertes Anonymitäts- und Anti-Forensic-Betriebssystem (basiert auf XFCE) mit automatischem VPN, Tor-Routing, DNSCrypt und Panic-Wipe-Tools.
- **Athena OS** – Hochmoderne Cybersecurity- und Pentesting-Distribution auf Arch-Basis mit themenbasierten Rollen-Modi.
- **Tails** – The Amnesic Incognito Live System: Das weltweit führende Privacy- und Anti-Überwachungs-System mit durchgehendem Tor-Routing.
- **CAINE Live (Forensic & Autopsy)** – Professionelle italienische Forensik-Live-Distribution mit The Sleuth Kit, Autopsy und schreibgeschütztem Block-Device-Zugriff.

### 🧰 04_Rescue-, Diagnose- & Notfall-Systeme (19 Distros & Tools)
- **Boot-Repair-Disk** – Offizielles 64-Bit Rettungswerkzeug zur Ein-Klick-Reparatur beschädigter GRUB- und EFI-Bootloader.
- **Clonezilla Live** – Die bewährte, weltbekannte Festplattenklon- und Image-Backup-Lösung für Bare-Metal-Restore.
- **Dr.Web LiveDisk** – Zuverlässige Antiviren-Rettungsumgebung von Doctor Web zur Säuberung infizierter Windows-Installationen.
- **ESET SysRescue Live** – Antiviren-Rettungsumgebung zur Erkennung und Entfernung hartnäckiger Malware außerhalb des Betriebssystems.
- **Foxclone** – Benutzerfreundliche, moderne Backup-, Image- und Klon-Lösung auf Ubuntu-Basis; explizit optimiert für Ventoy Multi-Boot USB-Sticks.
- **FygoOS PE** – Leistungsfähiges WinPE-basiertes Rettungssystem zur Diagnose, Datenrettung und Windows-Wartung.
- **GParted Live** – Bootfähiges Spezialsystem zur Verwaltung, Vergrößerung, Verkleinerung und Reparatur von Partitionen.
- **Grml** – Das bewährte, legendäre Debian-basierte Rettungs- und Diagnosesystem für Systemadministratoren mit zsh und hunderten Notfallwerkzeugen.
- **Kaspersky Rescue Disk** – Bootfähige Virenscan- und Bereinigungsumgebung zur Rettung schwer infizierter Systeme.
- **netboot.xyz** – Ultrakompakter Bootloader zum Starten dutzender Betriebssysteme direkt über das Internet per iPXE.
- **Rescatux** – Spezialisiertes Reparaturwerkzeug zur einfachen Wiederherstellung von Bootloadern (GRUB) und Zurücksetzen von Passwörtern.
- **Rescuezilla** – Die benutzerfreundliche grafische "Schweizer Taschenmesser"-Lösung für Image-Backups, Restore und Klonen ("Clonezilla mit GUI").
- **ShredOS Disk Sanitizer** – Moderner UEFI/BIOS DoD/NIST Datenträger-Löscher auf nwipe-Basis (unterstützt NVMe, SSD, HDD).
- **Super Grub2 Disk** – Universeller Multi-Boot-Rettungsbootloader zum Starten installierter Systeme bei defektem Bootloader.
- **SystemRescue (ehem. SystemRescueCd)** – Das klassische Notfall- und Rettungssystem für Linux- und Windows-Administratoren mit CLI/GUI-Tools und vorinstalliertem ClamAV-Antivirus.
- **Tiny Core Linux** – Winziges, modulares Mini-Linux-System (nur wenige Megabytes groß), das komplett im RAM läuft.
- **MemTest86+** – Das weltweit führende Open-Source Standalone-RAM-Diagnose-Werkzeug (Version 9.x) für DDR4/DDR5 und UEFI/BIOS.
- **Redo Rescue** – Benutzerfreundliche, intuitive grafische Point-and-Click Bare-Metal Backup- und Wiederherstellungslösung.
- **Ultimate Boot CD (UBCD)** – Die legendäre Diagnosesuite mit zahllosen Hardware-, CPU-, RAM- und Datenträger-Testwerkzeugen.

### 🌐 05_BSD & Unix (6 Distros)
- **DragonFly BSD** – Hochperformantes BSD-Derivat mit dem revolutionären HAMMER2-Cluster- und Snapshot-Dateisystem.
- **FreeBSD** – Hochentwickeltes, hochsicheres UNIX-Betriebssystem mit nativer ZFS-Unterstützung, Jails und legendärem Netzwerk-Stack.
- **NetBSD** – Extrem portables, sauberes BSD-Betriebssystem ("Of course it runs NetBSD") mit hoher Code-Integrität.
- **GhostBSD** – Benutzerfreundliche FreeBSD-Desktop-Distribution mit vorkonfiguriertem MATE-Desktop und grafischem Installer.
- **OPNsense** – Führende Open-Source-Firewall- und Routing-Plattform auf FreeBSD-Basis für professionelle Netzwerksicherheit.
- **OpenBSD** – Das auf maximale Sicherheit, Korrektheit und Kryptographie fokussierte BSD-Betriebssystem.

### 🪟 06_Windows-PE & Recovery (1 System)
- **Hiren's BootCD PE** – Die weltweite Referenz für Windows-Notfallumgebungen (Windows 11 PE x64). Ausgestattet mit über 100 Diagnose-, Datenrettungs-, Partitions-, Antivirus- und Hardware-Testtools für Windows-Systeme.

---

## 📦 Enthaltene Dateien

| Datei | Beschreibung |
|---|---|
| `update-linux-isos.bat` | Robuster Starter für Windows. Prüft/installiert PowerShell 7 und startet das Skript. |
| `update-linux-isos.ps1` | Hauptskript für Windows (Downloads, Hash-Prüfung, Archivierung, Ventoy-Themes, Sync). |
| `update-linux-isos.sh`  | Ausführbares Bash-Startskript für Linux (prüft Abhängigkeiten, richtet ggf. `.venv` ein). |
| `update_linux_isos.py`  | Vollständige Linux-Portierung in Python 3 (PEP 8, Pillow, Requests, Streaming-Downloads). |
| `distros.json`          | JSON-Konfigurationsdatei aller 80 Distributionen, Download-Quellen und Regex-Muster. |
| `.gitignore`            | Schließt ISO-Dateien, Logdateien und temporäre Ordner vom Git-Tracking aus. |
| `GITHUB_ANLEITUNG.md`   | Dokumentation zur Verwaltung und Pflege des GitHub-Repositories. |

---

## 🛠️ Verwendung

### Schneller Start unter Windows:
Einfach Doppelklick auf **`update-linux-isos.bat`**.

### Schneller Start unter Linux:
Im Terminal ausführen:
```bash
chmod +x update-linux-isos.sh
./update-linux-isos.sh
```

### Parameter & Optionen unter Linux:
```bash
# Regulärer Start (prüft & lädt Distros, fragt danach nach Ventoy-Kopie):
./update-linux-isos.sh

# Nur Testlauf ohne Downloads (Dry-Run):
./update-linux-isos.sh --dry-run

# Interaktive Distributionsauswahl öffnen:
./update-linux-isos.sh --select

# Downloads überspringen und direkt auf Ventoy synchronisieren:
./update-linux-isos.sh --skip-download

# Ventoy-Stick vorbereiten / Bootcode aktualisieren:
./update-linux-isos.sh --install-ventoy

# Ventoy-Theme eigenständig wechseln:
./update-linux-isos.sh --change-theme
# oder direkt ein bestimmtes Theme (1-7 oder Name) erzwingen:
./update-linux-isos.sh --theme darkglass42
```

### Parameter & Optionen unter Windows (PowerShell):
```powershell
# Interaktive Distributionsauswahl:
.\update-linux-isos.ps1 -SelectDistros

# Downloads überspringen und nur synchronisieren:
.\update-linux-isos.ps1 -SkipDownload

# Ventoy-Theme wechseln (Themes 1 bis 7):
.\update-linux-isos.ps1 -ChangeTheme
.\update-linux-isos.ps1 -Theme darkglass42 -SkipDownload
```

---

## 📄 Lizenz & Danksagung

Entwickelt für IT-Administratoren, Techniker und Linux-Enthusiasten.
Basiert auf den offiziellen Upstream-Quellen aller 80 Distributionen und dem herausragenden [Ventoy-Projekt](https://www.ventoy.net/).
