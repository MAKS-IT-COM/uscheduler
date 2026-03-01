#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Amends the latest commit, recreates its associated tag, and force pushes both to remote.

.DESCRIPTION
    This script performs the following operations:
    1. Gets the last commit and verifies it has an associated tag
    2. Stages all pending changes
    3. Amends the latest commit (keeps existing message)
    4. Deletes and recreates the tag on the amended commit
    5. Force pushes the branch and tag to remote
    
    All configuration is in scriptsettings.json.

.PARAMETER DryRun
    If specified, shows what would be done without making changes.

.EXAMPLE
    pwsh -File .\Force-AmendTaggedCommit.ps1
    
.EXAMPLE
    pwsh -File .\Force-AmendTaggedCommit.ps1 -DryRun

.NOTES
    CONFIGURATION (scriptsettings.json):
    - git.remote: Remote name to push to (default: "origin")
    - git.confirmBeforeAmend: Prompt before amending (default: true)
    - git.confirmWhenNoChanges: Prompt if no pending changes (default: true)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Get the directory of the current script (for loading settings and relative paths)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$utilsDir = Split-Path $scriptDir -Parent

#region Import Modules

# Import shared ScriptConfig module (settings loading + dependency checks)
$scriptConfigModulePath = Join-Path $utilsDir "ScriptConfig.psm1"
if (-not (Test-Path $scriptConfigModulePath)) {
    Write-Error "ScriptConfig module not found at: $scriptConfigModulePath"
    exit 1
}

# Import shared GitTools module (git operations used by this script)
$gitToolsModulePath = Join-Path $utilsDir "GitTools.psm1"
if (-not (Test-Path $gitToolsModulePath)) {
    Write-Error "GitTools module not found at: $gitToolsModulePath"
    exit 1
}

$loggingModulePath = Join-Path $utilsDir "Logging.psm1"
if (-not (Test-Path $loggingModulePath)) {
    Write-Error "Logging module not found at: $loggingModulePath"
    exit 1
}

Import-Module $scriptConfigModulePath -Force
Import-Module $loggingModulePath -Force
Import-Module $gitToolsModulePath -Force

#endregion

#region Helpers

function Select-PreferredHeadTag {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Tags
    )

    # Pick the latest tag on HEAD by git's own ordering (no tag-name parsing assumptions).
    $ordered = (& git tag --points-at HEAD --sort=-creatordate 2>$null)
    if ($LASTEXITCODE -eq 0 -and $ordered) {
        $orderedTags = @($ordered | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        if ($orderedTags.Count -gt 0) {
            return $orderedTags[0]
        }
    }

    # Fallback: keep script functional even if sorting is unavailable.
    return $Tags[0]
}

#endregion

#region Load Settings

$settings = Get-ScriptSettings -ScriptDir $scriptDir

#endregion

#region Configuration

# Git configuration with safe defaults when settings are omitted
$Remote = if ($settings.git.remote) { $settings.git.remote } else { "origin" }
$ConfirmBeforeAmend = if ($null -ne $settings.git.confirmBeforeAmend) { $settings.git.confirmBeforeAmend } else { $true }
$ConfirmWhenNoChanges = if ($null -ne $settings.git.confirmWhenNoChanges) { $settings.git.confirmWhenNoChanges } else { $true }

#endregion

#region Validate CLI Dependencies

Assert-Command git

#endregion

#region Main

Write-Log -Level "INFO" -Message "========================================"
Write-Log -Level "INFO" -Message "Force Amend Tagged Commit Script"
Write-Log -Level "INFO" -Message "========================================"

if ($DryRun) {
    Write-Log -Level "WARN" -Message "*** DRY RUN MODE - No changes will be made ***"
}

#region Preflight

# 1. Detect current branch
$Branch = Get-CurrentBranch

# 2. Read HEAD commit details
Write-LogStep "Getting last commit..."
$CommitMessage = Get-HeadCommitMessage
$CommitHash = Get-HeadCommitHash -Short
Write-Log -Level "INFO" -Message "Commit: $CommitHash - $CommitMessage"

