#!/usr/bin/env bash
# ==============================================================================
# Linux ISO Auto-Updater & Ventoy Sync Tool (Linux Bash Starter)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ANSI-Farbcodes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[96m"
C_GREEN="\033[92m"
C_YELLOW="\033[93m"
C_RED="\033[91m"
C_GRAY="\033[90m"

echo -e "${C_CYAN}===================================================================${C_RESET}"
echo -e "${C_BOLD} Linux ISO Auto-Updater & Ventoy Sync Tool (Linux Edition v2.3.0)${C_RESET}"
echo -e "${C_CYAN}===================================================================${C_RESET}"

# 1. Prüfen auf Python 3
if ! command -v python3 &>/dev/null; then
    echo -e "${C_RED}[FEHLER] python3 wurde nicht gefunden!${C_RESET}"
    echo -e "Bitte installiere Python 3 mit: ${C_YELLOW}sudo apt update && sudo apt install -y python3${C_RESET}"
    exit 1
fi

# 2. Prüfen, ob benötigte Module (requests, Pillow) bereits systemweit verfügbar sind
if python3 -c "import requests, PIL" &>/dev/null; then
    exec python3 "$SCRIPT_DIR/update_linux_isos.py" "$@"
fi

# 3. Falls nicht systemweit vorhanden: Virtual Environment (.venv) nutzen
VENV_DIR="$SCRIPT_DIR/.venv"

if [ ! -d "$VENV_DIR" ]; then
    echo -e "${C_CYAN}[INFO] Systemweite Module fehlen. Richte Virtual Environment in .venv ein...${C_RESET}"
    if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
        # Falls venv wegen fehlendem ensurepip oder Symlink-Einschränkungen auf Netzlaufwerken fehlschlägt
        echo -e "${C_YELLOW}[HINWEIS] Erstelle venv mit --copies...${C_RESET}"
        python3 -m venv --copies "$VENV_DIR" || {
            echo -e "${C_RED}[FEHLER] python3-venv ist nicht vollständig installiert!${C_RESET}"
            echo -e "Installiere die Pakete mit: ${C_YELLOW}sudo apt install -y python3-venv python3-requests python3-pil${C_RESET}"
            exit 1
        }
    fi
fi

# venv aktivieren
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

# 4. Abhängigkeiten im venv installieren falls noch nicht vorhanden
if ! python3 -c "import requests, PIL" &>/dev/null; then
    echo -e "${C_YELLOW}[SETUP] Installiere benötigte Python-Module (requests, Pillow)...${C_RESET}"
    python3 -m pip install --upgrade pip --quiet
    python3 -m pip install requests Pillow --quiet
    echo -e "${C_GREEN}[SETUP] Abhängigkeiten erfolgreich installiert.${C_RESET}"
fi

# 5. Starte Python-Skript
exec python3 "$SCRIPT_DIR/update_linux_isos.py" "$@"
