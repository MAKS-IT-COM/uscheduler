[CmdletBinding()]
param (
    [switch]$Automated,
    [string]$CurrentDateTimeUtc
)

#Requires -RunAsAdministrator

<#
.SYNOPSIS
    FreeFileSync Automated Backup Script
.DESCRIPTION
    Production-ready file synchronization solution with scheduling and secure credential management.
.VERSION
    1.0.1
.DATE
    2026-01-26
.NOTES
    - Requires FreeFileSync installed
    - Requires SchedulerTemplate.psm1 module
    - Requires sync.ffs_batch configuration file
#>

# Script Version
$ScriptVersion = "1.0.1"
$ScriptDate = "2026-01-26"

try {
    Import-Module "$PSScriptRoot\..\SchedulerTemplate.psm1" -Force -ErrorAction Stop
}
catch {
    Write-Error "Failed to load SchedulerTemplate.psm1: $_"
    exit 1
}

# Load Settings ============================================================

$settingsFile = Join-Path $PSScriptRoot "scriptsettings.json"

if (-not (Test-Path $settingsFile)) {
    Write-Error "Settings file not found: $settingsFile"
    exit 1
}

try {
    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
    Write-Verbose "Loaded settings from $settingsFile"
}
catch {
    Write-Error "Failed to load settings from $settingsFile : $_"
    exit 1
}

# Process Settings =========================================================

# Validate required settings
$requiredSettings = @('freeFileSyncExe', 'batchFile', 'nasRootShare')
foreach ($setting in $requiredSettings) {
    if (-not $settings.$setting) {
        Write-Error "Required setting '$setting' is missing or empty in $settingsFile"
        exit 1
    }
}

$FreeFileSyncExe = $settings.freeFileSyncExe
$FfsBatchFile = Join-Path $PSScriptRoot $settings.batchFile
$NasRootShare = $settings.nasRootShare
$CredentialEnvVar = $settings.credentialEnvVar

# Schedule Configuration
$Config = @{
    RunMonth = $settings.schedule.runMonth
    RunWeekday = $settings.schedule.runWeekday
    RunTime = $settings.schedule.runTime
    MinIntervalMinutes = $settings.schedule.minIntervalMinutes
}

# End Settings =============================================================

# Global variables
$script:SyncStats = @{
    StartTime = Get-Date
    EndTime = $null
    Success = $false
    ExitCode = $null
    ErrorMessage = $null
}

# Global reference to the process so that the exit handler can see it
$global:FFS_Process = $null

# Helper Functions =========================================================

function Test-Prerequisites {
    param([switch]$Automated)

    Write-Log "Checking prerequisites..." -Level Info -Automated:$Automated

    # Check if FreeFileSync executable exists
    if (-not (Test-Path -LiteralPath $FreeFileSyncExe)) {
        Write-Log "FreeFileSync not found: $FreeFileSyncExe" -Level Error -Automated:$Automated
        Write-Log "Please install FreeFileSync or update the path in scriptsettings.json" -Level Error -Automated:$Automated
        return $false
    }

    # Verify FreeFileSync version
    try {
        $ffsVersion = (Get-Item $FreeFileSyncExe).VersionInfo.FileVersion
        Write-Log "FreeFileSync version: $ffsVersion" -Level Info -Automated:$Automated
    }
    catch {
        Write-Log "Warning: Could not determine FreeFileSync version" -Level Warning -Automated:$Automated
    }

    # Check if batch file exists
    if (-not (Test-Path -LiteralPath $FfsBatchFile)) {
        Write-Log "Batch config not found: $FfsBatchFile" -Level Error -Automated:$Automated
        Write-Log "Please create sync.ffs_batch configuration file" -Level Error -Automated:$Automated
        return $false
    }

    Write-Log "All prerequisites passed" -Level Success -Automated:$Automated
    return $true
}

function Connect-NasShare {
    param(
        [string]$SharePath,
        [switch]$Automated
    )

    # Check if path is UNC
    if (-not $SharePath.StartsWith("\\")) {
        Write-Log "NAS path is local, no authentication needed" -Level Info -Automated:$Automated
        return $true
    }

    # Validate UNC path format
    if (-not (Test-UNCPath -Path $SharePath)) {
        Write-Log "Invalid UNC path format: $SharePath (expected \\server\share)" -Level Error -Automated:$Automated
        return $false
    }

    Write-Log "Authenticating to NAS share: $SharePath" -Level Info -Automated:$Automated

    # Validate credential environment variable name is configured
    if (-not $CredentialEnvVar) {
        Write-Log "credentialEnvVar is not configured in settings for UNC path authentication" -Level Error -Automated:$Automated
        return $false
    }

    try {
        # Retrieve credentials from environment variable
        $creds = Get-CredentialFromEnvVar -EnvVarName $CredentialEnvVar -Automated:$Automated

        if (-not $creds) {
            return $false
        }

        # Check if already connected
        $existingConnection = net use | Select-String $SharePath
        if ($existingConnection) {
            Write-Log "Already connected to $SharePath" -Level Info -Automated:$Automated
            return $true
        }

        # Connect to share
        $netUseResult = cmd /c "net use $SharePath $($creds.Password) /user:$($creds.Username) 2>&1"

        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to connect to $SharePath : $netUseResult" -Level Error -Automated:$Automated
            return $false
        }

        Write-Log "Successfully authenticated to $SharePath" -Level Success -Automated:$Automated
        return $true
    }
    catch {
        Write-Log "Error connecting to share: $_" -Level Error -Automated:$Automated
        return $false
    }
}

function Test-NasReachability {
    param(
        [string]$SharePath,
        [switch]$Automated
    )

    if (-not (Test-Path $SharePath)) {
        Write-Log "NAS share $SharePath is not reachable after authentication" -Level Warning -Automated:$Automated
        return $false
    }

    Write-Log "NAS share is reachable: $SharePath" -Level Success -Automated:$Automated
    return $true
}

function Start-FreeFileSyncProcess {
    param([switch]$Automated)

    Write-Log "Starting FreeFileSync batch synchronization..." -Level Info -Automated:$Automated
    Write-Log "  EXE:   $FreeFileSyncExe" -Level Info -Automated:$Automated
    Write-Log "  BATCH: $FfsBatchFile" -Level Info -Automated:$Automated

    # Ensure FreeFileSync is killed if PowerShell exits gracefully
    Register-EngineEvent PowerShell.Exiting -Action {
        if ($global:FFS_Process -and -not $global:FFS_Process.HasExited) {
            try {
                $global:FFS_Process.Kill()
            }
            catch {
            }
        }
    } | Out-Null

    try {
        # Use ProcessStartInfo to ensure that no window is shown
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FreeFileSyncExe
        $psi.Arguments  = "`"$FfsBatchFile`""
        $psi.WorkingDirectory = [System.IO.Path]::GetDirectoryName($FreeFileSyncExe)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $global:FFS_Process = $proc

        # Capture FFS console output
        $stdOut = $proc.StandardOutput.ReadToEnd()
        $stdErr = $proc.StandardError.ReadToEnd()

        $proc.WaitForExit()
        $exitCode = $proc.ExitCode

        if ($stdOut) {
            Write-Log "FreeFileSync STDOUT:" -Level Info -Automated:$Automated
            Write-Log $stdOut.TrimEnd() -Level Info -Automated:$Automated
        }

        if ($stdErr) {
            Write-Log "FreeFileSync STDERR:" -Level Warning -Automated:$Automated
            Write-Log $stdErr.TrimEnd() -Level Warning -Automated:$Automated
        }

        # Store exit code
        $script:SyncStats.ExitCode = $exitCode

        # Interpret exit code
        switch ($exitCode) {
            0 {
                Write-Log "FreeFileSync completed successfully (exit code 0)" -Level Success -Automated:$Automated
                $script:SyncStats.Success = $true
                return $true
            }
            1 {
                Write-Log "FreeFileSync completed with warnings (exit code 1)" -Level Warning -Automated:$Automated
                $script:SyncStats.Success = $true
                return $true
            }
            2 {
                Write-Log "FreeFileSync completed with errors (exit code 2)" -Level Error -Automated:$Automated
                $script:SyncStats.ErrorMessage = "FreeFileSync reported errors"
                return $false
            }
            3 {
                Write-Log "FreeFileSync was cancelled (exit code 3)" -Level Warning -Automated:$Automated
                $script:SyncStats.ErrorMessage = "FreeFileSync was cancelled"
                return $false
            }
            default {
                Write-Log "FreeFileSync exited with unexpected code $exitCode" -Level Error -Automated:$Automated
                $script:SyncStats.ErrorMessage = "Unexpected exit code: $exitCode"
                return $false
            }
        }
    }
    catch {
        Write-Log "Failed to execute FreeFileSync: $_" -Level Error -Automated:$Automated
        $script:SyncStats.ErrorMessage = "Execution failed: $_"
        return $false
    }
    finally {
        if ($global:FFS_Process -and -not $global:FFS_Process.HasExited) {
            Write-Log "PowerShell is stopping. Killing FreeFileSync process (PID $($global:FFS_Process.Id))..." -Level Warning -Automated:$Automated
            try {
                $global:FFS_Process.Kill()
            }
            catch {
                Write-Log "Failed to kill FreeFileSync process: $_" -Level Error -Automated:$Automated
            }
        }
    }
}

function Write-SyncSummary {
    param([switch]$Automated)

    $script:SyncStats.EndTime = Get-Date
    $duration = $script:SyncStats.EndTime - $script:SyncStats.StartTime

    Write-Log "" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "SYNC SUMMARY" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "Start Time    : $($script:SyncStats.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "End Time      : $($script:SyncStats.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "Duration      : $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -Level Info -Automated:$Automated
    Write-Log "Status        : $(if ($script:SyncStats.Success) { 'SUCCESS' } else { 'FAILED' })" -Level $(if ($script:SyncStats.Success) { 'Success' } else { 'Error' }) -Automated:$Automated
    Write-Log "Exit Code     : $($script:SyncStats.ExitCode)" -Level Info -Automated:$Automated

    if ($script:SyncStats.ErrorMessage) {
        Write-Log "Error         : $($script:SyncStats.ErrorMessage)" -Level Error -Automated:$Automated
    }

    Write-Log "========================================" -Level Info -Automated:$Automated
}

# Main Business Logic ======================================================

function Start-BusinessLogic {
    param([switch]$Automated)

    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "FreeFileSync Process Started" -Level Info -Automated:$Automated
    Write-Log "Script Version: $ScriptVersion ($ScriptDate)" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated

    # Check prerequisites
    if (-not (Test-Prerequisites -Automated:$Automated)) {
        Write-Log "Prerequisites check failed. Aborting sync." -Level Error -Automated:$Automated
        exit 1
    }

    # Connect to NAS share
    if (-not (Connect-NasShare -SharePath $NasRootShare -Automated:$Automated)) {
        Write-Log "Failed to connect to NAS share. Aborting sync." -Level Error -Automated:$Automated
        exit 1
    }

    # Verify NAS reachability
    if (-not (Test-NasReachability -SharePath $NasRootShare -Automated:$Automated)) {
        Write-Log "NAS share is not reachable. Continuing anyway..." -Level Warning -Automated:$Automated
    }

    # Execute FreeFileSync
    $syncResult = Start-FreeFileSyncProcess -Automated:$Automated

    # Print summary
    Write-SyncSummary -Automated:$Automated

    # Exit with appropriate code
    if (-not $syncResult) {
        exit 1
    }
}

# Entry Point ==============================================================

if ($Automated) {
    if (Get-Command Invoke-ScheduledExecution -ErrorAction SilentlyContinue) {
        $params = @{
            Config = $Config
            Automated = $Automated
            CurrentDateTimeUtc = $CurrentDateTimeUtc
            ScriptBlock = { Start-BusinessLogic -Automated:$Automated }
        }
        Invoke-ScheduledExecution @params
    }
    else {
        Write-Log "Invoke-ScheduledExecution not available. Execution aborted." -Level Error -Automated:$Automated
        exit 1
    }
}
else {
    Write-Log "Manual execution started" -Level Info -Automated:$Automated
    Start-BusinessLogic -Automated:$Automated
}
