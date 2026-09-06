@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Force-AmendTaggedCommit\Force-AmendTaggedCommit.ps1" %*
pause
