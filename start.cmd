@echo off
setlocal
cd /d "%~dp0"
if not exist "build\doodle_reef.exe" (
    echo Build the app first: powershell -ExecutionPolicy Bypass -File .\build.ps1
    pause
    exit /b 1
)
start "" "build\doodle_reef.exe"
