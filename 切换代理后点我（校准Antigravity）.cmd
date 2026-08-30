@echo off
rem ============================================================
rem  Antigravity Proxy Sync (manual entry)
rem  Double-click AFTER switching proxy software, or AFTER an
rem  Antigravity update broke the proxy. Then restart Antigravity.
rem  Runs Sync-AntigravityProxy.ps1 (v3.3): SELF-HEALS (restores
rem  version.dll / dbghelp.dll / config.json from backup if the
rem  update wiped them) then auto-calibrates the proxy port among
rem  9 common apps plus a dynamic full-port scan. One double-click
rem  fixes everything. Then restart Antigravity.
rem ============================================================
echo ============================================================
echo   Antigravity Proxy Sync - checking kit files and proxy...
echo   (auto-detect: 9 common proxy apps + dynamic port scan)
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
