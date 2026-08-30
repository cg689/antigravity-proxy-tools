@echo off
rem Antigravity launcher with proxy auto-sync (2026-08-30).
rem Runs Sync-AntigravityProxy.ps1 (v3.3), which SELF-HEALS after
rem Antigravity updates (restores version.dll / dbghelp.dll / config.json
rem from backup, then auto-calibrates the proxy port among 9 common apps
rem plus a dynamic full-port scan), then launches Antigravity.
rem Update happened -> just double-click this file as usual.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-AntigravityProxy.ps1"
start "" "%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe"
