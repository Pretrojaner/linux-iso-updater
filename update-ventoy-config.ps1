<#
.SYNOPSIS
    Ventoy Config & Theme Schnell-Aktualisierer
.DESCRIPTION
    Aktualisiert in wenigen Sekunden das Ventoy-Theme (Dark Glass 42) sowie die
    ventoy.json (Menu-Aliase & Distro-Kurzbeschreibungen / menu_tip Plugin)
    auf dem USB-Stick, OHNE ISOs neu herunterzuladen oder zu kopieren.
#>
[CmdletBinding()]
param(
    [string]$TargetDrive
)

$Host.UI.RawUI.WindowTitle = "Ventoy Config & Theme Updater"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host " VENTOY CONFIG & THEME SCHNELL-AKTUALISIERER" -ForegroundColor Yellow
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "Aktualisiert Theme, Aliase und Live-Distro-Kurztexte (menu_tip Plugin)`n" -ForegroundColor DarkGray

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Get-Location }

# update-linux-isos.ps1 einbinden fuer Hilfsfunktionen
$mainScript = Join-Path $scriptRoot "update-linux-isos.ps1"
if (-not (Test-Path $mainScript)) {
    $mainScript = "Z:\ISO_LOAD\update-linux-isos.ps1"
}

if (-not (Test-Path $mainScript)) {
    Write-Host "[FEHLER] update-linux-isos.ps1 konnte nicht gefunden werden!" -ForegroundColor Red
    pause
    return
}

# Funktionen aus Hauptskript laden
. $mainScript -SkipDownload -SkipVentoy

# Laufwerk abfragen
$drives = Get-AvailableUsbDrives
if (-not $drives) {
    Write-Host "[FEHLER] Keine angeschlossenen USB- oder Ventoy-Laufwerke gefunden!" -ForegroundColor Red
    pause
    return
}

if ([string]::IsNullOrWhiteSpace($TargetDrive)) {
    Write-Host "Verfuegbare USB- & Ventoy-Ziel-Laufwerke:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $labelStr = if ($d.Label) { "[$($d.Label)]" } else { "" }
        $hasVentoy = (Test-Path "$($d.DriveLetter)\ventoy") -or ($d.Label -match "Ventoy")
        $vMarker = if ($hasVentoy) { " [Ventoy bereit]" } else { " [Kein Ventoy]" }
        Write-Host " [$($i + 1)] $($d.DriveLetter) $labelStr ($($d.CapacityGB) GB, $($d.FileSystem))$vMarker" -ForegroundColor White
    }
    Write-Host ""
    $prompt = if ($drives.Count -eq 1) { "Bitte Nummer des Ventoy-Laufwerks eingeben (1-$($drives.Count)) [ENTER = 1]" } else { "Bitte Nummer des Ventoy-Laufwerks eingeben (1-$($drives.Count))" }
    $selection = (Read-Host $prompt).Trim()
    if ([string]::IsNullOrWhiteSpace($selection) -and $drives.Count -eq 1) {
        $selection = "1"
    }
    if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $drives.Count) {
        $TargetDrive = $drives[[int]$selection - 1].DriveLetter
    } else {
        Write-Host "[FEHLER] Ungueltige Auswahl. Abbruch." -ForegroundColor Red
        pause
        return
    }
}

