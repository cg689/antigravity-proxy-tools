@echo off
rem Antigravity launcher with proxy auto-sync (rebuilt 2026-08-26).
rem v2: the sync script now SELF-HEALS after Antigravity updates
rem (restores version.dll / dbghelp.dll / config.json from backup,
rem then calibrates the proxy port), so this launcher alone is enough:
rem update happened -> just start Antigravity from here as usual.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-AntigravityProxy.ps1"
start "" "%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe"
