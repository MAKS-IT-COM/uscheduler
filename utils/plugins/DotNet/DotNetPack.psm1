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
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Resolve-RelativePaths"

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
    }
    else {
        $artifactsDirectory = $sharedSettings.artifactsDirectory
    }
    $packageProjectPath = $null
    $releaseArchiveInputs = @()

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

    # dotnet pack can leave older packages in the artifacts directory.
    # Pick the newest file matching the current version rather than assuming a clean folder.
    $packageFile = $null
    $newestNupkgWrite = [datetime]::MinValue
    $nupkgCandidates = Get-ChildItem -Path $outputDir -Filter "*.nupkg"
    foreach ($candidate in $nupkgCandidates) {
        if (($candidate.Name -like "*$version*.nupkg") -and ($candidate.Name -notlike "*.symbols.nupkg") -and ($candidate.Name -notlike "*.snupkg")) {
            if ($candidate.LastWriteTime -gt $newestNupkgWrite) {
                $newestNupkgWrite = $candidate.LastWriteTime
                $packageFile = $candidate
            }
        }
    }

    if (-not $packageFile) {
        throw "Could not locate generated NuGet package for version $version in: $outputDir"
    }

    Write-Log -Level "OK" -Message "  Package ready: $($packageFile.FullName)"
    $releaseArchiveInputs = @($packageFile.FullName)

    $symbolsPackageFile = $null
    $newestSnupkgWrite = [datetime]::MinValue
    $snupkgCandidates = Get-ChildItem -Path $outputDir -Filter "*.snupkg"
    foreach ($candidate in $snupkgCandidates) {
        if ($candidate.Name -like "*$version*.snupkg") {
            if ($candidate.LastWriteTime -gt $newestSnupkgWrite) {
                $newestSnupkgWrite = $candidate.LastWriteTime
                $symbolsPackageFile = $candidate
            }
        }
    }

    if ($symbolsPackageFile) {
        Write-Log -Level "OK" -Message "  Symbols package ready: $($symbolsPackageFile.FullName)"
        $releaseArchiveInputs += $symbolsPackageFile.FullName
    }
    else {
        Write-Log -Level "WARN" -Message "  Symbols package (.snupkg) not found for version $version."
    }

    $sharedSettings | Add-Member -NotePropertyName packageFile -NotePropertyValue $packageFile -Force
    $sharedSettings | Add-Member -NotePropertyName symbolsPackageFile -NotePropertyValue $symbolsPackageFile -Force
    $sharedSettings | Add-Member -NotePropertyName releaseArchiveInputs -NotePropertyValue $releaseArchiveInputs -Force
}

Export-ModuleMember -Function Invoke-Plugin
