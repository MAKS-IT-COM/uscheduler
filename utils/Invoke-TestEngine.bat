@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0engines\test\Invoke-TestEngine.ps1" %*
pause
