#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET release archive plugin — zip from NuGet pack/publish artifacts.

.DESCRIPTION
    This plugin compresses .NET release artifact inputs prepared by an earlier
    DotNet plugin (DotNetPack or DotNetPublish) into a zip file
    and exposes the resulting release assets for later publisher plugins.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
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
    $sharedSettings = $Settings.context
    $artifactsDirectory = $sharedSettings.artifactsDirectory
    $version = $sharedSettings.version
    $archiveInputs = @()

    if ($sharedSettings.PSObject.Properties['releaseArchiveInputs'] -and $sharedSettings.releaseArchiveInputs) {
        $archiveInputs = @($sharedSettings.releaseArchiveInputs)
    }
    elseif ($sharedSettings.PSObject.Properties['packageFile'] -and $sharedSettings.packageFile) {
        $archiveInputs = @($sharedSettings.packageFile.FullName)
        if ($sharedSettings.PSObject.Properties['symbolsPackageFile'] -and $sharedSettings.symbolsPackageFile) {
            $archiveInputs += $sharedSettings.symbolsPackageFile.FullName
        }
    }

    if ($archiveInputs.Count -eq 0) {
        throw "DotNetCreateArchive plugin requires prepared artifacts. Run DotNetPack or DotNetPublish first."
    }

    if ([string]::IsNullOrWhiteSpace($artifactsDirectory)) {
        throw "DotNetCreateArchive plugin requires an artifacts directory in the shared context."
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
    if ($sharedSettings.PSObject.Properties['packageFile'] -and $sharedSettings.packageFile) {
        $releaseAssetPaths += $sharedSettings.packageFile.FullName
    }
    if ($sharedSettings.PSObject.Properties['symbolsPackageFile'] -and $sharedSettings.symbolsPackageFile) {
        $releaseAssetPaths += $sharedSettings.symbolsPackageFile.FullName
    }

    $sharedSettings | Add-Member -NotePropertyName releaseDir -NotePropertyValue $artifactsDirectory -Force
    $sharedSettings | Add-Member -NotePropertyName releaseArchivePath -NotePropertyValue $zipPath -Force
    $sharedSettings | Add-Member -NotePropertyName releaseAssetPaths -NotePropertyValue $releaseAssetPaths -Force
}

Export-ModuleMember -Function Invoke-Plugin
