#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Shared helpers for discovering .NET NuGet package artifacts on disk.
#>

function Resolve-DotNetPackageArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArtifactsDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if (-not (Test-Path $ArtifactsDirectory -PathType Container)) {
        throw "Artifacts directory not found: $ArtifactsDirectory"
    }

    $packageFile = $null
    $newestNupkgWrite = [datetime]::MinValue
    $nupkgCandidates = Get-ChildItem -Path $ArtifactsDirectory -Filter '*.nupkg'
    foreach ($candidate in $nupkgCandidates) {
        if (($candidate.Name -like "*$Version*.nupkg") -and ($candidate.Name -notlike '*.symbols.nupkg') -and ($candidate.Name -notlike '*.snupkg')) {
            if ($candidate.LastWriteTime -gt $newestNupkgWrite) {
                $newestNupkgWrite = $candidate.LastWriteTime
                $packageFile = $candidate
            }
        }
    }

    if (-not $packageFile) {
        throw "Could not locate generated NuGet package for version $Version in: $ArtifactsDirectory"
    }

    $releaseArchiveInputs = @($packageFile.FullName)

    $symbolsPackageFile = $null
    $newestSnupkgWrite = [datetime]::MinValue
    $snupkgCandidates = Get-ChildItem -Path $ArtifactsDirectory -Filter '*.snupkg'
    foreach ($candidate in $snupkgCandidates) {
        if ($candidate.Name -like "*$Version*.snupkg") {
            if ($candidate.LastWriteTime -gt $newestSnupkgWrite) {
                $newestSnupkgWrite = $candidate.LastWriteTime
                $symbolsPackageFile = $candidate
            }
        }
    }

    if ($symbolsPackageFile) {
        $releaseArchiveInputs += $symbolsPackageFile.FullName
    }

    return [pscustomobject]@{
        PackageFile          = $packageFile
        SymbolsPackageFile   = $symbolsPackageFile
        ReleaseArchiveInputs = $releaseArchiveInputs
    }
}

Export-ModuleMember -Function Resolve-DotNetPackageArtifacts
