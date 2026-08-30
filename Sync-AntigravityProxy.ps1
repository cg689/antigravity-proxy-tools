# Sync-AntigravityProxy.ps1
# Two jobs, in order:
#   1. SELF-HEAL: if Antigravity's auto-update wiped the proxy hijack kit
#      (version.dll / dbghelp.dll / config.json), re-deploy them from the
#      local backup folder next to this script.
#   2. CALIBRATE: auto-detect which local proxy app is alive AND can reach
#      Google, then align Antigravity's config.json (port + type) with it.
# Safe to run repeatedly. Pure ASCII content on purpose.
#
# v3.3 (2026-08-30): code-review hardening.
#   - Field-level config.json edit (regex replace of port/type only, no
#     full ConvertTo-Json rewrite that could mangle a future config shape)
#   - Async port probe with a 1.5s cap (TcpClient default blocks ~21s)
#   - Explicit error handling when config.json is missing/unreadable/corrupt
#   - Single-instance mutex (double-click can't race on config.json/log)
#   - Dynamic scan skips known DB/service ports + uses a shorter 2s timeout
# v3.2 (2026-08-27): dynamic port-scan fallback added. If none of the 9
#   default candidates match, enumerate all local listening ports and try
#   each as http then socks5 - so a proxy on a CUSTOM port is auto-detected
#   too. Fully portable across machines and non-default setups.
# v3.1 (2026-08-27): candidate list expanded from 3 to 9 common Windows
#   proxy apps (Clash/Mihomo 7890, v2rayN HTTP 10809, Shadowsocks 1080,
#   NekoBox 2080, Hiddify 12334, Qv2ray 1089 added) so it works out of the
#   box on other machines, not just this one. Install dir now auto-detected
#   via %LOCALAPPDATA% instead of a hard-coded user path.
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

# --- single-instance guard: prevent two concurrent runs (e.g. double-click
# --- twice) from racing on config.json / sync.log. Local namespace, so it
# --- works without admin privileges. ---
$mutex = New-Object System.Threading.Mutex($false, "AntigravityProxySync")
if (-not $mutex.WaitOne(0)) {
    Write-Host "Another instance of this script is already running. Exiting." -ForegroundColor Yellow
    exit 0
}

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
# Covers common Windows proxy apps and their DEFAULT local ports so it
# works out-of-the-box for other people, not just this machine.
$candidates = @(
    @{ name = "Clash Verge";  port = 7897;  type = "socks5" },  # Clash Verge / Rev mixed port
    @{ name = "Clash/Mihomo"; port = 7890;  type = "http"   },  # Clash / Clash for Windows / FlClash mixed port
    @{ name = "v2rayN";       port = 10808; type = "socks5" },  # v2rayN SOCKS5
    @{ name = "v2rayN HTTP";  port = 10809; type = "http"   },  # v2rayN HTTP
    @{ name = "Shadowsocks";  port = 1080;  type = "socks5" },  # shadowsocks-windows
    @{ name = "NekoBox";      port = 2080;  type = "socks5" },  # NekoBox / NekoRay mixed port
    @{ name = "Hiddify";      port = 12334; type = "socks5" },  # Hiddify-Next mixed port
    @{ name = "Qv2ray";       port = 1089;  type = "socks5" },  # Qv2ray SOCKS5
    @{ name = "Mesl";         port = 7688;  type = "http"   }   # Mesl Lite
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
        # Async connect with a 1.5s cap: a firewalled (DROP-ed) port would
        # otherwise block on TcpClient.Connect for its ~21s default timeout,
        # which would stall the whole full-port scan.
        $iar = $tcp.BeginConnect("127.0.0.1", $port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500, $false)
        if ($ok) {
            $tcp.EndConnect($iar)
            $ok = $tcp.Connected
        }
        $tcp.Close()
        return $ok
    } catch {
        return $false
    }
}

function Test-Candidate([int]$port, [string]$type, [int]$timeoutSec = 5) {
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
    $code = & curl.exe -x $proxyUrl -s -o NUL -w "%{http_code}" --connect-timeout $timeoutSec "http://www.gstatic.com/generate_204" 2>$null
    if ($code -eq "204") {
        Write-Host "  [$port/$type] Google OK (204)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [$port/$type] Google FAILED (code=$code)" -ForegroundColor Red
        return $false
    }
}

