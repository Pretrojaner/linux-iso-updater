# Linux ISO Auto-Updater & Ventoy Sync Tool (v2.1.0)

**Autor:** Ingo  
**Repository:** [Pretrojaner/linux-iso-updater](https://github.com/Pretrojaner/linux-iso-updater)  
**Version:** `2.1.0`

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

## 📂 Kategorisierte Ordnerstruktur

1. **`01_Desktop-Linux`** (Ubuntu, Linux Mint, Fedora, Arch, CachyOS, EndeavourOS, Garuda, Debian, Devuan, Zorin OS, Mageia, Omarchy, Alpine, Gentoo)
2. **`02_Enterprise-Server`** (Ubuntu Server LTS, Rocky Linux, AlmaLinux, CentOS Stream, Proxmox VE, TrueNAS SCALE, OpenMediaVault, ZimaOS, Rockstor)
3. **`03_Security-Pentest`** (Kali Linux, Parrot Security, BlackArch)
4. **`04_Rescue-Systeme`** (SystemRescue, Rescuezilla, GParted Live, Rescatux, netboot.xyz, Kaspersky Rescue Disk, ESET SysRescue, Tiny Core Linux, FygoOS)
5. **`05_BSD-Unix`** (FreeBSD)

---

## 📦 Enthaltene Dateien

| Datei | Beschreibung |
|---|---|
| `update-linux-isos.bat` | Robuster Starter. Prüft/installiert PowerShell 7 und startet das Skript mit Bypass-Rechten. |
| `update-linux-isos.ps1` | Hauptskript (Downloads, Hash-Prüfung, Archivierung, Ventoy-Theme & TreeView-Sync). |
| `distros.json` | JSON-Konfigurationsdatei aller Distributionen, Kategorien, Download-Quellen und Regex-Muster. |
| `.gitignore` | Schließt ISO-Dateien, Logdateien und Systemordner vom Git-Tracking aus. |
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

# Direkte Angabe des Ventoy-Ziellaufwerks (z. B. E:):
.\update-linux-isos.ps1 -TargetDrive E:

# Nur Ventoy-Synchronisation durchführen (Download überspringen):
.\update-linux-isos.ps1 -SkipDownload -TargetDrive E:
```