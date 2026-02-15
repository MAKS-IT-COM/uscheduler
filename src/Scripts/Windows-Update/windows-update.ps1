[CmdletBinding()]
param (
    [switch]$Automated,
    [string]$CurrentDateTimeUtc
)

#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Automated Windows Update management with scheduling and reporting.
.DESCRIPTION
    Production-ready Windows Update automation using PSWindowsUpdate module.
    Supports scheduled updates, category filtering, exclusions, pre/post checks,
    and auto-reboot with maintenance window control.
.VERSION
    1.0.0
.DATE
    2026-01-28
.NOTES
    - Requires PSWindowsUpdate module (auto-installed if missing)
    - Requires SchedulerTemplate.psm1 module
#>

# Script Version
$ScriptVersion = "1.0.0"
$ScriptDate = "2026-01-28"

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
$requiredSettings = @('preChecks', 'options')
foreach ($setting in $requiredSettings) {
    if (-not $settings.$setting) {
        Write-Error "Required setting '$setting' is missing or empty in $settingsFile"
        exit 1
    }
}

# Validate updateCategories separately (can be string "all" or array)
if (-not $settings.updateCategories) {
    Write-Error "Required setting 'updateCategories' is missing in $settingsFile"
    exit 1
}

# Extract settings
$UpdateCategoriesSetting = $settings.updateCategories
$Exclusions = $settings.exclusions
$PreChecks = $settings.preChecks
$Options = $settings.options
$Reporting = $settings.reporting

# Process updateCategories - can be "all" or an array of category names
$InstallAllCategories = $false
$UpdateCategories = @()

if ($UpdateCategoriesSetting -is [string] -and $UpdateCategoriesSetting -eq "all") {
    $InstallAllCategories = $true
}
elseif ($UpdateCategoriesSetting -is [array]) {
    $UpdateCategories = $UpdateCategoriesSetting
}
else {
    Write-Error "Invalid updateCategories setting. Must be 'all' or an array of category names."
    exit 1
}

# Get DryRun from settings
$DryRun = $Options.dryRun

# Schedule Configuration
$Config = @{
    RunMonth = $settings.schedule.runMonth
    RunWeekday = $settings.schedule.runWeekday
    RunTime = $settings.schedule.runTime
    MinIntervalMinutes = $settings.schedule.minIntervalMinutes
}

# End Settings =============================================================

# Global variables
$script:UpdateStats = @{
    StartTime = Get-Date
    EndTime = $null
    Success = $false
    Installed = 0
    Failed = 0
    Skipped = 0
    RebootRequired = $false
    ErrorMessage = $null
}

# Helper Functions =========================================================

function Test-PSWindowsUpdate {
    param([switch]$Automated)

    Write-Log "Checking PSWindowsUpdate module..." -Level Info -Automated:$Automated

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "PSWindowsUpdate module not found. Installing..." -Level Warning -Automated:$Automated

        try {
            # Try to install from PSGallery
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
            Write-Log "PSWindowsUpdate module installed successfully" -Level Success -Automated:$Automated
        }
        catch {
            Write-Log "Failed to install PSWindowsUpdate module: $_" -Level Error -Automated:$Automated
            Write-Log "Please install manually: Install-Module PSWindowsUpdate -Force" -Level Info -Automated:$Automated
            return $false
        }
    }

    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-Log "PSWindowsUpdate module loaded" -Level Success -Automated:$Automated
        return $true
    }
    catch {
        Write-Log "Failed to import PSWindowsUpdate module: $_" -Level Error -Automated:$Automated
        return $false
    }
}

