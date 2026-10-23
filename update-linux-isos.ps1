<#
.SYNOPSIS
    All-in-One Linux ISO Auto-Updater & Ventoy Sync Tool
.DESCRIPTION
    Version: 2.1.0
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
    [switch]$SelectDistros
)

# UTF-8 Konfiguration & Assemblies fuer PowerShell 5.1 & Konsole
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}
Add-Type -AssemblyName System.Net.Http

$ProgressPreference = 'SilentlyContinue'
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
$ScriptVersion = "2.1.0"
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
    $checksumUrlCandidates = @()
    if ($ExplicitChecksumUrl) { $checksumUrlCandidates += $ExplicitChecksumUrl }
    $checksumUrlCandidates += "$DownloadUrl.sha256"
    $checksumUrlCandidates += "$DownloadUrl.sha256sum"
    $checksumUrlCandidates += "$DownloadUrl.SHA256"
    $checksumUrlCandidates += ($DownloadUrl -replace '\.iso$', '.sha256')
    $checksumUrlCandidates += ($DownloadUrl -replace '\.iso$', '.sha256sum')

    $expectedHash = $null
    $hashAlgorithm = "SHA256"
    foreach ($cUrl in $checksumUrlCandidates) {
        $content = Get-WebContent -Uri $cUrl
        if ($content) {
            if ($content -match "([a-fA-F0-9]{64})\b") {
                $expectedHash = $Matches[1].ToLower()
                $hashAlgorithm = "SHA256"
                break
            }
        }
    }

    if (-not $expectedHash) {
        $sha512Candidates = @(
            "$DownloadUrl.sha512sum",
            "$DownloadUrl.sha512",
            ($DownloadUrl -replace '\.iso$', '.sha512sum'),
            ($DownloadUrl -replace '\.iso$', '.sha512')
        )
        foreach ($cUrl in $sha512Candidates) {
            $content = Get-WebContent -Uri $cUrl
            if ($content -and $content -match "([a-fA-F0-9]{128})\b") {
                $expectedHash = $Matches[1].ToLower()
                $hashAlgorithm = "SHA512"
                break
            }
        }
    }

    if (-not $expectedHash) {
        Write-LogDetail -Message "Keine Online-SHA256/SHA512-Pruefsumme gefunden fuer $Filename. Ueberspringe Hash-Verifikation." -Color DarkGray
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
    if ($Filename -match '(?i)ubuntucinnamon')   { return "Ubuntu Cinnamon" }
    if ($Filename -match '(?i)ubuntu.*live-server') { return "Ubuntu Server LTS" }
    if ($Filename -match '(?i)ubuntu')           { return "Ubuntu Desktop" }
    if ($Filename -match '(?i)Zorin')            { return "Zorin OS" }
    
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
    if ($Filename -match '(?i)systemrescue')     { return "SystemRescue Toolkit" }
    
    if ($Filename -match '(?i)FreeBSD')          { return "FreeBSD Release" }

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
        "05_BSD-Unix"
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

    Write-Host ""
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host "                    DISTRIBUTIONS-AUSWAHL (MEHRFACHWAHL)                                 " -ForegroundColor Yellow
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host "Waehle aus, welche Distributionen kuenftig geprueft, geladen und synchronisiert werden:" -ForegroundColor White
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
            $statusStr = if ($d.Enabled -ne $false) { "[x]" } else { "[ ]" }
            $sizeMB = if ($d.SizeBytes) { [math]::Round([long]$d.SizeBytes / 1MB, 0) } else { 0 }
            $sizeStr = if ($sizeMB -gt 0) { "ca. $sizeMB MB" } else { "Groesse unbekannt" }
            $numFmt = "{0,2}" -f $numIndex
            Write-Host ("   {0}) {1} {2,-32} ({3})" -f $numFmt, $statusStr, $d.Name, $sizeStr) -ForegroundColor White
            $numIndex++
        }
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
    $promptMsg = if ($IsReconfiguration) {
        "Neue Auswahl eingeben (ENTER = bisherige Auswahl unveraendert beibehalten):"
    } else {
        "Auswahl eingeben (ENTER = alle standardmaessig aktivierten Distros uebernehmen):"
    }
    Write-Host $promptMsg -ForegroundColor Yellow
    $rawInput = Read-Host "Auswahl (z.B. all / G1, G3 / 1,4,7-10)"

    if ([string]::IsNullOrWhiteSpace($rawInput)) {
        return
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

function Install-VentoyTheme {
    param([string]$VentoyDir)

    $themeDir = Join-Path $VentoyDir "theme"
    $bgPath = Join-Path $themeDir "background.png"
    $selPath = Join-Path $themeDir "select_c.png"
    $themeTxtPath = Join-Path $themeDir "theme.txt"

    if ((Test-Path $bgPath) -and (Test-Path $selPath) -and (Test-Path $themeTxtPath)) {
        Write-Log -Message "[VENTOY] Modern Dark Theme-Dateien bereits auf Ziel-Laufwerk vorhanden. Kopiere nichts neu." -Color DarkGreen -Level "OK"
        return
    }

    if (-not (Test-Path $themeDir)) {
        New-Item -ItemType Directory -Path $themeDir -Force | Out-Null
    }

    try {
        Add-Type -AssemblyName System.Drawing
        $width = 1920
        $height = 1080
        $bmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $rect = New-Object System.Drawing.Rectangle 0, 0, $width, $height
        $c1 = [System.Drawing.ColorTranslator]::FromHtml('#0f172a')
        $c2 = [System.Drawing.ColorTranslator]::FromHtml('#1e1e2e')
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c2, 45.0
        $g.FillRectangle($brush, $rect)

        $headerRect = New-Object System.Drawing.Rectangle 0, 0, $width, 80
        $headerBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#1e293b'))
        $g.FillRectangle($headerBrush, $headerRect)

        $footerRect = New-Object System.Drawing.Rectangle 0, 1020, $width, 60
        $g.FillRectangle($headerBrush, $footerRect)

        $pen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#38bdf8')), 3
        $g.DrawLine($pen, 0, 80, $width, 80)
        $g.DrawLine($pen, 0, 1020, $width, 1020)

        $bmp.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()

        $bmpSel = New-Object System.Drawing.Bitmap(32, 36, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $gSel = [System.Drawing.Graphics]::FromImage($bmpSel)
        $rectSel = New-Object System.Drawing.Rectangle 0, 0, 32, 36
        $brushSel = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#38bdf8'))
        $gSel.FillRectangle($brushSel, $rectSel)
        $bmpSel.Save($selPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $gSel.Dispose(); $bmpSel.Dispose()
    } catch {}

    $themeTxtContent = @'
# Ventoy Modern Dark Theme
desktop-image: "background.png"
desktop-color: "#0f172a"
title-text: "VENTOY MULTIBOOT SYSTEM MANAGER"
title-color: "#38bdf8"
message-color: "#94a3b8"

+ boot_menu {
    left = 10%
    top = 12%
    width = 80%
    height = 78%
    item_color = "#94a3b8"
    selected_item_color = "#0f172a"
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
    color = "#94a3b8"
    align = "center"
}
'@ -replace "`r`n", "`n"
    try {
        [System.IO.File]::WriteAllText($themeTxtPath, $themeTxtContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log -Message "[VENTOY] Modern Dark Theme (1080p) auf Ziel-Laufwerk eingerichtet." -Color Green -Level "ERFOLG"
    } catch {
        Write-Log -Message "[VENTOY] Fehler beim Schreiben von theme.txt ($themeTxtPath): $_" -Color Red -Level "FEHLER"
    }
}

function Start-VentoyCopyJob {
    param(
        [string]$TargetDrive,
        [string]$SourceDir,
        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($TargetDrive)) {
        Write-Host "`n=========================================================" -ForegroundColor Cyan
        Write-Host " VENTOY ZIEL-LAUFWERK AUSWAHL" -ForegroundColor Cyan
        Write-Host "=========================================================" -ForegroundColor Cyan
        
        $drives = Get-CimInstance Win32_Volume | Where-Object { 
            $_.DriveLetter -and ($_.DriveType -eq 2 -or ($_.FileSystem -match "FAT32|exFAT|NTFS" -and $_.DriveLetter -ne "C:"))
        } | Select-Object DriveLetter, Label, FileSystem, @{Name="FreeGB"; Expression={[math]::Round($_.FreeSpace/1GB, 2)}}, @{Name="CapacityGB"; Expression={[math]::Round($_.Capacity/1GB, 2)}}

        if (-not $drives) {
            $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne "C" } | Select-Object @{Name="DriveLetter"; Expression={$_.Name + ":"}}, @{Name="Label"; Expression={$_.Description}}, @{Name="FileSystem"; Expression={""}}, @{Name="FreeGB"; Expression={[math]::Round($_.Free/1GB, 2)}}, @{Name="CapacityGB"; Expression={0}}
        }

        if (-not $drives) {
            Write-Log -Message "Keine passenden Ziel-Laufwerke gefunden. Bitte Parameter -TargetDrive angeben (z.B. -TargetDrive E:)" -Color Red -Level "FEHLER"
            return
        }

        Write-Host "Verfuegbare Laufwerke:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $drives.Count; $i++) {
            $d = $drives[$i]
            $labelStr = if ($d.Label) { "[$($d.Label)]" } else { "" }
            Write-Host " [$($i + 1)] $($d.DriveLetter) $labelStr ($($d.FreeGB) GB frei / $($d.CapacityGB) GB Gesamt)" -ForegroundColor White
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

    $TargetDriveLetter = $TargetDrive.TrimEnd('\').TrimEnd(':') + ":"
    $TargetDriveRoot   = $TargetDriveLetter + "\"

    if (-not (Test-Path $TargetDriveRoot)) {
        Write-Log -Message "Ziel-Laufwerk $TargetDriveRoot existiert nicht oder ist nicht bereit!" -Color Red -Level "FEHLER"
        return
    }

    $distrosJsonPath = Join-Path $SourceDir "distros.json"
    $distroPatterns = @()
    if (Test-Path $distrosJsonPath) {
        try {
            $rawJson = Get-Content $distrosJsonPath -Raw -Encoding UTF8
            $distroPatterns = $rawJson | ConvertFrom-Json
        } catch {}
    }

    $categoryFolders = Get-ChildItem -Path $SourceDir -Directory | Where-Object {
        $_.Name -notlike "*Archiv*" -and $_.Name -notlike "*scratch*" -and $_.Name -notlike ".*"
    }

    $isoFilesToCopy = @()
    foreach ($folder in $categoryFolders) {
        $isos = Get-ChildItem -Path $folder.FullName -Filter "*.iso" -Recurse -File
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
        Write-Log -Message "Keine ISO-Dateien zum Kopieren auf Ventoy gefunden." -Color Yellow -Level "WARNUNG"
        return
    }

    $totalBytesToCopy = ($isoFilesToCopy | Measure-Object -Property SizeBytes -Sum).Sum
    $totalGBToCopy = [math]::Round($totalBytesToCopy / 1GB, 2)

    $freeBytes = 0
    try {
        $driveObj = New-Object System.IO.DriveInfo($TargetDriveLetter)
        $freeBytes = $driveObj.AvailableFreeSpace
    } catch {}
    $freeGB = [math]::Round($freeBytes / 1GB, 2)

    Write-Host "-----------------------------------------------------------------"
    Write-Log -Message "Ventoy-Kopiervorgang vorbereiten nach: $TargetDriveRoot" -Color Cyan -Level "VENTOY"
    Write-Log -Message "Gefundene ISO-Dateien: $($isoFilesToCopy.Count) Dateien in $($categoryFolders.Count) Ordnern ($totalGBToCopy GB)" -Color Green -Level "INFO"
    Write-Log -Message "Freier Speicherplatz auf $($TargetDriveRoot): $freeGB GB" -Color DarkGray -Level "INFO"

    # Bereinigung abgewaehlter/deaktivierter Distributionen auf dem Ventoy-Ziel-Laufwerk
    $deselectedDistros = $distroPatterns | Where-Object { $_.PSObject.Properties['Enabled'] -and $_.Enabled -eq $false -and $_.MatchPattern }
    if ($deselectedDistros -and $deselectedDistros.Count -gt 0) {
        foreach ($folder in $categoryFolders) {
            $dstCatDir = Join-Path $TargetDriveRoot $folder.Name
            if (Test-Path $dstCatDir) {
                $targetIsosInDir = Get-ChildItem -Path $dstCatDir -Filter "*.iso" -File -ErrorAction SilentlyContinue
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

    foreach ($folder in $categoryFolders) {
        $srcCatDir = $folder.FullName
        $dstCatDir = Join-Path $TargetDriveRoot $folder.Name

        $catIsos = @($isoFilesToCopy | Where-Object { $_.CategoryFolder -eq $folder.Name })
        if ($catIsos.Count -eq 0) { continue }

        Write-Host "-----------------------------------------------------------------"
        Write-Log -Message "Kategorie: $($folder.Name) ($($catIsos.Count) ISOs | ca. $([math]::Round(($catIsos | Measure-Object -Property SizeBytes -Sum).Sum / 1GB, 2)) GB)" -Color Yellow -Level "ORDNER"

        if (-not $DryRun) {
            if (-not (Test-Path $dstCatDir)) {
                New-Item -ItemType Directory -Path $dstCatDir -Force | Out-Null
            }

            foreach ($iso in $catIsos) {
                # Bereinigung veralteter ISOs auf dem Ziel-Laufwerk
                $distroMatch = $distroPatterns | Where-Object { $iso.Filename -match $_.MatchPattern }
                $patternToUse = if ($distroMatch) { $distroMatch.MatchPattern } else { ($iso.Filename -replace '[-_\d\.]+\.iso$', '') }

                if ($patternToUse) {
                    $oldTargetIsos = Get-ChildItem -Path $dstCatDir -Filter "*.iso" -File -ErrorAction SilentlyContinue | Where-Object {
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
                    Write-Log -Message "[KOPPIEREN ABGESCHLOSSEN] $($iso.Filename)" -Color Green -Level "ERFOLG"
                }
            }
        } else {
            foreach ($iso in $catIsos) {
                Write-Log -Message "[DRY-RUN] Wuerde veraltete ISOs bereinigen und kopieren: $($iso.Filename) ($($iso.SizeMB) MB) -> $dstCatDir\$($iso.Filename)" -Color DarkGray -Level "DRY-RUN"
            }
        }
    }

    # Ventoy Design & JSON Konfiguration
    Write-Host "-----------------------------------------------------------------"
    Write-Log -Message "Konfiguriere Ventoy Design & Dir-Modus (Theme + Aliases) auf $TargetDriveRoot..." -Color Cyan -Level "VENTOY"

    $ventoyDir = Join-Path $TargetDriveRoot "ventoy"
    $ventoyJsonPath = Join-Path $ventoyDir "ventoy.json"

    if (-not $DryRun) {
        Install-VentoyTheme -VentoyDir $ventoyDir

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
                    @{ "image" = "/05_BSD-Unix";          "alias" = "BSD & Unix (FreeBSD...)" }
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
# SCHRITT 1: ISO-UPDATE & DOWNLOAD
# ==============================================================================
if (-not $SkipDownload) {
    # DISTRIBUTIONS-KONFIGURATION AUS distros.json
    $DistrosJsonFile = Join-Path $IsoDirectory "distros.json"
    $Distros = @()
    $distroList = $null
    $script:jsonModified = $false

    $existingIsosForCheck = Get-ChildItem -Path $IsoDirectory -Filter "*.iso" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notlike "*Archiv*" }
    $isInitialRun = ($null -eq $existingIsosForCheck -or $existingIsosForCheck.Count -eq 0)

    if (Test-Path $DistrosJsonFile) {
        try {
            $jsonRaw = Get-Content $DistrosJsonFile -Raw -Encoding UTF8
            $distroList = $jsonRaw | ConvertFrom-Json

            if ($isInitialRun -or $SelectDistros) {
                Select-DistrosInteractive -DistroList $distroList -IsReconfiguration:$SelectDistros
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
                    if (-not $fn -or $fn -notlike "*.iso") {
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

    $existingIsos = Get-ChildItem -Path $IsoDirectory -Filter "*.iso" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notlike "*Archiv*" }
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

    foreach ($distro in $Distros) {
        Write-Host "----------------------------------------------------------------- "
        Write-Log -Message "Pruefe Distribution: $($distro.Name)" -Color Yellow -Level "CHECK"

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
        $targetPath   = Join-Path $categoryDir $latestInfo.Filename

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
    if (-not [string]::IsNullOrWhiteSpace($TargetDrive)) {
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
        Start-VentoyCopyJob -TargetDrive $TargetDrive -SourceDir $IsoDirectory -DryRun:$DryRun
    }
}

if ($scriptMutex -and $createdNew) {
    try {
        $scriptMutex.ReleaseMutex()
        $scriptMutex.Dispose()
    } catch {}
}
