#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Keep a Changelog header parsing and section extraction.

.DESCRIPTION
    Supports Keep a Changelog version lines and shared SemVer checks, including prerelease:
    ## [1.0.0] - 2026-05-24
    ## [0.1.0-alpha.1] - 2026-08-21
    ## [0.1.0-beta.1] - 2026-08-21
    ## [0.1.0-rc.1] - 2026-08-21
#>

function Get-ChangelogSemverPattern {
    return '\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?'
}

function Test-ReleaseSemver {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $false
    }

    return [bool]($Version -match ('^' + (Get-ChangelogSemverPattern) + '$'))
}

function Test-ReleaseSemverPrerelease {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Version
    )

    return (Test-ReleaseSemver -Version $Version) -and ($Version -match '-')
}

function Get-ReleaseSemverPrereleaseLabel {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Version
    )

    if (-not (Test-ReleaseSemverPrerelease -Version $Version)) {
        return $null
    }

    if ($Version -match '^\d+\.\d+\.\d+-([A-Za-z][0-9A-Za-z]*)') {
        return $Matches[1].ToLowerInvariant()
    }

    return 'next'
}

function Get-ChangelogVersionHeaderPattern {
    return '(?m)^##\s+\[(' + (Get-ChangelogSemverPattern) + ')\]\s*-\s*\d{4}-\d{2}-\d{2}\s*$'
}

function Get-ChangelogNextVersionHeaderPattern {
    return '(?m)^##\s+\[' + (Get-ChangelogSemverPattern) + '\]\s*-\s*\d{4}-\d{2}-\d{2}\s*$'
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

Export-ModuleMember -Function Get-ChangelogSemverPattern, Test-ReleaseSemver, Test-ReleaseSemverPrerelease, Get-ReleaseSemverPrereleaseLabel, Get-ChangelogVersionHeaderPattern, Get-ChangelogNextVersionHeaderPattern, Get-LatestChangelogVersion, Get-ChangelogReleaseNotesSection
