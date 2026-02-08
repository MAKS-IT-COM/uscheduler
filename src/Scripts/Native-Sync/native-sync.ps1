[CmdletBinding()]
param (
    [switch]$Automated,
    [string]$CurrentDateTimeUtc
)

#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Native PowerShell File Synchronization Script
.DESCRIPTION
    Production-ready file synchronization solution using pure PowerShell.
    Supports Mirror, Update, and TwoWay sync modes with filtering,
    progress reporting, and secure credential management.
.VERSION
    1.0.0
.DATE
    2026-01-26
.NOTES
    - No external dependencies (pure PowerShell)
    - Requires SchedulerTemplate.psm1 module
    - Supports local and UNC paths
#>

# Script Version
$ScriptVersion = "1.0.0"
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
$requiredSettings = @('syncMode', 'folderPairs')
foreach ($setting in $requiredSettings) {
    if (-not $settings.$setting) {
        Write-Error "Required setting '$setting' is missing or empty in $settingsFile"
        exit 1
    }
}

# Extract settings
$SyncMode = $settings.syncMode
$CompareMethod = if ($settings.compareMethod) { $settings.compareMethod } else { "TimeAndSize" }
$DeletionPolicy = if ($settings.deletionPolicy) { $settings.deletionPolicy } else { "RecycleBin" }
$VersioningFolder = $settings.versioningFolder
$FolderPairs = $settings.folderPairs
$Filters = $settings.filters
$Options = $settings.options
$NasRootShare = $settings.nasRootShare
$CredentialEnvVar = $settings.credentialEnvVar

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
$script:SyncStats = @{
    StartTime = Get-Date
    EndTime = $null
    Success = $false
    FilesScanned = 0
    FilesCopied = 0
    FilesUpdated = 0
    FilesDeleted = 0
    FilesSkipped = 0
    BytesCopied = 0
    Errors = 0
    Warnings = 0
    ErrorMessages = @()
}

# Helper Functions =========================================================