$driveLetter = $TargetDrive.TrimEnd('\').TrimEnd(':') + ":"
$ventoyDir = "$driveLetter\ventoy"

if (-not (Test-Path $ventoyDir)) {
    New-Item -ItemType Directory -Path $ventoyDir -Force | Out-Null
}

Write-Host "`n[1/3] Richte Theme 7 (Dark Glass 42) auf $driveLetter ein..." -ForegroundColor Cyan
Install-VentoyTheme -VentoyDir $ventoyDir -ThemeChoice "7" -Force

Write-Host "[2/3] Erfasse ISOs und generiere Menu-Aliase & Distro-Kurzbeschreibungen..." -ForegroundColor Cyan

# Alle ISOs scannen
$allTargetImages = @{}
$categoryOrder = @("01_Desktop-Linux", "02_Enterprise-Server", "03_Security-Pentest", "04_Rescue-Systeme", "05_BSD-Unix", "06_Windows-PE_Rescue")
foreach ($cat in $categoryOrder) {
    $catDir = Join-Path "$driveLetter\" $cat
    if (Test-Path $catDir) {
        $catFiles = Get-ChildItem -Path $catDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.iso', '.img' }
        foreach ($f in $catFiles) {
            $vpath = "/$cat/$($f.Name)"
            $allTargetImages[$vpath] = $f.Name
        }
    }
}

$menuAliases = @(
    @{ "image" = "/01_Desktop-Linux";     "alias" = "Desktop Linux (Ubuntu, Mint, Fedora, Arch, Zorin...)" },
    @{ "image" = "/02_Enterprise-Server"; "alias" = "Enterprise Server (RHEL, Rocky, Alma, Proxmox, TrueNAS...)" },
    @{ "image" = "/03_Security-Pentest";  "alias" = "Security & Pentesting (Kali, Parrot, BlackArch...)" },
    @{ "image" = "/04_Rescue-Systeme";   "alias" = "Rescue & Recovery (GParted, Rescuezilla, FygoOS...)" },
    @{ "image" = "/05_BSD-Unix";          "alias" = "BSD & Unix (FreeBSD, OpenBSD, NetBSD, DragonFly...)" },
    @{ "image" = "/06_Windows-PE_Rescue"; "alias" = "Windows PE & Recovery (Hiren's BootCD PE, WinPE, Recovery...)" }
)

$menuTips = @(
    @{ "dir" = "/01_Desktop-Linux";     "tip" = "Alltags-, Workstation- & Gaming-Betriebssysteme (Ubuntu, Mint, Fedora, Arch...)" },
    @{ "dir" = "/02_Enterprise-Server"; "tip" = "Enterprise-Server, Hypervisor & NAS-Systeme (RHEL, Proxmox, TrueNAS...)" },
    @{ "dir" = "/03_Security-Pentest";  "tip" = "IT-Sicherheit, Forensik, Anonymitaet & Penetration-Testing (Kali, Tails...)" },
    @{ "dir" = "/04_Rescue-Systeme";   "tip" = "Notfall-, Reparatur-, Hardware-Diagnose & Antivirus-Systeme" },
    @{ "dir" = "/05_BSD-Unix";          "tip" = "BSD-Derivate, Firewalls & alternative Unix-Systeme" },
    @{ "dir" = "/06_Windows-PE_Rescue"; "tip" = "Windows Preinstallation & PE-Rettungsumgebungen" }
)

foreach ($vpath in ($allTargetImages.Keys | Sort-Object)) {
    $fn = $allTargetImages[$vpath]
    $prettyTitle = Get-PrettyIsoName -Filename $fn
    $menuAliases += @{
        "image" = $vpath
        "alias" = $prettyTitle
    }
    $menuTips += @{
        "image" = $vpath
        "tip"   = (Get-IsoMenuTip -Filename $fn)
    }
}

Write-Host "[3/3] Schreibe /ventoy/ventoy.json..." -ForegroundColor Cyan

$ventoyJsonPath = Join-Path $ventoyDir "ventoy.json"
$configObj = @{}
if (Test-Path $ventoyJsonPath) {
    try {
        $rawJson = Get-Content $ventoyJsonPath -Raw -Encoding UTF8 -ErrorAction Stop
        $parsed = $rawJson | ConvertFrom-Json
        if ($parsed) { $configObj = $parsed }
    } catch {
        $configObj = @{}
    }
}

$controlSettings = @(
    @{ "VTOY_DEFAULT_MENU_MODE" = "1" },
    @{ "VTOY_TREE_VIEW_MENU_STYLE" = "1" },
    @{ "VTOY_FILT_DIR_LEVEL" = "0" },
    @{ "VTOY_MAX_MENU_NUM" = "12" }
)
$configObj | Add-Member -NotePropertyName "control" -NotePropertyValue $controlSettings -Force

$configObj | Add-Member -NotePropertyName "theme" -NotePropertyValue $themeSetting -Force
$configObj | Add-Member -NotePropertyName "menu_alias" -NotePropertyValue $menuAliases -Force
$configObj | Add-Member -NotePropertyName "menu_class" -NotePropertyValue (Get-VentoyMenuClassMapping) -Force

$tipConfig = @{
    "left"  = "6%"
    "top"   = "84%"
    "color" = "#73d4b8"
    "tips"  = $menuTips
}
$configObj | Add-Member -NotePropertyName "menu_tip" -NotePropertyValue $tipConfig -Force

$jsonOutput = ($configObj | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($ventoyJsonPath, $jsonOutput, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`n===================================================================" -ForegroundColor Green
Write-Host " VENTOY-KONFIGURATION ERFOLGREICH AKTUALISIERT!" -ForegroundColor Green
Write-Host "===================================================================" -ForegroundColor Green
Write-Host " Ziel-Laufwerk: $driveLetter" -ForegroundColor White
Write-Host " Theme:         Dark Glass 42 (Cyber-Hacker 127.0.0.1 Dual-Glassbox)" -ForegroundColor White
Write-Host " Distro-Icons:  80+ Distro-Logos (48x48 PNG) im Theme aktiv" -ForegroundColor White
Write-Host " Menue-Aliase:  $($allTargetImages.Count) ISOs mit klaren Namen" -ForegroundColor White
Write-Host " Menu-Tips:     $($allTargetImages.Count) Distros mit Kurzbeschreibung konfiguriert" -ForegroundColor White
Write-Host " Position Info: left = 6%, top = 84%, color = #73d4b8 (untere Glasbox)" -ForegroundColor White
Write-Host "===================================================================`n" -ForegroundColor Green

Write-Host "Fertig! Druecke eine Taste zum Beenden..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
