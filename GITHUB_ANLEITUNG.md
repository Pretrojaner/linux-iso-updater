# Anleitung: Linux ISO Auto-Updater auf GitHub hochladen

Autor: **Ingo**  
Projekt: **Linux ISO Auto-Updater & Ventoy Sync**

Diese Anleitung beschreibt Schritt für Schritt, wie die Projektdateien auf ein eigenes GitHub-Repository hochgeladen werden.

---

## ⚠️ Wichtiger Hinweis vorab (.gitignore)

Im Projektordner wurde eine Datei namens `.gitignore` angelegt.  
**Warum ist das wichtig?**  
GitHub erlaubt standardmäßig keine Dateien, die größer als **100 MB** sind. Linux-ISO-Dateien sind mehrere Gigabyte groß. Die `.gitignore`-Datei stellt sicher, dass beim Hochladen ausschließlich die Skriptdateien (`distros.json`, `update-linux-isos.bat`, `update-linux-isos.ps1` und Dokumentationen) hochgeladen werden, **niemals** die heruntergeladenen ISO-Dateien oder Logs.

---

## Methode 1: Über die Konsole / PowerShell (Empfohlen)

### Schritt 1: Neues Repository auf GitHub erstellen
1. Öffne im Browser [github.com](https://github.com/) und melde dich an.
2. Klicke oben rechts auf das **`+`**-Symbol und wähle **`New repository`**.
3. Vergib einen Namen, z. B. `linux-iso-updater` oder `iso-downloader`.
4. Wähle **Public** (öffentlich) oder **Private** (privat).
5. **Wichtig:** Setze **keinen** Haken bei *Add a README file*, *Add .gitignore* oder *Choose a license* (da diese bereits lokal existieren).
6. Klicke auf **Create repository**.
7. Kopiere die angezeigte Repository-URL (z. B. `https://github.com/<DeinBenutzername>/linux-iso-updater.git`).

---

### Schritt 2: Git lokal initialisieren und Dateien committen
Öffne die PowerShell oder das Terminal und führe folgende Befehle aus:

```powershell
# 1. In das Projektverzeichnis wechseln
cd "z:\Tauschen_ID\ID_Böckmann\dev\iso downloader"

# 2. Git-Repository initialisieren
git init

# 3. Haupt-Branch auf 'main' setzen
git branch -M main

# 4. Dateien zur Versionsverwaltung hinzufügen (ignoriert automatisch ISOs & Logs)
git add distros.json update-linux-isos.bat update-linux-isos.ps1 .gitignore GITHUB_ANLEITUNG.md README.md

# 5. Ersten Commit erstellen
git commit -m "Initial commit: Linux ISO Auto-Updater & Ventoy Sync Tool"
```

---

### Schritt 3: Mit GitHub verknüpfen und hochladen (Push)

Ersetze `<URL_DEINES_GITHUB_REPOS>` durch die URL aus Schritt 1:

```powershell
# 6. Remote-Repository verknüpfen
git remote add origin https://github.com/<DeinBenutzername>/linux-iso-updater.git

# 7. Dateien auf GitHub hochladen
git push -u origin main
```

> **Hinweis zur Authentifizierung:**  
> Wenn Git nach Benutzername und Passwort fragt, akzeptiert GitHub seit einiger Zeit kein normales Account-Passwort mehr, sondern ein **Personal Access Token (PAT)**:
> 1. Auf GitHub: `Settings` -> `Developer Settings` -> `Personal access tokens` -> `Tokens (classic)`.
> 2. `Generate new token (classic)` anklicken, Haken bei `repo` setzen und Token generieren.
> 3. Den erzeugten Token kopieren und bei der Passwort-Abfrage im Terminal einfügen.

---

## Methode 2: Über die GitHub-Webseite (Ohne Git-Befehle)

Falls du keine Git-Befehle auf der Kommandozeile verwenden möchtest:

1. Erstelle wie oben beschrieben ein neues Repository auf [github.com](https://github.com/).
2. Klicke im leeren Repository auf den blauen Link **`uploading an existing file`**.
3. Ziehe folgende Dateien per Drag & Drop in das Browserfenster:
   - `distros.json`
   - `update-linux-isos.bat`
   - `update-linux-isos.ps1`
   - `.gitignore`
   - `README.md`
4. Schreibe unten in das Feld Commit-Message z. B. `Initial commit`.
5. Klicke auf den grünen Button **Commit changes**.

---

## Methode 3: Mit GitHub Desktop

Falls du die grafische Oberfläche [GitHub Desktop](https://desktop.github.com/) installiert hast:

1. Öffne GitHub Desktop.
2. Wähle **File** -> **Add local repository...**
3. Wähle den Pfad: `z:\Tauschen_ID\ID_Böckmann\dev\iso downloader`.
4. Klicke auf **Create a repository**, falls noch keines initialisiert ist.
5. Klicke auf **Publish repository**, um es direkt mit deinem GitHub-Konto zu synchronisieren.

---

## Zukünftige Änderungen hochladen

Wenn du später Änderungen an Skripten oder an `distros.json` vornimmst, lädst du die Aktualisierungen so hoch:

```powershell
cd "z:\Tauschen_ID\ID_Böckmann\dev\iso downloader"
git add .
git commit -m "Update distributions configuration"
git push
```
