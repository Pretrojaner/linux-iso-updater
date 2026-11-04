<#
.SYNOPSIS
    All-in-One Linux ISO Auto-Updater & Ventoy Sync Tool
.DESCRIPTION
    Version: 2.5.0
    1. Prueft & laedt neueste Linux ISOs herunter, verifiziert SHA256/SHA512-Hashes & archiviert veraltete Dateien.
    2. Ermoeglicht interaktive Gruppenauswahl (Desktop, Server, Security, Rescue, BSD) mit Mehrfachwahl.
    3. Kopiert die ISO-Ordnerstruktur auf ein Ventoy-Ziel-Laufwerk, bereinigt abgewaehlte und veraltete Staende
       und richtet das Ventoy Modern Dark Theme inkl. Dir-Modus (TreeView) automatisch ein.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$TargetDrive,
    [string]$TargetDirectory,
    [string]$LogFileName = "update-linux-isos.log",
    [switch]$SkipDownload,
    [switch]$SkipVentoy,
    [switch]$SelectDistros,
    [switch]$InstallVentoy,
    [switch]$ChangeTheme,
    [string]$Theme
)

Write-Host "-- Es wird nach verfuegbaren Modulen gesucht --" -ForegroundColor DarkGray
$ProgressPreference = 'SilentlyContinue'
if ($env:PSModulePath) {
    try {
        $env:PSModulePath = (($env:PSModulePath -split [System.IO.Path]::PathSeparator) | Where-Object { $_ -notmatch '^[\\/]{2}' }) -join [System.IO.Path]::PathSeparator
    } catch {}
}

# UTF-8 Konfiguration & Assemblies fuer PowerShell 5.1 & Konsole
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}
Add-Type -AssemblyName System.Net.Http
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls

# Mehrfachstart-Schutz (Mutex)
$mutexName = "Global\LinuxIsoAutoUpdaterMutex"
$createdNew = $false
try {
    $scriptMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
} catch {
    $createdNew = $true
}

if (-not $createdNew) {
    Write-Host "`n[WARNUNG] Das ISO-Update-Skript laeuft bereits in einer anderen Instanz!" -ForegroundColor Yellow
    Write-Host "Mehrfachstart wurde verhindert.`n" -ForegroundColor Yellow
    return
}

# Pfade bestimmen
$IsoDirectory = if (-not [string]::IsNullOrWhiteSpace($TargetDirectory)) {
    $TargetDirectory
} elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} else {
    (Get-Location).Path
}

$LogFile = Join-Path $IsoDirectory $LogFileName
$ArchiveDir = Join-Path $IsoDirectory "Archiv"
$ScriptVersion = "2.4.0"
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

function ConvertTo-VersionString {
    param([string]$ver)
    if ([string]::IsNullOrWhiteSpace($ver)) { return "0.0" }
    if ($ver -match '^\d+$') { return "$ver.0" }
    return $ver
}

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] [$Level] $Message"
    Write-Host $formatted -ForegroundColor $Color
    try {
        Add-Content -Path $LogFile -Value $formatted -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Write-LogDetail {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::DarkGray
    )
    $formatted = "   $Message"
    Write-Host $formatted -ForegroundColor $Color
    try {
        Add-Content -Path $LogFile -Value $formatted -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

# Web-Content Hilfsfunktion
function Get-WebContent {
    param([string]$Uri)
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $true
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(15)
        $client.DefaultRequestHeaders.Add("User-Agent", $UserAgent)
        $client.DefaultRequestHeaders.Add("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        if ($response.IsSuccessStatusCode) {
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $client.Dispose(); $handler.Dispose()
            return $content
        }
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    } catch {}

    try {
        $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
        if ($curl) {
            $curlUserAgent = if ($Uri -match "sourceforge\.net") { "curl/8.4.0" } else { $UserAgent }
            $content = & curl.exe -sL -A $curlUserAgent --max-time 15 $Uri
            if (-not [string]::IsNullOrWhiteSpace($content)) { return $content }
        }
    } catch {}
    return $null
}

function Get-OnlineFileSize {
    param([string]$Url)
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $true
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(10)
        if ($Url -match "sourceforge\.net") { $client.DefaultRequestHeaders.Add("User-Agent", "curl/8.4.0") } else { $client.DefaultRequestHeaders.Add("User-Agent", $UserAgent) }

        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if ($response.IsSuccessStatusCode -and $response.Content.Headers.ContentLength) {
            $len = $response.Content.Headers.ContentLength
            $client.Dispose(); $handler.Dispose()
            if ($len -ge 1MB) { return $len }
        }
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    } catch {}

    try {
        $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
        if ($curl) {
            $curlUserAgent = if ($Url -match "sourceforge\.net") { "curl/8.4.0" } else { $UserAgent }
            $headers = & curl.exe -sIL -A $curlUserAgent --max-time 10 $Url | Out-String
            $lenMatches = [regex]::Matches($headers, '(?i)Content-Length:\s*(\d+)')
            if ($lenMatches.Count -gt 0) {
                $len = [long]$lenMatches[$lenMatches.Count - 1].Groups[1].Value
                if ($len -ge 1MB) { return $len }
            }
        }
    } catch {}
    return 0
}

function Test-IsoChecksum {
    param(
        [string]$FilePath,
        [string]$DownloadUrl,
        [string]$Filename,
        [string]$ExplicitChecksumUrl
    )

    $expectedHash = $null
    $hashAlgorithm = $null

    # 1. SHA512 Kandidaten
    $sha512Candidates = @(
        "$DownloadUrl.sha512sum",
        "$DownloadUrl.sha512",
        ($DownloadUrl -replace '\.iso$', '.sha512sum'),
        ($DownloadUrl -replace '\.iso$', '.sha512')
    )
    if ($ExplicitChecksumUrl -and ($ExplicitChecksumUrl -match 'sha512')) {
        $sha512Candidates = @($ExplicitChecksumUrl) + $sha512Candidates
    }

    # 2. SHA256 Kandidaten
    $sha256Candidates = @(
        "$DownloadUrl.sha256",
        "$DownloadUrl.sha256sum",
        "$DownloadUrl.SHA256",
        ($DownloadUrl -replace '\.iso$', '.sha256'),
        ($DownloadUrl -replace '\.iso$', '.sha256sum')
    )
    if ($ExplicitChecksumUrl -and ($ExplicitChecksumUrl -notmatch 'sha512' -and $ExplicitChecksumUrl -notmatch 'md5')) {
        $sha256Candidates = @($ExplicitChecksumUrl) + $sha256Candidates
    }

    # 3. MD5 Kandidaten
    $md5Candidates = @(
        "$DownloadUrl.md5",
        ($DownloadUrl -replace '\.iso$', '.md5')
    )
    if ($ExplicitChecksumUrl -and ($ExplicitChecksumUrl -match 'md5')) {
        $md5Candidates = @($ExplicitChecksumUrl) + $md5Candidates
    }

    # Bestimme Pruefungsreihenfolge basierend auf expliziter URL
    $algoOrder = @("SHA256", "SHA512", "MD5")
    if ($ExplicitChecksumUrl -match 'sha512') {
        $algoOrder = @("SHA512", "SHA256", "MD5")
    } elseif ($ExplicitChecksumUrl -match 'md5') {
        $algoOrder = @("MD5", "SHA256", "SHA512")
    }

    foreach ($algo in $algoOrder) {
        if ($expectedHash) { break }

        $candidates = switch ($algo) {
            "SHA512" { $sha512Candidates }
            "SHA256" { $sha256Candidates }
            "MD5"    { $md5Candidates }
        }
        $hexLen = switch ($algo) {
            "SHA512" { 128 }
            "SHA256" { 64 }
            "MD5"    { 32 }
        }

        foreach ($cUrl in $candidates) {
            $content = Get-WebContent -Uri $cUrl
            if ($content) {
                # Format: "Filename ... [Hash]" oder "[Hash] ... Filename"
                if ($Filename -and ($content -match "(?m)^.*$([regex]::Escape($Filename)).*?(?<![a-fA-F0-9])([a-fA-F0-9]{$hexLen})(?![a-fA-F0-9])")) {
                    $expectedHash = $Matches[1].ToLower()
                    $hashAlgorithm = $algo
                    break
                } elseif ($Filename -and ($content -match "(?m)^(?<![a-fA-F0-9])([a-fA-F0-9]{$hexLen})(?![a-fA-F0-9])\s+.*?$([regex]::Escape($Filename))")) {
                    $expectedHash = $Matches[1].ToLower()
                    $hashAlgorithm = $algo
                    break
                } elseif ($content -match "(?<![a-fA-F0-9])([a-fA-F0-9]{$hexLen})(?![a-fA-F0-9])") {
                    $expectedHash = $Matches[1].ToLower()
                    $hashAlgorithm = $algo
                    break
                }
            }
        }
    }

    if (-not $expectedHash) {
        Write-LogDetail -Message "Keine Online-Pruefsumme gefunden fuer $Filename. Ueberspringe Hash-Verifikation." -Color DarkGray
        return $true
    }

    $fileMB = [math]::Round((Get-Item $FilePath).Length / 1MB, 2)
    Write-LogDetail -Message "Erwarteter Hash ($hashAlgorithm): $expectedHash" -Color DarkGray
    Write-LogDetail -Message "Berechne lokalen $hashAlgorithm-Hash ($fileMB MB)... Bitte warten." -Color DarkGray

    try {
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm $hashAlgorithm).Hash.ToLower()
        Write-LogDetail -Message "Berechneter Hash: $actualHash" -Color DarkGray
        if ($actualHash -eq $expectedHash) {
            Write-LogDetail -Message "$hashAlgorithm-Pruefsumme VERIFIZIERT: OK" -Color DarkGreen
            return $true
        } else {
            Write-Log -Message "$hashAlgorithm-Pruefsumme FALSCH! Erwartet: $expectedHash | Berechnet: $actualHash" -Color Red -Level "FEHLER"
            return $false
        }
    } catch {
        Write-Log -Message "Fehler bei der Berechung der Pruefsumme: $_" -Color Red -Level "FEHLER"
        return $true
    }
}

function Start-HttpDownload {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$DestinationPath,
        [string]$Filename
    )

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true

    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromHours(2)
    if ($Url -match "sourceforge\.net") { $client.DefaultRequestHeaders.Add("User-Agent", "curl/8.4.0") } else { $client.DefaultRequestHeaders.Add("User-Agent", $UserAgent) }
    $client.DefaultRequestHeaders.Add("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")

    try {
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP Statuscode $($response.StatusCode) - $($response.ReasonPhrase)"
        }

        $totalBytes = $response.Content.Headers.ContentLength
        if (-not $totalBytes) { $totalBytes = -1 }

        $inputStream  = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream = [System.IO.File]::Create($DestinationPath)

        $buffer = New-Object byte[] 65536 # 64 KB Buffer
        $totalBytesRead = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastReportTime = 0

        while (($bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $bytesRead)
            $totalBytesRead += $bytesRead

            $currentTime = $stopwatch.ElapsedMilliseconds
            if ($currentTime - $lastReportTime -ge 200 -or $totalBytesRead -eq $totalBytes) {
                $speedBytesPerSec = if ($stopwatch.Elapsed.TotalSeconds -gt 0) { $totalBytesRead / $stopwatch.Elapsed.TotalSeconds } else { 0 }
                $speedMBs         = [math]::Round($speedBytesPerSec / 1MB, 2)
                $transMB          = [math]::Round($totalBytesRead / 1MB, 2)

                if ($totalBytes -gt 0) {
                    $percent   = [math]::Round(($totalBytesRead / $totalBytes) * 100, 1)
                    $totalMB   = [math]::Round($totalBytes / 1MB, 2)
                    $barWidth  = 25
                    $completed = [math]::Floor(($percent / 100) * $barWidth)
                    $remaining = $barWidth - $completed
                    $barStr = ("=" * $completed) + ("-" * $remaining)

                    $statusLine = "`r   [LADEN] [$barStr] {0,5:N1}% | {1,8:N2} / {2,8:N2} MB | {3,6:N2} MB/s  " -f $percent, $transMB, $totalMB, $speedMBs
                    Write-Host $statusLine -NoNewline -ForegroundColor Cyan
                } else {
                    $statusLine = "`r   [LADEN] {0,8:N2} MB empfangen | {1,6:N2} MB/s  " -f $transMB, $speedMBs
                    Write-Host $statusLine -NoNewline -ForegroundColor Cyan
                }

                $lastReportTime  = $currentTime
            }
        }

        $stopwatch.Stop()
        Write-Host ""

        if ($totalBytes -gt 0 -and $totalBytesRead -lt $totalBytes) {
            $downloadedMB = [math]::Round($totalBytesRead / 1MB, 2)
            $expectedMB   = [math]::Round($totalBytes / 1MB, 2)
            throw "Download abgebrochen oder unvollstaendig! ($downloadedMB MB von $expectedMB MB empfangen)"
        }

        return $totalBytesRead
    }
    catch {
        $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
        if ($curl) {
            Write-Host "`n   [DOWNLOAD FALLBACK] Nutze curl.exe fuer $Filename..." -ForegroundColor Yellow
            $curlUserAgent = if ($Url -match "sourceforge\.net") { "curl/8.4.0" } else { $UserAgent }
            & curl.exe -L -A $curlUserAgent --progress-bar -o $DestinationPath $Url
            if (Test-Path $DestinationPath) {
                $item = Get-Item $DestinationPath
                if ($item.Length -gt 1MB) {
                    return $item.Length
                }
            }
        }
        throw $_
    }
    finally {
        if ($outputStream) { $outputStream.Close(); $outputStream.Dispose() }
        if ($inputStream)  { $inputStream.Close();  $inputStream.Dispose() }
        if ($client)       { $client.Dispose() }
        if ($handler)      { $handler.Dispose() }
    }
}

