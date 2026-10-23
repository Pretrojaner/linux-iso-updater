# Linux ISO Auto-Updater & Ventoy Sync Tool (v2.2.0)

**Autor:** Ingo  
**Repository:** [Pretrojaner/linux-iso-updater](https://github.com/Pretrojaner/linux-iso-updater)  
**Version:** `2.2.0`

Ein PowerShell-basiertes All-in-One Automatisierungswerkzeug zum Herunterladen, Aktualisieren und Verifizieren von Linux-, Server-, BSD- und Rescue-ISOs sowie zur automatischen Synchronisation und Theme-Einrichtung auf bootfähigen Ventoy-USB-Laufwerken.

---

## 🚀 Funktionen

- **Versions- & Release-Scraping:** Prüft online automatisch die neuesten ISO-Releases für über 30 Linux-Distributionen, Enterprise-Server, Rettungssysteme und BSD-Derivate.
- **Interaktive Distributions-Auswahl (`-SelectDistros`):**
  - Übersichtliche Darstellung in 5 Gruppen (`G1` bis `G5`).
  - Mehrfachauswahl via Ziffern (`1, 3, 5-8`), Gruppen (`G1, G4`) oder `all`.
  - Bei Neu- oder Umkonfiguration werden abgewählte ISOs auf Wunsch lokal und auf dem Ventoy-Laufwerk bereinigt.
- **Integritätsprüfung:**
  - Berechnet und verifiziert automatisch SHA256- und SHA512-Prüfsummen direkt nach dem Download.
  - Überspringt bereits vorhandene, aktuelle ISOs für blitzschnelle Durchläufe.
- **Automatische Ventoy-Installation (`-InstallVentoy`):**
  - Installiert oder aktualisiert Ventoy direkt per Kommandozeile (CLI) ohne grafische Dialoge (GUI).
  - Erkennt Ventoy lokal oder installiert es vollautomatisch via Windows Package Manager (`winget`) bzw. direkt von GitHub Releases.
  - Sichere Laufwerksauswahl mit Bestätigungsabfrage vor dem Formatieren (`/I` mit GPT und NTFS).
  - Erkennt vorhandene Ventoy-Sticks und bietet zerstörungsfreie Bootcode-Aktualisierungen (`/U`) unter Beibehaltung aller vorhandenen Dateien an.
- **Intelligente Vorab-Speicherplatzprüfung:**
  - Berechnet vor dem Kopieren den exakten Speicherbedarf aller aktivierten ISOs.
  - Bereits auf dem Ziel-Laufwerk vorhandene, identische Dateien werden vom Bedarf abgezogen.
  - Zeigt bei der Laufwerksauswahl farblich an, ob ausreichend freier Speicher vorhanden ist.
  - Bricht bei Speichermangel auf Wunsch sicher ab und weist den genauen Fehlbetrag in GB aus.
- **Automatische Archivierung & Bereinigung:**
  - Ältere lokale ISO-Versionen werden automatisch in den Ordner `Archiv/` verschoben.
  - Abgewählte und veraltete ISOs werden auf dem Ventoy-Ziellaufwerk endgültig gelöscht.
- **Ventoy-Synchronisation & Modern Dark Theme:**
  - Automatische Erkennung des Ventoy-Ziellaufwerks.
  - Richtet das Ventoy-Menü im strukturierten TreeView-Modus (Kategorien) ein.
  - Installiert automatisch ein 1080p Dark-Theme (24-Bit RGB) und vergibt saubere, lesbare Menü-Aliase in `ventoy.json` (UTF-8 ohne BOM).
- **Zusammenfassungstabelle:**
  - Übersichtliche Status-Tabelle vor dem Kopiervorgang (`Neu geladen` oder `Update: Alt -> Neu` mit Größenangabe).
- **PowerShell 7 Auto-Bootstrap:**
  - Die Starter-Batchdatei prüft auf `pwsh.exe`. Fehlt PowerShell 7 auf einem Fremdrechner, bietet sie die vollautomatische Installation via `winget` oder MSI-Download an.

---

## 📂 Unterstützte Distributionen & Systeme (37 Betriebssysteme)

### 🖥️ 01_Desktop-Linux
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

### 🏢 02_Enterprise-Server & NAS
- **AlmaLinux** – Binärkompatibles 1:1 RHEL-Enterprise-Betriebssystem und stabiler Nachfolger von CentOS.
- **CentOS Stream 9** – Die kontinuierlich aktualisierte Upstream-Entwicklungsplattform für Red Hat Enterprise Linux (RHEL).
- **Proxmox VE** – Führende Open-Source-Virtualisierungsplattform für KVM-VMs, LXC-Container und Software-Defined Storage.
- **Rocky Linux** – Community-getriebenes, hochstabiles Enterprise-Betriebssystem mit 100%iger RHEL-Kompatibilität.
- **OpenMediaVault** – Modulare, webbasierte Network Attached Storage (NAS)-Lösung auf Debian-Basis.
- **ZimaOS** – Modernes, einsteigerfreundliches Cloud- & NAS-Betriebssystem für Home-Server und Personal-Cloud.
- **FreeNAS (TrueNAS SCALE)** – Leistungsstarkes Enterprise-Storage- und NAS-System mit ZFS-Dateisystem und Docker/Apps-Support.
- **Ubuntu Server LTS** – Die bewährte Long-Term-Support-Plattform für Cloud-, Rechenzentrums- und Server-Workloads.
- **Rockstor** – BTRFS-fokussierte NAS- und Speicher-Distribution mit flexiblen „Rock-ons“ (Docker-Apps) und Web-Verwaltung.

### 🛡️ 03_Security- & Penetration-Testing
- **Kali Linux** – Die weltweite Standard-Distribution für professionelle Penetrationstests, Ethical Hacking und Security-Audits.
- **BlackArch Linux** – Auf Arch basierende Sicherheits-Distribution mit über 2.800 vorinstallierten Pentesting-Werkzeugen.
- **Parrot Security** – All-in-One-Umgebung für Cyber-Security, Penetration-Testing, Reverse Engineering und digitale Privatsphäre.

### 🧰 04_Rescue-, Diagnose- & Notfall-Systeme
- **Tiny Core Linux** – Winziges, modulares Mini-Linux-System (nur wenige Megabytes groß), das komplett im RAM läuft.
- **Rescuezilla** – Die benutzerfreundliche grafische "Schweizer Taschenmesser"-Lösung für Image-Backups, Restore und Klonen ("Clonezilla mit GUI").
- **GParted Live** – Bootfähiges Spezialsystem zur Verwaltung, Vergrößerung, Verkleinerung und Reparatur von Partitionen.
- **FygoOS PE** – Leistungsfähiges WinPE-basiertes Rettungssystem zur Diagnose, Datenrettung und Windows-Wartung.
- **netboot.xyz** – Ultrakompakter Bootloader zum Starten dutzender Betriebssysteme direkt über das Internet per iPXE.
- **SystemRescue** – Das klassische Notfall- und Rettungssystem für Linux- und Windows-Administratoren mit CLI- und GUI-Tools.
- **Rescatux** – Spezialisiertes Reparaturwerkzeug zur einfachen Wiederherstellung von Bootloadern (GRUB) und Zurücksetzen von Passwörtern.
- **Kaspersky Rescue Disk** – Bootfähige Virenscan- und Bereinigungsumgebung zur Rettung schwer infizierter Systeme.
- **ESET SysRescue Live** – Antiviren-Rettungsumgebung zur Erkennung und Entfernung hartnäckiger Malware außerhalb des Betriebssystems.
- **Phoronix Test Suite (PTS Desktop Live)** – Automatisierte Benchmarking- und Hardware-Testplattform für Performance- und Stabilitätstests.

### 🌐 05_BSD & Unix
- **FreeBSD** – Hochentwickeltes, hochsicheres UNIX-Betriebssystem mit nativer ZFS-Unterstützung, Jails und legendärem Netzwerk-Stack.

---

## 📦 Enthaltene Dateien

| Datei | Beschreibung |
|---|---|
| `update-linux-isos.bat` | Robuster Starter. Prüft/installiert PowerShell 7 und startet das Skript mit Bypass-Rechten. |
| `update-linux-isos.ps1` | Hauptskript (Downloads, Hash-Prüfung, Archivierung, Ventoy-CLI-Installation, Theme & Sync). |
| `distros.json` | JSON-Konfigurationsdatei aller Distributionen, Kategorien, Download-Quellen und Regex-Muster. |
| `.gitignore` | Schließt ISO-Dateien, Logdateien und temporäre Ordner vom Git-Tracking aus. |
| `GITHUB_ANLEITUNG.md` | Dokumentation zur Verwaltung und Pflege des GitHub-Repositories. |

---

## 🛠️ Verwendung

### Schneller Start:
Einfach Doppelklick auf **`update-linux-isos.bat`**.

### Parameter & Optionen (PowerShell / CLI):
```powershell
# Regulärer Start (prüft & lädt Distros, fragt danach nach Ventoy-Kopie):
.\update-linux-isos.ps1

# Nur Testlauf ohne Downloads (Dry-Run):
.\update-linux-isos.ps1 -DryRun

# Distributionsauswahl interaktiv anpassen / rekonfigurieren:
.\update-linux-isos.ps1 -SelectDistros

# Ventoy automatisiert auf USB-Laufwerk installieren/aktualisieren (ohne GUI):
.\update-linux-isos.ps1 -InstallVentoy

# Ventoy direkt auf ein bestimmtes Ziellaufwerk installieren (z. B. D:):
.\update-linux-isos.ps1 -InstallVentoy -TargetDrive D:

# Direkte Angabe des Ventoy-Ziellaufwerks beim ISO-Kopieren:
.\update-linux-isos.ps1 -TargetDrive E:

# Nur Ventoy-Synchronisation durchführen (Download überspringen):
.\update-linux-isos.ps1 -SkipDownload -TargetDrive E:
```
