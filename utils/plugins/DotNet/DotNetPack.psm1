#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET pack plugin for producing package artifacts.

.DESCRIPTION
    This plugin creates package output for the release pipeline.
    It packs the configured .NET project, resolves the generated
    package artifacts, and publishes them into shared runtime context
    for later plugins.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        # Load this globally only as a fallback. Re-importing PluginSupport in its own execution path
        # can invalidate commands already resolved by the release engine.
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Set-EngineFact"
    Import-PluginDependency -ModuleName "DotNetArtifactSupport" -RequiredCommand "Resolve-DotNetPackageArtifacts"

    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $version = $sharedSettings.version

    if ($Settings.PSObject.Properties['projectFiles'] -and $null -ne $Settings.projectFiles) {
        $projectFiles = @(Resolve-RelativePaths -Value $Settings.projectFiles -BasePath $scriptDir)
    }
    elseif ($sharedSettings.PSObject.Properties['projectFiles'] -and $null -ne $sharedSettings.projectFiles) {
        $projectFiles = @($sharedSettings.projectFiles)
    }
    else {
        $projectFiles = @()
    }

    if ($Settings.PSObject.Properties['artifactsDir'] -and -not [string]::IsNullOrWhiteSpace([string]$Settings.artifactsDir)) {
        $artifactsDirectory = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$Settings.artifactsDir)))
        Set-EngineState -Context $sharedSettings -Name 'artifactsDirectory' -Value $artifactsDirectory
        Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
    }
    else {
        $artifactsDirectory = $sharedSettings.artifactsDirectory
    }

    Assert-Command dotnet

    if ($projectFiles.Count -eq 0) {
        throw "DotNetPack plugin requires projectFiles in plugin settings or projectFiles on shared context."
    }

    $outputDir = $artifactsDirectory

    if (!(Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    # First path in the configured project list is the pack target.
    $packageProjectPath = (@($projectFiles))[0]
    Write-Log -Level "STEP" -Message "Packing NuGet package..."
    $dotnetPackArguments = @(
        'pack', $packageProjectPath, '-c', 'Release', '-o', $outputDir, '--nologo',
        '-p:IncludeSymbols=true', '-p:SymbolPackageFormat=snupkg'
    )
    & dotnet @dotnetPackArguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet pack failed for $packageProjectPath."
    }

    $resolved = Resolve-DotNetPackageArtifacts -ArtifactsDirectory $outputDir -Version $version

    Write-Log -Level "OK" -Message "  Package ready: $($resolved.PackageFile.FullName)"
    if ($resolved.SymbolsPackageFile) {
        Write-Log -Level "OK" -Message "  Symbols package ready: $($resolved.SymbolsPackageFile.FullName)"
    }
    else {
        Write-Log -Level "WARN" -Message "  Symbols package (.snupkg) not found for version $version."
    }

    Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'packageFile' -Value $resolved.PackageFile -Overwrite Replace -LegacyProperty 'packageFile'
    Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'symbolsPackageFile' -Value $resolved.SymbolsPackageFile -Overwrite Replace -LegacyProperty 'symbolsPackageFile'
    Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -Value $resolved.ReleaseArchiveInputs -Overwrite Replace -LegacyProperty 'releaseArchiveInputs'
}

Export-ModuleMember -Function Invoke-Plugin