function Copy-FileWithProgress {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    $srcFile = [System.IO.File]::OpenRead($SourcePath)
    $dstFile = [System.IO.File]::Create($DestinationPath)
    $totalBytes = $srcFile.Length
    $totalBytesRead = 0
    $buffer = New-Object byte[] (1024 * 1024) # 1 MB Puffer
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastReportTime = 0

    try {
        while (($bytesRead = $srcFile.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $dstFile.Write($buffer, 0, $bytesRead)
            $totalBytesRead += $bytesRead

            $currentTime = $sw.ElapsedMilliseconds
            if ($currentTime - $lastReportTime -ge 100 -or $totalBytesRead -eq $totalBytes) {
                $percent   = [math]::Round(($totalBytesRead / $totalBytes) * 100, 1)
                $transMB   = [math]::Round($totalBytesRead / 1MB, 1)
                $totalMB   = [math]::Round($totalBytes / 1MB, 1)
                $speedMBs  = [math]::Round(($totalBytesRead / 1MB) / [math]::Max($sw.Elapsed.TotalSeconds, 0.001), 2)

                $barWidth = 25
                $completed = [math]::Floor(($percent / 100) * $barWidth)
                $remaining = $barWidth - $completed
                $barStr = ("=" * $completed) + ("-" * $remaining)

                $statusLine = "`r   [KOPIERE] [$barStr] {0,5:N1}% | {1,8:N1} / {2,8:N1} MB | {3,6:N2} MB/s   " -f $percent, $transMB, $totalMB, $speedMBs
                Write-Host $statusLine -NoNewline -ForegroundColor Cyan
                $lastReportTime = $currentTime
            }
        }
    } finally {
        $sw.Stop()
        Write-Host ""
        $dstFile.Close(); $dstFile.Dispose()
        $srcFile.Close(); $srcFile.Dispose()
    }
}

function Get-PrettyIsoName {
    param([string]$Filename)
    
    if ($Filename -match '(?i)clonezilla')       { return "Clonezilla Live Disk Backup" }
    if ($Filename -match '(?i)caine')            { return "CAINE Live Digital Forensics & TSK" }
    if ($Filename -match '(?i)drweb')            { return "Dr.Web LiveDisk Antivirus" }
    if ($Filename -match '(?i)stresslinux')      { return "Stresslinux Hardware Load Test" }
    if ($Filename -match '(?i)openbsd|install\d+\.iso') { return "OpenBSD Release" }
    if ($Filename -match '(?i)NetBSD')           { return "NetBSD Release" }
    if ($Filename -match '(?i)dfly|dragonfly')   { return "DragonFly BSD Release" }
    if ($Filename -match '(?i)alpine')           { return "Alpine Linux Standard" }
    if ($Filename -match '(?i)archlinux')        { return "Arch Linux" }
    if ($Filename -match '(?i)cachyos')          { return "CachyOS Desktop Linux" }
    if ($Filename -match '(?i)debian')           { return "Debian GNU/Linux" }
    if ($Filename -match '(?i)devuan')           { return "Devuan GNU/Linux" }
    if ($Filename -match '(?i)endeavouros')      { return "EndeavourOS Linux" }
    if ($Filename -match '(?i)Fedora')           { return "Fedora Workstation Live" }
    if ($Filename -match '(?i)garuda')           { return "Garuda Linux Dr460nized" }
    if ($Filename -match '(?i)linuxmint')        { return "Linux Mint Cinnamon" }
    if ($Filename -match '(?i)livegui.*gentoo')  { return "Gentoo Live GUI" }
    if ($Filename -match '(?i)Mageia')           { return "Mageia Linux" }
    if ($Filename -match '(?i)omarchy')          { return "Omarchy Linux" }
    if ($Filename -match '(?i)lubuntu')          { return "Lubuntu Desktop" }
    if ($Filename -match '(?i)antix')            { return "antiX Linux Full" }
    if ($Filename -match '(?i)cld.*x86_64')      { return "Calculate Linux Desktop KDE" }
    if ($Filename -match '(?i)crux')             { return "CRUX Linux" }
    if ($Filename -match '(?i)elementaryos')     { return "elementary OS" }
    if ($Filename -match '(?i)linux-lite')       { return "Linux Lite" }
    if ($Filename -match '(?i)manjaro')          { return "Manjaro Linux XFCE" }
    if ($Filename -match '(?i)mx-.*xfce')        { return "MX Linux Xfce" }
    if ($Filename -match '(?i)nixos.*graphical') { return "NixOS Graphical" }
    if ($Filename -match '(?i)opensuse.*tumbleweed') { return "openSUSE Tumbleweed" }
    if ($Filename -match '(?i)pop-os')           { return "Pop!_OS" }
    if ($Filename -match '(?i)slackware')        { return "Slackware Linux DVD" }
    if ($Filename -match '(?i)solus.*budgie')    { return "Solus Budgie" }
    if ($Filename -match '(?i)void-live')        { return "Void Linux XFCE" }
    if ($Filename -match '(?i)winux')            { return "Winux Desktop" }
    if ($Filename -match '(?i)ubuntucinnamon')   { return "Ubuntu Cinnamon" }
    if ($Filename -match '(?i)ubuntu.*live-server') { return "Ubuntu Server LTS" }
    if ($Filename -match '(?i)ubuntu')           { return "Ubuntu Desktop" }
    if ($Filename -match '(?i)Zorin')            { return "Zorin OS" }
    if ($Filename -match '(?i)kodachi')          { return "Kodachi OS" }
    
    if ($Filename -match '(?i)AlmaLinux')        { return "AlmaLinux Enterprise" }
    if ($Filename -match '(?i)CentOS')           { return "CentOS Stream" }
    if ($Filename -match '(?i)openmediavault')   { return "OpenMediaVault NAS" }
    if ($Filename -match '(?i)zimaos')           { return "ZimaOS Storage & Cloud" }
    if ($Filename -match '(?i)TrueNAS|FreeNAS')  { return "FreeNAS / TrueNAS SCALE" }
    if ($Filename -match '(?i)proxmox')          { return "Proxmox VE Hypervisor" }
    if ($Filename -match '(?i)Rocky')            { return "Rocky Linux" }
    if ($Filename -match '(?i)Rockstor')         { return "Rockstor Btrfs NAS" }
    
    if ($Filename -match '(?i)blackarch')        { return "BlackArch Linux (Full)" }
    if ($Filename -match '(?i)kali')             { return "Kali Linux Security" }
    if ($Filename -match '(?i)Parrot')           { return "Parrot Security OS" }
    
    if ($Filename -match '(?i)CorePure64')       { return "Tiny Core Linux Pure64" }
    if ($Filename -match '(?i)eset_sysrescue')   { return "ESET SysRescue Live" }
    if ($Filename -match '(?i)fygoos')           { return "FygoOS PE Rescue" }
    if ($Filename -match '(?i)gparted')          { return "GParted Live Partition Editor" }
    if ($Filename -match '(?i)krd')              { return "Kaspersky Rescue Disk" }
    if ($Filename -match '(?i)netboot\.xyz')     { return "netboot.xyz Multi-Boot" }
    if ($Filename -match '(?i)pts-desktop-live|phoronix') { return "Phoronix Test Suite Live" }
    if ($Filename -match '(?i)rescatux')         { return "Rescatux Boot & GRUB Repair" }
    if ($Filename -match '(?i)rescuezilla')      { return "Rescuezilla Recovery" }
    if ($Filename -match '(?i)systemrescue')     { return "SystemRescue (ehem. SystemRescueCd)" }
    
    if ($Filename -match '(?i)FreeBSD')          { return "FreeBSD Release" }

    if ($Filename -match '(?i)hbcd|hiren')       { return "Hiren's BootCD PE (Windows Recovery Environment)" }
    if ($Filename -match '(?i)boot-repair')      { return "Boot-Repair-Disk (GRUB & EFI Repair)" }
    if ($Filename -match '(?i)super_?grub')      { return "Super Grub2 Disk (Multi-Boot Rescue)" }
    if ($Filename -match '(?i)ubcd')             { return "Ultimate Boot CD (Diagnostic Suite)" }
    if ($Filename -match '(?i)shredos')          { return "ShredOS (Disk Sanitizer & DoD Wipe)" }

    $clean = $Filename -replace '\.iso$', '' -replace '[-_]', ' '
    return "$clean"
}

function Select-DistrosInteractive {
    param(
        [array]$DistroList,
        [switch]$IsReconfiguration
    )

    $categoryOrder = @(
        "01_Desktop-Linux",
        "02_Enterprise-Server",
        "03_Security-Pentest",
        "04_Rescue-Systeme",
        "05_BSD-Unix",
        "06_Windows-PE_Rescue"
    )

    $orderedList = @()
    $groupMap = [hashtable]::new()
    $groupIndex = 1

    foreach ($cat in $categoryOrder) {
        $inCat = $DistroList | Where-Object { $_.Category -eq $cat }
        if ($inCat) {
            $groupMap[$groupIndex] = @{
                Category = $cat
                Items = @()
            }
            foreach ($item in $inCat) {
                $orderedList += $item
                $groupMap[$groupIndex].Items += $item
            }
            $groupIndex++
        }
    }
    $leftovers = $DistroList | Where-Object { $categoryOrder -notcontains $_.Category }
    if ($leftovers) {
        $groupMap[$groupIndex] = @{
            Category = "Sonstige"
            Items = @()
        }
        foreach ($item in $leftovers) {
            $orderedList += $item
            $groupMap[$groupIndex].Items += $item
        }
    }

    $existingIsos = Get-ChildItem -Path $IsoDirectory -Recurse -File -ErrorAction SilentlyContinue | Where-Object { 
        $_.DirectoryName -notlike "*Archiv*" -and $_.Name -notlike "*.part" -and $_.Length -gt 1MB -and ($_.Extension -in '.iso', '.img') 
    }

    Write-Host ""
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host "                    DISTRIBUTIONS-AUSWAHL (MEHRFACHWAHL)                                 " -ForegroundColor Yellow
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host "Waehle aus, welche Distributionen kuenftig geprueft, geladen und synchronisiert werden:" -ForegroundColor White
    Write-Host "Legende: [x] = ISO bereits lokal vorhanden | [ ] = Noch nicht heruntergeladen" -ForegroundColor DarkGray
    Write-Host "Eingabeformate: 'all' (alle), Gruppen z.B. 'G1, G4' oder Nummern z.B. '1, 3, 5-8'!" -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $numIndex = 1
    $indexItemMap = @{}

    foreach ($gKey in ($groupMap.Keys | Sort-Object { [int]$_ })) {
        $g = $groupMap[$gKey]
        Write-Host "`n [Gruppe G$gKey] $($g.Category)" -ForegroundColor Cyan
        Write-Host " ----------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        foreach ($d in $g.Items) {
            $indexItemMap[$numIndex] = $d
            $localMatch = $null
            if ($d.MatchPattern -and $existingIsos) {
                $localMatch = $existingIsos | Where-Object { $_.Name -match $d.MatchPattern } | Select-Object -First 1
            }

            $isPresent = ($null -ne $localMatch)
            $statusStr = if ($isPresent) { "[x]" } else { "[ ]" }
            $statusColor = if ($isPresent) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkGray }

            if ($isPresent) {
                $sizeMB = [math]::Round($localMatch.Length / 1MB, 0)
                $sizeStr = "$sizeMB MB vorhanden"
            } else {
                $sizeMB = if ($d.SizeBytes) { [math]::Round([long]$d.SizeBytes / 1MB, 0) } else { 0 }
                $sizeStr = if ($sizeMB -gt 0) { "ca. $sizeMB MB Download" } else { "Groesse unbekannt" }
            }

            $numFmt = "{0,2}" -f $numIndex
            Write-Host "   $numFmt) " -NoNewline -ForegroundColor White
            Write-Host "$statusStr " -NoNewline -ForegroundColor $statusColor
            Write-Host ("{0,-32} " -f $d.Name) -NoNewline -ForegroundColor White
            Write-Host "($sizeStr)" -ForegroundColor DarkGray
            $numIndex++
        }
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Auswahl eingeben (ENTER = alle Distros auswaehlen):" -ForegroundColor Yellow
    $rawInput = Read-Host "Auswahl (z.B. all / G1, G3 / 1,4,7-10) [ENTER = all]"

    if ([string]::IsNullOrWhiteSpace($rawInput)) {
        $rawInput = "all"
    }

    $selectedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($rawInput.Trim() -eq "all" -or $rawInput.Trim() -eq "*") {
        foreach ($d in $orderedList) { [void]$selectedNames.Add($d.Name) }
    } else {
        $tokens = $rawInput -split '[,; ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        foreach ($tok in $tokens) {
            $t = $tok.Trim()
            if ($t -match '^[gG](\d+)$') {
                $gId = [int]$Matches[1]
                if ($groupMap.ContainsKey($gId)) {
                    foreach ($d in $groupMap[$gId].Items) {
                        [void]$selectedNames.Add($d.Name)
                    }
                }
            } elseif ($t -match '^(\d+)-(\d+)$') {
                $start = [int]$Matches[1]
                $end = [int]$Matches[2]
                for ($n = $start; $n -le $end; $n++) {
                    if ($indexItemMap.ContainsKey($n)) {
                        [void]$selectedNames.Add($indexItemMap[$n].Name)
                    }
                }
            } elseif ($t -match '^\d+$') {
                $n = [int]$t
                if ($indexItemMap.ContainsKey($n)) {
                    [void]$selectedNames.Add($indexItemMap[$n].Name)
                }
            }
        }
    }

    foreach ($d in $orderedList) {
        $d.Enabled = $selectedNames.Contains($d.Name)
    }

    $activeCount = ($orderedList | Where-Object { $_.Enabled -eq $true }).Count
    Write-Host "`n[INFO] Es wurden $activeCount von $($orderedList.Count) Distributionen aktiviert.`n" -ForegroundColor Green
}

function Expand-Bz2Archive {
    param(
        [Parameter(Mandatory=$true)][string]$Bz2Path,
        [Parameter(Mandatory=$true)][string]$DestinationIsoPath
    )

    $outDir = Split-Path $DestinationIsoPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    # 1. 7-Zip
    $sevenZip = (Get-Command 7z.exe, 7za.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    if (-not $sevenZip -and (Test-Path "C:\Program Files (x86)\Universal Extractor\bin\7z.exe")) {
        $sevenZip = "C:\Program Files (x86)\Universal Extractor\bin\7z.exe"
    }
    if (-not $sevenZip -and (Test-Path "C:\Program Files\7-Zip\7z.exe")) {
        $sevenZip = "C:\Program Files\7-Zip\7z.exe"
    }
    if ($sevenZip) {
        try {
            & $sevenZip e -y "-o$outDir" $Bz2Path | Out-Null
            if (Test-Path $DestinationIsoPath) { return $true }
        } catch {}
    }

    # 2. Python Fallback
    $py = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $escapedBz2 = $Bz2Path.Replace('\', '\\')
            $escapedIso = $DestinationIsoPath.Replace('\', '\\')
            $pyScript = "import bz2; open(r'$escapedIso', 'wb').write(bz2.decompress(open(r'$escapedBz2', 'rb').read()))"
            & python.exe -c $pyScript
            if (Test-Path $DestinationIsoPath) { return $true }
        } catch {}
    }

    # 3. Windows tar.exe Fallback
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        try {
            & tar.exe -xf $Bz2Path -C $outDir | Out-Null
            if (Test-Path $DestinationIsoPath) { return $true }
        } catch {}
    }

    return $false
}

function Get-VentoyThemeDefinitions {
    return [ordered]@{
        "1" = [ordered]@{
            Key        = "moderndark"
            Name       = "Modern Dark"
            Desc       = "Slate Blue & Cyan (Modern, aufgeraeumt & Blade Runner 2049 Artwork)"
            Title      = "VENTOY MULTIBOOT SYSTEM MANAGER"
            TitleColor = "#38bdf8"
            Bg1        = "#0f172a"
            Bg2        = "#1e1e2e"
            Header     = "#1e293b"
            Accent     = "#38bdf8"
            Text       = "#94a3b8"
            SelBg      = "#38bdf8"
            SelFg      = "#0f172a"
            ImageUrl   = "https://m.media-amazon.com/images/M/MV5BMTU5NTkwNTA2NF5BMl5BanBnXkFtZTgwMjQ5MjY2MzI@.jpg"
        }
        "2" = [ordered]@{
            Key        = "matrix"
            Name       = "Matrix Hacker Terminal"
            Desc       = "Nerdig, tiefes Schwarz & Hackers (1995) Terminal-Phosphorgruen"
            Title      = "ROOT@TERMINAL // MULTIBOOT MATRIX"
            TitleColor = "#22c55e"
            Bg1        = "#050a05"
            Bg2        = "#0a170d"
            Header     = "#0f2314"
            Accent     = "#22c55e"
            Text       = "#86efac"
            SelBg      = "#22c55e"
            SelFg      = "#050a05"
            ImageUrl   = "https://m.media-amazon.com/images/M/MV5BYzc0OTAxOWQtMWUxNS00ZjAxLTlmODAtMzQyNzQ2NzJmODUzXkEyXkFqcGc@.jpg"
        }
        "3" = [ordered]@{
            Key        = "cybertech"
            Name       = "Cyber Tech & Network"
            Desc       = "Technik & Cyber-Infrastruktur, Hackers (1995) Electric Blue"
            Title      = "CYBER-NET // MULTIBOOT NETWORK OS SUITE"
            TitleColor = "#38bdf8"
            Bg1        = "#020817"
            Bg2        = "#0c1e3d"
            Header     = "#0f274c"
            Accent     = "#3b82f6"
            Text       = "#93c5fd"
            SelBg      = "#3b82f6"
            SelFg      = "#020817"
            ImageUrl   = "https://m.media-amazon.com/images/M/MV5BZmE2ZDQ2ZjYtYjMwMy00YWQ2LThmNTYtZWE0YmNkNDlhOTRkXkEyXkFqcGc@.jpg"
        }
        "4" = [ordered]@{
            Key        = "tuxamber"
            Name       = "Tux Classic Linux"
            Desc       = "Klassisch puristisches Distro-Thema (Anthrazit & Gold, bewusst OHNE Hintergrundbild)"
            Title      = "TUX MULTIBOOT // LINUX SYSTEM REPOSITORY"
            TitleColor = "#f59e0b"
            Bg1        = "#18181b"
            Bg2        = "#27272a"
            Header     = "#2e2e33"
            Accent     = "#f59e0b"
            Text       = "#fde68a"
            SelBg      = "#f59e0b"
            SelFg      = "#18181b"
            ImageUrl   = $null
        }
        "5" = [ordered]@{
            Key        = "crimson"
            Name       = "Crimson Security & Audit"
            Desc       = "Security & Pentest, Mr. Robot Blood Crimson Red Artwork"
            Title      = "CRIMSON SECURITY // RED TEAM AUDIT & RECOVERY"
            TitleColor = "#ef4444"
            Bg1        = "#0c0505"
            Bg2        = "#1f0a0a"
            Header     = "#2e0f0f"
            Accent     = "#ef4444"
            Text       = "#fca5a5"
            SelBg      = "#ef4444"
            SelFg      = "#0c0505"
            ImageUrl   = "https://m.media-amazon.com/images/M/MV5BMjI2MDY5Mzk4NV5BMl5BanBnXkFtZTgwMTUyMzk3MjE@.jpg"
        }
        "6" = [ordered]@{
            Key        = "synthwave"
            Name       = "Synthwave Neon Retro"
            Desc       = "80s Retro-Wave, Cyberpunk Hackers (1995) Hot Pink & Cyan Neon"
            Title      = "SYNTHWAVE MULTIBOOT // RETRO-WAVE"
            TitleColor = "#f472b6"
            Bg1        = "#13071f"
            Bg2        = "#280b3d"
            Header     = "#381054"
            Accent     = "#ec4899"
            Text       = "#e879f9"
            SelBg      = "#ec4899"
            SelFg      = "#13071f"
            ImageUrl   = "https://m.media-amazon.com/images/M/MV5BNjlhNDgxZWMtYWNjMy00NDE3LTlkNjEtNDYwNTQwNWViMDllXkEyXkFqcGc@.jpg"
        }
        "7" = [ordered]@{
            Key        = "medicatdark"
            Name       = "MediCat Dark Glass"
            Desc       = "MediCat 9-Slice Box-Design mit edlem, dunklem Anthrazit-/Glas-Hintergrund (ohne Wallpaper)"
            Title      = "MEDICAT MULTIBOOT TOOLKIT // DARK GLASS EDITION"
            TitleColor = "#38bdf8"
            Bg1        = "#0a0e17"
            Bg2        = "#121824"
            Header     = "#141c2b"
            Accent     = "#38bdf8"
            Text       = "#94a3b8"
            SelBg      = "#1e293b"
            SelFg      = "#38bdf8"
            ImageUrl   = $null
        }
    }
}

function Select-VentoyThemeInteractive {
    param([string]$DefaultChoice = "1")

    $themes = Get-VentoyThemeDefinitions
    Write-Host "`n=========================================================" -ForegroundColor Cyan
    Write-Host " VENTOY THEME AUSWAHL (7 Themen)" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan

    foreach ($k in $themes.Keys) {
        $t = $themes[$k]
        $defMarker = if ($k -eq $DefaultChoice -or $t.Key -eq $DefaultChoice) { " [Aktuell / Standard]" } else { "" }
        Write-Host " [$k] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($t.Name)" -NoNewline -ForegroundColor White
        if ($defMarker) { Write-Host "$defMarker" -ForegroundColor Green } else { Write-Host "" }
        Write-Host "     $($t.Desc)" -ForegroundColor DarkGray
    }
    Write-Host ""
    $choice = Read-Host "Bitte Nummer des Ventoy-Themes eingeben (1-7) [Standard: $DefaultChoice]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $DefaultChoice
    }
    foreach ($k in $themes.Keys) {
        if ($themes[$k].Key -eq $choice.ToLower()) {
            return $k
        }
    }
    if (-not $themes.Contains($choice)) {
        $choice = "1"
    }
    return $choice
}

function Get-MediCatThemeAssets {
    $b64 = "H4sIAAAAAAAC/+192XLi2pbtr1ScV9+4SELCUBHnQT0CtISEGqSXChBYPWDTqKmof79DOG3jvLnTeGflPrnz4AjSJEYTrW6sMcecc/Hf/yjWm+N/hf93t4n+8Z//8Y/EFQyrpMZqtOXxQ2ZOLDtR+9Rs/5FF3scvcdcPuLv2BXEuaN5cx7PuvH0/XSrieHRg8Vx9ZHLHG1q+7ZQ9nxkcJoWSLZlRPtnEh5B//plKAzZUlXTBuJSmjvKAyY/T2eR0vO8nmppn09loThyqtOeCFHjxbjbc1YFLenZupevikBqemUwbNpoOo95apcul51L+TGCXXnUMmx2L6+NAHSSBvWv/fwjmVjyptWgt7djlXKAWDZWYnnXyCyfyZNrUZHIK8ZwkbDnx9FKX/Ig02TFQlcT3SOInZaSnfK3P+iUR+xURKbxn2xj2liIiH2kvj7S9p1EWpLuZJfsR7m2/3Oi9sLAK3NN2NbRKI+mfVt1Vd7IJm0kxqIO6Xxl2xk0avp40Wj2Z4/qEbtYeR/nz6IDr0wu7cjAnaVjk5UrNT8tEqAPV7/ne6LSamwMt0V4/s+2Xy8/Ea0f/uc3H87h04zhEWyYpf9KS177LfPTNYmhRobQ9TboCHRblcdkdbSaMlU4Ydx94dL7cWM2kkY/oj0QbxoelyjXGRtguu9YpZOJTKF3YYLjmdQ4U5LScDcqFOqCWXYL38yd9hj6v39+37VADrYip1ZDvTerBMay55/GccemSoU5rVSnPny8ODst390Aoax5Q17Y7pC0uVJ2TU7jNsuvWPuMqq8I9rkT9bDOUdlJYuPFKHdSuOjgtpbd546jxCa83aEupSRrsadFYWe2WhYXx1XfnPp3zPbM7yv25lVuqQgU2lZznkUhVeNS6a1bE3pakpkrSbEtdPPdDaWT0KVDzYu1Y+GxnoKVaqafyAfPyoKfE0W29R+yopzfta2FPl/iX+yXtXMe8pfzPXKtaqVEEWAN0vGrHzqPjgHFOocpt0I7L8eqZzGCP+UCWjJVPZ1rz9d9nDpGc4egUFPm+bW9Ij4ZmIowsR2d0O2NIQtWTVH6+X5kmRpYfw64VLwuSzxzM4RYnRG638MweafiuzriZn+oHUpDYryk6sM16YkdcYMuHQJJZw85zH31q2Er+3OcCse2dvGQIDVw4ruRcxnxoxwLrOc+Mwm9gl9WZIJvYQmJ4+iFIfeAHxRLbpyfeKCM2iYm0in2bJC9jgjnZs7ujXYtVvlf9b9q/06Tq5b61xZygL0fcNOH7LW4YOclD+3X97xczoVnJLrOSdrHftXZLhsVaIXXgYX4BF7Xh8xowij/u1yDVu7oUNUFhHnRV4/yaLkgKjLQjmqTOwS9MWmdkijBKrDNaiX59+czuQnWB1VqtS1o5sWU8tMqVZNpI+e7E5rv4ffn+ZskE1IpR6sBRNgEwDX0lPK9lwbyYN8BXrOeE37roX/y9G9ZZMmk+aPeGxFiv2cXn7ZbAAN/j0sB5G5eFh3FJQ1ZvfC5QNdxnSPlNdPBtjdJndGJIchfjkgd2EOupUwe2w/jAJPSfstqYvRUT58v0Yu3OsHYVs90DakPCHpBQJX6f1+/LNSEzKFbDVQz8EAIG8+SPsQPrgf8aO17aky5U5YjrsSdqwOl+O1fOmL9Us9fPwh5FLbwBxmXU+PMgDy7uY+FxzQo2gG0jC/fQzuVJke8CaYs5EDaBZyV6TTE+o6QT282JpB0MKc/RL5mOdWZ4boKx5nTPeZtbm9U28NgrcenlGnIKNlbXn49y01thD8GczJ73BU252DtE9HHCUpoYz3Hv2bK7asazt/b4TIw5vcoDtAX7xqldJ5PueY7YwVxG/5Snl/U6U/Omxe51u37EwbnfLNVtfKzjcHieQ+f3P6+zkWyl5/exRrtWVDpfqWd7nfVQiH3mkK9EIV8W7VrSWv5hU9zD6EyQMNdM19Q8hkS+yrMRG4wUUKfNk66Xi7utMDnzKH7muIY15kRf0/75j//zH88sbP0hCxPYSxYWPPiDhxsLu7GwGwv7V7MwEwgn9/Q0/BMs7BvX/qIsLEgjBjtAA5Z18BnsBCLFgoW1TAasIToQG6+pMofdFO8DX7iOhZVBqnV1G2vN0yqsH/SDSRkzivObFZiIW+h2WJFU5gIpKo3Ps7DP2v8XsDChwPhXQJaDnyrAG8w/yeQmdp4SRj4Qz69II2O80B6JZ38PFuagf0ax4Tm4Z50hYMfElik9obgAs2niuWkgCXFQuIVh+wwRr2JhDR60/rdkYbvCkHxgQ+sJ0KmfZuiXGCysZeE+Y4gUreM1387BTPG+xr+ChX0Ll35XFnY/KCnl8UyQqDML83PvmYXplMDS6qTn8+gE+i5ejBO9c2Y+LQ5y8lM2iqLon29MbHOlHrZ+ZmL85DS5k25M7MbEbkzsV2BiTk+3/T/JxL669hdlYtBlOPjXlN6YB9+TWVxLGZKJNapkeqEfDBW6UqNBIwOD8Eh6HRMza73RaaI61MSD7uM50Kscyk+gi+CzJq0W0gjYpfJE90jm159lYp+2/9czMbBbvQEzsU1oik4VzKCH2VYC5sihf8FQoJipPmuASfpY978FEyt02lD1ruHJGBcH7fcPBgbVEDEuXtuOFRiY1oAdsz6eX6mHtUysafeDvyETSwIpozHeuH8a2mzETGyTJRK8Hs+soT2zPiN39dTNoenSPqNfycS+xqXflYlxUrFcnQmS6rwwsWm/0+l3+GYUDSemaA6rwtXERz4SHu5m3cpJhtriu4zsWnHshZLd6+Ne8gElGxo3SnajZP9+lOxbsPpzKZmt9Vr4/FOU7Otrf1FKZnhYf7YS+6BffsOX2ArhpLehtIxCqOlAGL/0UwQE7HbrMKmrKFlqQqRSQOVCGnSCCTy/DXVSEIhAR+Ji0n5mqkO4wlbljRI9+SQl+7z9dpt914eWOkhXz+tMaPslbNfVRn/djs1C2bxStqLaTZ/7LGv7TPcUhGz9KpDOAkUFypES22wmALrARp+1wlCDfmsghKAfX7YqbPFv21MG/GzO29O19/WXUkoi5anuyV3SOJjToCBJG06zCswL1oAY6bf92uQZkUAlCq3+ayilBjz6meJeVmENsKRZoZ06FUCAQvsp4AjmUpy34WXD8xvdC2JDHRXGH4l7WEMElNJQ4Dpg/8KjOr/W/AillP8VIVYO4xzr7Xqq6RQ4VmH8GqLKoNpW5idUFyIwws9xDjG6hvh7HaX8/3D1tw2xMidld6aUwVncs7TqrjvbmwyvC7xczh0pnlqK1usNg13J7R/KQWHOhpj9ZY1NuO8km4CtBS0ql6SoWNVcJpz9ZEb8KPONh5g96o8hL+2W3Zjhd3txs4ln5XA4nWyHTw+TyMwVt3RChQjz0B1qPlGbRb/Lu0WMLYuJh4M4+h51LX8GdV17N+p6o6436vrzqasOaI3+JHX96tpfNa6LLK8gxVaMWFNg8xWpacQZW4oS5z6y60iBtWqHNJGs2E81+jo1Uaf1hiCTCmqf7ca6CkUNtBf3xfppnkFRo0B/oA5ZOX4zn6aun7f/C1HXV1px90wRrJYiUFCTKt8Ouy3lIYh7QiWtiNqqcXAbEihRhdYAk6H6uqDl2stWvF9cbLkv9wxMucCJy3E605PzVh2esf1lfsS75/a/3Z/DuNVl+9/orpKecRE0zf+y7q5U1tBHOjLNHBrYTvu2gHHyKYI1YyD7MIDiSOB2YM1gDcdFq1t/mwaB8th4pArWGVQ16Yfjm+VXFOj0UbtDRmGudQF8e1QEnsagPQe4gqU/O88VFnkTaeDJcAGsjDQCYr2IVTZ69w9cgJYytm4a6+I5XLcSMXTmh92A2Xs34K09ZAtqj+vb/a7/v6w4BxlyGhgoq8gdcVpsgdsZtW4ni/5AO6GyIxMTfYTrtZrMvuMeAOd0GutEgmsAbEec/AfdA/MT7sELnf3iNoLOfsu1/LJO33OK9G3NOpmlPr/vgme19t7xN/fY0vAw0TrTwhSpZUsDhaeZYwmunA7vV1ol7vlIli3r5Ejjrn6crEdcWO05tSsdDkIiCyJ3NO+FsR+5d51gO34Utn3RD8eyaN+pyuBgWZFD0yO1353MNPlx+2DKB9ZkQ8HQh5aKDT3QmvFqYT/yXjhc6ZIiMtw6nK7F2Bbicmt1hKD/4INSyEtqz5rfocT7W3z9xohvjPhvGl9vH3820/Hra3/ZTEeItI3TtGIuSf0u+olp2S9YZYMdCYzYSiCWchD0sHOH9XVirlyCXUP0a3dtcGobngHjnDPeIAzT7fo3wL51NYhJ4XeD2WfF3E/b/8vFUN0WcrA7iOCYE4wP1kw1z3U8edJ6HxANOez8ZVDITJCu8t8j0xEsLzXB6LVmYo8gtmeYUzo8FTrWi7YGBeu0wGd57ZhprC5eWW9ib88M6O+Y6QjG16D2CWIo1lUaog/gBUAM9VPUdiUUE7R7c5qhz0wI59qVYqj5b5Lp2FscZunwMtNR9V7rTYaCsxiDKbGhchdv171sUH6Pif2MuPqNit2o2E2c/EuoGJK77exPUrGvrv1FqZiOElWUYxbn2HQbG0P5bJBaeSue+E0L904XRRGIJ5o0iifi66iYEreCjO6ZZ+rQUiW/jU/WdEw8B3TEabDCGF3VQVUcjny26OTz9v96KvZJAfP3iEujuCLV29RT3GfWbdM8EYVuKTLbpn1OWnra5DlpkO4HIQolFtfFpdt0R/FvGZdGSu4qJ8U5LyFvU4YnrfCqtkUnJD1jko1yaclB3B7lv558JRX7Gpd+21RHbWoOzgRp/haXtvdml9f4SqbCvjhGCoRla9N6IKLNsy0R2S11HD3dP86eNnWz5Md32ziiEJdu/L06lOL9gHlci7toG45P8bzkaVPpanG2jaktM+eHk6cgu5/Yh4zriW6n2SXG8dAxTGk06Q2e6phxF9Eflxjvy1sa5Y3u3eje35fuIU3sT9O9d9f+qnQP9cM4bQTUDvefOue4JyowkDIWY122ahwP+qdzUOUYokJTua7GGEqCA/XLRV2pyertto/YEsagPQmkaas7gqKtEW5jqz71+Vj0p+3f0ig/XSON9FSb59o6YcQKq7YyA2lyoHERqDRSbtO88FFDTdpUVahtvwVdLRSMl4schxHSiKH6FagPP88fuECokoIbUfmeU5HW1VCdmlxPV+u/KV1F/XPWxbVpq4QSu01RltuKMuQPjNpToXDuAPIHGmBOe9IS419NV9/j6m+bRinvT+UzXc1e6aqzNzPQ1RILI+F38yOXTA3WlrZLaqHgqB9vcKfNO/2pK8xELaEyObdHUXmOG1vTO9Fjt8fxKLJCeST4D0G0FeZatGP2VSY8ddLhnaBs/PruxAZ0xPQ4hhusHxpeWmFTP83y+MB8T50sbyfi3Njqja3+fU/EwW78p0/EeXftr1r0g5rroIBAWeAMQhRv4Gw/nI6DeYidyUBGIupmuwSMMFDlBqficNeJk6jZbpCx2J7D5ulgLfyhzXLU2+w4BtlRXgAhRkP8DMnrjJt8Pk78aft/OdtDJmQXO3jTMn6/wfwQIU7ZbX271m0zUtHXld8KeYWFDLrRbxIntmIIxZUurXBepMyQtp32M9vDZtU9tz2Nn2PJHvp9dl2cGOu3Nv6Wddhb1FwLOEUTNeeow/fTlgWThKjt+QY+G6CYCPFeGgVFGc7PxKk42dUn4rzHpd/2RJyHB/Io/+iJOPt1vg4PV5wRvTlzseyLcjj30gf/PRfb220un1zKfLErz3/rPLNQdmN0vT3WA29ZMjXfTLStFi1Va+X1KLcY7Zeer0Q8c/d0N+TK5nETxZvVenrSq3p9MJaRjEqzu6AJ+8VpsBp1d+N+w/VWAi/x/mzZraneurnDvRkCm99jxHmJVfv+lB+Lct/U+bE67KPdY1Xqoxx9okqlGMVTWeLFOG77ZBZHHdDjWRX1+a1mV3zJb/0H0FZ5609LkZf3/xpb4r4pesETGVD3x6AP5joUo2YVSnS8NUf7aLTost8Ugvd5slo/XTGewrszv415ded9NJ4T+et6/7E5ncXLpp/yDCq1hGk67U868f6hm1qFWY0KjcoiTT2xMo+M/rGwyL314/5797258r615/uWuM2qc/jovrPn9bHNFoxJmYykQ7y/7/H4LVh6NF5FWmM2brSzZWE4E021x0+Ejpc9ZfbWlU/ePAjuHpCWobGjQTU299n0PiOrfaNtCh55GiPuoMZSv8jvFtRO6oiP/WjY3SrsWOIyLRoMvJNbdv0FrxfFOFP5UhSjMi+czSkX0vD+yKgTskrX9nqaqIRM42rDrSLLo5jtZkWthSJfDtggZ/ldOps0apEEyblNvJwrdjY7moUoXvTf/mf034Pzpf8+Ne7jUn1IBGFK+YtU1gM1iLqZuF+sUsePU5YyhrFZ+mocuXIxCfnHeNGJ2i2NrzrqlHVkSaB41yRCIcgp46ooo2S9uwWfSn2JL41eFeXYmrl9PJTLwVifOPyW76v9bdDn2b1dfnOOHdZPRbJZ5P+13FZXrJAztvLJl546uau76fnUi7mlwMO0X5mFKbwwitHSA8twwbg9MPswz88X1MrOVWIKnp5unD2QV2+iZQfPP+9RHtmH2I2x49/fHzvYjXftbuM2LtFlujQZd7twYnh1rr3OOMfv7p58lBhr6Xl3vtw93rwaXP/FC+m1/3/2WFvP5dmDXan7i90wJo4oSGCBuSY5RzJrS1plSpNCDsyZxi7L6rOzR1rpdb/EA7/BSlLk56OEl8x+K4/0CzP+rkfJ+vMvniRDHy69SbCGGVIbrvUmG3eYl8FsMEObcP/ILMRcCpJPeoMyznb+ir28MpLvhIrNRucsO6taDZm0Y+s4jWk7tSWPZLBWycxcxZID8fKMzgv9+MKe9d5e+qG9Sw8E4znataza2ozQt2CiSpst+N0MTAlhfcWwZSgiJjRCubJsAmMj2czMkkAjsRxXtjLt+WzNZ3vZH3tQr/aoj+1d1IlkVh4ypF60Ck/Lht+YYTv3n5nhswJ0VoTav0+7cQn2/BTMzQjeSas81e06PtL17rEFahnjJCvOmjztKV4WeJHXy7Gw63DN1Df7U9lO3QOJD4YpiwIfQUkSz5v6959LfIcDeygFe1fKj6OuN9/+QT3HO8S8IpnwEjEFz3Q3wxti3hDz90TMnQpE61qyhgQ1IJzjnxHOkIloOoFsprmE8aPwHRHldYh5Yc/+0N6PIWbmA9FWsBkyQDjaSluE01mTGglWZomGQ+CLmvjeAP46xHyz1/3Y3s9BzBUZinSLYiL9BTFxzpsqRGs94NWToHBYew4fq5IV0T4WnGOSi+dTk3eAkKZAt/k4ZbVLNtEViLi5kkOaX7ysgutmuxsi3hDxN+WQpQkOZto+qqsuOJ+jVaZDBDMFf8JhWaatSGZ9FYd8tUekD+39IIcUBL3leMgxuOR8ZqoIJqWIemZJVhYIOqIL13HIV3v1x/Z+DiJm0IsPLSJK8RuHjGQC4UznM7k367inoNkyw0G5USdRObOXAB5zuBXoqPPIDvl3P4JJVwSItuJ4O1qbd0r3WyrEe3S8ljB+gUf+od8ZxDd4vMHjbwqPHEFxpC475dkl/kLwzCyQiDwS4RqX+H9pNoKiXwePb/aaD+39IDxmOIA6Ki2bp94IHtzgTKfMbASjPP4vSLiX5jp4fLVHf2zv58CjJzYq1+qERPgCj49hRlHjMuVNK3lIHo9P43E3kgjD9qNoP2Vdph/Pt8LybvggLXdWJWuKM7djiYmqh70sx6kSUVE4LWJzvfHNR614shH+6Zfpse/FHRnfXmBbE5VPq33fy/bKUF2zZo/fqjV/P9/eazMzqO+YpiCzfjcEAu6nonxIG5HntMFQNziOOsws5b7Db9kd4o7LMC9NTwvVuWpmA2yF0qMslJVk3AlOmin+bsMr4d43DuOFN5tls0hcHpKnirX1oS0fY3m50HJa3hhaYDyc+p3+Eymkbd+Z70Vp0BcEnJ3WH+ghHY4e99uPxdRrTkG7Qf0N6v9toB7fAYkCMEdjLn15M9NrAuanw58H5IHR6t0rmfCrPfNjez8I9fhuyMavTJyLcAnNZqMxlqxX8OdVvWW0zepKJvxqj/3Y3s+B+tl95/n48cnhBeozZy8TQL2+EseiZSiCO08cq+8M944G6UIWE/7hPq34Y+XMhZ1oeiOa2RtPveYpDNj7GgBLNf2jKcxll9qq620txKciSxYm0QQ2PogC8eYlsKyK7hFko2eAJN27rwjtLzSb0chwbwzDHiNWbJ+dmfNo6HG7cnhQR/sZzfK9u477JIUP/rFUNqugvzryK3ZXTWJ5KhzjdfLQD+nNztRmdedJSOaVbD5GHOvstXyzPvALY6Q+HcxA5UaNx4r9vmBFvJZmrl9PC0emPobz/U3XuKH5Dc1f0bwyHI2GDoGY1psOAQKLnNQI2gTqPiRLNRtFIMlVaP5qz5I+tPeDaC5zZupChxgJbzqEzhpSoBpSiLP5EM+SA+wgMnMdmr/aEz+293PQfB5uN+vyE7qG1xsbdTa9VDNM9dQcKsTAZOFgs+Cmsi3zdpIszefzNL6ra+xvusYNHm/w+BYIa0P5MrEF1XynQ5i06SCUnuoMpE6ZUDqrXwWPb/Ys6UN7PxgIa0P5+LIqORDe6RCSK7TkGoeZIvHI7JpNVF8XCHu1J35s7+fAY5Xt+2ELYjp5JbsZLbe6hh6n08ra3Ut+N3lELtWwr1PpeKqrpyTSou3IV9dpj5WWT0M29stdRITN/XbDjU/L1a6wkEbvsVWq9/hOWe62OT/wSrnLMdGTP17fHSKtWw/6VSmWvUV/ski7w2DrDZnH5HFvRllnVZrjxeOqtCJ5P/b5TU6Jp3E+S9f9Hj8NtWVBKbuHIahupGwltcicrDxs6QelNHh2u4o7UqQoiUzvuQN7tB99YZbsBj02XkfRI4u0banHy/KCmxaKafaDh+7AEO74A7phMXHl4zy+e6KvSXHY33SMG7TfoP0N2gWzsRT45gq5zHFA/YIhO5QlnXMVmvbblcl1OQ5v9uwP7f0gtCuQwXEQD+XUFzkJHL6jjbVsKA9pyBn2uSaIug7aX+01H9v7OdC+eaJV4Qzt8bscB5z5yAvBPpjxgi4Jppjxww6lz+4y5olfNrNq0DMXfZ4m9xK7E1LkPeOrNfq1MdqbYqUsZVXntUqphKdtnJUCmyjJw0Ts4Md079kksRmB2fLhjOXVvYTiiGgrFvZkG2Y5j9xbx1zwql/rdSaMeZHhKVbyCzqSvLGCRjwWVfT0qGZFX8h4wpteyMcBvdVEmvdGE01ZqLifSRwpWrxPeUXgV0KRqHtZk1yf3/M9UY3EyBobMFkCcEWHGSZSES9HwRZfksnPkO4ve8V4j5KHqB5+yNzLWwbbDd1v6P6K7lCNCbKzTO6dqoxT8K02xyLDmDt6bUhEsGZXofubvfRDez+I7lCNKY2Dg/BOVSZUoCDHAoQ7qqAwAxYU5Tp0f7XHfWzv56D7uhN4Z5n6qwy29+g+E99nrr08N/kVWCkqvmI/kh/1e74+fav2/n/+H1FWCQ0UkAAA"
    $bytes = [System.Convert]::FromBase64String($b64)
    $msIn = New-Object System.IO.MemoryStream(,$bytes)
    $gz = New-Object System.IO.Compression.GZipStream($msIn, [System.IO.Compression.CompressionMode]::Decompress)
    $msOut = New-Object System.IO.MemoryStream
    $gz.CopyTo($msOut)
    $gz.Dispose()
    $msIn.Dispose()
    $json = [System.Text.Encoding]::UTF8.GetString($msOut.ToArray())
    $msOut.Dispose()
    return ($json | ConvertFrom-Json)
}

