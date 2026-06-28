@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Update-RepoUtils\Update-RepoUtils.ps1" %*
pause
