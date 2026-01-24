[CmdletBinding()]
param (
    [switch]$Automated,
    [string]$CurrentDateTimeUtc
)

#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

<#
.SYNOPSIS
    Hyper-V Automated Backup Script
.DESCRIPTION
    Production-ready Hyper-V backup solution with scheduling, checkpoints, and retention management.
.VERSION
    1.0.0
.DATE
    2026-01-24
.NOTES
    - Requires Administrator privileges
    - Requires Hyper-V PowerShell module
    - Requires SchedulerTemplate.psm1 module
#>

# Script Version
$ScriptVersion = "1.0.0"
$ScriptDate = "2026-01-24"

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
$requiredSettings = @('backupRoot', 'tempExportRoot', 'retentionCount')
foreach ($setting in $requiredSettings) {
    if (-not $settings.$setting) {
        Write-Error "Required setting '$setting' is missing or empty in $settingsFile"
        exit 1
    }
}

$BackupRoot = $settings.backupRoot
$CredentialEnvVar = $settings.credentialEnvVar
$TempExportRoot = $settings.tempExportRoot
$RetentionCount = $settings.retentionCount
$MinFreeSpaceGB = $settings.minFreeSpaceGB
$BlacklistedVMs = $settings.excludeVMs

# Schedule Configuration
$Config = @{
    RunMonth = $settings.schedule.runMonth
    RunWeekday = $settings.schedule.runWeekday
    RunTime = $settings.schedule.runTime
    MinIntervalMinutes = $settings.schedule.minIntervalMinutes
}

# Set hostname and backup path
$Hostname = ($env:COMPUTERNAME).ToLower()
$BackupPath = "$BackupRoot\Hyper-V\Backups\$Hostname"

# Validate and set temp directory
if (-not (Test-Path $TempExportRoot)) {
    try {
        $TempExportRoot = [System.IO.Path]::GetTempPath()
    }
    catch {
        $TempExportRoot = $env:TEMP
    }
}

# End Settings =============================================================

# Global variables
$script:BackupStats = @{
    TotalVMs = 0
    SuccessfulVMs = 0
    FailedVMs = 0
    SkippedVMs = 0
    StartTime = Get-Date
    EndTime = $null
    FailureMessages = @()
}

# Helper Functions =========================================================

function Test-Prerequisites {
    param([switch]$Automated)
    
    Write-Log "Checking prerequisites..." -Level Info -Automated:$Automated

    # Check if running as Administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Script must be run as Administrator!" -Level Error -Automated:$Automated
        return $false
    }

    # Check Hyper-V module
    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        Write-Log "Hyper-V PowerShell module is not installed!" -Level Error -Automated:$Automated
        return $false
    }

    # Check Hyper-V service
    $hvService = Get-Service -Name vmms -ErrorAction SilentlyContinue
    if (-not $hvService -or $hvService.Status -ne 'Running') {
        Write-Log "Hyper-V Virtual Machine Management service is not running!" -Level Error -Automated:$Automated
        return $false
    }

    # Check temp directory
    if (-not (Test-Path $TempExportRoot)) {
        try {
            New-Item -Path $TempExportRoot -ItemType Directory -Force | Out-Null
            Write-Log "Created temp directory: $TempExportRoot" -Level Success -Automated:$Automated
        }
        catch {
            Write-Log "Failed to create temp directory: $_" -Level Error -Automated:$Automated
            return $false
        }
    }

    # Check free space on temp drive
    if ($MinFreeSpaceGB -gt 0) {
        $tempDrive = (Get-Item $TempExportRoot).PSDrive.Name
        $freeSpace = (Get-PSDrive $tempDrive).Free / 1GB
        
        if ($freeSpace -lt $MinFreeSpaceGB) {
            Write-Log "Insufficient free space on drive ${tempDrive}: ($([math]::Round($freeSpace, 2)) GB available, $MinFreeSpaceGB GB required)" -Level Error -Automated:$Automated
            return $false
        }
        
        Write-Log "Free space on drive ${tempDrive}: $([math]::Round($freeSpace, 2)) GB" -Level Info -Automated:$Automated
    }

    Write-Log "All prerequisites passed" -Level Success -Automated:$Automated
    return $true
}