function Install-VentoyTheme {
    param(
        [string]$VentoyDir,
        [string]$ThemeChoice = "1",
        [switch]$Force,
        [switch]$DryRun
    )

    $themes = Get-VentoyThemeDefinitions
    $selectedTheme = $themes["1"]
    if ($themes.Contains($ThemeChoice)) {
        $selectedTheme = $themes[$ThemeChoice]
    } else {
        foreach ($k in $themes.Keys) {
            if ($themes[$k].Key -eq $ThemeChoice.ToLower()) {
                $selectedTheme = $themes[$k]
                break
            }
        }
    }

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Wuerde Ventoy-Theme '$($selectedTheme.Name)' (1080p) auf '$VentoyDir' einrichten." -Color Cyan -Level "INFO"
        return
    }

    $themeDir = Join-Path $VentoyDir "theme"
    $bgPath = Join-Path $themeDir "background.png"
    $selPath = Join-Path $themeDir "select_c.png"
    $themeTxtPath = Join-Path $themeDir "theme.txt"
    $activeRecordPath = Join-Path $VentoyDir "theme_active.txt"

    if (-not $Force -and (Test-Path $activeRecordPath)) {
        $existingTheme = (Get-Content $activeRecordPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($existingTheme -eq $selectedTheme.Key -and (Test-Path $bgPath) -and (Test-Path $selPath) -and (Test-Path $themeTxtPath)) {
            Write-Log -Message "[VENTOY] Theme '$($selectedTheme.Name)' ist bereits aktiv auf Ziel-Laufwerk." -Color DarkGreen -Level "OK"
            return
        }
    }

    if (-not (Test-Path $themeDir)) {
        New-Item -ItemType Directory -Path $themeDir -Force | Out-Null
    }

    try {
        Add-Type -AssemblyName System.Drawing
        $width = 1920
        $height = 1080

        if ($selectedTheme.ImageUrl) {
            $tempImgFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ventoy_bg_$([System.IO.Path]::GetRandomFileName()).jpg")
            $imgDownloaded = $false
            try {
                Write-Log -Message "[VENTOY] Lade Theme-Hintergrundbild herunter..." -Color Cyan -Level "THEME"
                Invoke-WebRequest -Uri $selectedTheme.ImageUrl -OutFile $tempImgFile -UseBasicParsing -TimeoutSec 30
                if ((Test-Path $tempImgFile) -and (Get-Item $tempImgFile).Length -gt 0) {
                    $imgDownloaded = $true
                    $srcImg = [System.Drawing.Image]::FromFile($tempImgFile)
                    $bmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
                    $g = [System.Drawing.Graphics]::FromImage($bmp)
                    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

                    # Bild auf 1920x1080 skalieren
                    $g.DrawImage($srcImg, 0, 0, $width, $height)

                    # Dezente halbtransparente Header- und Footer-Balken fuer erstklassige Menue-Lesbarkeit
                    $hdrColor = [System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Header)
                    $hdrBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, $hdrColor.R, $hdrColor.G, $hdrColor.B))
                    $g.FillRectangle($hdrBrush, (New-Object System.Drawing.Rectangle 0, 0, $width, 80))
                    $g.FillRectangle($hdrBrush, (New-Object System.Drawing.Rectangle 0, 1020, $width, 60))

                    # Akzentlinien oben und unten
                    $accentPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Accent)), 3
                    $g.DrawLine($accentPen, 0, 80, $width, 80)
                    $g.DrawLine($accentPen, 0, 1020, $width, 1020)

                    $bmp.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
                    $g.Dispose(); $bmp.Dispose(); $srcImg.Dispose()
                    Write-Log -Message "[VENTOY] Hintergrundbild fuer '$($selectedTheme.Name)' erfolgreich auf Ventoy-Laufwerk eingerichtet." -Color Green -Level "OK"
                }
            } catch {
                Write-Log -Message "[VENTOY] Download des Theme-Bildes fehlgeschlagen: $_. Verwende Farbverlauf als Fallback." -Color Yellow -Level "WARNUNG"
            } finally {
                # Heruntergeladenes Bild direkt wieder loeschen
                if (Test-Path $tempImgFile) {
                    Remove-Item -Path $tempImgFile -Force -ErrorAction SilentlyContinue
                }
            }

            if (-not $imgDownloaded) {
                # Fallback: Prozeduraler Farbverlauf
                $bmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $rect = New-Object System.Drawing.Rectangle 0, 0, $width, $height
                $c1 = [System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Bg1)
                $c2 = [System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Bg2)
                $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c2, 45.0
                $g.FillRectangle($brush, $rect)

                $headerRect = New-Object System.Drawing.Rectangle 0, 0, $width, 80
                $headerBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Header))
                $g.FillRectangle($headerBrush, $headerRect)
                $footerRect = New-Object System.Drawing.Rectangle 0, 1020, $width, 60
                $g.FillRectangle($headerBrush, $footerRect)

                $accentPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Accent)), 3
                $g.DrawLine($accentPen, 0, 80, $width, 80)
                $g.DrawLine($accentPen, 0, 1020, $width, 1020)

                $bmp.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $g.Dispose(); $bmp.Dispose()
            }
        } else {
            # Kein Hintergrundbild (z. B. Tux Classic Linux bewusst ohne Hintergrund)
            if (Test-Path $bgPath) {
                Remove-Item -Path $bgPath -Force -ErrorAction SilentlyContinue
            }
            Write-Log -Message "[VENTOY] Theme '$($selectedTheme.Name)' wird puristisch ohne Hintergrundbild eingerichtet." -Color Cyan -Level "THEME"
        }

        if ($selectedTheme.Key -eq "medicatdark") {
            # MediCat 9-Slice PNGs entpacken
            try {
                $assets = Get-MediCatThemeAssets
                foreach ($prop in $assets.PSObject.Properties) {
                    $assetFile = Join-Path $themeDir $prop.Name
                    $assetBytes = [System.Convert]::FromBase64String($prop.Value)
                    [System.IO.File]::WriteAllBytes($assetFile, $assetBytes)
                }
                Write-Log -Message "[VENTOY] MediCat 9-Slice Rahmen- und Terminal-Grafiken entpackt." -Color Cyan -Level "THEME"
            } catch {
                Write-Log -Message "[VENTOY] Fehler beim Entpacken der MediCat Theme-Assets: $_" -Color Yellow -Level "WARNUNG"
            }

            # Prozeduraler edler Dark-Glass Farbverlauf fuer background.png
            $bmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $rect = New-Object System.Drawing.Rectangle 0, 0, $width, $height
            $c1 = [System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Bg1)
            $c2 = [System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Bg2)
            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c2, 45.0
            $g.FillRectangle($brush, $rect)

            $headerRect = New-Object System.Drawing.Rectangle 0, 0, $width, 70
            $headerBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Header))
            $g.FillRectangle($headerBrush, $headerRect)
            $footerRect = New-Object System.Drawing.Rectangle 0, 1020, $width, 60
            $g.FillRectangle($headerBrush, $footerRect)

            $accentPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml($selectedTheme.Accent)), 2
            $g.DrawLine($accentPen, 0, 70, $width, 70)
            $g.DrawLine($accentPen, 0, 1020, $width, 1020)

            $bmp.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose(); $bmp.Dispose()
        } else {
            # Bereinige eventuelle 9-Slice PNGs von medicatdark, damit Standard-Themes sauber rendern
            Get-ChildItem -Path $themeDir -Filter "menu_*.png" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $themeDir -Filter "slider_*.png" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $themeDir -Filter "terminal_box_*.png" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

            # Selection bar (select_c.png)
            $bmpSel = New-Object System.Drawing.Bitmap(32, 36, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $gSel = [System.Drawing.Graphics]::FromImage($bmpSel)
            $rectSel = New-Object System.Drawing.Rectangle 0, 0, 32, 36
            $brushSel = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($selectedTheme.SelBg))
            $gSel.FillRectangle($brushSel, $rectSel)
            $bmpSel.Save($selPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $gSel.Dispose(); $bmpSel.Dispose()
        }
    } catch {
        Write-Log -Message "[VENTOY] Warnung beim Erstellen der Theme-Grafiken: $_" -Color Yellow -Level "WARNUNG"
    }

    if ($selectedTheme.Key -eq "medicatdark") {
        $themeTxtContent = @"
# Ventoy Theme: $($selectedTheme.Name)
desktop-image: "background.png"
title-text: " "
title-font: "ascii"
title-color: "$($selectedTheme.TitleColor)"
message-font: "ascii"
message-color: "$($selectedTheme.Text)"
terminal-box: "terminal_box_*.png"

+ hbox {
    top = 9%
    left = 20%
    width = 60%
    + vbox {
        + label {text = "$($selectedTheme.Title)" color = "$($selectedTheme.TitleColor)" align = "left"}
    }
}

+ boot_menu {
    left = 20%
    top = 16%
    width = 60%
    height = 72%
    menu_pixmap_style = "menu_*.png"
    item_font = "ascii"
    item_color = "$($selectedTheme.Text)"
    item_height = 34
    item_spacing = 4
    item_padding = 8
    selected_item_font = "ascii"
    selected_item_color = "$($selectedTheme.TitleColor)"
    selected_item_pixmap_style = "select_*.png"
    item_icon_space = 20
    scrollbar = true
    scrollbar_width = 10
    scrollbar_thumb = "slider_*.png"
}

+ label {
    left = 0%
    top = 95%
    width = 100%
    height = 30
    text = "[F1] Memdisk  |  [F2] Power  |  [F3] ListView/TreeView  |  [F4] Localboot  |  [F5] Tools"
    color = "$($selectedTheme.Text)"
    align = "center"
}
"@ -replace "`r`n", "`n"
    } else {
        $desktopImageLine = if ($selectedTheme.ImageUrl -and (Test-Path $bgPath)) { 'desktop-image: "background.png"' } else { '# bewusst kein Hintergrundbild' }

        $themeTxtContent = @"
# Ventoy Theme: $($selectedTheme.Name)
$desktopImageLine
desktop-color: "$($selectedTheme.Bg1)"
title-text: "$($selectedTheme.Title)"
title-color: "$($selectedTheme.TitleColor)"
message-color: "$($selectedTheme.Text)"

+ boot_menu {
    left = 10%
    top = 12%
    width = 80%
    height = 78%
    item_color = "$($selectedTheme.Text)"
    selected_item_color = "$($selectedTheme.SelFg)"
    selected_item_pixmap_style = "select_*.png"
    item_icon_space = 24
    item_height = 36
    item_padding = 10
    item_spacing = 4
}

+ label {
    left = 0%
    top = 95%
    width = 100%
    height = 30
    text = "[F1] Memdisk  |  [F2] Power  |  [F3] ListView/TreeView  |  [F4] Localboot  |  [F5] Tools"
    color = "$($selectedTheme.Text)"
    align = "center"
}
"@ -replace "`r`n", "`n"
    }

    try {
        [System.IO.File]::WriteAllText($themeTxtPath, $themeTxtContent, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($activeRecordPath, $selectedTheme.Key, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log -Message "[VENTOY] Theme '$($selectedTheme.Name)' (1080p) auf Ziel-Laufwerk eingerichtet." -Color Green -Level "ERFOLG"
    } catch {
        Write-Log -Message "[VENTOY] Fehler beim Schreiben von theme.txt ($themeTxtPath): $_" -Color Red -Level "FEHLER"
    }
}

function Get-AvailableUsbDrives {
    param(
        [switch]$IncludeVentoyOnly = $false
    )
    $usbLetters = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 1. Get-Disk USB-BusType
    try {
        $usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' }
        if ($usbDisks) {
            foreach ($d in $usbDisks) {
                $parts = $d | Get-Partition -ErrorAction SilentlyContinue
                foreach ($p in $parts) {
                    if ($p.DriveLetter) {
                        [void]$usbLetters.Add("$($p.DriveLetter):")
                    }
                }
            }
        }
    } catch {}

    # 2. Win32_DiskDrive WMI InterfaceType
    try {
        $usbDrivesWmi = Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -eq 'USB' -or $_.MediaType -match 'External|Removable' }
        foreach ($ud in $usbDrivesWmi) {
            $query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($ud.DeviceID)'} WHERE AssocClass = Win32_DiskDriveToDiskPartition"
            $partitions = Get-CimInstance -Query $query
            foreach ($part in $partitions) {
                $query2 = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'} WHERE AssocClass = Win32_LogicalDiskToPartition"
                $logicals = Get-CimInstance -Query $query2
                foreach ($log in $logicals) {
                    if ($log.DeviceID) {
                        [void]$usbLetters.Add($log.DeviceID)
                    }
                }
            }
        }
    } catch {}

    # 3. Win32_Volume mit DriveType 2 (Wechseldatentraeger)
    try {
        $remVolumes = Get-CimInstance Win32_Volume | Where-Object { $_.DriveType -eq 2 -and $_.DriveLetter }
        foreach ($rv in $remVolumes) {
            [void]$usbLetters.Add($rv.DriveLetter)
        }
    } catch {}

    # USB- und Ventoy-Volumes filtern (ohne VTOYEFI-Bootpartition und Winz-Partitionen < 0.5 GB)
    $vols = Get-CimInstance Win32_Volume | Where-Object {
        $_.DriveLetter -and $_.DriveLetter -ne "C:" -and (
            $usbLetters.Contains($_.DriveLetter) -or 
            $_.DriveType -eq 2 -or 
            $_.Label -match "Ventoy" -or
            (Test-Path "$($_.DriveLetter)\ventoy")
        )
    } | Select-Object DriveLetter, Label, FileSystem, DriveType,
        @{Name="FreeGB"; Expression={[math]::Round($_.FreeSpace/1GB, 2)}},
        @{Name="CapacityGB"; Expression={[math]::Round($_.Capacity/1GB, 2)}} |
        Where-Object { $_.Label -notmatch '(?i)VTOYEFI|EFI' -and $_.CapacityGB -ge 0.5 }

    # Fallback falls keine reinen USB-Flags erkannt wurden, aber Ventoy-Ordner vorhanden ist
    if (-not $vols -and -not $IncludeVentoyOnly) {
        $vols = Get-CimInstance Win32_Volume | Where-Object {
            $_.DriveLetter -and $_.DriveLetter -ne "C:" -and ($_.DriveType -eq 2 -or (Test-Path "$($_.DriveLetter)\ventoy"))
        } | Select-Object DriveLetter, Label, FileSystem, DriveType,
            @{Name="FreeGB"; Expression={[math]::Round($_.FreeSpace/1GB, 2)}},
            @{Name="CapacityGB"; Expression={[math]::Round($_.Capacity/1GB, 2)}} |
            Where-Object { $_.Label -notmatch '(?i)VTOYEFI|EFI' -and $_.CapacityGB -ge 0.5 }
    }

    return $vols
}

