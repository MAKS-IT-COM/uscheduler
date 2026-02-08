@echo off

REM Change directory to the location of the script
cd /d %~dp0

REM Run GitHub release script
powershell -ExecutionPolicy Bypass -File "%~dp0Release-ToGitHub.ps1"

pause
