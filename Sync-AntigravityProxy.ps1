# Sync-AntigravityProxy.ps1
# Two jobs, in order:
#   1. SELF-HEAL: if Antigravity's auto-update wiped the proxy hijack kit
#      (version.dll / dbghelp.dll / config.json), re-deploy them from the
#      local backup folder next to this script.
#   2. CALIBRATE: auto-detect which local proxy app is alive AND can reach
#      Google, then align Antigravity's config.json (port + type) with it.
# Safe to run repeatedly. Pure ASCII content on purpose.
#
# v3.0 (2026-08-26): SELF-HEAL stage added. Antigravity auto-updated on
#   2026-08-25 and wiped version.dll + config.json from the install dir
#   (known behaviour, manual section 4.1). Now one double-click restores
#   the kit AND calibrates the port - no manual file copying anymore.
#   Also deploys dbghelp.dll (part of the v2.2 kit, agy.exe CLI shim).
#   Backup path is derived from $PSScriptRoot (no Chinese literal in the
#   code, immune to encoding misreads, works wherever this folder lives).
# v2.2 (2026-08-24): Log path derived from $PSScriptRoot.
# v2.1 (2026-08-22): Moved to the E: drive management folder.
# v2   (2026-08-22): TcpClient instead of Test-NetConnection (faster),
#   retry rounds for proxy port warmup after switching proxy apps.

$ErrorActionPreference = 'SilentlyContinue'

# --- paths (install dir auto-detected, no hard-coded user name; backup = next to this script) ---
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\antigravity'
if (-not (Test-Path $installDir)) {
    # fallback: find the newest antigravity* folder under %LOCALAPPDATA%\Programs
    $found = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'antigravity*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($found) { $installDir = $found.FullName }
}
$configPath = Join-Path $installDir 'config.json'
$backupDir  = Join-Path $PSScriptRoot 'antigravity-proxy-setup\extracted'
$logFile    = Join-Path $PSScriptRoot 'sync.log'

# The hijack kit that Antigravity updates wipe.
$kitFiles = @('version.dll', 'dbghelp.dll', 'config.json')

# Priority order: first candidate that passes BOTH tests wins.
$candidates = @(
    @{ name = "Clash Verge"; port = 7897;  type = "socks5" },
    @{ name = "Mesl";        port = 7688;  type = "http"   },
    @{ name = "v2rayN";      port = 10808; type = "socks5" }
)

# How many seconds to wait and retry if no port is found on first pass.
# This handles the race condition: user just switched proxy apps, the new
# one is still starting up and hasn't opened its port yet.
$retryRounds = 3
$retryWait   = 5  # seconds between rounds

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    # trim log if it grows beyond ~256KB
    $f = Get-Item $logFile
    if ($f.Length -gt 262144) {
        $tail = Get-Content $logFile -Tail 200
        Set-Content -Path $logFile -Value $tail -Encoding UTF8
    }
}

function Test-PortFast([int]$port) {
    # Use raw TcpClient instead of Test-NetConnection:
    # - 5x faster (no ping, no progress bar, no ICMP)
    # - Returns clean boolean, no noise
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", $port)
        $ok = $tcp.Connected
        $tcp.Close()
        return $ok
    } catch {
        return $false
    }
}

function Test-Candidate([int]$port, [string]$type) {
    # Layer 1: is anything listening on 127.0.0.1:port?
    if (-not (Test-PortFast $port)) {
        Write-Host "  [$port/$type] port not listening" -ForegroundColor DarkGray
        return $false
    }
    Write-Host "  [$port/$type] port is listening, testing Google..." -ForegroundColor Cyan
    # Layer 2: can this proxy actually reach Google? (204 = reachable, 000 = dead node)
    # IMPORTANT: socks5h (not socks5) = remote DNS resolution. Local DNS for google.com/gstatic.com
    # is poisoned in CN and would produce false negatives for socks5 candidates.
    $scheme = $type
    if ($type -eq "socks5") { $scheme = "socks5h" }
    $proxyUrl = ("{0}://127.0.0.1:{1}" -f $scheme, $port)
    $code = & curl.exe -x $proxyUrl -s -o NUL -w "%{http_code}" --connect-timeout 5 "http://www.gstatic.com/generate_204" 2>$null
    if ($code -eq "204") {
        Write-Host "  [$port/$type] Google OK (204)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [$port/$type] Google FAILED (code=$code)" -ForegroundColor Red
        return $false
    }
}

# --- stage 0: sanity ---
Write-Host "=== Antigravity Proxy Sync v3 ===" -ForegroundColor Yellow
Write-Host ""

if (-not (Test-Path $installDir)) {
    Write-Log "ERROR: Antigravity install dir not found: $installDir"
    Write-Host "ERROR: Antigravity install dir not found: $installDir" -ForegroundColor Red
    Write-Host "Antigravity may have moved to a new install path. Update the installDir line in this script." -ForegroundColor Red
    exit 1
}

