@echo off
setlocal
pwsh -NoProfile -File "%~dp0engines\test\Invoke-TestEngine.ps1" %*
exit /b %ERRORLEVEL%
