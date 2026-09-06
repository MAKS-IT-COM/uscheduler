#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Discovers existing .NET NuGet package artifacts.

.DESCRIPTION
    Scans artifactsDir for .nupkg/.snupkg matching the release version and populates shared
    context (packageFile, symbolsPackageFile, releaseArchiveInputs) for downstream plugins.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $pluginSupportModulePath = Join-Path $srcDir 'modules/Engine/PluginSupport.psm1'
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName 'Logging' -RequiredCommand 'Write-Log'
    Import-PluginDependency -ModuleName 'DotNetArtifactSupport' -RequiredCommand 'Resolve-DotNetPackageArtifacts'
    Import-PluginDependency -ModuleName 'EngineContext' -RequiredCommand 'Set-EngineFact'

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $version = $sharedSettings.version

    if ($Settings.PSObject.Properties['artifactsDir'] -and -not [string]::IsNullOrWhiteSpace([string]$Settings.artifactsDir)) {
        $artifactsDirectory = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$Settings.artifactsDir)))
        Set-EngineState -Context $sharedSettings -Name 'artifactsDirectory' -Value $artifactsDirectory
        Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
    }
    else {
        $artifactsDirectory = $sharedSettings.artifactsDirectory
    }

    if ([string]::IsNullOrWhiteSpace($artifactsDirectory)) {
        throw 'DiscoverDotNetPackageArtifacts requires artifactsDir in plugin settings or artifactsDirectory on shared context.'
    }

    Write-Log -Level 'STEP' -Message "Discovering NuGet package artifacts in $artifactsDirectory ..."
    $resolved = Resolve-DotNetPackageArtifacts -ArtifactsDirectory $artifactsDirectory -Version $version

    Write-Log -Level 'OK' -Message "  Package ready: $($resolved.PackageFile.FullName)"
    if ($resolved.SymbolsPackageFile) {
        Write-Log -Level 'OK' -Message "  Symbols package ready: $($resolved.SymbolsPackageFile.FullName)"
    }
    else {
        Write-Log -Level 'WARN' -Message "  Symbols package (.snupkg) not found for version $version."
    }

    Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'packageFile' -Value $resolved.PackageFile -Overwrite Replace -LegacyProperty 'packageFile'
    Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'symbolsPackageFile' -Value $resolved.SymbolsPackageFile -Overwrite Replace -LegacyProperty 'symbolsPackageFile'
    Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -Value $resolved.ReleaseArchiveInputs -Overwrite Replace -LegacyProperty 'releaseArchiveInputs'
}

function Get-PluginMetadata {
    [pscustomobject]@{ mutatesRemote = $false }
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata
