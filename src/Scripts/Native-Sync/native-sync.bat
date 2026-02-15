@echo off
setlocal EnableDelayedExpansion

REM ============================================================================
REM Native Sync Launcher
REM VERSION: 1.0.0
REM DATE: 2026-01-26
REM DESCRIPTION: Batch file launcher for native-sync.ps1 with admin check
REM ============================================================================

echo.
echo ============================================
echo Native PowerShell Sync Launcher
echo ============================================
echo.

REM Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo [ERROR] This script must be run as Administrator!
    echo.
    echo Please right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo [OK] Running with Administrator privileges
echo.

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%native-sync.ps1"

REM Check if PowerShell script exists
if not exist "%PS_SCRIPT%" (
    echo [ERROR] PowerShell script not found: %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

echo [OK] Found PowerShell script: %PS_SCRIPT%
echo.
echo ============================================
echo Starting sync process...
echo ============================================
echo.

REM Execute PowerShell script
REM Note: Logging is handled by UScheduler service
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

REM Capture exit code
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo ============================================
echo Sync process completed
echo Exit Code: %EXIT_CODE%
echo ============================================
echo.

if %EXIT_CODE% EQU 0 (
    echo [SUCCESS] Sync completed successfully
) else (
    echo [ERROR] Sync completed with errors
)

echo.
pause

endlocal
exit /b %EXIT_CODE%