function Connect-BackupShare {
    param(
        [string]$SharePath,
        [switch]$Automated
    )

    # Check if path is UNC
    if (-not $SharePath.StartsWith("\\")) {
        Write-Log "Backup path is local, no authentication needed" -Level Info -Automated:$Automated
        return $true
    }

    Write-Log "Authenticating to UNC share: $SharePath" -Level Info -Automated:$Automated

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

function Get-VMDiskSize {
    param(
        [string]$VMName,
        [switch]$Automated
    )

    try {
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        $vhds = $vm | Get-VMHardDiskDrive | Get-VHD -ErrorAction SilentlyContinue
        
        if ($vhds) {
            $totalSize = ($vhds | Measure-Object -Property FileSize -Sum).Sum
            return $totalSize
        }
        
        return 0
    }
    catch {
        Write-Log "Warning: Could not determine disk size for VM '$VMName': $_" -Level Warning -Automated:$Automated
        return 0
    }
}

function Backup-VM {
    param(
        [string]$VMName,
        [string]$BackupFolder,
        [string]$DateSuffix,
        [switch]$Automated
    )

    Write-Log "=== Processing VM: $VMName ===" -Level Info -Automated:$Automated

    try {
        # Check if VM exists
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        
        # Check VM state
        $vmState = $vm.State
        Write-Log "VM '$VMName' state: $vmState" -Level Info -Automated:$Automated

        # Check if backup already exists
        $vmBackupPath = Join-Path -Path $BackupFolder -ChildPath $VMName
        if (Test-Path $vmBackupPath) {
            Write-Log "Backup for VM '$VMName' already exists at '$vmBackupPath'. Skipping..." -Level Warning -Automated:$Automated
            $script:BackupStats.SkippedVMs++
            return $false
        }

        # Estimate required space
        $vmDiskSize = Get-VMDiskSize -VMName $VMName -Automated:$Automated
        if ($vmDiskSize -gt 0) {
            $vmDiskSizeGB = [math]::Round($vmDiskSize / 1GB, 2)
            Write-Log "VM '$VMName' estimated size: $vmDiskSizeGB GB" -Level Info -Automated:$Automated
            
            # Check if enough temp space
            if ($MinFreeSpaceGB -gt 0) {
                $tempDrive = (Get-Item $TempExportRoot).PSDrive.Name
                $freeSpace = (Get-PSDrive $tempDrive).Free
                
                if ($freeSpace -lt ($vmDiskSize * 1.5)) {
                    Write-Log "Insufficient temp space for VM '$VMName' (need ~$([math]::Round($vmDiskSize * 1.5 / 1GB, 2)) GB, have $([math]::Round($freeSpace / 1GB, 2)) GB)" -Level Error -Automated:$Automated
                    $script:BackupStats.FailedVMs++
                    $script:BackupStats.FailureMessages += "Insufficient space for $VMName"
                    return $false
                }
            }
        }

        # Create checkpoint
        Write-Log "Creating checkpoint for VM '$VMName'..." -Level Info -Automated:$Automated
        $checkpointName = "Backup-$DateSuffix"
        
        try {
            Checkpoint-VM -Name $VMName -SnapshotName $checkpointName -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to create checkpoint for VM '$VMName': $_" -Level Error -Automated:$Automated
            $script:BackupStats.FailedVMs++
            $script:BackupStats.FailureMessages += "Checkpoint failed for $VMName"
            return $false
        }

        # Verify checkpoint
        $checkpoint = Get-VMSnapshot -VMName $VMName -Name $checkpointName -ErrorAction SilentlyContinue
        if (-not $checkpoint) {
            Write-Log "Checkpoint verification failed for VM '$VMName'" -Level Error -Automated:$Automated
            $script:BackupStats.FailedVMs++
            $script:BackupStats.FailureMessages += "Checkpoint verification failed for $VMName"
            return $false
        }

        Write-Log "Checkpoint created successfully: $checkpointName" -Level Success -Automated:$Automated

        # Export VM to temp location
        $tempExportPath = Join-Path -Path $TempExportRoot -ChildPath "$VMName-$DateSuffix"
        Write-Log "Exporting VM '$VMName' to temp location: $tempExportPath" -Level Info -Automated:$Automated
        
        try {
            Export-VM -Name $VMName -Path $tempExportPath -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to export VM '$VMName': $_" -Level Error -Automated:$Automated
            
            # Cleanup temp if export failed
            if (Test-Path $tempExportPath) {
                Remove-Item -Path $tempExportPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $script:BackupStats.FailedVMs++
            $script:BackupStats.FailureMessages += "Export failed for $VMName"
            return $false
        }

        Write-Log "Export completed successfully" -Level Success -Automated:$Automated

        # Copy to NAS
        Write-Log "Copying VM '$VMName' export to backup location: $vmBackupPath" -Level Info -Automated:$Automated
        
        try {
            if (-not (Test-Path $vmBackupPath)) {
                New-Item -Path $vmBackupPath -ItemType Directory -Force | Out-Null
            }
            
            Copy-Item -Path "$tempExportPath\*" -Destination $vmBackupPath -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to copy VM '$VMName' to backup location: $_" -Level Error -Automated:$Automated
            
            # Cleanup partial backup
            if (Test-Path $vmBackupPath) {
                Remove-Item -Path $vmBackupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $script:BackupStats.FailedVMs++
            $script:BackupStats.FailureMessages += "Copy to NAS failed for $VMName"
            return $false
        }

        Write-Log "Copy to backup location completed successfully" -Level Success -Automated:$Automated

        # Cleanup temp export
        Write-Log "Cleaning up temp export for VM '$VMName'..." -Level Info -Automated:$Automated
        
        try {
            if (Test-Path $tempExportPath) {
                Remove-Item -Path $tempExportPath -Recurse -Force -ErrorAction Stop
            }
            Write-Log "Temp cleanup completed" -Level Success -Automated:$Automated
        }
        catch {
            Write-Log "Warning: Failed to cleanup temp export: $_" -Level Warning -Automated:$Automated
        }

        Write-Log "=== Backup completed successfully for VM: $VMName ===" -Level Success -Automated:$Automated
        $script:BackupStats.SuccessfulVMs++
        return $true
    }
    catch {
        Write-Log "Unexpected error processing VM '$VMName': $_" -Level Error -Automated:$Automated
        $script:BackupStats.FailedVMs++
        $script:BackupStats.FailureMessages += "Unexpected error for $VMName : $_"
        return $false
    }
}

function Remove-OldCheckpoints {
    param(
        [array]$VMs,
        [switch]$Automated
    )

    Write-Log "Starting checkpoint cleanup for all VMs..." -Level Info -Automated:$Automated
    
    $totalCheckpoints = 0
    
    foreach ($vm in $VMs) {
        $vmName = $vm.Name
        
        try {
            $checkpoints = Get-VMSnapshot -VMName $vmName -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -like "Backup-*" }

            if ($checkpoints) {
                foreach ($checkpoint in $checkpoints) {
                    Write-Log "Removing checkpoint '$($checkpoint.Name)' from VM '$vmName'..." -Level Info -Automated:$Automated
                    
                    try {
                        Remove-VMSnapshot -VMName $vmName -Name $checkpoint.Name -Confirm:$false -ErrorAction Stop
                        $totalCheckpoints++
                    }
                    catch {
                        Write-Log "Warning: Failed to remove checkpoint '$($checkpoint.Name)' from VM '$vmName': $_" -Level Warning -Automated:$Automated
                    }
                }
            }
        }
        catch {
            Write-Log "Warning: Error accessing checkpoints for VM '$vmName': $_" -Level Warning -Automated:$Automated
        }
    }
    
    Write-Log "Checkpoint cleanup completed. Removed $totalCheckpoints checkpoint(s)" -Level Success -Automated:$Automated
}

function Remove-OldBackups {
    param(
        [string]$BackupPath,
        [int]$RetentionCount,
        [switch]$Automated
    )

    Write-Log "Starting old backup cleanup (retention: $RetentionCount most recent)..." -Level Info -Automated:$Automated

    try {
        if (-not (Test-Path $BackupPath)) {
            Write-Log "Backup path does not exist, skipping cleanup" -Level Warning -Automated:$Automated
            return
        }

        $backupDirs = Get-ChildItem -Path $BackupPath -Directory -ErrorAction Stop | 
                      Sort-Object Name -Descending

        if ($backupDirs.Count -le $RetentionCount) {
            Write-Log "Only $($backupDirs.Count) backup(s) found, no cleanup needed" -Level Info -Automated:$Automated
            return
        }

        $dirsToRemove = $backupDirs | Select-Object -Skip $RetentionCount
        $removedCount = 0

        foreach ($dir in $dirsToRemove) {
            Write-Log "Removing old backup folder: $($dir.Name)" -Level Info -Automated:$Automated
            
            try {
                Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
                $removedCount++
            }
            catch {
                Write-Log "Warning: Failed to remove backup folder '$($dir.Name)': $_" -Level Warning -Automated:$Automated
            }
        }

        Write-Log "Old backup cleanup completed. Removed $removedCount backup folder(s)" -Level Success -Automated:$Automated
    }
    catch {
        Write-Log "Error during backup cleanup: $_" -Level Error -Automated:$Automated
    }
}

function Write-BackupSummary {
    param([switch]$Automated)

    $script:BackupStats.EndTime = Get-Date
    $duration = $script:BackupStats.EndTime - $script:BackupStats.StartTime
    
    Write-Log "" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "BACKUP SUMMARY" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "Start Time    : $($script:BackupStats.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "End Time      : $($script:BackupStats.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "Duration      : $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -Level Info -Automated:$Automated
    Write-Log "Total VMs     : $($script:BackupStats.TotalVMs)" -Level Info -Automated:$Automated
    Write-Log "Successful    : $($script:BackupStats.SuccessfulVMs)" -Level Success -Automated:$Automated
    Write-Log "Failed        : $($script:BackupStats.FailedVMs)" -Level $(if ($script:BackupStats.FailedVMs -gt 0) { 'Error' } else { 'Info' }) -Automated:$Automated
    Write-Log "Skipped       : $($script:BackupStats.SkippedVMs)" -Level Info -Automated:$Automated
    
    if ($script:BackupStats.FailureMessages.Count -gt 0) {
        Write-Log "" -Level Info -Automated:$Automated
        Write-Log "ERRORS:" -Level Error -Automated:$Automated
        foreach ($failureMsg in $script:BackupStats.FailureMessages) {
            Write-Log "  - $failureMsg" -Level Error -Automated:$Automated
        }
    }
    
    Write-Log "========================================" -Level Info -Automated:$Automated
}

# Main Business Logic ======================================================

function Start-BusinessLogic {
    param([switch]$Automated)

    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "Hyper-V Backup Process Started" -Level Info -Automated:$Automated
    Write-Log "Script Version: $ScriptVersion ($ScriptDate)" -Level Info -Automated:$Automated
    Write-Log "Host: $Hostname" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated

    # Check prerequisites
    if (-not (Test-Prerequisites -Automated:$Automated)) {
        Write-Log "Prerequisites check failed. Aborting backup." -Level Error -Automated:$Automated
        exit 1
    }

    # Connect to backup share
    if (-not (Connect-BackupShare -SharePath $BackupRoot -Automated:$Automated)) {
        Write-Log "Failed to connect to backup share. Aborting backup." -Level Error -Automated:$Automated
        exit 1
    }

    # Create backup destination if it doesn't exist
    if (-not (Test-Path $BackupPath)) {
        Write-Log "Backup path does not exist. Creating: $BackupPath" -Level Info -Automated:$Automated
        try {
            New-Item -Path $BackupPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Created backup path: $BackupPath" -Level Success -Automated:$Automated
        }
        catch {
            Write-Log "Failed to create backup path '$BackupPath': $_" -Level Error -Automated:$Automated
            exit 1
        }
    }

    # Get all VMs
    try {
        $vms = Get-VM -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to retrieve VMs: $_" -Level Error -Automated:$Automated
        exit 1
    }

    if (-not $vms -or $vms.Count -eq 0) {
        Write-Log "No VMs found on this host. Aborting backup." -Level Warning -Automated:$Automated
        exit 0
    }

    $script:BackupStats.TotalVMs = $vms.Count
    Write-Log "Found $($vms.Count) VM(s) on this host" -Level Info -Automated:$Automated

    # Create backup folder with timestamp
    $dateSuffix = Get-Date -Format "yyyyMMddHHmmss"
    $backupFolder = Join-Path -Path $BackupPath -ChildPath $dateSuffix

    try {
        New-Item -Path $backupFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Log "Created backup folder: $backupFolder" -Level Success -Automated:$Automated
    }
    catch {
        Write-Log "Failed to create backup folder '$backupFolder': $_" -Level Error -Automated:$Automated
        exit 1
    }

    # Process each VM
    foreach ($vm in $vms) {
        $vmName = $vm.Name

        if ($BlacklistedVMs -contains $vmName) {
            Write-Log "Skipping blacklisted VM: $vmName" -Level Warning -Automated:$Automated
            $script:BackupStats.SkippedVMs++
            continue
        }

        Backup-VM -VMName $vmName -BackupFolder $backupFolder -DateSuffix $dateSuffix -Automated:$Automated
    }

    # Cleanup old checkpoints
    Remove-OldCheckpoints -VMs $vms -Automated:$Automated

    # Cleanup old backups
    Remove-OldBackups -BackupPath $BackupPath -RetentionCount $RetentionCount -Automated:$Automated

    # Print summary
    Write-BackupSummary -Automated:$Automated
}

# Entry Point ==============================================================

if ($Automated) {
    if (Get-Command Invoke-ScheduledExecution -ErrorAction SilentlyContinue) {
        Invoke-ScheduledExecution `
            -Config $Config `
            -Automated:$Automated `
            -CurrentDateTimeUtc $CurrentDateTimeUtc `
            -ScriptBlock { Start-BusinessLogic -Automated:$Automated }
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