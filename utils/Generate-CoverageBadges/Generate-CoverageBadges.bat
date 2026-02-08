@echo off
REM Generate-CoverageBadges.bat - Wrapper for Generate-CoverageBadges.ps1
REM Runs tests and generates SVG coverage badges for README

pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generate-CoverageBadges.ps1" %*
set EXITCODE=%ERRORLEVEL%
popd
exit /b %EXITCODE%
