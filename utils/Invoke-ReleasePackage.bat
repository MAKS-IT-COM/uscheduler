@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0engines\release\Invoke-ReleasePackage.ps1" %*
pause
