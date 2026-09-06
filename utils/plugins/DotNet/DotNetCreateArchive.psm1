#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET release archive plugin — zip from NuGet pack/publish artifacts.

.DESCRIPTION
    This plugin compresses .NET release artifact inputs prepared by an earlier
    DotNet plugin (DotNetPack or DotNetPublish) into a zip file
    and exposes the resulting release assets for later publisher plugins.

    For desktop apps with per-RID publish folders, the zip is the portable
    build only (default win-x64). Windows installer and Flatpak artifacts are
    separate GitHub assets and are never added to this zip.
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
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Add-ReleaseAssetPaths"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $artifactsDirectory = $sharedSettings.artifactsDirectory
    $version = $sharedSettings.version
    $archiveInputs = @()

    $fromFact = Get-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -LegacyProperty @('releaseArchiveInputs')
    if ($null -ne $fromFact) {
        $archiveInputs = @($fromFact)
    }
    else {
        $packageFile = Get-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'packageFile' -LegacyProperty @('packageFile')
        if ($null -ne $packageFile) {
            $archiveInputs = @($packageFile.FullName)
            $symbolsPackageFile = Get-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'symbolsPackageFile' -LegacyProperty @('symbolsPackageFile')
            if ($null -ne $symbolsPackageFile) {
                $archiveInputs += $symbolsPackageFile.FullName
            }
        }
    }

    $portableRid = $null
    if ($pluginSettings.PSObject.Properties['portableRuntimeIdentifier'] -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.portableRuntimeIdentifier)) {
        $portableRid = ([string]$pluginSettings.portableRuntimeIdentifier).Trim()
    }

    $publishOutputs = @(Get-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'publishOutputs' -Default @())
    if ($publishOutputs.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($portableRid)) {
            $portableRid = 'win-x64'
        }

        $portableOutputs = @(
            $publishOutputs |
                Where-Object { [string]$_.runtimeIdentifier -eq $portableRid }
        )
        if ($portableOutputs.Count -eq 0) {
            $portableOutputs = @(
                $publishOutputs |
                    Where-Object { ([string]$_.runtimeIdentifier).StartsWith('win-', [System.StringComparison]::OrdinalIgnoreCase) }
            )
        }

        if ($portableOutputs.Count -gt 0) {
            $archiveInputs = @($portableOutputs | ForEach-Object { [string]$_.directory })
            Write-Log -Level "INFO" -Message "  Portable zip uses runtime '$portableRid' only (installer/Flatpak stay out of the zip)."
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

    $newAssets = [System.Collections.Generic.List[string]]::new()
    $newAssets.Add($zipPath)
    $packageFile = Get-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'packageFile' -LegacyProperty @('packageFile')
    if ($null -ne $packageFile) {
        $newAssets.Add($packageFile.FullName)
    }
    $symbolsPackageFile = Get-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'symbolsPackageFile' -LegacyProperty @('symbolsPackageFile')
    if ($null -ne $symbolsPackageFile) {
        $newAssets.Add($symbolsPackageFile.FullName)
    }

    Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
    Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archivePath' -Value $zipPath -Overwrite Replace -LegacyProperty 'releaseArchivePath'
    Add-ReleaseAssetPaths -Context $sharedSettings -Path @($newAssets)
}

Export-ModuleMember -Function Invoke-Plugin