# --- stage 0: sanity ---
Write-Host "=== Antigravity Proxy Sync v3.3 ===" -ForegroundColor Yellow
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

if ($null -eq $winner) {
    # Fallback: dynamic port scan - covers proxy apps on custom/non-default
    # ports that are NOT in the fixed candidate list. Enumerate every local
    # listening port and try each one as an http proxy, then socks5 proxy.
    Write-Host "No default candidate matched. Scanning all local listening ports..." -ForegroundColor Yellow
    $skipPorts = @($candidates | ForEach-Object { [int]$_.port })
    # Common DB / system-service ports that are never a proxy. Skipping them
    # avoids burning a 2x timeout on each one during the full-port scan.
    $knownNonProxy = @(135, 139, 445, 1433, 1521, 3306, 3389, 5432, 6379, 27017, 9200)
    $ports = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty LocalPort -Unique |
        Where-Object { $_ -ge 1024 -and ($skipPorts -notcontains [int]$_) -and ($knownNonProxy -notcontains [int]$_) } |
        Sort-Object
    foreach ($p in $ports) {
        $p = [int]$p
        # Shorter 2s timeout here (vs 5s for fixed candidates) to keep the
        # full-port scan fast on machines with many listening ports.
        foreach ($t in @("http", "socks5")) {
            if (Test-Candidate -port $p -type $t -timeoutSec 2) {
                $winner = @{ name = "Custom $p"; port = $p; type = $t }
                break
            }
        }
        if ($null -ne $winner) { break }
    }
}

Write-Host ""

# Read config as raw text and extract port/type via regex (field-level,
# keep original bytes). This avoids a ConvertFrom-Json -> ConvertTo-Json
# full rewrite, which could mangle the file if Antigravity changes its
# config shape in a future update (single-element arrays, depth > 10, etc).
try {
    $raw = Get-Content $configPath -Raw -Encoding UTF8
} catch {
    Write-Log "ERROR: cannot read config.json: $configPath ($($_.Exception.Message))"
    Write-Host "ERROR: cannot read config.json: $configPath" -ForegroundColor Red
    exit 1
}
$curPort = 0
$curType = ''
$m = [regex]::Match($raw, '"port"\s*:\s*(\d+)')
if ($m.Success) { $curPort = [int]$m.Groups[1].Value }
$m = [regex]::Match($raw, '"type"\s*:\s*"([^"]+)"')
if ($m.Success) { $curType = $m.Groups[1].Value }
if ($curPort -le 0 -or [string]::IsNullOrEmpty($curType)) {
    Write-Log "ERROR: config.json has no valid port/type - file may be corrupt. Not touching it."
    Write-Host "ERROR: config.json has no valid port/type - file may be corrupt. Not touched. Check the backup." -ForegroundColor Red
    exit 1
}

if ($null -eq $winner) {
    $candList = ($candidates | ForEach-Object { "$($_.name):$($_.port)" }) -join ', '
    Write-Log "NO-PROXY: none of the $($candidates.Count) candidates can reach Google. Config unchanged ($curType/$curPort). Check proxy apps and nodes."
    Write-Host "RESULT: NO-PROXY" -ForegroundColor Red
    Write-Host "None of the $($candidates.Count) proxy apps ($candList) can reach Google." -ForegroundColor Red
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

# Field-level rewrite: replace only the port and type values, preserving
# every other byte (comments, indentation, key order) exactly as-is.
$newRaw = [regex]::Replace($raw, '("port"\s*:\s*)\d+', ('${1}' + $winner.port))
$newRaw = [regex]::Replace($newRaw, '("type"\s*:\s*)"[^"]*"', ('${1}"' + $winner.type + '"'))
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($configPath, $newRaw, $utf8Bom)
Write-Log ("SWITCHED: {0}/{1} -> {2} {3}://127.0.0.1:{4} . Restart Antigravity to apply." -f $curType, $curPort, $winner.name, $winner.type, $winner.port)
Write-Host "RESULT: SWITCHED" -ForegroundColor Green
Write-Host "$curType/$curPort -> $($winner.name) $($winner.type)://127.0.0.1:$($winner.port)" -ForegroundColor Green
if ($redeployed) {
    Write-Host "Hijack kit was also just restored from backup." -ForegroundColor Yellow
}
Write-Host "Restart Antigravity to apply." -ForegroundColor Yellow
