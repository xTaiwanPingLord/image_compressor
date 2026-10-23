@echo off
echo Building Windows app, first build may take 5-10 minutes...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1"
if errorlevel 1 pause
