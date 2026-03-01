#requires -Version 7.0
#requires -PSEdition Core

#
# Shared Git helpers for utility scripts.
#

function Import-LoggingModuleInternal {
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        return
    }

    $modulePath = Join-Path $PSScriptRoot "Logging.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
}

function Write-GitToolsLogInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "STEP", "DEBUG")]
        [string]$Level = "INFO"
    )

    Import-LoggingModuleInternal

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level $Level -Message $Message
        return
    }

    Write-Host $Message -ForegroundColor Gray
}

# Internal:
# Purpose:
# - Execute a git command and enforce fail-fast error handling.
function Invoke-GitInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [switch]$CaptureOutput,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = "Git command failed"
    )

    if ($CaptureOutput) {
        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-Error "$ErrorMessage (exit code: $exitCode)"
            exit 1
        }

        if ($null -eq $output) {
            return ""
        }

        return ($output -join "`n").Trim()
    }

    & git @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Error "$ErrorMessage (exit code: $exitCode)"
        exit 1
    }
}

# Used by:
# - utils/Release-NuGetPackage/Release-NuGetPackage.ps1
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Resolve and print the current branch name.
function Get-CurrentBranch {
    Write-GitToolsLogInternal -Level "STEP" -Message "Detecting current branch..."

    $branch = Invoke-GitInternal -Arguments @("rev-parse", "--abbrev-ref", "HEAD") -CaptureOutput -ErrorMessage "Could not determine current branch"
    Write-GitToolsLogInternal -Level "OK" -Message "Branch: $branch"
    return $branch
}

# Used by:
# - utils/Release-NuGetPackage/Release-NuGetPackage.ps1
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Return `git status --short` output for pending-change checks.
function Get-GitStatusShort {
    return Invoke-GitInternal -Arguments @("status", "--short") -CaptureOutput -ErrorMessage "Failed to get git status"
}

# Used by:
# - utils/Release-NuGetPackage/Release-NuGetPackage.ps1
# Purpose:
# - Get exact tag name attached to HEAD (release flow).
function Get-CurrentCommitTag {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    Write-GitToolsLogInternal -Level "STEP" -Message "Checking for tag on current commit..."
    $tag = Invoke-GitInternal -Arguments @("describe", "--tags", "--exact-match", "HEAD") -CaptureOutput -ErrorMessage "No tag found on current commit. Create a tag: git tag v$Version"
    return $tag
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Get all tag names pointing at HEAD.
function Get-HeadTags {
    $tagsRaw = Invoke-GitInternal -Arguments @("tag", "--points-at", "HEAD") -CaptureOutput -ErrorMessage "Failed to list tags on HEAD"

    if ([string]::IsNullOrWhiteSpace($tagsRaw)) {
        return @()
    }

    return @($tagsRaw -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

# Used by:
# - utils/Release-NuGetPackage/Release-NuGetPackage.ps1
# Purpose:
# - Check whether a given tag exists on the remote.
function Test-RemoteTagExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $false)]
        [string]$Remote = "origin"
    )

    $remoteTag = Invoke-GitInternal -Arguments @("ls-remote", "--tags", $Remote, $Tag) -CaptureOutput -ErrorMessage "Failed to check remote tag existence"
    return [bool]$remoteTag
}

# Used by:
# - utils/Release-NuGetPackage/Release-NuGetPackage.ps1
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Push tag to remote (optionally with `--force`).
function Push-TagToRemote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $false)]
        [string]$Remote = "origin",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $pushArgs = @("push")
    if ($Force) {
        $pushArgs += "--force"
    }
    $pushArgs += @($Remote, $Tag)

    Invoke-GitInternal -Arguments $pushArgs -ErrorMessage "Failed to push tag $Tag to remote $Remote"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Push branch to remote (optionally with `--force`).
function Push-BranchToRemote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Branch,

        [Parameter(Mandatory = $false)]
        [string]$Remote = "origin",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $pushArgs = @("push")
    if ($Force) {
        $pushArgs += "--force"
    }
    $pushArgs += @($Remote, $Branch)

    Invoke-GitInternal -Arguments $pushArgs -ErrorMessage "Failed to push branch $Branch to remote $Remote"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Get HEAD commit hash.
function Get-HeadCommitHash {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Short
    )

    $format = if ($Short) { "--format=%h" } else { "--format=%H" }
    return Invoke-GitInternal -Arguments @("log", "-1", $format) -CaptureOutput -ErrorMessage "Failed to get HEAD commit hash"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Get HEAD commit subject line.
function Get-HeadCommitMessage {
    return Invoke-GitInternal -Arguments @("log", "-1", "--format=%s") -CaptureOutput -ErrorMessage "Failed to get HEAD commit message"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Stage all changes (tracked, untracked, deletions).
function Add-AllChanges {
    Invoke-GitInternal -Arguments @("add", "-A") -ErrorMessage "Failed to stage changes"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Amend HEAD commit and keep existing commit message.
function Update-HeadCommitNoEdit {
    Invoke-GitInternal -Arguments @("commit", "--amend", "--no-edit") -ErrorMessage "Failed to amend commit"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Delete local tag.
function Remove-LocalTag {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    Invoke-GitInternal -Arguments @("tag", "-d", $Tag) -ErrorMessage "Failed to delete local tag"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Create local tag.
function New-LocalTag {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    Invoke-GitInternal -Arguments @("tag", $Tag) -ErrorMessage "Failed to create tag"
}

# Used by:
# - utils/Force-AmendTaggedCommit/Force-AmendTaggedCommit.ps1
# Purpose:
# - Get HEAD one-line commit info.
function Get-HeadCommitOneLine {
    return Invoke-GitInternal -Arguments @("log", "-1", "--oneline") -CaptureOutput -ErrorMessage "Failed to read final commit state"
}

Export-ModuleMember -Function Get-CurrentBranch, Get-GitStatusShort, Get-CurrentCommitTag, Get-HeadTags, Test-RemoteTagExists, Push-TagToRemote, Push-BranchToRemote, Get-HeadCommitHash, Get-HeadCommitMessage, Add-AllChanges, Update-HeadCommitNoEdit, Remove-LocalTag, New-LocalTag, Get-HeadCommitOneLine