function Ensure-VentoyTarget {
    param(
        [string]$TargetDrive,
        [string]$ToolsDir = $null,
        [switch]$DryRun
    )
    if ([string]::IsNullOrWhiteSpace($TargetDrive)) { return $null }

    $driveLetter = $TargetDrive.TrimEnd('\').TrimEnd(':') + ":"
    $ventoyDir = "$driveLetter\ventoy"
    $targetVol = Get-CimInstance Win32_Volume | Where-Object { $_.DriveLetter -eq $driveLetter }
    $isVentoy = (Test-Path $ventoyDir) -or ($targetVol -and $targetVol.Label -match "Ventoy")

    if (-not $isVentoy) {
        Write-Host ""
        Write-Host "=========================================================" -ForegroundColor Yellow
        Write-Host " [HINWEIS] Auf Laufwerk $driveLetter wurde noch kein Ventoy gefunden!" -ForegroundColor Yellow
        Write-Host "=========================================================" -ForegroundColor Yellow
        Write-Host "Damit das Laufwerk bootfaehig ist, muss Ventoy darauf eingerichtet werden." -ForegroundColor White
        Write-Host ""
        $ans = Read-Host "Moechtest du Ventoy jetzt automatisch auf $driveLetter installieren? (J/n)"
        if ($ans -ne 'n' -and $ans -ne 'N') {
            Install-VentoyToDisk -TargetDrive $driveLetter -ToolsDir $ToolsDir -DryRun:$DryRun
        } else {
            Write-Log -Message "Ventoy-Installation uebersprungen. Fahre fort..." -Color Yellow -Level "WARNUNG"
        }
    }
    return $driveLetter
}

function Set-VentoyThemeStandalone {
    param(
        [string]$TargetDrive,
        [string]$ThemeChoice,
        [switch]$DryRun
    )

    Write-Host "`n=========================================================" -ForegroundColor Cyan
    Write-Host " VENTOY THEME KONFIGURATION" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($TargetDrive)) {
        $drives = Get-AvailableUsbDrives

        if (-not $drives) {
            Write-Log -Message "Keine angeschlossenen USB- oder Ventoy-Wechseldatentraeger gefunden!" -Color Red -Level "FEHLER"
            return
        }

        Write-Host "Verfuegbare USB- & Ventoy-Ziel-Laufwerke:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $drives.Count; $i++) {
            $d = $drives[$i]
            $labelStr = if ($d.Label) { "[$($d.Label)]" } else { "" }
            $hasVentoy = (Test-Path "$($d.DriveLetter)\ventoy") -or ($d.Label -match "Ventoy")
            $vMarker = if ($hasVentoy) { " [Ventoy bereit]" } else { " [Kein Ventoy]" }
            Write-Host " [$($i + 1)] $($d.DriveLetter) $labelStr ($($d.CapacityGB) GB, $($d.FileSystem))$vMarker" -ForegroundColor White
        }
        Write-Host ""
        $selection = Read-Host "Bitte Nummer des Ventoy-Laufwerks eingeben (1-$($drives.Count))"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $drives.Count) {
            $TargetDrive = $drives[[int]$selection - 1].DriveLetter
        } else {
            Write-Log -Message "Ungueltige Auswahl. Abbruch." -Color Red -Level "FEHLER"
            return
        }
    }

    $driveLetter = Ensure-VentoyTarget -TargetDrive $TargetDrive -ToolsDir (Join-Path $IsoDirectory "tools\ventoy") -DryRun:$DryRun
    if (-not $driveLetter -or -not (Test-Path "$driveLetter\")) {
        Write-Log -Message "Laufwerk $driveLetter existiert nicht oder ist nicht bereit!" -Color Red -Level "FEHLER"
        return
    }
    $ventoyDir = "$driveLetter\ventoy"

    $activeThemeFile = Join-Path $ventoyDir "theme_active.txt"
    $currentActive = "1"
    if (Test-Path $activeThemeFile) {
        $tVal = (Get-Content $activeThemeFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($tVal) { $currentActive = $tVal }
    }

    $chosenTheme = $ThemeChoice
    if ([string]::IsNullOrWhiteSpace($chosenTheme)) {
        $chosenTheme = Select-VentoyThemeInteractive -DefaultChoice $currentActive
    }

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Wuerde Ventoy-Theme auf Laufwerk $driveLetter anpassen." -Color Cyan -Level "INFO"
        Install-VentoyTheme -VentoyDir $ventoyDir -ThemeChoice $chosenTheme -Force -DryRun:$DryRun
        return
    }

    Install-VentoyTheme -VentoyDir $ventoyDir -ThemeChoice $chosenTheme -Force

    # ventoy.json theme Eintrag aktualisieren
    $ventoyJsonPath = Join-Path $ventoyDir "ventoy.json"
    try {
        $cfg = @{}
        if (Test-Path $ventoyJsonPath) {
            try { $cfg = (Get-Content $ventoyJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json } catch {}
        }
        if (-not $cfg) { $cfg = @{} }
        $themeBlock = @{
            "file" = "/ventoy/theme/theme.txt"
            "gfxmode" = "1920x1080"
            "display_mode" = "GUI"
        }
        $cfg | Add-Member -NotePropertyName "theme" -NotePropertyValue $themeBlock -Force
        $jsonOut = ($cfg | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($ventoyJsonPath, $jsonOut, (New-Object System.Text.UTF8Encoding($false)))
    } catch {}

    Write-Log -Message "Ventoy-Theme erfolgreich konfiguriert auf $driveLetter!" -Color Green -Level "ERFOLG"
}

function Find-OrInstallVentoy {
    param([string]$ToolsDir)

    # 1. PATH und WinGet-Verzeichnisse pruefen
    $candidates = @()
    $cmd = Get-Command Ventoy2Disk.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }

    if ($env:LOCALAPPDATA) {
        $wingetMatches = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter "Ventoy2Disk.exe" -Recurse -File -ErrorAction SilentlyContinue
        if ($wingetMatches) { $candidates += ($wingetMatches | Select-Object -ExpandProperty FullName) }
    }

    if ($ToolsDir -and (Test-Path $ToolsDir)) {
        $localMatches = Get-ChildItem -Path $ToolsDir -Filter "Ventoy2Disk.exe" -Recurse -File -ErrorAction SilentlyContinue
        if ($localMatches) { $candidates += ($localMatches | Select-Object -ExpandProperty FullName) }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            Write-Log -Message "Ventoy2Disk gefunden: $c" -Color DarkGray -Level "VENTOY"
            return $c
        }
    }

    # 2. Versuch: Automatische Installation via WinGet
    Write-Log -Message "Ventoy2Disk.exe nicht lokal gefunden. Versuche Installation..." -Color Yellow -Level "VENTOY"
    $hasWinget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($hasWinget) {
        Write-Log -Message "Installiere Ventoy via Windows Package Manager (winget)..." -Color Cyan -Level "VENTOY"
        try {
            $wingetProc = Start-Process -FilePath "winget.exe" -ArgumentList "install --id Ventoy.Ventoy -e --source winget --accept-source-agreements --accept-package-agreements --silent" -Wait -PassThru -NoNewWindow
            if ($wingetProc.ExitCode -eq 0) {
                Write-Log -Message "Ventoy erfolgreich via winget installiert." -Color Green -Level "VENTOY"
                if ($env:LOCALAPPDATA) {
                    $postWinget = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter "Ventoy2Disk.exe" -Recurse -File -ErrorAction SilentlyContinue
                    if ($postWinget) { return $postWinget[0].FullName }
                }
            }
        } catch {
            Write-Log -Message "winget-Installation fehlgeschlagen: $($_.Exception.Message)" -Color Yellow -Level "WARNUNG"
        }
    }

    # 3. Fallback: Direkter GitHub-Download des offiziellen Windows-Release-Zips
    Write-Log -Message "Lade offizielles Ventoy Windows-Paket von GitHub Releases herunter..." -Color Cyan -Level "VENTOY"
    $targetDir = if ($ToolsDir) { $ToolsDir } else { (Join-Path $IsoDirectory "tools\ventoy") }
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

    try {
        $apiResp = Invoke-RestMethod -Uri "https://api.github.com/repos/ventoy/Ventoy/releases/latest" -Headers @{ "User-Agent" = "Linux-ISO-Updater" } -ErrorAction Stop
        $asset = $apiResp.assets | Where-Object { $_.name -match '^ventoy-.*-windows\.zip$' } | Select-Object -First 1
        if (-not $asset) {
            throw "Kein passendes Release-Asset (ventoy-*-windows.zip) auf GitHub gefunden."
        }

        $tempZip = Join-Path $env:TEMP $asset.name
        Write-Log -Message "Download: $($asset.browser_download_url) ($([math]::Round($asset.size / 1MB, 2)) MB)..." -Color Cyan -Level "VENTOY"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -UserAgent "Linux-ISO-Updater" -UseBasicParsing

        Write-Log -Message "Entpacke Ventoy nach: $targetDir..." -Color Cyan -Level "VENTOY"
        Expand-Archive -Path $tempZip -DestinationPath $targetDir -Force
        Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue

        $downloadedExe = Get-ChildItem -Path $targetDir -Filter "Ventoy2Disk.exe" -Recurse -File | Select-Object -First 1
        if ($downloadedExe) {
            Write-Log -Message "Ventoy erfolgreich heruntergeladen und entpackt." -Color Green -Level "VENTOY"
            return $downloadedExe.FullName
        }
    } catch {
        Write-Log -Message "Automatischer Download von Ventoy fehlgeschlagen: $($_.Exception.Message)" -Color Red -Level "FEHLER"
    }

    return $null
}

