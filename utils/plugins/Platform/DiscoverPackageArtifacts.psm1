#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Discovers package artifacts produced by pack plugins or container build pipelines.

.DESCRIPTION
    Stack-agnostic scanner for artifactsDir. Detects .NET .nupkg/.snupkg or npm .tgz files
    and populates shared context (packageFile, releaseAssetPaths, releaseArchiveInputs).
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

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $version = $sharedSettings.version

    if ($Settings.PSObject.Properties['artifactsDir'] -and -not [string]::IsNullOrWhiteSpace([string]$Settings.artifactsDir)) {
        $artifactsDirectory = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$Settings.artifactsDir)))
        if (Get-Command Set-EngineState -ErrorAction SilentlyContinue) {
            Set-EngineState -Context $sharedSettings -Name 'artifactsDirectory' -Value $artifactsDirectory
            Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
        }
        else {
            $sharedSettings | Add-Member -NotePropertyName artifactsDirectory -NotePropertyValue $artifactsDirectory -Force
            $sharedSettings | Add-Member -NotePropertyName releaseDir -NotePropertyValue $artifactsDirectory -Force
        }
    }
    else {
        $artifactsDirectory = $sharedSettings.artifactsDirectory
    }

    if ([string]::IsNullOrWhiteSpace($artifactsDirectory)) {
        throw 'DiscoverPackageArtifacts requires artifactsDir in plugin settings or artifactsDirectory on shared context.'
    }

    $nupkgCandidates = @(Get-ChildItem -Path $artifactsDirectory -Filter '*.nupkg' -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notlike '*.symbols.nupkg' -and $_.Name -notlike '*.snupkg'
    })
    $tgzCandidates = @(Get-ChildItem -Path $artifactsDirectory -Filter '*.tgz' -ErrorAction SilentlyContinue)

    if ($nupkgCandidates.Count -gt 0 -and $tgzCandidates.Count -gt 0) {
        throw "DiscoverPackageArtifacts found both NuGet and npm artifacts in $artifactsDirectory. Use one package stack per repository."
    }

    if ($nupkgCandidates.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace([string]$version)) {
            throw 'DiscoverPackageArtifacts requires release version on shared context when discovering .nupkg artifacts.'
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

        $sharedSettings | Add-Member -NotePropertyName packageFile -NotePropertyValue $resolved.PackageFile -Force
        $sharedSettings | Add-Member -NotePropertyName symbolsPackageFile -NotePropertyValue $resolved.SymbolsPackageFile -Force
        $sharedSettings | Add-Member -NotePropertyName releaseArchiveInputs -NotePropertyValue $resolved.ReleaseArchiveInputs -Force
        $sharedSettings | Add-Member -NotePropertyName releaseAssetPaths -NotePropertyValue $resolved.ReleaseArchiveInputs -Force
        if (Get-Command Set-EngineFact -ErrorAction SilentlyContinue) {
            Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'packageFile' -Value $resolved.PackageFile -Overwrite Replace -LegacyProperty 'packageFile'
            Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'symbolsPackageFile' -Value $resolved.SymbolsPackageFile -Overwrite Replace -LegacyProperty 'symbolsPackageFile'
            Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -Value $resolved.ReleaseArchiveInputs -Overwrite Replace -LegacyProperty 'releaseArchiveInputs'
            Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'assetPaths' -Value $resolved.ReleaseArchiveInputs -Overwrite Replace -LegacyProperty 'releaseAssetPaths'
        }
        return
    }

    if ($tgzCandidates.Count -gt 0) {
        Import-PluginDependency -ModuleName 'NpmArtifactSupport' -RequiredCommand 'Resolve-NpmPackageArtifacts'

        Write-Log -Level 'STEP' -Message "Discovering npm package artifacts in $artifactsDirectory ..."
        $resolved = Resolve-NpmPackageArtifacts -ArtifactsDirectory $artifactsDirectory -Version $version

        foreach ($tarball in $resolved.PackageFiles) {
            Write-Log -Level 'OK' -Message "  Package ready: $($tarball.FullName)"
        }

        $sharedSettings | Add-Member -NotePropertyName packageFile -NotePropertyValue $resolved.PackageFile -Force
        $sharedSettings | Add-Member -NotePropertyName releaseArchiveInputs -NotePropertyValue $resolved.ReleaseArchiveInputs -Force
        $sharedSettings | Add-Member -NotePropertyName releaseAssetPaths -NotePropertyValue $resolved.ReleaseAssetPaths -Force
        $sharedSettings | Add-Member -NotePropertyName releaseDir -NotePropertyValue $artifactsDirectory -Force
        if (Get-Command Set-EngineFact -ErrorAction SilentlyContinue) {
            Set-EngineFact -Context $sharedSettings -Namespace 'npm' -Name 'packageFile' -Value $resolved.PackageFile -Overwrite Replace -LegacyProperty 'packageFile'
            Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -Value $resolved.ReleaseArchiveInputs -Overwrite Replace -LegacyProperty 'releaseArchiveInputs'
            Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'assetPaths' -Value $resolved.ReleaseAssetPaths -Overwrite Replace -LegacyProperty 'releaseAssetPaths'
            if (Get-Command Set-EngineState -ErrorAction SilentlyContinue) {
                Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
            }
        }
        return
    }

    throw "DiscoverPackageArtifacts found no .nupkg or .tgz files in: $artifactsDirectory"
}

function Get-PluginMetadata {
    [pscustomobject]@{ mutatesRemote = $false }
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata
