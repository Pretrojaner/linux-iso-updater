@echo off
setlocal
chcp 65001 >nul
title Ventoy Config ^& Theme Schnell-Aktualisierer

echo.
echo ===================================================================
echo  Ventoy Config ^& Theme Schnell-Aktualisierer
echo ===================================================================
echo.

where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-ventoy-config.ps1" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-ventoy-config.ps1" %*
)

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [FEHLER] Ein Fehler ist aufgetreten.
    pause
)
