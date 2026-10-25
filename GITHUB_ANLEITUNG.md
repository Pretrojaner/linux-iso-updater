# Anleitung: Linux ISO Auto-Updater auf GitHub verwalten

Autor: **Ingo**  
Projekt: **Linux ISO Auto-Updater & Ventoy Sync**  
Repository: [Pretrojaner/linux-iso-updater](https://github.com/Pretrojaner/linux-iso-updater)

Diese Anleitung beschreibt, wie das GitHub-Repository aktualisiert wird, wie `.gitignore` funktioniert und wie neue Releases erstellt werden.

---

## 1. Wichtiger Hinweis: Schutz vor großen Dateien (`.gitignore`)

Auf GitHub gilt ein striktes Limit: Dateien über **100 MB** können nicht hochgeladen werden. Linux-ISO-Dateien sind meist mehrere Gigabyte groß.

Die im Projekt enthaltene `.gitignore`-Datei schließt daher automatisch aus:
- Alle ISO- und Image-Dateien (`*.iso`, `*.img`, `*.raw` etc.)
- Die Download- und Kategorieordner (`01_Desktop-Linux/` bis `05_BSD-Unix/`)
- Logdateien (`*.log`, `update-linux-isos.log`)
- Den Archiv-Ordner (`Archiv/`)

Beim Hochladen (Push) werden somit **nur** die Skript- und Konfigurationsdateien übertragen:
- `update-linux-isos.bat`
- `update-linux-isos.ps1`
- `distros.json`
- `README.md`, `GITHUB_ANLEITUNG.md`, `.gitignore`

---

## 2. Änderungen auf GitHub hochladen (Git-Konsole)

Öffne eine PowerShell im Projektordner:

```powershell
# 1. In das Projektverzeichnis wechseln
cd "g:\Antigravity\miniprojekte"

# 2. Status prüfen (zeigt geänderte Dateien)
git status

# 3. Geänderte Skripte und Dokumentation stagen
git add distros.json update-linux-isos.bat update-linux-isos.ps1 .gitignore README.md GITHUB_ANLEITUNG.md

# 4. Commit mit aussagekräftiger Nachricht erstellen
git commit -m "Update auf Version 2.4.0: Gruppenauswahl, Ventoy-Cleanup, Rockstor, PS7-Installer"

# 5. Zu GitHub hochladen
git push origin main
```

> **Hinweis zur Authentifizierung:**  
> Bei der Passwortabfrage im Terminal muss das **GitHub Personal Access Token (PAT)** eingegeben werden (nicht das Web-Passwort).

---

## 3. GitHub Releases & Download-ZIP erstellen

Für Endanwender, die nicht das gesamte Git-Repository klonen möchten, wird unter dem GitHub-Reiter **Releases** ein fertiges ZIP-Paket (bestehend aus `.bat`, `.ps1` und `distros.json`) bereitgestellt.

### So erstellst du ein neues Release auf GitHub:
1. Gehe im Webbrowser auf dein Repository: `https://github.com/Pretrojaner/linux-iso-updater`
2. Klicke auf der rechten Seite auf **Releases** -> **Draft a new release**.
3. **Tag version:** z. B. `v2.4.0` (Target: `main`).
4. **Release title:** `Linux ISO Auto-Updater v2.4.0`.
5. **Beschreibung:** Release Notes / Changelog einfügen.
6. **Binaries anhängen:** Das vorbereitete `linux-iso-updater-v2.4.0.zip` per Drag & Drop in das Feld *Attach binaries by dropping them here or selecting them* ziehen.
7. Klicke auf **Publish release**.

---

## 4. Dateien für ein ZIP-Release zusammenstellen

Um das ZIP-Paket für ein Release lokal zu erstellen, reicht folgender PowerShell-Befehl:

```powershell
Compress-Archive -Path "update-linux-isos.bat", "update-linux-isos.ps1", "update-linux-isos.sh", "update_linux_isos.py", "distros.json" -DestinationPath "linux-iso-updater-v2.4.0.zip" -Force
```