# Linux ISO Auto-Updater & Ventoy Sync Tool

**Autor:** Ingo  

Ein PowerShell-basiertes Automatisierungswerkzeug zum Herunterladen, Aktualisieren und Verifizieren von Linux- und Rescue-ISOs sowie zur automatischen Synchronisation auf bootfähige Ventoy-USB-Laufwerke.

---

## 🚀 Funktionen

- **Automatischer Versionscheck:** Sucht online nach den neuesten ISO-Releases für mehr als 25 Linux-Distributionen, BSD- und Rettungssysteme.
- **Integritätsprüfung:** Berechnet und verifiziert automatisch SHA256- und SHA512-Prüfsummen.
- **Automatische Archivierung:** Veraltete ISO-Versionen werden automatisch in einen `Archiv/`-Ordner verschoben.
- **Ventoy-Synchronisation:**
  - Automatische Erkennung und Formatierung von Ventoy-Ziellaufwerken.
  - Löscht veraltete ISOs direkt auf dem USB-Laufwerk.
  - Richtet das Ventoy-Menü im strukturierten TreeView-Modus (Kategorien) ein.
  - Installiert ein generiertes 1080p Dark-Theme und vergibt lesbare Aliase für alle ISOs.
- **Kategorisierte Struktur:**
  - `01_Desktop-Linux` (Ubuntu, Mint, Fedora, Arch, Zorin, etc.)
  - `02_Enterprise-Server` (Rocky Linux, AlmaLinux, CentOS, Proxmox, TrueNAS, etc.)
  - `03_Security-Pentest` (Kali Linux, Parrot Security, BlackArch)
  - `04_Rescue-Systeme` (GParted, Rescuezilla, SystemRescue, netboot.xyz, etc.)
  - `05_BSD-Unix` (FreeBSD)

---

## 📂 Enthaltene Dateien

| Datei | Beschreibung |
|---|---|
| `update-linux-isos.bat` | Starter-Batchdatei. Wählt automatisch `pwsh.exe` oder `powershell.exe` mit Bypass-Rechten. |
| `update-linux-isos.ps1` | Hauptskript mit Download-Logik, Prüfsummenvalidierung und Ventoy-Setup. |
| `distros.json` | JSON-Konfigurationsdatei mit Download-Quellen, Regex-Patterns und Kategorien. |
| `.gitignore` | Verhindert das versehentliche Hochladen riesiger ISO-Dateien auf GitHub. |
| `GITHUB_ANLEITUNG.md` | Schritt-für-Schritt-Anleitung zum Hochladen dieses Repositories auf GitHub. |

---

## 🛠️ Verwendung

### Schneller Start:
Doppelklick auf `update-linux-isos.bat`.

### Über PowerShell:
```powershell
# Nur Testlauf ohne Downloads (Dry-Run):
.\update-linux-isos.ps1 -DryRun

# Regulärer Start mit anschließendem Ventoy-Sync:
.\update-linux-isos.ps1

# Direkte Angabe des Ventoy-Laufwerks (z. B. E:):
.\update-linux-isos.ps1 -TargetDrive E:

# Nur Ventoy-Sync durchführen (ohne Download):
.\update-linux-isos.ps1 -SkipDownload -TargetDrive E:
```