function Get-AllUpdateCategories {
    param([switch]$Automated)

    try {
        # Use Windows Update COM API
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        # Set to search Microsoft Update (includes more categories)
        $microsoftUpdateServiceId = "7971f918-a847-4430-9279-4a52d1efe18d"
        try {
            $updateSearcher.ServiceID = $microsoftUpdateServiceId
            $updateSearcher.ServerSelection = 3  # ssOthers
        }
        catch {
            # Fall back to default
        }

        $categories = @{}

        # Method 1: Search for pending and installed updates
        $searches = @("IsInstalled=0", "IsInstalled=1 and IsHidden=0")

        foreach ($searchCriteria in $searches) {
            try {
                $searchResult = $updateSearcher.Search($searchCriteria)
                foreach ($update in $searchResult.Updates) {
                    foreach ($cat in $update.Categories) {
                        # Filter by Type = "UpdateClassification" (excludes product names)
                        if ($cat.Name -and $cat.Type -eq "UpdateClassification") {
                            if (-not $categories.ContainsKey($cat.Name)) {
                                $categories[$cat.Name] = $true
                            }
                        }
                    }
                }
            }
            catch {
                # Continue with next search
            }
        }

        # Method 2: Also check update history for more categories
        try {
            $historyCount = $updateSearcher.GetTotalHistoryCount()
            if ($historyCount -gt 0) {
                $history = $updateSearcher.QueryHistory(0, [Math]::Min($historyCount, 200))
                foreach ($entry in $history) {
                    if ($entry.Categories) {
                        foreach ($cat in $entry.Categories) {
                            if ($cat.Name -and $cat.Type -eq "UpdateClassification") {
                                if (-not $categories.ContainsKey($cat.Name)) {
                                    $categories[$cat.Name] = $true
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            # History query failed, continue with what we have
        }

        return $categories
    }
    catch {
        return @{}
    }
}

function Test-PreUpdateChecks {
    param([switch]$Automated)

    Write-Log "Running pre-update checks..." -Level Info -Automated:$Automated

    # Check disk space
    $systemDrive = $env:SystemDrive
    $drive = Get-PSDrive -Name $systemDrive.TrimEnd(':')
    $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
    $minSpaceGB = $PreChecks.minDiskSpaceGB

    Write-Log "Free space on $systemDrive : $freeSpaceGB GB" -Level Info -Automated:$Automated

    if ($freeSpaceGB -lt $minSpaceGB) {
        Write-Log "Insufficient disk space. Required: $minSpaceGB GB, Available: $freeSpaceGB GB" -Level Error -Automated:$Automated
        return $false
    }

    # Check for pending reboot
    if ($PreChecks.checkPendingReboot) {
        $rebootRequired = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        if ($rebootRequired) {
            Write-Log "System has pending reboot from previous updates" -Level Warning -Automated:$Automated
            if ($Options.rebootBehavior -eq 'never') {
                Write-Log "Reboot required but rebootBehavior is 'never'" -Level Error -Automated:$Automated
                return $false
            }
        }
    }

    # Check Windows Update service
    $wuService = Get-Service -Name wuauserv
    if ($wuService.Status -ne 'Running') {
        Write-Log "Starting Windows Update service..." -Level Info -Automated:$Automated
        try {
            Start-Service -Name wuauserv -ErrorAction Stop
            Write-Log "Windows Update service started" -Level Success -Automated:$Automated
        }
        catch {
            Write-Log "Failed to start Windows Update service: $_" -Level Error -Automated:$Automated
            return $false
        }
    }

    Write-Log "Pre-update checks passed" -Level Success -Automated:$Automated
    return $true
}

function Update-DefenderSignatures {
    param([switch]$Automated)

    Write-Log "Updating Microsoft Defender signatures..." -Level Info -Automated:$Automated

    try {
        # Get current signature version before update
        $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        $beforeVersion = if ($defenderStatus) { $defenderStatus.AntivirusSignatureVersion } else { "Unknown" }

        # Update signatures using built-in cmdlet (more reliable than Windows Update)
        Update-MpSignature -ErrorAction Stop

        # Get new version
        $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        $afterVersion = if ($defenderStatus) { $defenderStatus.AntivirusSignatureVersion } else { "Unknown" }

        if ($beforeVersion -ne $afterVersion) {
            Write-Log "Defender signatures updated: $beforeVersion -> $afterVersion" -Level Success -Automated:$Automated
            $script:UpdateStats.Installed++
        }
        else {
            Write-Log "Defender signatures already up to date (Version: $afterVersion)" -Level Info -Automated:$Automated
        }

        return $true
    }
    catch {
        Write-Log "Failed to update Defender signatures: $_" -Level Warning -Automated:$Automated
        return $false
    }
}

function Invoke-WindowsUpdateRescan {
    param([switch]$Automated)

    Write-Log "Refreshing Windows Update UI..." -Level Info -Automated:$Automated

    try {
        # startinteractivescan refreshes the Windows Update GUI to reflect actual installed state
        $null = Start-Process -FilePath "UsoClient.exe" -ArgumentList "startinteractivescan" -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
        Write-Log "Windows Update UI refreshed" -Level Success -Automated:$Automated
    }
    catch {
        Write-Log "Could not refresh Windows Update UI: $_" -Level Warning -Automated:$Automated
    }
}

function Get-AvailableUpdates {
    param([switch]$Automated)

    Write-Log "Scanning for available updates..." -Level Info -Automated:$Automated

    try {
        # Get updates
        $updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose:$false | Where-Object {
            $update = $_
            $included = $false

            # Check categories - if "all", include everything; otherwise filter by category list
            if ($InstallAllCategories) {
                $included = $true
            }
            else {
                # Categories is a collection of Category objects with Name property
                foreach ($cat in $UpdateCategories) {
                    foreach ($updateCategory in $update.Categories) {
                        $categoryName = if ($updateCategory.Name) { $updateCategory.Name } else { $updateCategory.ToString() }
                        if ($categoryName -match $cat) {
                            $included = $true
                            break
                        }
                    }
                    if ($included) { break }
                }
            }

            # Apply KB exclusions
            if ($included -and $Exclusions.kbNumbers.Count -gt 0) {
                foreach ($kb in $Exclusions.kbNumbers) {
                    if ($update.KBArticleIDs -contains $kb) {
                        Write-Log "Excluded by KB: $($update.Title) [$kb]" -Level Info -Automated:$Automated
                        $included = $false
                        break
                    }
                }
            }

            # Apply title exclusions
            if ($included -and $Exclusions.titlePatterns.Count -gt 0) {
                foreach ($pattern in $Exclusions.titlePatterns) {
                    if ($update.Title -like $pattern) {
                        Write-Log "Excluded by pattern: $($update.Title) [$pattern]" -Level Info -Automated:$Automated
                        $included = $false
                        break
                    }
                }
            }

            # Exclude Defender signature updates (handled separately via Update-MpSignature)
            if ($included -and $update.Title -like "*Security Intelligence Update for Microsoft Defender*") {
                Write-Log "Skipping (handled separately): $($update.Title)" -Level Info -Automated:$Automated
                $included = $false
            }

            return $included
        }

        return $updates
    }
    catch {
        Write-Log "Failed to scan for updates: $_" -Level Error -Automated:$Automated
        return @()
    }
}

function Install-AvailableUpdates {
    param(
        $Updates,
        [switch]$Automated
    )

    if ($Updates.Count -eq 0) {
        Write-Log "No updates to install" -Level Info -Automated:$Automated
        return
    }

    Write-Log "Found $($Updates.Count) update(s) to install" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated

    foreach ($update in $Updates) {
        $sizeKB = [math]::Round($update.Size / 1KB, 2)
        $kbDisplay = if ($update.KBArticleIDs) { $update.KBArticleIDs -join ',' } else { "N/A" }
        Write-Log "  [$kbDisplay] $($update.Title) ($sizeKB KB)" -Level Info -Automated:$Automated
    }

    Write-Log "========================================" -Level Info -Automated:$Automated

    if ($DryRun) {
        Write-Log "DRY RUN MODE - No updates will be installed" -Level Warning -Automated:$Automated
        $script:UpdateStats.Skipped = $Updates.Count
        return
    }

    # Install updates - pipe directly to preserve update selection
    Write-Log "Installing updates..." -Level Info -Automated:$Automated

    try {
        $installParams = @{
            AcceptAll = $true
            IgnoreReboot = ($Options.rebootBehavior -ne 'auto')
            Verbose = $false
        }

        # Pipe updates directly to Install-WindowsUpdate for reliable installation
        $result = $Updates | Install-WindowsUpdate @installParams

        # Process results
        foreach ($item in $result) {
            if ($item.Result -eq "Installed" -or $item.Result -eq "Downloaded") {
                $script:UpdateStats.Installed++
                Write-Log "Installed: $($item.Title)" -Level Success -Automated:$Automated
            }
            elseif ($item.Result -eq "Failed") {
                $script:UpdateStats.Failed++
                Write-Log "Failed: $($item.Title)" -Level Error -Automated:$Automated
            }
            else {
                $script:UpdateStats.Skipped++
                Write-Log "Skipped: $($item.Title) [Result: $($item.Result)]" -Level Warning -Automated:$Automated
            }

            if ($item.RebootRequired) {
                $script:UpdateStats.RebootRequired = $true
            }
        }
    }
    catch {
        Write-Log "Update installation failed: $_" -Level Error -Automated:$Automated
        $script:UpdateStats.Failed = $Updates.Count
        $script:UpdateStats.ErrorMessage = "Installation failed: $_"
    }
}

function Invoke-PostUpdateActions {
    param([switch]$Automated)

    Write-Log "Running post-update actions..." -Level Info -Automated:$Automated

    # Check reboot requirement
    if ($script:UpdateStats.RebootRequired) {
        Write-Log "System reboot required" -Level Warning -Automated:$Automated

        if ($Options.rebootBehavior -eq 'auto') {
            $delayMinutes = $Options.rebootDelayMinutes
            Write-Log "System will reboot in $delayMinutes minutes..." -Level Warning -Automated:$Automated

            if ($delayMinutes -gt 0) {
                Start-Sleep -Seconds ($delayMinutes * 60)
            }

            # Remove lock file before reboot to prevent future runs from being blocked
            $lockFile = [IO.Path]::ChangeExtension($PSCommandPath, ".lock")
            if (Test-Path $lockFile) {
                Remove-Item $lockFile -Force
                Write-Log "Lock file removed before reboot" -Level Info -Automated:$Automated
            }

            Write-Log "Initiating system reboot..." -Level Warning -Automated:$Automated
            Restart-Computer -Force
        }
        else {
            Write-Log "Manual reboot required" -Level Warning -Automated:$Automated
        }
    }

    # Generate update report
    if ($Reporting.generateReport) {
        $reportPath = Join-Path $PSScriptRoot "update-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

        $reportContent = @"
Windows Update Report
=====================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Statistics:
-----------
Updates Installed: $($script:UpdateStats.Installed)
Updates Failed: $($script:UpdateStats.Failed)
Updates Skipped: $($script:UpdateStats.Skipped)
Reboot Required: $($script:UpdateStats.RebootRequired)

Recent Update History:
----------------------
"@

        try {
            $history = Get-WindowsUpdate -Last 10 -Verbose:$false
            foreach ($item in $history) {
                $reportContent += "`n[$($item.Date)] $($item.Title) - $($item.Result)"
            }
        }
        catch {
            $reportContent += "`nFailed to retrieve update history"
        }

        $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
        Write-Log "Report saved: $reportPath" -Level Success -Automated:$Automated

        # Send email notification if enabled
        if ($Reporting.emailNotification -and $Reporting.emailSettings) {
            $hostname = $env:COMPUTERNAME
            $status = if ($script:UpdateStats.Failed -eq 0) { "SUCCESS" } else { "COMPLETED WITH ERRORS" }
            $subject = "[$hostname] Windows Update Report - $status"

            Send-EmailNotification -EmailSettings $Reporting.emailSettings -Subject $subject -Body $reportContent -Automated:$Automated
        }
    }
}

function Write-UpdateSummary {
    param([switch]$Automated)

    $script:UpdateStats.EndTime = Get-Date
    $duration = $script:UpdateStats.EndTime - $script:UpdateStats.StartTime

    Write-Log "" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "UPDATE SUMMARY" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "Start Time    : $($script:UpdateStats.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "End Time      : $($script:UpdateStats.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "Duration      : $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -Level Info -Automated:$Automated
    Write-Log "Status        : $(if ($script:UpdateStats.Failed -eq 0) { 'SUCCESS' } else { 'COMPLETED WITH ERRORS' })" -Level $(if ($script:UpdateStats.Failed -eq 0) { 'Success' } else { 'Warning' }) -Automated:$Automated
    Write-Log "" -Level Info -Automated:$Automated
    Write-Log "Installed     : $($script:UpdateStats.Installed)" -Level Info -Automated:$Automated
    Write-Log "Failed        : $($script:UpdateStats.Failed)" -Level $(if ($script:UpdateStats.Failed -eq 0) { 'Info' } else { 'Error' }) -Automated:$Automated
    Write-Log "Skipped       : $($script:UpdateStats.Skipped)" -Level Info -Automated:$Automated
    Write-Log "Reboot Needed : $($script:UpdateStats.RebootRequired)" -Level Info -Automated:$Automated

    if ($script:UpdateStats.ErrorMessage) {
        Write-Log "" -Level Info -Automated:$Automated
        Write-Log "Error: $($script:UpdateStats.ErrorMessage)" -Level Error -Automated:$Automated
    }

    Write-Log "========================================" -Level Info -Automated:$Automated

    $script:UpdateStats.Success = ($script:UpdateStats.Failed -eq 0)
}

# Main Business Logic ======================================================

function Start-BusinessLogic {
    param([switch]$Automated)

    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "Windows Update Process Started" -Level Info -Automated:$Automated
    Write-Log "Script Version: $ScriptVersion ($ScriptDate)" -Level Info -Automated:$Automated
    if ($InstallAllCategories) {
        Write-Log "Update Categories: ALL" -Level Info -Automated:$Automated
        # Query and display all known categories from Windows Update
        $knownCategories = Get-AllUpdateCategories -Automated:$Automated
        if ($knownCategories.Count -gt 0) {
            $categoryList = ($knownCategories.Keys | Sort-Object) -join ', '
            Write-Log "  Available: $categoryList" -Level Info -Automated:$Automated
        }
        else {
            Write-Log "  Available: (unable to query)" -Level Info -Automated:$Automated
        }
    }
    else {
        Write-Log "Update Categories: $($UpdateCategories -join ', ')" -Level Info -Automated:$Automated
    }
    if ($DryRun) {
        Write-Log "DRY RUN MODE - No changes will be made" -Level Warning -Automated:$Automated
    }
    Write-Log "========================================" -Level Info -Automated:$Automated

    # Check PSWindowsUpdate module
    if (-not (Test-PSWindowsUpdate -Automated:$Automated)) {
        Write-Log "PSWindowsUpdate module check failed. Aborting." -Level Error -Automated:$Automated
        exit 1
    }

    # Run pre-update checks
    if (-not (Test-PreUpdateChecks -Automated:$Automated)) {
        Write-Log "Pre-update checks failed. Aborting." -Level Error -Automated:$Automated
        exit 1
    }

    # Update Microsoft Defender signatures first (more reliable than Windows Update)
    if (-not $DryRun) {
        $null = Update-DefenderSignatures -Automated:$Automated
    }
    else {
        Write-Log "DRY RUN: Skipping Defender signature update" -Level Info -Automated:$Automated
    }

    # Scan for updates
    $updates = Get-AvailableUpdates -Automated:$Automated

    if ($updates.Count -eq 0) {
        Write-Log "System is up to date. No updates available." -Level Success -Automated:$Automated
    }
    else {
        # Install updates
        Install-AvailableUpdates -Updates $updates -Automated:$Automated

        # Post-update actions
        Invoke-PostUpdateActions -Automated:$Automated
    }

    # Refresh Windows Update cache (clears stale pending updates from UI)
    if (-not $DryRun) {
        Invoke-WindowsUpdateRescan -Automated:$Automated
    }

    # Print summary
    Write-UpdateSummary -Automated:$Automated

    # Exit with appropriate code
    if ($script:UpdateStats.Failed -gt 0) {
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
