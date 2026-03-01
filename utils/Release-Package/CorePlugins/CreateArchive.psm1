#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Creates a release zip from prepared build artifacts.

.DESCRIPTION
    This plugin compresses the release artifact inputs prepared by an earlier
    producer plugin (for example DotNetPack or DotNetPublish) into a zip file
    and exposes the resulting release assets for later publisher plugins.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.Context
    $artifactsDirectory = $sharedSettings.ArtifactsDirectory
    $version = $sharedSettings.Version
    $archiveInputs = @()

    if ($sharedSettings.PSObject.Properties['ReleaseArchiveInputs'] -and $sharedSettings.ReleaseArchiveInputs) {
        $archiveInputs = @($sharedSettings.ReleaseArchiveInputs)
    }
    elseif ($sharedSettings.PSObject.Properties['PackageFile'] -and $sharedSettings.PackageFile) {
        $archiveInputs = @($sharedSettings.PackageFile.FullName)
        if ($sharedSettings.PSObject.Properties['SymbolsPackageFile'] -and $sharedSettings.SymbolsPackageFile) {
            $archiveInputs += $sharedSettings.SymbolsPackageFile.FullName
        }
    }

    if ($archiveInputs.Count -eq 0) {
        throw "CreateArchive plugin requires prepared artifacts. Run a producer plugin (for example DotNetPack or DotNetPublish) first."
    }

    if ([string]::IsNullOrWhiteSpace($artifactsDirectory)) {
        throw "CreateArchive plugin requires an artifacts directory in the shared context."
    }

    if (-not (Test-Path $artifactsDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $artifactsDirectory | Out-Null
    }

    $zipNamePattern = if ($pluginSettings.PSObject.Properties['zipNamePattern'] -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.zipNamePattern)) {
        [string]$pluginSettings.zipNamePattern
    }
    else {
        "release-{version}.zip"
    }

    $zipFileName = $zipNamePattern -replace '\{version\}', $version
    $zipPath = Join-Path $artifactsDirectory $zipFileName

    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Write-Log -Level "STEP" -Message "Creating release archive..."
    Compress-Archive -Path $archiveInputs -DestinationPath $zipPath -CompressionLevel Optimal -Force

    if (-not (Test-Path $zipPath -PathType Leaf)) {
        throw "Failed to create release archive at: $zipPath"
    }

    Write-Log -Level "OK" -Message "  Release archive ready: $zipPath"

    $releaseAssetPaths = @($zipPath)
    if ($sharedSettings.PSObject.Properties['PackageFile'] -and $sharedSettings.PackageFile) {
        $releaseAssetPaths += $sharedSettings.PackageFile.FullName
    }
    if ($sharedSettings.PSObject.Properties['SymbolsPackageFile'] -and $sharedSettings.SymbolsPackageFile) {
        $releaseAssetPaths += $sharedSettings.SymbolsPackageFile.FullName
    }

    $sharedSettings | Add-Member -NotePropertyName ReleaseDir -NotePropertyValue $artifactsDirectory -Force
    $sharedSettings | Add-Member -NotePropertyName ReleaseArchivePath -NotePropertyValue $zipPath -Force
    $sharedSettings | Add-Member -NotePropertyName ReleaseAssetPaths -NotePropertyValue $releaseAssetPaths -Force
}

Export-ModuleMember -Function Invoke-Plugin