# 3. Ensure HEAD has at least one tag
Write-LogStep "Finding tag on last commit..."
$tags = Get-HeadTags
if ($tags.Count -eq 0) {
    Write-Error "No tag found on the last commit ($CommitHash). This script requires the last commit to have an associated tag."
    exit 1
}

# If multiple tags exist, choose the latest one on HEAD by git ordering.
if ($tags.Count -gt 1) {
    Write-Log -Level "WARN" -Message "Multiple tags found on HEAD: $($tags -join ', ')"
}
$TagName = Select-PreferredHeadTag -Tags $tags
Write-Log -Level "OK" -Message "Found tag: $TagName"

# 4. Inspect pending changes before amend
Write-LogStep "Checking pending changes..."
$Status = Get-GitStatusShort
if (-not [string]::IsNullOrWhiteSpace($Status)) {
    Write-Log -Level "INFO" -Message "Pending changes:"
    $Status -split "`r?`n" | ForEach-Object { Write-Log -Level "INFO" -Message "  $_" }
}
else {
    Write-Log -Level "WARN" -Message "No pending changes found"
    if ($ConfirmWhenNoChanges -and -not $DryRun) {
        $confirm = Read-Host "`n   No changes to amend. Continue to recreate tag and force push? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Log -Level "WARN" -Message "Aborted by user"
            exit 0
        }
    }
}

# 5. Show operation summary and request explicit confirmation
Write-Log -Level "INFO" -Message "----------------------------------------"
Write-Log -Level "INFO" -Message "Summary of operations:"
Write-Log -Level "INFO" -Message "----------------------------------------"
Write-Log -Level "INFO" -Message "Branch: $Branch"
Write-Log -Level "INFO" -Message "Commit: $CommitHash"
Write-Log -Level "INFO" -Message "Tag:    $TagName"
Write-Log -Level "INFO" -Message "Remote: $Remote"
Write-Log -Level "INFO" -Message "----------------------------------------"

if ($ConfirmBeforeAmend -and -not $DryRun) {
    $confirm = Read-Host "   Proceed with amend and force push? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Log -Level "WARN" -Message "Aborted by user"
        exit 0
    }
}

#endregion

#region Amend And Push

# 6. Stage all changes to include them in amended commit
Write-LogStep "Staging all changes..."
if (-not $DryRun) {
    Add-AllChanges
}
Write-Log -Level "OK" -Message "All changes staged"

# 7. Amend HEAD commit while preserving commit message
Write-LogStep "Amending commit..."
if (-not $DryRun) {
    Update-HeadCommitNoEdit
}
Write-Log -Level "OK" -Message "Commit amended"

# 8. Move existing local tag to the amended commit
Write-LogStep "Deleting local tag '$TagName'..."
if (-not $DryRun) {
    Remove-LocalTag -Tag $TagName
}
Write-Log -Level "OK" -Message "Local tag deleted"

# 9. Recreate the same tag on new HEAD
Write-LogStep "Recreating tag '$TagName' on amended commit..."
if (-not $DryRun) {
    New-LocalTag -Tag $TagName
}
Write-Log -Level "OK" -Message "Tag recreated"

# 10. Force push updated branch history
Write-LogStep "Force pushing branch '$Branch' to $Remote..."
if (-not $DryRun) {
    Push-BranchToRemote -Branch $Branch -Remote $Remote -Force
}
Write-Log -Level "OK" -Message "Branch force pushed"

# 11. Force push moved tag
Write-LogStep "Force pushing tag '$TagName' to $Remote..."
if (-not $DryRun) {
    Push-TagToRemote -Tag $TagName -Remote $Remote -Force
}
Write-Log -Level "OK" -Message "Tag force pushed"

#endregion

#region Summary

Write-Log -Level "OK" -Message "========================================"
Write-Log -Level "OK" -Message "Operation completed successfully!"
Write-Log -Level "OK" -Message "========================================"

# Show resulting HEAD commit after amend
Write-Log -Level "INFO" -Message "Final state:"
$finalLog = Get-HeadCommitOneLine
Write-Log -Level "INFO" -Message $finalLog

#endregion

#endregion