function Install-VentoyToDisk {
    [CmdletBinding()]
    param(
        [string]$TargetDrive,
        [string]$ToolsDir,
        [switch]$DryRun
    )

    Write-Host "`n=========================================================" -ForegroundColor Cyan
    Write-Host " AUTOMATISIERTE VENTOY-INSTALLATION (CLI)" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan

    $ventoyExe = Find-OrInstallVentoy -ToolsDir $ToolsDir
    if (-not $ventoyExe -or -not (Test-Path $ventoyExe)) {
        Write-Log -Message "Ventoy2Disk.exe konnte weder lokal gefunden noch automatisch beschafft werden." -Color Red -Level "FEHLER"
        return
    }

    $ventoyDir = Split-Path -Path $ventoyExe -Parent

    if ([string]::IsNullOrWhiteSpace($TargetDrive)) {
        Write-Host "`nErmittle verfuegbare USB- & Wechseldatentraeger..." -ForegroundColor Cyan

        $drives = Get-AvailableUsbDrives

        if (-not $drives) {
            Write-Log -Message "Keine angeschlossenen USB-Wechseldatentraeger fuer die Ventoy-Installation gefunden!" -Color Red -Level "FEHLER"
            return
        }

        Write-Host "`nVerfuegbare USB-Ziel-Laufwerke fuer Ventoy-Installation:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $drives.Count; $i++) {
            $d = $drives[$i]
            $labelStr = if ($d.Label) { "[$($d.Label)]" } else { "" }
            $hasVentoy = (Test-Path "$($d.DriveLetter)\ventoy") -or ($d.Label -match "Ventoy")
            $vMarker = if ($hasVentoy) { " [Ventoy installiert]" } else { " [Neuinstallation moeglich]" }
            Write-Host " [$($i + 1)] $($d.DriveLetter) $labelStr ($($d.CapacityGB) GB Gesamt, $($d.FreeGB) GB frei, $($d.FileSystem))$vMarker" -ForegroundColor White
        }
        Write-Host ""
        $selection = Read-Host "Bitte Nummer des Ziellaufwerks fuer Ventoy eingeben (1-$($drives.Count))"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $drives.Count) {
            $TargetDrive = $drives[[int]$selection - 1].DriveLetter
        } else {
            Write-Log -Message "Ungueltige Auswahl. Ventoy-Installation abgebrochen." -Color Red -Level "FEHLER"
            return
        }
    }

    $driveLetter = $TargetDrive.TrimEnd('\').TrimEnd(':') + ":"

    # Pruefen, ob auf dem Laufwerk bereits Ventoy installiert ist
    $isVentoyInstalled = $false
    $targetVol = Get-CimInstance Win32_Volume | Where-Object { $_.DriveLetter -eq $driveLetter }
    if ($targetVol -and ($targetVol.Label -match "Ventoy" -or (Test-Path "$driveLetter\ventoy"))) {
        $isVentoyInstalled = $true
    }

    $installMode = "/I"
    if ($isVentoyInstalled) {
        Write-Host ""
        Write-Host "[HINWEIS] Auf Laufwerk $driveLetter scheint bereits Ventoy vorhanden zu sein!" -ForegroundColor Yellow
        Write-Host " [1] Neuinstallation (/I - Datentraeger neu formatieren mit GPT/NTFS, ALLE DATEN LOESCHEN)" -ForegroundColor Red
        Write-Host " [2] Aktualisierung (/U - Aktualisiert Ventoy-Bootcode, behaelt vorhandene ISOs & Dateien!)" -ForegroundColor Green
        Write-Host " [3] Abbrechen" -ForegroundColor Gray
        $modeChoice = Read-Host "Waehle eine Option (1, 2 oder 3)"
        if ($modeChoice -eq "2") {
            $installMode = "/U"
        } elseif ($modeChoice -eq "1") {
            $installMode = "/I"
        } else {
            Write-Log -Message "Ventoy-Installation durch Benutzer abgebrochen." -Color Yellow -Level "ABBRUCH"
            return
        }
    }

    if ($installMode -eq "/I") {
        Write-Host ""
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
        Write-Host " WARNUNG: Alle vorhandenen Daten auf Laufwerk $driveLetter werden UNWIDERRUFLICH GELOESCHT!" -ForegroundColor Red
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
        $confirm = Read-Host "Bist du VOLLKOMMEN SICHER, dass du Ventoy auf $driveLetter installieren willst? (j/N)"
        if ($confirm -ne 'j' -and $confirm -ne 'J' -and $confirm -ne 'ja') {
            Write-Log -Message "Installation aus Sicherheitsgruenden abgebrochen." -Color Yellow -Level "ABBRUCH"
            return
        }
    }

    $actionName = if ($installMode -eq "/I") { "Neuinstallation (GPT / NTFS)" } else { "Aktualisierung" }
    Write-Log -Message "Starte Ventoy $actionName auf Laufwerk $driveLetter (CLI-Modus ohne GUI)..." -Color Cyan -Level "VENTOY"

    $cliArgs = "VTOYCLI $installMode /Drive:$driveLetter /GPT /FS:NTFS"

    if ($DryRun) {
        Write-Log -Message "[DRY-RUN] Wuerde ausfuehren: $ventoyExe $cliArgs (im Ordner $ventoyDir)" -Color DarkGray -Level "DRY-RUN"
        return
    }

    # Alte Statusdateien aufraeumen
    $doneFile = Join-Path $ventoyDir "cli_done.txt"
    $percentFile = Join-Path $ventoyDir "cli_percent.txt"
    $logFile = Join-Path $ventoyDir "cli_log.txt"
    Remove-Item -Path $doneFile, $percentFile, $logFile -Force -ErrorAction SilentlyContinue

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    try {
        if ($isAdmin) {
            # Direkt ausfuehren mit Konsolenfortschritt
            $proc = Start-Process -FilePath $ventoyExe -ArgumentList $cliArgs -WorkingDirectory $ventoyDir -PassThru -NoNewWindow
            while (-not $proc.HasExited) {
                if (Test-Path $percentFile) {
                    try {
                        $pctText = (Get-Content $percentFile -Raw -ErrorAction SilentlyContinue).Trim()
                        if ($pctText -match '^\d+$') {
                            Write-Progress -Activity "Ventoy Installation auf $driveLetter" -Status "Fortschritt: $pctText%" -PercentComplete [int]$pctText
                        }
                    } catch {}
                }
                Start-Sleep -Milliseconds 400
            }
            Write-Progress -Activity "Ventoy Installation auf $driveLetter" -Completed
        } else {
            # Erfordert Administratorrechte -> Windows UAC Prompt
            Write-Log -Message "Ventoy2Disk benoetigt Administratorrechte zum Schreiben von Boot-Sektoren." -Color Yellow -Level "INFO"
            Write-Host "Fordere Administratorrechte an (UAC)..." -ForegroundColor Cyan
            $proc = Start-Process -FilePath $ventoyExe -ArgumentList $cliArgs -WorkingDirectory $ventoyDir -Verb RunAs -PassThru -Wait
        }

        # Status pruefen
        $success = $false
        if (Test-Path $doneFile) {
            $doneVal = (Get-Content $doneFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($doneVal -eq "0") {
                $success = $true
            }
        } elseif ($proc.ExitCode -eq 0) {
            $success = $true
        }

        if ($success) {
            Write-Log -Message "Ventoy wurde ERFOLGREICH auf $driveLetter eingerichtet!" -Color Green -Level "ERFOLG"
            $script:TargetDrive = $driveLetter
            Start-Sleep -Seconds 3
        } else {
            Write-Log -Message "Ventoy-Installation fehlgeschlagen!" -Color Red -Level "FEHLER"
            if (Test-Path $logFile) {
                $errContent = Get-Content $logFile -Tail 15 -ErrorAction SilentlyContinue
                Write-Host ($errContent -join "`n") -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Log -Message "Fehler beim Ausfuehren von Ventoy2Disk: $($_.Exception.Message)" -Color Red -Level "FEHLER"
    }
}

function Start-VentoyCopyJob {
    param(
        [string]$TargetDrive,
        [string]$SourceDir,
        [switch]$DryRun
    )

    $distrosJsonPath = Join-Path $SourceDir "distros.json"
    $distroPatterns = @()
    if (Test-Path $distrosJsonPath) {
        try {
            $rawJson = Get-Content $distrosJsonPath -Raw -Encoding UTF8
            $distroPatterns = $rawJson | ConvertFrom-Json
        } catch {}
    }

    $categoryFolders = Get-ChildItem -Path $SourceDir -Directory | Where-Object {
        $_.Name -notlike "*Archiv*" -and $_.Name -notlike "*scratch*" -and $_.Name -notlike ".*" -and $_.Name -notlike "*tools*"
    }

    $isoFilesToCopy = @()
    foreach ($folder in $categoryFolders) {
        $isos = Get-ChildItem -Path $folder.FullName -Recurse -File | Where-Object { $_.Extension -in '.iso', '.img' }
        foreach ($iso in $isos) {
            # Pruefen, ob die Distro in distros.json aktiviert ist
            $isDistroEnabled = $true
            if ($distroPatterns -and $distroPatterns.Count -gt 0) {
                $matchedDistro = $distroPatterns | Where-Object { $_.MatchPattern -and ($iso.Name -match $_.MatchPattern) } | Select-Object -First 1
                if ($matchedDistro -and $matchedDistro.PSObject.Properties['Enabled'] -and $matchedDistro.Enabled -eq $false) {
                    $isDistroEnabled = $false
                }
            }

            if (-not $isDistroEnabled) {
                continue
            }

            $relPath = $iso.FullName.Substring($SourceDir.TrimEnd('\').Length + 1)
            $isoFilesToCopy += [PSCustomObject]@{
                SourcePath     = $iso.FullName
                RelPath        = $relPath
                CategoryFolder = $folder.Name
                Filename       = $iso.Name
                SizeBytes      = $iso.Length
                SizeMB         = [math]::Round($iso.Length / 1MB, 2)
                SizeGB         = [math]::Round($iso.Length / 1GB, 2)
            }
        }
    }

    if ($isoFilesToCopy.Count -eq 0) {
        Write-Log -Message "Keine aktivierten ISO-Dateien zum Kopieren auf Ventoy im Quellverzeichnis gefunden." -Color Yellow -Level "WARNUNG"
        return
    }

    $totalBytesToCopy = ($isoFilesToCopy | Measure-Object -Property SizeBytes -Sum).Sum
    $totalGBToCopy = [math]::Round($totalBytesToCopy / 1GB, 2)

    if ([string]::IsNullOrWhiteSpace($TargetDrive)) {
        Write-Host "`n=========================================================" -ForegroundColor Cyan
        Write-Host " VENTOY ZIEL-LAUFWERK AUSWAHL" -ForegroundColor Cyan
        Write-Host "=========================================================" -ForegroundColor Cyan
        Write-Host " Benoetigter Speicherplatz fuer alle aktivierten ISOs: $totalGBToCopy GB ($($isoFilesToCopy.Count) Dateien)`n" -ForegroundColor Yellow
        
        $drives = Get-AvailableUsbDrives

        if (-not $drives) {
            Write-Log -Message "Keine angeschlossenen USB- oder Ventoy-Wechseldatentraeger gefunden!" -Color Red -Level "FEHLER"
            Write-Log -Message "Bitte schliesse deinen USB-Stick an oder gib das Ziellaufwerk mit -TargetDrive an (z.B. -TargetDrive E:)" -Color Yellow -Level "INFO"
            return
        }

        Write-Host "Verfuegbare USB- & Ventoy-Ziel-Laufwerke:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $drives.Count; $i++) {
            $d = $drives[$i]
            $labelStr = if ($d.Label) { "[$($d.Label)]" } else { "" }
            $hasVentoy = (Test-Path "$($d.DriveLetter)\ventoy") -or ($d.Label -match "Ventoy")
            $vMarker = if ($hasVentoy) { " [Ventoy bereit]" } else { " [Kein Ventoy]" }
            $spaceStatus = if ($d.FreeGB -ge $totalGBToCopy) {
                "--> [GENUG PLATZ]"
            } else {
                "--> [ZU WENIG PLATZ - fehlen ca. $([math]::Round($totalGBToCopy - $d.FreeGB, 2)) GB]"
            }
            $statusColor = if ($d.FreeGB -ge $totalGBToCopy) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }

            Write-Host " [$($i + 1)] $($d.DriveLetter) $labelStr ($($d.FreeGB) GB frei / $($d.CapacityGB) GB)$vMarker " -NoNewline -ForegroundColor White
            Write-Host "$spaceStatus" -ForegroundColor $statusColor
        }
        Write-Host ""
        $selection = Read-Host "Bitte Nummer des Ventoy-Ziel-Laufwerks eingeben (1-$($drives.Count))"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $drives.Count) {
            $TargetDrive = $drives[[int]$selection - 1].DriveLetter
        } else {
            Write-Log -Message "Ungueltige Auswahl. Abbruch." -Color Red -Level "FEHLER"
            return
        }
    }

    $toolsDir = Join-Path $SourceDir "tools\ventoy"
    $TargetDriveLetter = Ensure-VentoyTarget -TargetDrive $TargetDrive -ToolsDir $toolsDir -DryRun:$DryRun
    if (-not $TargetDriveLetter) {
        Write-Log -Message "Abbruch des Kopiervorgangs." -Color Red -Level "ABBRUCH"
        return
    }
    $TargetDriveRoot   = $TargetDriveLetter + "\"

    if (-not (Test-Path $TargetDriveRoot)) {
        Write-Log -Message "Ziel-Laufwerk $TargetDriveRoot existiert nicht oder ist nicht bereit!" -Color Red -Level "FEHLER"
        return
    }

    $freeBytes = 0
    try {
        $driveObj = New-Object System.IO.DriveInfo($TargetDriveLetter)
        $freeBytes = $driveObj.AvailableFreeSpace
    } catch {}
    $freeGB = [math]::Round($freeBytes / 1GB, 2)

    # Berechne wie viele Bytes TATSaeCHLICH neu kopiert werden muessen
    $actualBytesNeeded = 0
    $alreadyPresentCount = 0
    $needCopyCount = 0

    foreach ($iso in $isoFilesToCopy) {
        $dstFolder = Join-Path $TargetDriveRoot $iso.CategoryFolder
        $dstFilePath = Join-Path $dstFolder $iso.Filename
        if (Test-Path $dstFilePath) {
            try {
                $dstItem = Get-Item $dstFilePath -ErrorAction SilentlyContinue
                if ($dstItem -and $dstItem.Length -eq $iso.SizeBytes) {
                    $alreadyPresentCount++
                    continue
                }
            } catch {}
        }
        $actualBytesNeeded += $iso.SizeBytes
        $needCopyCount++
    }

    $actualGBNeeded = [math]::Round($actualBytesNeeded / 1GB, 2)

    Write-Log -Message "Ventoy-Kopiervorgang vorbereiten nach: $TargetDriveRoot" -Color Cyan -Level "VENTOY"
    Write-Log -Message "Gefundene ISO-Dateien: $($isoFilesToCopy.Count) Dateien in $($categoryFolders.Count) Ordnern (Gesamt: $totalGBToCopy GB)" -Color Green -Level "INFO"
    Write-Log -Message "Bereits auf Ziel vorhanden: $alreadyPresentCount ISOs | Neu zu kopieren: $needCopyCount ISOs ($actualGBNeeded GB)" -Color DarkGray -Level "INFO"
    Write-Log -Message "Freier Speicherplatz auf $($TargetDriveRoot): $freeGB GB" -Color DarkGray -Level "INFO"

    # SPEICHERPLATZ-PRUeFUNG
    if ($freeBytes -lt $actualBytesNeeded) {
        $shortageGB = [math]::Round(($actualBytesNeeded - $freeBytes) / 1GB, 2)
        Write-Host ""
        Write-Log -Message "=========================================================" -Color Red -Level "FEHLER"
        Write-Log -Message "[SPEICHERPLATZ-FEHLER] Nicht genuegend freier Speicherplatz auf Ziel-Laufwerk $TargetDriveRoot!" -Color Red -Level "FEHLER"
        Write-Log -Message "  Benoetigt fuer neue/geaenderte ISOs: $actualGBNeeded GB" -Color Yellow -Level "FEHLER"
        Write-Log -Message "  Freier Speicherplatz verfuegbar:      $freeGB GB" -Color Yellow -Level "FEHLER"
        Write-Log -Message "  Fehlender Speicherplatz:              $shortageGB GB" -Color Red -Level "FEHLER"
        Write-Log -Message "=========================================================" -Color Red -Level "FEHLER"
        Write-Host ""

        if ($DryRun) {
            Write-Log -Message "[DRY-RUN] Speicherplatz reicht nicht aus. Im Echtlauf wuerde der Kopiervorgang fehlschlagen." -Color Yellow -Level "DRY-RUN"
        } else {
            $abortChoice = Read-Host "Moechtest du den Kopiervorgang jetzt abbrechen? (J/n)"
            if ($abortChoice -ne 'n' -and $abortChoice -ne 'N') {
                Write-Log -Message "Kopiervorgang durch Benutzer wegen unzureichendem Speicherplatz abgebrochen." -Color Yellow -Level "ABBRUCH"
                return
            }
            Write-Log -Message "Kopiervorgang wird auf ausdruecklichen Wunsch fortgesetzt (Laufwerk koennte vollaufen)..." -Color Yellow -Level "WARNUNG"
        }
    }

    # Bereinigung abgewaehlter/deaktivierter Distributionen auf dem Ventoy-Ziel-Laufwerk
    $deselectedDistros = $distroPatterns | Where-Object { $_.PSObject.Properties['Enabled'] -and $_.Enabled -eq $false -and $_.MatchPattern }
    if ($deselectedDistros -and $deselectedDistros.Count -gt 0) {
        foreach ($folder in $categoryFolders) {
            $dstCatDir = Join-Path $TargetDriveRoot $folder.Name
            if (Test-Path $dstCatDir) {
                $targetIsosInDir = Get-ChildItem -Path $dstCatDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.iso', '.img' }
                foreach ($des in $deselectedDistros) {
                    $matchesToDelete = $targetIsosInDir | Where-Object { $_.Name -match $des.MatchPattern }
                    foreach ($mFile in $matchesToDelete) {
                        $mMB = [math]::Round($mFile.Length / 1MB, 2)
                        if ($DryRun) {
                            Write-Log -Message "[DRY-RUN] Abgewaehlte ISO auf Ventoy-Ziel wuerde geloescht: $($mFile.Name) ($mMB MB) [$($des.Name)]" -Color Yellow -Level "CLEANUP"
                        } else {
                            Write-Log -Message "[CLEANUP] Abgewaehlte ISO auf Ventoy-Ziel ENDGUeLTIG geloescht: $($mFile.Name) ($mMB MB) [$($des.Name)]" -Color Yellow -Level "CLEANUP"
                            try {
                                [System.IO.File]::Delete($mFile.FullName)
                            } catch {
                                Remove-Item -Path $mFile.FullName -Force
                            }
                        }
                    }
                }
            }
        }
    }

    $totalCopyCount = $isoFilesToCopy.Count
    $currentCopyIdx = 0

    foreach ($folder in $categoryFolders) {
        $srcCatDir = $folder.FullName
        $dstCatDir = Join-Path $TargetDriveRoot $folder.Name

        $catIsos = @($isoFilesToCopy | Where-Object { $_.CategoryFolder -eq $folder.Name })
        if ($catIsos.Count -eq 0) { continue }

        if (-not $DryRun) {
            if (-not (Test-Path $dstCatDir)) {
                New-Item -ItemType Directory -Path $dstCatDir -Force | Out-Null
            }

            foreach ($iso in $catIsos) {
                $currentCopyIdx++
                $remainingCopy = $totalCopyCount - $currentCopyIdx

                try { Clear-Host } catch {}
                Write-Host "==========================================================================================" -ForegroundColor Cyan
                Write-Host (" VENTOY-KOPIERSTATUS: {0} von {1} ISOs | {2} verbleibend | Aktuell: {3} ({4} MB)" -f $currentCopyIdx, $totalCopyCount, $remainingCopy, $iso.Filename, $iso.SizeMB) -ForegroundColor Yellow
                Write-Host "==========================================================================================" -ForegroundColor Cyan
                Write-Log -Message "[$currentCopyIdx/$totalCopyCount] Kategorie: $($folder.Name) | ISO: $($iso.Filename)" -Color DarkGray -Level "ORDNER"

                # Bereinigung veralteter ISOs auf dem Ziel-Laufwerk
                $distroMatch = $distroPatterns | Where-Object { $iso.Filename -match $_.MatchPattern }
                $patternToUse = if ($distroMatch) { $distroMatch.MatchPattern } else { ($iso.Filename -replace '[-_\d\.]+\.iso$', '') }

                if ($patternToUse) {
                    $oldTargetIsos = Get-ChildItem -Path $dstCatDir -File -ErrorAction SilentlyContinue | Where-Object { ($_.Extension -in '.iso', '.img') -and
                        $_.Name -ne $iso.Filename -and $_.Name -match $patternToUse
                    }
                    foreach ($oldTargetIso in $oldTargetIsos) {
                        $oldMB = [math]::Round($oldTargetIso.Length / 1MB, 2)
                        Write-Log -Message "[CLEANUP] Veraltete ISO auf Ziel-Laufwerk ENDGUeLTIG geloescht: $($oldTargetIso.Name) ($oldMB MB)" -Color Yellow -Level "CLEANUP"
                        try {
                            [System.IO.File]::Delete($oldTargetIso.FullName)
                        } catch {
                            Remove-Item -Path $oldTargetIso.FullName -Force
                        }
                    }
                }

                $targetIsoPath = Join-Path $dstCatDir $iso.Filename
                $needCopy = $true
                if (Test-Path $targetIsoPath) {
                    $targetFileItem = Get-Item $targetIsoPath
                    if ($targetFileItem.Length -eq $iso.SizeBytes) {
                        Write-Log -Message "[BEREITS VORHANDEN] $($iso.Filename) ($($iso.SizeMB) MB) ist aktuell auf Ziel-Laufwerk." -Color DarkGreen -Level "OK"
                        $needCopy = $false
                    }
                }

                if ($needCopy) {
                    Write-Log -Message "[KOPIERE ISO] $($iso.Filename) ($($iso.SizeMB) MB)" -Color Cyan -Level "LADEN"
                    Copy-FileWithProgress -SourcePath $iso.SourcePath -DestinationPath $targetIsoPath
                    Write-Log -Message "[KOPIEREN ABGESCHLOSSEN] $($iso.Filename)" -Color Green -Level "ERFOLG"
                }
            }
        } else {
            foreach ($iso in $catIsos) {
                $currentCopyIdx++
                $remainingCopy = $totalCopyCount - $currentCopyIdx
                Write-Log -Message "[DRY-RUN] [$currentCopyIdx/$totalCopyCount] Wuerde veraltete ISOs bereinigen und kopieren: $($iso.Filename) ($($iso.SizeMB) MB) -> $dstCatDir\$($iso.Filename)" -Color DarkGray -Level "DRY-RUN"
            }
        }
    }

    if (-not $DryRun) {
        try { Clear-Host } catch {}
        Write-Host "==========================================================================================" -ForegroundColor Cyan
        Write-Host (" VENTOY-KOPIERSTATUS: Alle {0} ISOs erfolgreich abgeglichen!" -f $totalCopyCount) -ForegroundColor Green
        Write-Host "==========================================================================================" -ForegroundColor Cyan
        Write-Host ""
    }

    # Ventoy Design & JSON Konfiguration"
    Write-Log -Message "Konfiguriere Ventoy Design & Dir-Modus (Theme + Aliases) auf $TargetDriveRoot..." -Color Cyan -Level "VENTOY"

    $ventoyDir = Join-Path $TargetDriveRoot "ventoy"
    $ventoyJsonPath = Join-Path $ventoyDir "ventoy.json"

    if (-not $DryRun) {
        $currentActiveTheme = "1"
        $activeThemeFile = Join-Path $ventoyDir "theme_active.txt"
        if (Test-Path $activeThemeFile) {
            $tVal = (Get-Content $activeThemeFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($tVal) { $currentActiveTheme = $tVal }
        }

        $themeToUse = if ($Theme) { $Theme } else { $currentActiveTheme }
        Write-Host ""
        Write-Host "=========================================================" -ForegroundColor Cyan
        $askTheme = Read-Host "Moechtest du das Ventoy-Theme auswaehlen oder aendern? (j/N)"
        if ($askTheme -match '^(j|ja|y|yes)$') {
            $themeToUse = Select-VentoyThemeInteractive -DefaultChoice $currentActiveTheme
        }

        Install-VentoyTheme -VentoyDir $ventoyDir -ThemeChoice $themeToUse -Force -DryRun:$DryRun

        $alreadyConfigured = $false
        $configObj = @{}
        if (Test-Path $ventoyJsonPath) {
            try {
                $rawJson = Get-Content $ventoyJsonPath -Raw -Encoding UTF8 -ErrorAction Stop
                $parsed = $rawJson | ConvertFrom-Json
                if ($parsed) { 
                    $configObj = $parsed 
                    # Pruefen ob Theme & TreeView bereits konfiguriert sind
                    $hasTheme = ($parsed.PSObject.Properties['theme'] -and $parsed.theme.file -eq "/ventoy/theme/theme.txt")
                    $hasMode  = ($parsed.PSObject.Properties['control'] -and ($parsed.control | Where-Object { $_.VTOY_DEFAULT_MENU_MODE -eq "1" }))
                    if ($hasTheme -and $hasMode) {
                        $alreadyConfigured = $true
                    }
                }
            } catch {
                $configObj = @{}
            }
        }

        if ($alreadyConfigured) {
            Write-Log -Message "[VENTOY] ventoy.json (Dir-Modus & Theme) bereits auf Ziel-Laufwerk vorhanden. Schreibe nichts neu." -Color DarkGreen -Level "OK"
        } else {
            try {
                if (-not (Test-Path $ventoyDir)) {
                    New-Item -ItemType Directory -Path $ventoyDir -Force | Out-Null
                }

                $controlSettings = @(
                    @{ "VTOY_DEFAULT_MENU_MODE" = "1" },
                    @{ "VTOY_TREE_VIEW_MENU_STYLE" = "1" },
                    @{ "VTOY_FILT_DIR_LEVEL" = "0" },
                    @{ "VTOY_MAX_MENU_NUM" = "12" }
                )

                if ($configObj.PSObject -and $configObj.PSObject.Properties['control']) {
                    $existingControl = [array]$configObj.control
                    foreach ($setting in $controlSettings) {
                        $key = ($setting.Keys | Select-Object -First 1)
                        $found = $false
                        foreach ($item in $existingControl) {
                            if ($item.PSObject -and $item.PSObject.Properties[$key]) {
                                $item.$key = $setting[$key]
                                $found = $true
                                break
                            }
                        }
                        if (-not $found) {
                            $existingControl += $setting
                        }
                    }
                    $configObj.control = $existingControl
                } else {
                    $configObj | Add-Member -NotePropertyName "control" -NotePropertyValue $controlSettings -Force
                }

                $themeSetting = @{
                    "file"         = "/ventoy/theme/theme.txt"
                    "gfxmode"      = "1920x1080"
                    "display_mode" = "GUI"
                }
                $configObj | Add-Member -NotePropertyName "theme" -NotePropertyValue $themeSetting -Force

                $menuAliases = @(
                    @{ "image" = "/01_Desktop-Linux";     "alias" = "Desktop Linux (Ubuntu, Mint, Fedora, Arch, Zorin...)" },
                    @{ "image" = "/02_Enterprise-Server"; "alias" = "Enterprise Server (RHEL, Rocky, Alma, Proxmox, TrueNAS...)" },
                    @{ "image" = "/03_Security-Pentest";  "alias" = "Security & Pentesting (Kali, Parrot, BlackArch...)" },
                    @{ "image" = "/04_Rescue-Systeme";   "alias" = "Rescue & Recovery (GParted, Rescuezilla, FygoOS...)" },
                    @{ "image" = "/05_BSD-Unix";          "alias" = "BSD & Unix (FreeBSD, OpenBSD, NetBSD, DragonFly...)" },
                    @{ "image" = "/06_Windows-PE_Rescue"; "alias" = "Windows PE & Recovery (Hiren's BootCD PE, WinPE, Recovery...)" }
                )

                foreach ($iso in $isoFilesToCopy) {
                    $vtoyImagePath = "/" + $iso.RelPath.Replace('\', '/')
                    $prettyTitle   = Get-PrettyIsoName -Filename $iso.Filename
                    $menuAliases += @{
                        "image" = $vtoyImagePath
                        "alias" = $prettyTitle
                    }
                }

                $configObj | Add-Member -NotePropertyName "menu_alias" -NotePropertyValue $menuAliases -Force

                $jsonOutput = ($configObj | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
                [System.IO.File]::WriteAllText($ventoyJsonPath, $jsonOutput, (New-Object System.Text.UTF8Encoding($false)))

                Write-Log -Message "Ventoy Modern Dark Theme & Menu-Aliases erfolgreich angewendet!" -Color Green -Level "ERFOLG"
            } catch {
                Write-Log -Message "Fehler beim Konfigurieren/Schreiben von ventoy.json auf ${ventoyJsonPath}: $_" -Color Red -Level "FEHLER"
            }
        }
    }
}

# ==============================================================================
# SCHRITT 0: VENTOY INSTALLATION AUF ZIEL-LAUFWERK (OPTIONAL VIA -InstallVentoy)
# ==============================================================================
if ($InstallVentoy) {
    Install-VentoyToDisk -TargetDrive $TargetDrive -ToolsDir (Join-Path $IsoDirectory "tools\ventoy") -DryRun:$DryRun

    if ($SkipDownload -and $SkipVentoy) {
        Write-Log -Message "Ventoy-Installation abgeschlossen." -Color Green -Level "ENDE"
        if ($scriptMutex -and $createdNew) {
            try { $scriptMutex.ReleaseMutex(); $scriptMutex.Dispose() } catch {}
        }
        return
    }

    if (-not $SkipDownload) {
        Write-Host ""
        $continueUpdates = Read-Host "Moechtest du nun mit dem ISO-Download / Abgleich fortfahren? (J/n)"
        if ($continueUpdates -eq 'n' -or $continueUpdates -eq 'N') {
            if (-not $SkipVentoy) {
                $copyExisting = Read-Host "Moechtest du bereits vorhandene lokale ISOs jetzt auf den Ventoy-Stick kopieren? (J/n)"
                if ($copyExisting -ne 'n' -and $copyExisting -ne 'N') {
                    $chosenTarget = if ($script:TargetDrive) { $script:TargetDrive } else { $TargetDrive }
                    Start-VentoyCopyJob -TargetDrive $chosenTarget -SourceDir $IsoDirectory -DryRun:$DryRun
                }
            }
            Write-Log -Message "Vorgang beendet." -Color Green -Level "ENDE"
            if ($scriptMutex -and $createdNew) {
                try { $scriptMutex.ReleaseMutex(); $scriptMutex.Dispose() } catch {}
            }
            return
        }
    }
}

# ==============================================================================
# SCHRITT 0.5: VENTOY THEME AeNDERN (STANDALONE VIA -ChangeTheme / -Theme)
# ==============================================================================
if ($ChangeTheme -or ($PSBoundParameters.ContainsKey('Theme') -and -not [string]::IsNullOrWhiteSpace($Theme) -and $SkipDownload)) {
    Set-VentoyThemeStandalone -TargetDrive $TargetDrive -ThemeChoice $Theme -DryRun:$DryRun
    if ($scriptMutex -and $createdNew) {
        try { $scriptMutex.ReleaseMutex(); $scriptMutex.Dispose() } catch {}
    }
    return
}

# ==============================================================================
# SCHRITT 1: ISO-UPDATE & DOWNLOAD
# ==============================================================================
if (-not $SkipDownload) {
    # DISTRIBUTIONS-KONFIGURATION AUS distros.json
    $DistrosJsonFile = Join-Path $IsoDirectory "distros.json"
    $Distros = @()
    $distroList = $null
    $script:jsonModified = $false

    $existingIsosForCheck = Get-ChildItem -Path $IsoDirectory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notlike "*Archiv*" -and ($_.Extension -in '.iso', '.img') }
    $isInitialRun = ($null -eq $existingIsosForCheck -or $existingIsosForCheck.Count -eq 0)

    if (Test-Path $DistrosJsonFile) {
        try {
            $jsonRaw = Get-Content $DistrosJsonFile -Raw -Encoding UTF8
            $distroList = $jsonRaw | ConvertFrom-Json

            Select-DistrosInteractive -DistroList $distroList -IsReconfiguration:($SelectDistros -or -not $isInitialRun)
            $script:jsonModified = $true

                # Pruefen, ob zuvor heruntergeladene ISOs jetzt abgewaehlt sind
                if ($existingIsosForCheck -and $existingIsosForCheck.Count -gt 0) {
                    $deselectedWithFiles = @()
                    foreach ($dItem in $distroList) {
                        if ($dItem.Enabled -eq $false -and $dItem.MatchPattern) {
                            $foundFiles = $existingIsosForCheck | Where-Object { $_.Name -match $dItem.MatchPattern }
                            if ($foundFiles) {
                                $deselectedWithFiles += [PSCustomObject]@{
                                    Name  = $dItem.Name
                                    Files = $foundFiles
                                }
                            }
                        }
                    }

                    if ($deselectedWithFiles.Count -gt 0) {
                        Write-Host ""
                        Write-Host "==========================================================================================" -ForegroundColor Yellow
                        Write-Host "                    ABGEWAEHLTE DISTRIBUTIONEN MIT LOKALEN DATEIEN                       " -ForegroundColor Yellow
                        Write-Host "==========================================================================================" -ForegroundColor Yellow
                        Write-Host "Fuer folgende jetzt abgewaehlte Distributionen existieren bereits heruntergeladene ISOs:" -ForegroundColor White
                        foreach ($des in $deselectedWithFiles) {
                            foreach ($f in $des.Files) {
                                $sizeMB = [math]::Round($f.Length / 1MB, 2)
                                Write-Host " - $($des.Name): $($f.Name) ($sizeMB MB)" -ForegroundColor Cyan
                            }
                        }
                        Write-Host ""
                        $delAns = Read-Host "Moechtest du diese nicht mehr ausgewaehlten ISOs jetzt loeschen? (j/N)"
                        if ($delAns -eq 'j' -or $delAns -eq 'J') {
                            foreach ($des in $deselectedWithFiles) {
                                foreach ($f in $des.Files) {
                                    try {
                                        Remove-Item -Path $f.FullName -Force
                                        Write-Host "   [GELOESCHT] $($f.Name)" -ForegroundColor Green
                                    } catch {
                                        Write-Host "   [FEHLER] Konnte $($f.Name) nicht loeschen: $_" -ForegroundColor Red
                                    }
                                }
                            }
                        } else {
                            Write-Host "   [BEIBEHALTEN] Lokale Dateien werden behalten, aber kuenftig nicht mehr synchronisiert." -ForegroundColor DarkGray
                        }
                    }
                }

            foreach ($item in $distroList) {
                if ($item.PSObject.Properties['Enabled'] -and $item.Enabled -eq $false) {
                    continue
                }

                $sb = $null
                $matchPattern = if ($item.PSObject.Properties['MatchPattern']) { $item.MatchPattern } else { $null }

                if ($item.PSObject.Properties['Script'] -and -not [string]::IsNullOrWhiteSpace($item.Script)) {
                    $sb = [scriptblock]::Create($item.Script)
                } elseif ($item.PSObject.Properties['Url'] -and -not [string]::IsNullOrWhiteSpace($item.Url)) {
                    $directUrl = $item.Url
                    $cleanUrl  = $directUrl -replace '\?.*$', ''
                    $fn = [System.IO.Path]::GetFileName($cleanUrl)
                    if (-not $fn -or ($fn -notmatch '(?i)\.(iso|img)$')) {
                        $fn = "$($item.Name -replace '\s+', '_').iso"
                    }
                    if (-not $matchPattern) {
                        $baseName = $fn -replace '[-_\d\.]+\.iso$', ''
                        if (-not $baseName) { $baseName = $item.Name -replace '\s+', '' }
                        $matchPattern = "$baseName.*"
                    }
                    $ver = if ($fn -match '(\d+\.\d+(\.\d+)?)') { $Matches[1] } else { "Direkt" }
                    $sbStr = "return @{ Version = '$ver'; Url = '$directUrl'; Filename = '$fn' }"
                    $sb = [scriptblock]::Create($sbStr)
                }

                if ($sb) {
                    $Distros += @{
                        Name         = $item.Name
                        MatchPattern = $matchPattern
                        GetLatest    = $sb
                        Item         = $item
                    }
                }
            }
        } catch {
            Write-Host "   [FEHLER] Fehler beim Lesen von distros.json: $_" -ForegroundColor Red
        }
    }

    # SPEICHERPLATZPRUeFUNG VOR DEM START
    $driveRoot = [System.IO.Path]::GetPathRoot($IsoDirectory)
    $freeBytes = 0
    try {
        $driveObj = New-Object System.IO.DriveInfo($driveRoot)
        $freeBytes = $driveObj.AvailableFreeSpace
    } catch {
        try {
            $diskCim = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($driveRoot.TrimEnd('\'))'"
            $freeBytes = [long]$diskCim.FreeSpace
        } catch {}
    }
    $freeGB = [math]::Round($freeBytes / 1GB, 2)

    $existingIsos = Get-ChildItem -Path $IsoDirectory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notlike "*Archiv*" -and ($_.Extension -in '.iso', '.img') }
    $isInitialRun = ($null -eq $existingIsos -or $existingIsos.Count -eq 0)

    $totalAllDistrosBytes = 0
    $neededNewBytes = 0
    $existingIsosSizeSum = 0

    if ($existingIsos) {
        foreach ($isoFile in $existingIsos) {
            $existingIsosSizeSum += $isoFile.Length
        }
    }

    if ($distroList) {
        foreach ($d in $distroList) {
            if ($d.Enabled -ne $false) {
                $dSize = [long](3500 * 1MB)
                if ($d.SizeBytes -and [long]$d.SizeBytes -gt 0) {
                    $dSize = [long]$d.SizeBytes
                }
                $totalAllDistrosBytes += $dSize

                $hasLocalFile = $false
                if ($existingIsos -and $d.MatchPattern) {
                    $hasLocalFile = [bool]($existingIsos | Where-Object { $_.Name -match $d.MatchPattern })
                }
                if (-not $hasLocalFile) {
                    $neededNewBytes += $dSize
                }
            }
        }
    }

    $totalAllGB    = [math]::Round($totalAllDistrosBytes / 1GB, 2)
    $existingGB    = [math]::Round($existingIsosSizeSum / 1GB, 2)
    $neededNewGB   = [math]::Round($neededNewBytes / 1GB, 2)

    Write-Log -Message "=========================================================" -Color Cyan -Level "START"
    if ($DryRun) {
        Write-Log -Message "[DRY-RUN MODUS] Starte Pruefung der ISO-Dateien in: $IsoDirectory" -Color Yellow -Level "DRY-RUN"
    } else {
        Write-Log -Message "Starte Linux ISO Auto-Update v$ScriptVersion in: $IsoDirectory" -Color Cyan -Level "INFO"
    }
    Write-Log -Message "Log-Datei: $LogFile" -Color DarkGray -Level "INFO"

    if ($isInitialRun) {
        Write-Log -Message "[ERSTAUSFUeHRUNG] Erster Start erkannt. Fuer den Erst-Download aller Distros werden ca. 140 GB Speicherplatz empfohlen." -Color Yellow -Level "INFO"
        Write-Log -Message "[SPEICHERPLATZ] Freier Speicherplatz auf Laufwerk $driveRoot $freeGB GB | Benoetigt fuer alle Distros: ca. $totalAllGB GB" -Color DarkGray -Level "INFO"
        if ($freeBytes -lt $totalAllDistrosBytes -and -not $DryRun) {
            Write-Log -Message "[WARNUNG] ACHTUNG: Der freie Speicherplatz ($freeGB GB) auf Laufwerk $driveRoot ist geringer als der empfohlene Speicherplatz ($totalAllGB GB)!" -Color Red -Level "WARNUNG"
        }
    } else {
        Write-Log -Message "[SPEICHERPLATZ] Freier Speicherplatz auf Laufwerk $($driveRoot): $freeGB GB | Vorhandene ISOs: $existingGB GB | Noch benoetigter Speicherplatz (fuer fehlende Distros): ca. $neededNewGB GB (Gesamtbedarf: $totalAllGB GB)" -Color DarkGray -Level "INFO"
        if ($freeBytes -lt $neededNewBytes -and -not $DryRun) {
            Write-Log -Message "[WARNUNG] ACHTUNG: Der freie Speicherplatz ($freeGB GB) auf Laufwerk $($driveRoot) ist geringer als der fuer fehlende Distros benoetigte Speicherplatz ($neededNewGB GB)!" -Color Red -Level "WARNUNG"
        }
    }
    Write-Log -Message "=========================================================`n" -Color Cyan -Level "START"

    $totalDownloadedBytesAll = 0
    $summaryItems = @()
    $totalDistrosCount = $Distros.Count
    $currentDistroIdx = 0

    foreach ($distro in $Distros) {
        $currentDistroIdx++
        $remainingDistros = $totalDistrosCount - $currentDistroIdx

        try { Clear-Host } catch {}
        Write-Host "==========================================================================================" -ForegroundColor Cyan
        Write-Host (" DISTRO-FORTSCHRITT: {0} von {1} verarbeitet | {2} verbleibend | Aktuell: {3}" -f $currentDistroIdx, $totalDistrosCount, $remainingDistros, $distro.Name) -ForegroundColor Yellow
        Write-Host "==========================================================================================" -ForegroundColor Cyan
        Write-Log -Message "[$currentDistroIdx/$totalDistrosCount] Pruefe Distribution: $($distro.Name)" -Color Yellow -Level "CHECK"

        try {
            $latestInfo = & $distro.GetLatest
        } catch {
            Write-Log -Message "Fehler beim Abrufen der Online-Version fuer $($distro.Name): $_" -Color Red -Level "FEHLER"
            continue
        }

        if (-not $latestInfo) {
            Write-Log -Message "Konnte keine aktuelle Online-Version fuer $($distro.Name) ermitteln." -Color Red -Level "FEHLER"
            continue
        }

        if ($latestInfo.Filename -notlike "*.iso") {
            Write-Log -Message "[UeBERSPRUNGEN] Format ist kein ISO ($($latestInfo.Filename)) fuer $($distro.Name)" -Color Yellow -Level "WARNUNG"
            continue
        }

        Write-LogDetail -Message "Neueste Version online: $($latestInfo.Version)" -Color DarkGray
        Write-LogDetail -Message "Gesuchte Datei:         $($latestInfo.Filename)" -Color DarkGray
        Write-LogDetail -Message "Download-URL:           $($latestInfo.Url)" -Color DarkGray

        $categoryName = if ($distro.Item -and $distro.Item.Category) { $distro.Item.Category } else { "01_Desktop-Linux" }
        $categoryDir  = Join-Path $IsoDirectory $categoryName
        $effectiveTargetFilename = if ($latestInfo.PSObject.Properties['ExtractTo'] -and $latestInfo.ExtractTo) { $latestInfo.ExtractTo } else { $latestInfo.Filename }
        $targetPath   = Join-Path $categoryDir $effectiveTargetFilename

        $rootFile = Join-Path $IsoDirectory $latestInfo.Filename
        if ((Test-Path -Path $rootFile) -and $targetPath -ne $rootFile) {
            if (-not $DryRun) {
                if (-not (Test-Path -Path $categoryDir)) {
                    New-Item -ItemType Directory -Path $categoryDir -Force | Out-Null
                }
                Move-Item -Path $rootFile -Destination $targetPath -Force
                Write-LogDetail -Message "Datei aus Hauptverzeichnis nach $categoryName\ einsortiert." -Color Yellow
            }
        }

        # ARCHIV ROUTINE
        $searchFolders = @($IsoDirectory, $categoryDir)
        $oldFiles = Get-ChildItem -Path $searchFolders -File -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -match $distro.MatchPattern -and $_.Name -ne $latestInfo.Filename -and $_.DirectoryName -notlike "*Archiv*"
        }

        $oldVersionStr = $null
        if ($oldFiles) {
            $oldVersList = @()
            foreach ($oldFile in $oldFiles) {
                $verDetected = $null
                if ($oldFile.Name -match $distro.MatchPattern -and $Matches.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($Matches[1])) {
                    $verDetected = $Matches[1]
                } elseif ($oldFile.BaseName -match '(\d{4}\.\d{2}\.\d{2}|\d+\.\d+(\.\d+)?|\d{6})') {
                    $verDetected = $Matches[1]
                } else {
                    $verDetected = $oldFile.BaseName
                }
                if ($verDetected -and ($oldVersList -notcontains $verDetected)) {
                    $oldVersList += $verDetected
                }

                $oldSizeMB = [math]::Round($oldFile.Length / 1MB, 2)
                if ($DryRun) {
                    Write-Log -Message "[ARCHIV DRY-RUN] Veraltete Datei gefunden: $($oldFile.Name) (Groesse: $oldSizeMB MB) -> wuerde nach Archiv\ verschoben" -Color Yellow -Level "ARCHIV"
                } else {
                    if (-not (Test-Path -Path $ArchiveDir)) {
                        New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null
                    }
                    $destPath = Join-Path $ArchiveDir $oldFile.Name
                    Move-Item -Path $oldFile.FullName -Destination $destPath -Force
                    Write-Log -Message "[ARCHIV] Veraltete Datei ins Archiv verschoben: $($oldFile.Name) (Groesse: $oldSizeMB MB) -> Archiv\" -Color Yellow -Level "ARCHIV"
                }
            }
            if ($oldVersList.Count -gt 0) {
                $oldVersionStr = $oldVersList -join ", "
            }
        }

        $isAlreadyPresent = $false
        if (Test-Path -Path $targetPath) {
            $fileItem = Get-Item $targetPath
            $onlineSizeBytes = Get-OnlineFileSize -Url $latestInfo.Url

            if ($onlineSizeBytes -ge 1MB) {
                if ($distro.Item -and $distro.Item.SizeBytes -ne $onlineSizeBytes) {
                    $distro.Item | Add-Member -NotePropertyName "SizeBytes" -NotePropertyValue $onlineSizeBytes -Force
                    $script:jsonModified = $true
                }
                $sizeDiff = [math]::Abs($fileItem.Length - $onlineSizeBytes)
                if ($sizeDiff -lt 1MB) {
                    $isAlreadyPresent = $true
                } else {
                    $localMB  = [math]::Round($fileItem.Length / 1MB, 2)
                    $onlineMB = [math]::Round($onlineSizeBytes / 1MB, 2)
                    Write-Log -Message "[UNVOLLSTAeNDIG] Lokale Datei $($latestInfo.Filename) - ${localMB} MB (Online: ${onlineMB} MB). Datei wird geloescht und neu geladen." -Color Yellow -Level "WARNUNG"
                    Remove-Item -Path $targetPath -Force
                }
            } else {
                if ($fileItem.Length -gt 1MB) {
                    $isAlreadyPresent = $true
                } else {
                    $fileMB = [math]::Round($fileItem.Length / 1MB, 2)
                    Write-Log -Message "[WARNUNG] Lokale Datei $($latestInfo.Filename) ist zu klein - ${fileMB} MB. Wird erneuert." -Color Yellow -Level "WARNUNG"
                    Remove-Item -Path $targetPath -Force
                }
            }
        }

        if ($isAlreadyPresent) {
            $fileItem = Get-Item $targetPath
            $fileSizeMB = [math]::Round($fileItem.Length / 1MB, 2)
            Write-Log -Message "[AKTUELLES ISO]" -Color DarkGreen -Level "OK"
            Write-LogDetail -Message "Dateiname: $($latestInfo.Filename)" -Color DarkGreen
            Write-LogDetail -Message "Version:   $($latestInfo.Version)" -Color DarkGreen
            Write-LogDetail -Message "Groesse:     $fileSizeMB MB" -Color DarkGreen
            Write-LogDetail -Message "Status:    Vorhanden (Hash-Pruefung uebersprungen)" -Color DarkGreen
        }

        if (-not $isAlreadyPresent) {
            if ($DryRun) {
                Write-Log -Message "[DRY-RUN UNVOLLSTAeNDIG] ISO nicht vorhanden oder veraltet: $($latestInfo.Filename)" -Color Yellow -Level "DRY-RUN"
                try {
                    $handler = New-Object System.Net.Http.HttpClientHandler
                    $handler.AllowAutoRedirect = $true
                    $client = New-Object System.Net.Http.HttpClient($handler)
                    $client.Timeout = [TimeSpan]::FromSeconds(10)
                    if ($latestInfo.Url -match "sourceforge\.net") { $client.DefaultRequestHeaders.Add("User-Agent", "curl/8.4.0") } else { $client.DefaultRequestHeaders.Add("User-Agent", $UserAgent) }

                    $res = $client.GetAsync($latestInfo.Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                    $drySuccess = $false
                    if ($res.IsSuccessStatusCode) {
                        $sizeMB = "Unbekannt"
                        if ($res.Content.Headers.ContentLength) {
                            $sizeMB = [math]::Round($res.Content.Headers.ContentLength / 1MB, 2)
                        }
                        Write-Log -Message "[DRY-RUN OK] Neue Version verfuegbar: Dateiname: $($latestInfo.Filename) | Version: $($latestInfo.Version) | Online-Groesse: $sizeMB MB" -Color Green -Level "DRY-RUN"
                        $drySuccess = $true
                        $summaryItems += [PSCustomObject]@{
                            Distribution = $distro.Name
                            Aktion       = if ($oldVersionStr) { "Update (Dry-Run)" } else { "Neu (Dry-Run)" }
                            Version      = if ($oldVersionStr) { "$oldVersionStr -> $($latestInfo.Version)" } else { "$($latestInfo.Version)" }
                            Groesse      = if ($sizeMB -ne "Unbekannt") { "$sizeMB MB" } else { "Unbekannt" }
                        }
                    } else {
                        Write-Log -Message "[DRY-RUN WARNUNG] Link liefert HTTP Status $($res.StatusCode) fuer Dateiname: $($latestInfo.Filename)" -Color Yellow -Level "DRY-RUN"
                        $drySuccess = $true
                    }
                    $client.Dispose(); $handler.Dispose()
                } catch {}

                if (-not $drySuccess) {
                    try {
                        $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
                        if ($curl) {
                            $curlUserAgent = if ($latestInfo.Url -match "sourceforge\.net") { "curl/8.4.0" } else { $UserAgent }
                            $headers = & curl.exe -sIL -A $curlUserAgent --max-time 15 $latestInfo.Url | Out-String
                            if ($headers -match 'HTTP/\d(\.\d)? 200') {
                                $sizeMB = "Unbekannt"
                                if ($headers -match 'Content-Length:\s*(\d+)') {
                                    $sizeMB = [math]::Round([long]$Matches[1] / 1MB, 2)
                                }
                                Write-Log -Message "[DRY-RUN OK] Neue Version verfuegbar: Dateiname: $($latestInfo.Filename) | Version: $($latestInfo.Version) | Online-Groesse: $sizeMB MB" -Color Green -Level "DRY-RUN"
                                $summaryItems += [PSCustomObject]@{
                                    Distribution = $distro.Name
                                    Aktion       = if ($oldVersionStr) { "Update (Dry-Run)" } else { "Neu (Dry-Run)" }
                                    Version      = if ($oldVersionStr) { "$oldVersionStr -> $($latestInfo.Version)" } else { "$($latestInfo.Version)" }
                                    Groesse      = if ($sizeMB -ne "Unbekannt") { "$sizeMB MB" } else { "Unbekannt" }
                                }
                            } else {
                                Write-Log -Message "[DRY-RUN WARNUNG] Link konnte nicht bestaetigt werden fuer Dateiname: $($latestInfo.Filename)" -Color Yellow -Level "DRY-RUN"
                            }
                        }
                    } catch {}
                }
            } else {
                Write-Log -Message "[UPDATE GESTARTET] Lade neue Version herunter: Dateiname: $($latestInfo.Filename) | Version: $($latestInfo.Version)" -Color Green -Level "DOWNLOAD"
                
                try {
                    if (-not (Test-Path -Path $categoryDir)) {
                        New-Item -ItemType Directory -Path $categoryDir -Force | Out-Null
                    }
                    $bytesDownloaded = Start-HttpDownload -Url $latestInfo.Url -DestinationPath $targetPath -Filename $latestInfo.Filename
                    $downloadedMB = [math]::Round($bytesDownloaded / 1MB, 2)

                    Write-Log -Message "[DOWNLOAD ERFOLGREICH] Dateiname: $($latestInfo.Filename) | Version: $($latestInfo.Version) | Groesse: $downloadedMB MB" -Color Green -Level "ERFOLG"

                    if ($latestInfo.PSObject.Properties['ExtractTo'] -and $latestInfo.ExtractTo) {
                        $extractedIsoPath = Join-Path $categoryDir $latestInfo.ExtractTo
                        Write-Log -Message "[ENTPACKEN] Entpacke $($latestInfo.Filename) nach $($latestInfo.ExtractTo)..." -Color Cyan -Level "INFO"
                        $extractedOk = Expand-Bz2Archive -Bz2Path $targetPath -DestinationIsoPath $extractedIsoPath
                        if ($extractedOk -and (Test-Path $extractedIsoPath)) {
                            Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
                            $targetPath = $extractedIsoPath
                            $latestInfo.Filename = $latestInfo.ExtractTo
                            Write-Log -Message "[ENTPACKT] $($latestInfo.ExtractTo) erfolgreich entpackt und bereitgestellt!" -Color Green -Level "ERFOLG"
                        } else {
                            Write-Log -Message "[WARNUNG] Entpacken von $($latestInfo.Filename) fehlgeschlagen. Bitte manuell entpacken." -Color Yellow -Level "WARNUNG"
                        }
                    }

                    $checksumValid = Test-IsoChecksum -FilePath $targetPath -DownloadUrl $latestInfo.Url -Filename $latestInfo.Filename -ExplicitChecksumUrl $latestInfo.ChecksumUrl
                    if (-not $checksumValid) {
                        Write-Log -Message "[FEHLER] Pruefsumme des frisch heruntergeladenen ISOs $($latestInfo.Filename) IST UNGUeLTIG! Datei wird geloescht." -Color Red -Level "FEHLER"
                        if (Test-Path -Path $targetPath) { Remove-Item -Path $targetPath -Force }
                    } else {
                        $totalDownloadedBytesAll += $bytesDownloaded
                        $summaryItems += [PSCustomObject]@{
                            Distribution = $distro.Name
                            Aktion       = if ($oldVersionStr) { "Update" } else { "Neu geladen" }
                            Version      = if ($oldVersionStr) { "$oldVersionStr -> $($latestInfo.Version)" } else { "$($latestInfo.Version)" }
                            Groesse      = "$downloadedMB MB"
                        }
                    }
                } catch {
                    Write-Log -Message "[DOWNLOAD FEHLER] Abgeschlossen mit Fehler: $_" -Color Red -Level "FEHLER"
                    if (Test-Path -Path $targetPath) { 
                        Remove-Item -Path $targetPath -Force 
                        Write-Log -Message "[CLEANUP] Unvollstaendige Datei $($latestInfo.Filename) wurde geloescht." -Color Yellow -Level "CLEANUP"
                    }
                }
            }
        }
        Write-Host ""
    }

    Write-Log -Message "=========================================================" -Color Cyan -Level "ENDE"
    Write-Log -Message "ISO Auto-Update-Vorgang abgeschlossen." -Color Cyan -Level "ENDE"

    if ($summaryItems.Count -gt 0) {
        try { Clear-Host } catch {}
        Write-Host ""
        $titleText = if ($DryRun) { "UeBERSICHT: VERFUeGBARE UPDATES / NEUE ISOS (DRY-RUN)" } else { "UeBERSICHT: HERUNTERGELADENE & AKTUALISIERTE ISOS" }
        Write-Log -Message $titleText -Color Cyan -Level "INFO"
        Write-Host ("-" * 85) -ForegroundColor DarkGray
        $headerLine = "   {0,-26} | {1,-16} | {2,-24} | {3,12}" -f "Distribution", "Status", "Version", "Groesse"
        Write-Host $headerLine -ForegroundColor Yellow
        Write-Host ("-" * 85) -ForegroundColor DarkGray
        try { Add-Content -Path $LogFile -Value $headerLine -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}

        foreach ($sItem in $summaryItems) {
            $rowLine = "   {0,-26} | {1,-16} | {2,-24} | {3,12}" -f $sItem.Distribution, $sItem.Aktion, $sItem.Version, $sItem.Groesse
            $rowColor = if ($sItem.Aktion -like "Update*") { [ConsoleColor]::Cyan } else { [ConsoleColor]::Green }
            Write-Host $rowLine -ForegroundColor $rowColor
            try { Add-Content -Path $LogFile -Value $rowLine -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
        }
        Write-Host ("-" * 85) -ForegroundColor DarkGray
        Write-Host ""
    }

    if (-not $DryRun) {
        if ($totalDownloadedBytesAll -gt 0) {
            $totalMB = [math]::Round($totalDownloadedBytesAll / 1MB, 2)
            $totalGB = [math]::Round($totalDownloadedBytesAll / 1GB, 2)
            if ($totalGB -ge 1.0) {
                Write-Log -Message "Insgesamt heruntergeladen: $totalMB MB ($totalGB GB)" -Color Green -Level "ENDE"
            } else {
                Write-Log -Message "Insgesamt heruntergeladen: $totalMB MB" -Color Green -Level "ENDE"
            }
        } else {
            Write-Log -Message "Alle Distros sind bereits aktuell." -Color Green -Level "ENDE"
        }
    }
    Write-Log -Message "=========================================================" -Color Cyan -Level "ENDE"

    if ($script:jsonModified -and $distroList -and (Test-Path $DistrosJsonFile)) {
        try {
            $updatedJson = $distroList | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($DistrosJsonFile, $updatedJson, (New-Object System.Text.UTF8Encoding($true)))
        } catch {}
    }
}

# ==============================================================================
# SCHRITT 2: VENTOY KOPIEREN & DESIGN
# ==============================================================================
if (-not $SkipVentoy) {
    $shouldCopy = $false
    $chosenTarget = if ($script:TargetDrive) { $script:TargetDrive } else { $TargetDrive }

    if (-not [string]::IsNullOrWhiteSpace($chosenTarget)) {
        $shouldCopy = $true
    } elseif (-not $DryRun) {
        Write-Host ""
        Write-Host "=========================================================" -ForegroundColor Cyan
        $ans = Read-Host "Moechtest du die ISO-Dateien jetzt auf ein Ventoy-Ziel-Laufwerk kopieren? (J/n)"
        if ($ans -ne 'n' -and $ans -ne 'N') {
            $shouldCopy = $true
        }
    }

    if ($shouldCopy) {
        Start-VentoyCopyJob -TargetDrive $chosenTarget -SourceDir $IsoDirectory -DryRun:$DryRun
    }
}

if ($scriptMutex -and $createdNew) {
    try {
        $scriptMutex.ReleaseMutex()
        $scriptMutex.Dispose()
    } catch {}
}