# --- stage 1: self-heal the hijack kit (fixes 'Antigravity updated, proxy broke') ---
Write-Host "--- Stage 1: checking hijack kit in install dir ---" -ForegroundColor Yellow
$missing = @($kitFiles | Where-Object { -not (Test-Path (Join-Path $installDir $_)) })
$redeployed = $false

if ($missing.Count -eq 0) {
    Write-Host "Kit OK: version.dll + dbghelp.dll + config.json all present." -ForegroundColor Green
} else {
    Write-Host "Missing after Antigravity update: $($missing -join ', ')" -ForegroundColor Red
    $noBackup = @($missing | Where-Object { -not (Test-Path (Join-Path $backupDir $_)) })
    if ($noBackup.Count -gt 0) {
        Write-Log "ERROR: files missing in BOTH install dir and backup: $($noBackup -join ', ')"
        Write-Host "ERROR: these files are missing in the backup too: $($noBackup -join ', ')" -ForegroundColor Red
        Write-Host "Backup folder: $backupDir" -ForegroundColor Red
        Write-Host "Re-download antigravity-proxy v2.2 (win-x64 zip) and unpack its files into that backup folder." -ForegroundColor Red
        exit 1
    }
    foreach ($f in $missing) {
        Copy-Item -LiteralPath (Join-Path $backupDir $f) -Destination (Join-Path $installDir $f) -Force
    }
    $redeployed = $true
    Write-Log "REDEPLOYED: $($missing -join ', ') restored from backup (Antigravity update had wiped them)."
    Write-Host "REDEPLOYED from backup: $($missing -join ', ')" -ForegroundColor Green
}
Write-Host ""

# --- stage 2: calibrate config.json to the live proxy app ---
Write-Host "--- Stage 2: detecting active proxy ---" -ForegroundColor Yellow

if (-not (Test-Path $configPath)) {
    # Safety net - should be unreachable after stage 1.
    Write-Log "ERROR: config.json still missing at $configPath after self-heal."
    Write-Host "ERROR: config.json still missing! Check the backup folder." -ForegroundColor Red
    exit 1
}

$winner = $null

for ($round = 1; $round -le $retryRounds; $round++) {
    if ($round -gt 1) {
        Write-Host "Retry ${round}/${retryRounds} (waiting ${retryWait}s for proxy to start)..." -ForegroundColor Yellow
        Start-Sleep -Seconds $retryWait
    }
    Write-Host "Round ${round} - Testing $($candidates.Count) candidates..." -ForegroundColor Yellow
    foreach ($c in $candidates) {
        if (Test-Candidate -port $c.port -type $c.type) { $winner = $c; break }
    }
    if ($null -ne $winner) { break }
    Write-Host ""
}

Write-Host ""

$json = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$curPort = [int]$json.proxy.port
$curType = [string]$json.proxy.type

if ($null -eq $winner) {
    Write-Log "NO-PROXY: none of the 3 candidates can reach Google. Config unchanged ($curType/$curPort). Check proxy apps and nodes."
    Write-Host "RESULT: NO-PROXY" -ForegroundColor Red
    Write-Host "None of the 3 proxy apps (Clash Verge:7897, Mesl:7688, v2rayN:10808) can reach Google." -ForegroundColor Red
    Write-Host "Check: 1) Is a proxy app running? 2) Is its node alive (not dead/blocked)?" -ForegroundColor Red
    if ($redeployed) {
        Write-Host "Note: hijack kit WAS restored, so the DLL part is fixed - only the proxy app side needs attention." -ForegroundColor Yellow
    }
    exit 0
}

if ($curPort -eq $winner.port -and $curType -eq $winner.type) {
    Write-Log ("OK: {0} ({1}://127.0.0.1:{2}) matches config, no change." -f $winner.name, $winner.type, $winner.port)
    Write-Host "RESULT: OK" -ForegroundColor Green
    Write-Host "$($winner.name) ($($winner.type)://127.0.0.1:$($winner.port)) matches config, no change needed." -ForegroundColor Green
    if ($redeployed) {
        Write-Host "Hijack kit was just restored - restart Antigravity to load it." -ForegroundColor Yellow
    }
    exit 0
}

$json.proxy.port = $winner.port
$json.proxy.type = $winner.type
$json | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
Write-Log ("SWITCHED: {0}/{1} -> {2} {3}://127.0.0.1:{4} . Restart Antigravity to apply." -f $curType, $curPort, $winner.name, $winner.type, $winner.port)
Write-Host "RESULT: SWITCHED" -ForegroundColor Green
Write-Host "$curType/$curPort -> $($winner.name) $($winner.type)://127.0.0.1:$($winner.port)" -ForegroundColor Green
if ($redeployed) {
    Write-Host "Hijack kit was also just restored from backup." -ForegroundColor Yellow
}
Write-Host "Restart Antigravity to apply." -ForegroundColor Yellow
