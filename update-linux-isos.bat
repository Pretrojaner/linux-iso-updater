@echo off
setlocal EnableDelayedExpansion
title Linux ISO Auto-Updater v2.4.0

:: Pruefen ob PowerShell 7 (pwsh.exe) verfuegbar ist
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo -- Es wird nach verfuegbaren Modulen gesucht --
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-linux-isos.ps1" %*
    goto :end
)

:: PowerShell 7 nicht gefunden -> Hinweis und Installationsabfrage
echo ===================================================================
echo [HINWEIS] PowerShell 7 (pwsh.exe) wurde nicht gefunden!
echo ===================================================================
echo Dieses Skript benoetigt PowerShell 7, um Downloads (u.a. Cloudflare-
echo geschuetzte Mirrors und moderne HTTPS/TLS-Verbindungen) zuverlaessig
echo durchzufuehren. Unter der alten Windows PowerShell 5.1 koennen Downloads
echo fehlschlagen oder blockiert werden.
echo.
set /p INSTALL_CHOICE="Moechtest du PowerShell 7 jetzt automatisch installieren? (J/n): "
if /i "%INSTALL_CHOICE%"=="n" (
    echo.
    echo [WARNUNG] Starte mit Windows PowerShell 5.1 (einzelne Downloads koennen fehlschlagen)...
    echo.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-linux-isos.ps1" %*
    goto :end
)

echo.
echo [INFO] Versuche Installation von PowerShell 7...

:: 1. Versuch: winget
where winget.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [INFO] Nutze Windows Package Manager (winget)...
    winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
    if %ERRORLEVEL% EQU 0 (
        echo [ERFOLG] PowerShell 7 wurde installiert!
        goto :launch_pwsh
    )
)

:: 2. Versuch: Download MSI via Windows PowerShell 5.1
echo [INFO] Lade PowerShell 7 MSI-Installer herunter...
set "TEMP_MSI=%TEMP%\PowerShell-7-Setup.msi"
powershell.exe -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $api = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'; $msi = ($api.assets | Where-Object { $_.name -match '^PowerShell-7\..*-win-x64\.msi$' } | Select-Object -First 1).browser_download_url; Write-Host 'Download von:' $msi; Invoke-WebRequest -Uri $msi -OutFile '%TEMP_MSI%'"

if exist "%TEMP_MSI%" (
    echo [INFO] Starte Installation... Bitte kurz warten...
    msiexec.exe /i "%TEMP_MSI%" /passive /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1
    del /f /q "%TEMP_MSI%" >nul 2>&1
) else (
    echo [FEHLER] Download fehlgeschlagen.
    pause
    goto :end
)

:launch_pwsh
:: Pfad ggf. im laufenden cmd aktualisieren
set "PATH=%ProgramFiles%\PowerShell\7;%LOCALAPPDATA%\Microsoft\PowerShell\7;%PATH%"
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [START] Starte Linux ISO Auto-Updater mit PowerShell 7...
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-linux-isos.ps1" %*
) else (
    echo.
    echo [HINWEIS] PowerShell 7 wurde installiert. Bitte starte diese .bat Datei einmal neu!
)

:end
echo.
echo ===================================================================
echo Vorgang abgeschlossen. Fenster bleibt geoeffnet.
echo ===================================================================
pause
endlocal