function Test-FilterMatch {
    param(
        [string]$RelativePath,
        [array]$IncludePatterns,
        [array]$ExcludePatterns
    )

    # Check exclude patterns first
    foreach ($pattern in $ExcludePatterns) {
        # Handle directory patterns (ending with \)
        if ($pattern.EndsWith('\')) {
            $dirPattern = $pattern.TrimEnd('\')
            if ($RelativePath -like "*$dirPattern*") {
                return $false
            }
        }
        # Handle file patterns
        elseif ($RelativePath -like $pattern) {
            return $false
        }
        # Handle wildcard patterns like *\thumbs.db
        elseif ($pattern.StartsWith('*\')) {
            $filePattern = $pattern.Substring(2)
            if ($RelativePath -like "*\$filePattern" -or $RelativePath -eq $filePattern) {
                return $false
            }
        }
    }

    # Check include patterns
    if ($IncludePatterns.Count -eq 0 -or ($IncludePatterns.Count -eq 1 -and $IncludePatterns[0] -eq '*')) {
        return $true
    }

    foreach ($pattern in $IncludePatterns) {
        if ($RelativePath -like $pattern) {
            return $true
        }
    }

    return $false
}

function Get-RelativePath {
    param(
        [string]$FullPath,
        [string]$BasePath
    )

    $BasePath = $BasePath.TrimEnd('\')
    if ($FullPath.StartsWith($BasePath, [StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($BasePath.Length).TrimStart('\')
    }
    return $FullPath
}

function Get-LongPath {
    param(
        [string]$Path
    )

    # Add \\?\ prefix for long path support (>260 chars) on Windows
    # Skip if already prefixed or if it's a relative path
    if ($Path.StartsWith('\\?\') -or $Path.StartsWith('\\?\UNC\')) {
        return $Path
    }

    # Handle UNC paths: \\server\share -> \\?\UNC\server\share
    if ($Path.StartsWith('\\')) {
        return '\\?\UNC\' + $Path.Substring(2)
    }

    # Handle local paths: C:\path -> \\?\C:\path
    if ($Path.Length -ge 2 -and $Path[1] -eq ':') {
        return '\\?\' + $Path
    }

    return $Path
}

function Compare-FileByTimeAndSize {
    param(
        [System.IO.FileInfo]$SourceFile,
        [System.IO.FileInfo]$DestFile,
        [switch]$IgnoreTimeShift
    )

    if (-not $DestFile -or -not $DestFile.Exists) {
        return "LeftOnly"
    }

    if (-not $SourceFile -or -not $SourceFile.Exists) {
        return "RightOnly"
    }

    # Compare sizes first
    if ($SourceFile.Length -ne $DestFile.Length) {
        if ($SourceFile.LastWriteTimeUtc -gt $DestFile.LastWriteTimeUtc) {
            return "LeftNewer"
        }
        else {
            return "RightNewer"
        }
    }

    # Compare times
    $timeDiff = ($SourceFile.LastWriteTimeUtc - $DestFile.LastWriteTimeUtc).TotalSeconds

    # Handle DST time shift (1 hour = 3600 seconds)
    if ($IgnoreTimeShift) {
        $timeDiff = $timeDiff % 3600
    }

    if ([Math]::Abs($timeDiff) -lt 2) {
        return "Same"
    }
    elseif ($timeDiff -gt 0) {
        return "LeftNewer"
    }
    else {
        return "RightNewer"
    }
}

function Get-AllItems {
    param(
        [string]$Path,
        [switch]$ExcludeSymlinks,
        [switch]$Automated
    )

    $items = @{
        Files = @{}
        Directories = @{}
    }

    $longPath = Get-LongPath -Path $Path

    if (-not (Test-Path -LiteralPath $longPath)) {
        Write-Log "Path does not exist: $Path" -Level Warning -Automated:$Automated
        return $items
    }

    try {
        $allItems = Get-ChildItem -LiteralPath $longPath -Recurse -Force -ErrorAction SilentlyContinue

        foreach ($item in $allItems) {
            # Skip symlinks if configured
            if ($ExcludeSymlinks -and $item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                continue
            }

            # Strip the long path prefix for relative path calculation
            $itemPath = $item.FullName
            if ($itemPath.StartsWith('\\?\UNC\')) {
                $itemPath = '\\' + $itemPath.Substring(8)
            }
            elseif ($itemPath.StartsWith('\\?\')) {
                $itemPath = $itemPath.Substring(4)
            }

            $relativePath = Get-RelativePath -FullPath $itemPath -BasePath $Path

            if ($item.PSIsContainer) {
                $items.Directories[$relativePath] = $item
            }
            else {
                $items.Files[$relativePath] = $item
            }
        }
    }
    catch {
        Write-Log "Error scanning path $Path : $_" -Level Error -Automated:$Automated
        $script:SyncStats.Errors++
    }

    return $items
}

function Get-SyncActions {
    param(
        [hashtable]$SourceItems,
        [hashtable]$DestItems,
        [string]$SyncMode,
        [string]$SourcePath,
        [string]$DestPath,
        [array]$IncludePatterns,
        [array]$ExcludePatterns,
        [switch]$IgnoreTimeShift,
        [switch]$Automated
    )

    $actions = @()

    # Process source files
    foreach ($relativePath in $SourceItems.Files.Keys) {
        $script:SyncStats.FilesScanned++

        # Check filters
        if (-not (Test-FilterMatch -RelativePath $relativePath -IncludePatterns $IncludePatterns -ExcludePatterns $ExcludePatterns)) {
            $script:SyncStats.FilesSkipped++
            continue
        }

        $sourceFile = $SourceItems.Files[$relativePath]
        $destFile = $DestItems.Files[$relativePath]

        $comparison = Compare-FileByTimeAndSize -SourceFile $sourceFile -DestFile $destFile -IgnoreTimeShift:$IgnoreTimeShift

        $action = $null

        switch ($comparison) {
            "LeftOnly" {
                $action = @{
                    Type = "Copy"
                    Source = $sourceFile.FullName
                    Destination = Join-Path $DestPath $relativePath
                    RelativePath = $relativePath
                    Size = $sourceFile.Length
                }
            }
            "LeftNewer" {
                $action = @{
                    Type = "Update"
                    Source = $sourceFile.FullName
                    Destination = Join-Path $DestPath $relativePath
                    RelativePath = $relativePath
                    Size = $sourceFile.Length
                }
            }
            "RightNewer" {
                switch ($SyncMode) {
                    "Mirror" {
                        # Mirror overwrites right with left
                        $action = @{
                            Type = "Update"
                            Source = $sourceFile.FullName
                            Destination = Join-Path $DestPath $relativePath
                            RelativePath = $relativePath
                            Size = $sourceFile.Length
                        }
                    }
                    "TwoWay" {
                        # TwoWay updates left from right
                        $action = @{
                            Type = "Update"
                            Source = $destFile.FullName
                            Destination = $sourceFile.FullName
                            RelativePath = $relativePath
                            Size = $destFile.Length
                            Direction = "ToLeft"
                        }
                    }
                    # Update mode: skip
                }
            }
            "Same" {
                $script:SyncStats.FilesSkipped++
            }
        }

        if ($action) {
            $actions += $action
        }
    }

    # Process destination-only files
    foreach ($relativePath in $DestItems.Files.Keys) {
        if ($SourceItems.Files.ContainsKey($relativePath)) {
            continue  # Already processed
        }

        $script:SyncStats.FilesScanned++

        # Check filters
        if (-not (Test-FilterMatch -RelativePath $relativePath -IncludePatterns $IncludePatterns -ExcludePatterns $ExcludePatterns)) {
            $script:SyncStats.FilesSkipped++
            continue
        }

        $destFile = $DestItems.Files[$relativePath]

        switch ($SyncMode) {
            "Mirror" {
                $actions += @{
                    Type = "Delete"
                    Source = $null
                    Destination = $destFile.FullName
                    RelativePath = $relativePath
                    Size = $destFile.Length
                }
            }
            "TwoWay" {
                $actions += @{
                    Type = "Copy"
                    Source = $destFile.FullName
                    Destination = Join-Path $SourcePath $relativePath
                    RelativePath = $relativePath
                    Size = $destFile.Length
                    Direction = "ToLeft"
                }
            }
            # Update mode: skip destination-only files
            default {
                $script:SyncStats.FilesSkipped++
            }
        }
    }

    # Process directories (for deletion in Mirror mode)
    if ($SyncMode -eq "Mirror") {
        foreach ($relativePath in $DestItems.Directories.Keys) {
            if (-not $SourceItems.Directories.ContainsKey($relativePath)) {
                # Check if directory should be excluded
                if (-not (Test-FilterMatch -RelativePath $relativePath -IncludePatterns $IncludePatterns -ExcludePatterns $ExcludePatterns)) {
                    continue
                }

                $actions += @{
                    Type = "DeleteDir"
                    Source = $null
                    Destination = $DestItems.Directories[$relativePath].FullName
                    RelativePath = $relativePath
                    Size = 0
                }
            }
        }
    }

    return $actions
}

function Remove-ToRecycleBin {
    param(
        [string]$Path
    )

    Add-Type -AssemblyName Microsoft.VisualBasic
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path
        if ($item.PSIsContainer) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
        else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
    }
}

function Invoke-SyncAction {
    param(
        [hashtable]$Action,
        [string]$DeletionPolicy,
        [string]$VersioningFolder,
        [switch]$DryRun,
        [switch]$ShowProgress,
        [switch]$Automated
    )

    $actionType = $Action.Type
    $source = $Action.Source
    $destination = $Action.Destination
    $relativePath = $Action.RelativePath
    $size = $Action.Size
    $direction = if ($Action.Direction) { " ($($Action.Direction))" } else { "" }

    # Format size for display
    $sizeDisplay = if ($size -gt 1MB) {
        "{0:N2} MB" -f ($size / 1MB)
    }
    elseif ($size -gt 1KB) {
        "{0:N2} KB" -f ($size / 1KB)
    }
    else {
        "$size bytes"
    }

    $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }

    try {
        switch ($actionType) {
            "Copy" {
                if ($ShowProgress) {
                    Write-Log "$prefix[COPY]$direction $relativePath ($sizeDisplay)" -Level Info -Automated:$Automated
                }

                if (-not $DryRun) {
                    $destDir = Split-Path $destination -Parent
                    $longDestDir = Get-LongPath -Path $destDir
                    $longSource = Get-LongPath -Path $source
                    $longDest = Get-LongPath -Path $destination

                    if (-not (Test-Path -LiteralPath $longDestDir)) {
                        New-Item -Path $longDestDir -ItemType Directory -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $longSource -Destination $longDest -Force
                    $script:SyncStats.FilesCopied++
                    $script:SyncStats.BytesCopied += $size
                }
                else {
                    $script:SyncStats.FilesCopied++
                }
            }
            "Update" {
                if ($ShowProgress) {
                    Write-Log "$prefix[UPDATE]$direction $relativePath ($sizeDisplay)" -Level Info -Automated:$Automated
                }

                if (-not $DryRun) {
                    $longSource = Get-LongPath -Path $source
                    $longDest = Get-LongPath -Path $destination
                    Copy-Item -LiteralPath $longSource -Destination $longDest -Force
                    $script:SyncStats.FilesUpdated++
                    $script:SyncStats.BytesCopied += $size
                }
                else {
                    $script:SyncStats.FilesUpdated++
                }
            }
            "Delete" {
                if ($ShowProgress) {
                    Write-Log "$prefix[DELETE] $relativePath ($sizeDisplay)" -Level Warning -Automated:$Automated
                }

                if (-not $DryRun) {
                    $longDest = Get-LongPath -Path $destination
                    switch ($DeletionPolicy) {
                        "RecycleBin" {
                            Remove-ToRecycleBin -Path $destination
                        }
                        "Versioning" {
                            if ($VersioningFolder) {
                                $versionPath = Join-Path $VersioningFolder $relativePath
                                $versionDir = Split-Path $versionPath -Parent
                                $longVersionDir = Get-LongPath -Path $versionDir
                                $longVersionPath = Get-LongPath -Path $versionPath
                                if (-not (Test-Path -LiteralPath $longVersionDir)) {
                                    New-Item -Path $longVersionDir -ItemType Directory -Force | Out-Null
                                }
                                Move-Item -LiteralPath $longDest -Destination $longVersionPath -Force
                            }
                            else {
                                Remove-Item -LiteralPath $longDest -Force
                            }
                        }
                        default {
                            # Permanent
                            Remove-Item -LiteralPath $longDest -Force
                        }
                    }
                    $script:SyncStats.FilesDeleted++
                }
                else {
                    $script:SyncStats.FilesDeleted++
                }
            }
            "DeleteDir" {
                if ($ShowProgress) {
                    Write-Log "$prefix[DELETE DIR] $relativePath" -Level Warning -Automated:$Automated
                }

                if (-not $DryRun) {
                    $longDest = Get-LongPath -Path $destination
                    switch ($DeletionPolicy) {
                        "RecycleBin" {
                            Remove-ToRecycleBin -Path $destination
                        }
                        "Versioning" {
                            if ($VersioningFolder) {
                                $versionPath = Join-Path $VersioningFolder $relativePath
                                $versionParent = Split-Path $versionPath -Parent
                                $longVersionParent = Get-LongPath -Path $versionParent
                                $longVersionPath = Get-LongPath -Path $versionPath
                                if (-not (Test-Path -LiteralPath $longVersionParent)) {
                                    New-Item -Path $longVersionParent -ItemType Directory -Force | Out-Null
                                }
                                Move-Item -LiteralPath $longDest -Destination $longVersionPath -Force
                            }
                            else {
                                Remove-Item -LiteralPath $longDest -Recurse -Force
                            }
                        }
                        default {
                            Remove-Item -LiteralPath $longDest -Recurse -Force
                        }
                    }
                }
            }
        }
        return $true
    }
    catch {
        Write-Log "Error executing $actionType on $relativePath : $_" -Level Error -Automated:$Automated
        $script:SyncStats.Errors++
        $script:SyncStats.ErrorMessages += "[$actionType] $relativePath : $_"
        return $false
    }
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

function Write-SyncSummary {
    param([switch]$Automated)

    $script:SyncStats.EndTime = Get-Date
    $duration = $script:SyncStats.EndTime - $script:SyncStats.StartTime

    # Format bytes
    $bytesDisplay = if ($script:SyncStats.BytesCopied -gt 1GB) {
        "{0:N2} GB" -f ($script:SyncStats.BytesCopied / 1GB)
    }
    elseif ($script:SyncStats.BytesCopied -gt 1MB) {
        "{0:N2} MB" -f ($script:SyncStats.BytesCopied / 1MB)
    }
    elseif ($script:SyncStats.BytesCopied -gt 1KB) {
        "{0:N2} KB" -f ($script:SyncStats.BytesCopied / 1KB)
    }
    else {
        "$($script:SyncStats.BytesCopied) bytes"
    }

    Write-Log "" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "SYNC SUMMARY" -Level Info -Automated:$Automated
    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "Start Time    : $($script:SyncStats.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "End Time      : $($script:SyncStats.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info -Automated:$Automated
    Write-Log "Duration      : $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -Level Info -Automated:$Automated
    Write-Log "Status        : $(if ($script:SyncStats.Errors -eq 0) { 'SUCCESS' } else { 'COMPLETED WITH ERRORS' })" -Level $(if ($script:SyncStats.Errors -eq 0) { 'Success' } else { 'Warning' }) -Automated:$Automated
    Write-Log "" -Level Info -Automated:$Automated
    Write-Log "Files Scanned : $($script:SyncStats.FilesScanned)" -Level Info -Automated:$Automated
    Write-Log "Files Copied  : $($script:SyncStats.FilesCopied)" -Level Info -Automated:$Automated
    Write-Log "Files Updated : $($script:SyncStats.FilesUpdated)" -Level Info -Automated:$Automated
    Write-Log "Files Deleted : $($script:SyncStats.FilesDeleted)" -Level Info -Automated:$Automated
    Write-Log "Files Skipped : $($script:SyncStats.FilesSkipped)" -Level Info -Automated:$Automated
    Write-Log "Bytes Copied  : $bytesDisplay" -Level Info -Automated:$Automated
    Write-Log "" -Level Info -Automated:$Automated
    Write-Log "Errors        : $($script:SyncStats.Errors)" -Level $(if ($script:SyncStats.Errors -eq 0) { 'Info' } else { 'Error' }) -Automated:$Automated
    Write-Log "Warnings      : $($script:SyncStats.Warnings)" -Level Info -Automated:$Automated

    if ($script:SyncStats.ErrorMessages.Count -gt 0) {
        Write-Log "" -Level Info -Automated:$Automated
        Write-Log "Error Details:" -Level Error -Automated:$Automated
        foreach ($msg in $script:SyncStats.ErrorMessages) {
            Write-Log "  - $msg" -Level Error -Automated:$Automated
        }
    }

    Write-Log "========================================" -Level Info -Automated:$Automated

    $script:SyncStats.Success = ($script:SyncStats.Errors -eq 0)
}

# Main Business Logic ======================================================

function Start-BusinessLogic {
    param(
        [switch]$Automated,
        [switch]$DryRun
    )

    Write-Log "========================================" -Level Info -Automated:$Automated
    Write-Log "Native PowerShell Sync Started" -Level Info -Automated:$Automated
    Write-Log "Script Version: $ScriptVersion ($ScriptDate)" -Level Info -Automated:$Automated
    Write-Log "Sync Mode: $SyncMode" -Level Info -Automated:$Automated
    Write-Log "Compare Method: $CompareMethod" -Level Info -Automated:$Automated
    Write-Log "Deletion Policy: $DeletionPolicy" -Level Info -Automated:$Automated
    if ($DryRun) {
        Write-Log "DRY RUN MODE - No changes will be made" -Level Warning -Automated:$Automated
    }
    Write-Log "========================================" -Level Info -Automated:$Automated

    # Connect to NAS share if needed
    if ($NasRootShare) {
        if (-not (Connect-NasShare -SharePath $NasRootShare -Automated:$Automated)) {
            Write-Log "Failed to connect to NAS share. Aborting sync." -Level Error -Automated:$Automated
            exit 1
        }
    }

    # Process each folder pair
    $pairIndex = 0
    foreach ($pair in $FolderPairs) {
        $pairIndex++

        $leftPath = $pair.left
        $rightPath = $pair.right

        # Skip empty pairs
        if ([string]::IsNullOrWhiteSpace($leftPath) -or [string]::IsNullOrWhiteSpace($rightPath)) {
            continue
        }

        Write-Log "" -Level Info -Automated:$Automated
        Write-Log "Processing Folder Pair $pairIndex" -Level Info -Automated:$Automated
        Write-Log "  Left:  $leftPath" -Level Info -Automated:$Automated
        Write-Log "  Right: $rightPath" -Level Info -Automated:$Automated

        # Verify paths exist (using long path support)
        $longLeftPath = Get-LongPath -Path $leftPath
        $longRightPath = Get-LongPath -Path $rightPath

        if (-not (Test-Path -LiteralPath $longLeftPath)) {
            Write-Log "Source path does not exist: $leftPath" -Level Error -Automated:$Automated
            $script:SyncStats.Errors++
            continue
        }

        # Create destination if it doesn't exist
        if (-not (Test-Path -LiteralPath $longRightPath)) {
            if (-not $DryRun) {
                try {
                    New-Item -Path $longRightPath -ItemType Directory -Force | Out-Null
                    Write-Log "Created destination directory: $rightPath" -Level Info -Automated:$Automated
                }
                catch {
                    Write-Log "Failed to create destination: $rightPath - $_" -Level Error -Automated:$Automated
                    $script:SyncStats.Errors++
                    continue
                }
            }
            else {
                Write-Log "[DRY-RUN] Would create destination directory: $rightPath" -Level Info -Automated:$Automated
            }
        }

        # Scan directories
        Write-Log "Scanning source directory..." -Level Info -Automated:$Automated
        $sourceItems = Get-AllItems -Path $leftPath -ExcludeSymlinks:$Options.excludeSymlinks -Automated:$Automated
        Write-Log "  Found $($sourceItems.Files.Count) files, $($sourceItems.Directories.Count) directories" -Level Info -Automated:$Automated

        Write-Log "Scanning destination directory..." -Level Info -Automated:$Automated
        $destItems = Get-AllItems -Path $rightPath -ExcludeSymlinks:$Options.excludeSymlinks -Automated:$Automated
        Write-Log "  Found $($destItems.Files.Count) files, $($destItems.Directories.Count) directories" -Level Info -Automated:$Automated

        # Get include/exclude patterns
        $includePatterns = if ($Filters -and $Filters.include) { $Filters.include } else { @('*') }
        $excludePatterns = if ($Filters -and $Filters.exclude) { $Filters.exclude } else { @() }

        # Calculate sync actions
        Write-Log "Calculating sync actions..." -Level Info -Automated:$Automated
        $actions = Get-SyncActions `
            -SourceItems $sourceItems `
            -DestItems $destItems `
            -SyncMode $SyncMode `
            -SourcePath $leftPath `
            -DestPath $rightPath `
            -IncludePatterns $includePatterns `
            -ExcludePatterns $excludePatterns `
            -IgnoreTimeShift:$Options.ignoreTimeShift `
            -Automated:$Automated

        Write-Log "  $($actions.Count) actions to perform" -Level Info -Automated:$Automated

        # Execute actions
        if ($actions.Count -gt 0) {
            Write-Log "" -Level Info -Automated:$Automated
            Write-Log "Executing sync actions..." -Level Info -Automated:$Automated

            # Sort actions: copies first, then updates, then deletes (files before directories)
            $sortedActions = $actions | Sort-Object {
                switch ($_.Type) {
                    "Copy" { 1 }
                    "Update" { 2 }
                    "Delete" { 3 }
                    "DeleteDir" { 4 }
                }
            }

            # For directory deletions, sort by path length descending (delete deepest first)
            $dirDeletes = $sortedActions | Where-Object { $_.Type -eq "DeleteDir" } | Sort-Object { $_.RelativePath.Length } -Descending
            $otherActions = $sortedActions | Where-Object { $_.Type -ne "DeleteDir" }
            $sortedActions = @($otherActions) + @($dirDeletes)

            foreach ($action in $sortedActions) {
                Invoke-SyncAction `
                    -Action $action `
                    -DeletionPolicy $DeletionPolicy `
                    -VersioningFolder $VersioningFolder `
                    -DryRun:$DryRun `
                    -ShowProgress:$Options.showProgress `
                    -Automated:$Automated | Out-Null
            }
        }
    }

    # Print summary
    Write-SyncSummary -Automated:$Automated

    # Exit with appropriate code
    if ($script:SyncStats.Errors -gt 0) {
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
            ScriptBlock = { Start-BusinessLogic -Automated:$Automated -DryRun:$DryRun }
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
    Start-BusinessLogic -Automated:$Automated -DryRun:$DryRun
}
