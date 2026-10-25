# Linux ISO Auto-Updater & Ventoy Sync Tool (v2.3.0)

**Autor:** Ingo  
**Repository:** [Pretrojaner/linux-iso-updater](https://github.com/Pretrojaner/linux-iso-updater)  
**Version:** `2.3.0`

Ein PowerShell-basiertes All-in-One Automatisierungswerkzeug zum Herunterladen, Aktualisieren und Verifizieren von Linux-, Server-, BSD- und Rescue-ISOs sowie zur automatischen Synchronisation und Theme-Einrichtung auf bootfähigen Ventoy-USB-Laufwerken.

> [!IMPORTANT]
> **Wichtiger Hinweis zu Speicherort & benötigtem Speicherplatz:**
> - **Speicherort:** Alle ISO-Dateien werden standardmäßig direkt im **selben Verzeichnis abgelegt, in dem sich die Skripte befinden** (strukturiert in Unterordnern von `01_Desktop-Linux` bis `05_BSD-Unix`).
> - **Speicherplatzbedarf:** Platziere das Skriptpaket daher unbedingt auf einem Laufwerk mit ausreichend freiem Speicherplatz! Für den vollständigen Download aller 43 vorkonfigurierten Distributionen werden ca. **140 GB** freier Speicherplatz empfohlen.
> - **Flexible Auswahl:** Beim Start öffnet sich automatisch das interaktive Auswahlmenü. Du kannst mit `[ENTER]` direkt alle Distros laden (`all`) oder gezielt einzelne Gruppen (z. B. `G1, G4`) bzw. Nummern auswählen, um nur die gewünschten Systeme zu beziehen und Speicherplatz zu sparen.

---

## 🚀 Funktionen

- **Versions- & Release-Scraping:** Prüft online automatisch die neuesten ISO-Releases für 43 Linux-Distributionen, Enterprise-Server, Rettungssysteme und BSD-Derivate.
- **Interaktive Distributions-Auswahl (`-SelectDistros`):**
  - Übersichtliche Darstellung in 5 Gruppen (`G1` bis `G5`).
  - Mehrfachauswahl via Ziffern (`1, 3, 5-8`), Gruppen (`G1, G4`) oder `all`.
  - Bei Neu- oder Umkonfiguration werden abgewählte ISOs auf Wunsch lokal und auf dem Ventoy-Laufwerk bereinigt.
- **Integritätsprüfung:**
  - Berechnet und verifiziert automatisch SHA256-, SHA512- und MD5-Prüfsummen direkt nach dem Download.
  - Erkennt dateispezifische Hashes auch in Multi-File-Prüfsummendateien präzise.
  - Überspringt bereits vorhandene, aktuelle ISOs für blitzschnelle Durchläufe.
- **Automatische Ventoy-Installation (`-InstallVentoy`):**
  - Installiert oder aktualisiert Ventoy direkt per Kommandozeile (CLI) ohne grafische Dialoge (GUI).
  - Erkennt Ventoy lokal oder installiert es vollautomatisch via Windows Package Manager (`winget`) bzw. direkt von GitHub Releases.
  - Sichere Laufwerksauswahl mit Bestätigungsabfrage vor dem Formatieren (`/I` mit GPT und NTFS).
  - Erkennt vorhandene Ventoy-Sticks und bietet zerstörungsfreie Bootcode-Aktualisierungen (`/U`) unter Beibehaltung aller vorhandenen Dateien an.
- **Ventoy Themes (6 Styles zur Auswahl & `-ChangeTheme`):**
  - Generiert automatisch hochauflösende 1080p RGB-Hintergründe und Menügrafiken.
  - **6 Themes enthalten:**
    1. `moderndark` – Modern Dark (Slate Blue & Cyan Accent) [Standard]
    2. `matrix` – Matrix Hacker Terminal (Nerdig, tiefschwarz & leuchtendes Phosphorgruen)
    3. `cybertech` – Cyber Tech & Network (Deep Navy & Electric Blue Infrastruktur)
    4. `tuxamber` – Tux Classic Linux (Anthrazit-Carbon & warmes Tux-Gold)
    5. `crimson` – Crimson Security & Audit (Dark Carbon & Blood Crimson Red)
    6. `synthwave` – Synthwave Neon Retro (Midnight Purple & 80s Hot Pink/Cyan)
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

## 📂 Unterstützte Distributionen & Systeme (43 Betriebssysteme)

### 🖥️ 01_Desktop-Linux (15 Distros)
- **CachyOS** – Performance- und Gaming-optimierte Arch-Linux-Distribution mit angepassten x86-64-v3/v4-Kerneln.
- **Garuda Linux** – Visuell ansprechendes, Arch-basiertes Desktop-System mit BTRFS-Snapshots und Gaming-Fokus ("dr460nized").
- **Linux Mint Cinnamon** – Äußerst anwenderfreundliche, elegante Desktop-Distribution auf Ubuntu-Basis mit vertrautem Desktop-Layout.
- **Omarchy** – Schlankes, modernes Arch-Derivat mit leichtgewichtiger Basis und schnellem Installer.
- **Ubuntu Desktop** – Die weltweit meistgenutzte Standard-Linux-Desktop-Distribution mit GNOME-Arbeitsumgebung.
- **Ubuntu Cinnamon** – Offizieller Ubuntu-Flavor mit dem modernen, flexiblen Cinnamon-Desktop.
- **Zorin OS Education** – Speziell für Schulen, Schüler und Bildung konzipierte Zorin-OS-Version mit vorinstallierter Lernsoftware.
- **Alpine Linux** – Extrem ressourcenschonende, hochsichere Mini-Distribution auf musl-libc- und busybox-Basis.
- **Arch Linux** – Puristische, flexible Rolling-Release-Distribution nach dem KISS-Prinzip („Keep It Simple, Stupid“).
- **Debian** – Das universelle, extrem stabile Betriebssystem und Basis unzähliger moderner Linux-Distributionen.
- **Devuan** – Solider Debian-Fork ohne systemd für Liebhaber klassischer Init-Systeme (SysVinit/OpenRC).
- **Fedora Workstation** – Innovative, wegweisende Distribution des Red-Hat-Ökosystems mit neuesten Linux-Technologien.
- **Gentoo LiveGUI** – Quellcode-basierte Meta-Distribution als sofort bootfähiges Live-System mit grafischer Oberfläche.
- **Mageia** – Community-gestützter Mandriva-Nachfolger mit komfortablem Kontrollzentrum und hoher Stabilität.
- **EndeavourOS** – Benutzerfreundlicher Arch-Linux-Installer mit aktiver Community und schlanker Standardkonfiguration.

### 🏢 02_Enterprise-Server & NAS (9 Distros)
- **AlmaLinux** – Binärkompatibles 1:1 RHEL-Enterprise-Betriebssystem und stabiler Nachfolger von CentOS.
- **CentOS Stream 9** – Die kontinuierlich aktualisierte Upstream-Entwicklungsplattform für Red Hat Enterprise Linux (RHEL).
- **Proxmox VE** – Führende Open-Source-Virtualisierungsplattform für KVM-VMs, LXC-Container und Software-Defined Storage.
- **Rocky Linux** – Community-getriebenes, hochstabiles Enterprise-Betriebssystem mit 100%iger RHEL-Kompatibilität.
- **OpenMediaVault** – Modulare, webbasierte Network Attached Storage (NAS)-Lösung auf Debian-Basis.
- **ZimaOS** – Modernes, einsteigerfreundliches Cloud- & NAS-Betriebssystem für Home-Server und Personal-Cloud.
- **FreeNAS (TrueNAS SCALE)** – Leistungsstarkes Enterprise-Storage- und NAS-System mit ZFS-Dateisystem und Docker/Apps-Support.
- **Ubuntu Server LTS** – Die bewährte Long-Term-Support-Plattform für Cloud-, Rechenzentrums- und Server-Workloads.
- **Rockstor** – BTRFS-fokussierte NAS- und Speicher-Distribution mit flexiblen „Rock-ons“ (Docker-Apps) und Web-Verwaltung.

### 🛡️ 03_Security- & Penetration-Testing (4 Distros)
- **Kali Linux** – Die weltweite Standard-Distribution für professionelle Penetrationstests, Ethical Hacking und Security-Audits.
- **BlackArch Linux** – Auf Arch basierende Sicherheits-Distribution mit über 2.800 vorinstallierten Pentesting-Werkzeugen.
- **Parrot Security** – All-in-One-Umgebung für Cyber-Security, Penetration-Testing, Reverse Engineering und digitale Privatsphäre.
- **CAINE Live (Forensic & Autopsy)** – Professionelle italienische Forensik-Live-Distribution mit The Sleuth Kit, Autopsy und schreibgeschütztem Block-Device-Zugriff.

### 🧰 04_Rescue-, Diagnose- & Notfall-Systeme (11 Distros)
- **Clonezilla Live** – Die bewährte, weltbekannte Festplattenklon- und Image-Backup-Lösung für Bare-Metal-Restore.
- **Tiny Core Linux** – Winziges, modulares Mini-Linux-System (nur wenige Megabytes groß), das komplett im RAM läuft.
- **Rescuezilla** – Die benutzerfreundliche grafische "Schweizer Taschenmesser"-Lösung für Image-Backups, Restore und Klonen ("Clonezilla mit GUI").
- **GParted Live** – Bootfähiges Spezialsystem zur Verwaltung, Vergrößerung, Verkleinerung und Reparatur von Partitionen.
- **FygoOS PE** – Leistungsfähiges WinPE-basiertes Rettungssystem zur Diagnose, Datenrettung und Windows-Wartung.
- **netboot.xyz** – Ultrakompakter Bootloader zum Starten dutzender Betriebssysteme direkt über das Internet per iPXE.
- **SystemRescue (ehem. SystemRescueCd)** – Das klassische Notfall- und Rettungssystem für Linux- und Windows-Administratoren mit CLI/GUI-Tools und vorinstalliertem ClamAV-Antivirus.
- **Rescatux** – Spezialisiertes Reparaturwerkzeug zur einfachen Wiederherstellung von Bootloadern (GRUB) und Zurücksetzen von Passwörtern.
- **Kaspersky Rescue Disk** – Bootfähige Virenscan- und Bereinigungsumgebung zur Rettung schwer infizierter Systeme.
- **ESET SysRescue Live** – Antiviren-Rettungsumgebung zur Erkennung und Entfernung hartnäckiger Malware außerhalb des Betriebssystems.
- **Dr.Web LiveDisk** – Zuverlässige Antiviren-Rettungsumgebung von Doctor Web zur Säuberung infizierter Windows-Installationen.

### 🌐 05_BSD & Unix (4 Distros)
- **FreeBSD** – Hochentwickeltes, hochsicheres UNIX-Betriebssystem mit nativer ZFS-Unterstützung, Jails und legendärem Netzwerk-Stack.
- **OpenBSD** – Das auf maximale Sicherheit, Korrektheit und Kryptographie fokussierte BSD-Betriebssystem.
- **NetBSD** – Extrem portables, sauberes BSD-Betriebssystem ("Of course it runs NetBSD") mit hoher Code-Integrität.
- **DragonFly BSD** – Hochperformantes BSD-Derivat mit dem revolutionären HAMMER2-Cluster- und Snapshot-Dateisystem.

---

## 📦 Enthaltene Dateien

| Datei | Beschreibung |
|---|---|
| `update-linux-isos.bat` | Robuster Starter für Windows. Prüft/installiert PowerShell 7 und startet das Skript. |
| `update-linux-isos.ps1` | Hauptskript für Windows (Downloads, Hash-Prüfung, Archivierung, Ventoy-Themes, Sync). |
| `update-linux-isos.sh`  | Ausführbares Bash-Startskript für Linux (prüft Abhängigkeiten, richtet ggf. `.venv` ein). |
| `update_linux_isos.py`  | Vollständige Linux-Portierung in Python 3 (PEP 8, Pillow, Requests, Streaming-Downloads). |
| `distros.json`          | JSON-Konfigurationsdatei aller 45 Distributionen, Download-Quellen und Regex-Muster. |
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

# Distributionsauswahl interaktiv anpassen:
./update-linux-isos.sh --select

# Ventoy automatisiert auf USB-Laufwerk installieren/aktualisieren:
./update-linux-isos.sh --install-ventoy

# Ventoy Theme interaktiv auswählen und auf USB-Stick einrichten:
./update-linux-isos.sh --change-theme

# Direktes Theme setzen (z. B. matrix, cybertech, moderndark):
./update-linux-isos.sh --change-theme --theme matrix --target /media/$USER/Ventoy

# Nur Ventoy-Synchronisation durchführen (Download überspringen):
./update-linux-isos.sh --skip-download --target /media/$USER/Ventoy
```

### Parameter & Optionen unter Windows (PowerShell / CLI):
```powershell
# Regulärer Start (prüft & lädt Distros, fragt danach nach Ventoy-Kopie):
.\update-linux-isos.ps1

# Nur Testlauf ohne Downloads (Dry-Run):
.\update-linux-isos.ps1 -DryRun

# Distributionsauswahl interaktiv anpassen / rekonfigurieren:
.\update-linux-isos.ps1 -SelectDistros

# Ventoy automatisiert auf USB-Laufwerk installieren/aktualisieren (ohne GUI):
.\update-linux-isos.ps1 -InstallVentoy

# Ventoy Theme interaktiv auswählen und auf USB-Stick einrichten (ohne Downloads):
.\update-linux-isos.ps1 -ChangeTheme

# Direktes Theme setzen (z. B. Matrix Hacker Green):
.\update-linux-isos.ps1 -Theme matrix -TargetDrive D:

# Direkte Angabe des Ventoy-Ziellaufwerks beim ISO-Kopieren:
.\update-linux-isos.ps1 -TargetDrive E:

# Nur Ventoy-Synchronisation durchführen (Download überspringen):
.\update-linux-isos.ps1 -SkipDownload -TargetDrive E:
```
