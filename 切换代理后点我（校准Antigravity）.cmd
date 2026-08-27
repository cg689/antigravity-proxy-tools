@echo off
rem ============================================================
rem  Antigravity Proxy Sync (manual entry)
rem  Double-click AFTER switching proxy software, or AFTER an
rem  Antigravity update broke the proxy. Then restart Antigravity.
rem  v4 (2026-08-26): script now SELF-HEALS - if the Antigravity
rem  update wiped version.dll / dbghelp.dll / config.json, they
rem  are restored from the local backup automatically, then the
rem  proxy port is calibrated. One double-click fixes everything.
rem  v3 (2026-08-24): pure ASCII + CRLF + self-locating path.
rem  (v2 was saved with LF line endings and broke cmd.exe parsing.)
rem ============================================================
echo ============================================================
echo   Antigravity Proxy Sync v4 - checking kit files and proxy...
echo   (Clash Verge:7897 / Mesl:7688 / v2rayN:10808)
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-AntigravityProxy.ps1"

echo.
echo ============================================================
echo   Latest log entries:
echo ============================================================
powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%~dp0sync.log' -Tail 3"
echo.
echo If you see SWITCHED or OK, restart Antigravity and you are done.
echo If you see REDEPLOYED, the update wiped the hijack files and they
echo were restored automatically - also just restart Antigravity.
echo If you see NO-PROXY, check your proxy app and its node first.
echo.
pause
