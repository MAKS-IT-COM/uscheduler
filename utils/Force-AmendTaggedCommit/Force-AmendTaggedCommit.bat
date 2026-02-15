@echo off

REM Change directory to the location of the script
cd /d %~dp0

REM Run Force Amend Tagged Commit script
powershell -ExecutionPolicy Bypass -File "%~dp0Force-AmendTaggedCommit.ps1"

pause
