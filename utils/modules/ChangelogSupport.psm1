#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Keep a Changelog header parsing and section extraction.

.DESCRIPTION
    Supports only the standard Keep a Changelog version line:
    ## [1.0.0] - 2026-05-24
#>

function Get-ChangelogVersionHeaderPattern {
    return '(?m)^##\s+\[(\d+\.\d+\.\d+)\]\s*-\s*\d{4}-\d{2}-\d{2}\s*$'
}

function Get-ChangelogNextVersionHeaderPattern {
    return '(?m)^##\s+\[\d+\.\d+\.\d+\]\s*-\s*\d{4}-\d{2}-\d{2}\s*$'
}

function Get-LatestChangelogVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseNotesContent
    )

    $match = [regex]::Match($ReleaseNotesContent, (Get-ChangelogVersionHeaderPattern))
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function Get-ChangelogReleaseNotesSection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseNotesContent,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $escapedVersion = [regex]::Escape($Version)
    $nextHeaderPattern = Get-ChangelogNextVersionHeaderPattern
    $headerPattern = "(?ms)^##\s+\[$escapedVersion\]\s*-\s*\d{4}-\d{2}-\d{2}.*?(?=$nextHeaderPattern|\Z)"
    $match = [regex]::Match($ReleaseNotesContent, $headerPattern)

    if (-not $match.Success) {
        return $null
    }

    return $match.Value.Trim()
}

Export-ModuleMember -Function Get-ChangelogVersionHeaderPattern, Get-ChangelogNextVersionHeaderPattern, Get-LatestChangelogVersion, Get-ChangelogReleaseNotesSection
