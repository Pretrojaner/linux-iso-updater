@echo off
rem Autor: Ingo
chcp 65001 >nul
title Linux ISO Auto-Updater

where /q pwsh.exe
if %ERRORLEVEL%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-linux-isos.ps1" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-linux-isos.ps1" %*
)

echo.
echo =========================================================
echo Vorgang abgeschlossen. Fenster bleibt geöffnet.
echo =========================================================
pause
