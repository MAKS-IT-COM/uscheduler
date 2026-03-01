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
    $pluginSupportModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "PluginSupport.psm1"
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

    $sharedSettings = $Settings.Context
    $projectFiles = $sharedSettings.ProjectFiles
    $artifactsDirectory = $sharedSettings.ArtifactsDirectory
    $version = $sharedSettings.Version
    $packageProjectPath = $null
    $releaseArchiveInputs = @()

    Assert-Command dotnet

    if (-not $sharedSettings.PSObject.Properties['ProjectFiles'] -or $projectFiles.Count -eq 0) {
        throw "DotNetPack plugin requires project files in the shared context."
    }

    $outputDir = $artifactsDirectory

    if (!(Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    # The release context guarantees ProjectFiles is an array, so index 0 is the first project path,
    # not the first character of a string.
    $packageProjectPath = $projectFiles[0]
    Write-Log -Level "STEP" -Message "Packing NuGet package..."
    dotnet pack $packageProjectPath -c Release -o $outputDir --nologo `
        -p:IncludeSymbols=true `
        -p:SymbolPackageFormat=snupkg
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet pack failed for $packageProjectPath."
    }

    # dotnet pack can leave older packages in the artifacts directory.
    # Pick the newest file matching the current version rather than assuming a clean folder.
    $packageFile = Get-ChildItem -Path $outputDir -Filter "*.nupkg" |
        Where-Object {
            $_.Name -like "*$version*.nupkg" -and
            $_.Name -notlike "*.symbols.nupkg" -and
            $_.Name -notlike "*.snupkg"
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $packageFile) {
        throw "Could not locate generated NuGet package for version $version in: $outputDir"
    }

    Write-Log -Level "OK" -Message "  Package ready: $($packageFile.FullName)"
    $releaseArchiveInputs = @($packageFile.FullName)

    $symbolsPackageFile = Get-ChildItem -Path $outputDir -Filter "*.snupkg" |
        Where-Object { $_.Name -like "*$version*.snupkg" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($symbolsPackageFile) {
        Write-Log -Level "OK" -Message "  Symbols package ready: $($symbolsPackageFile.FullName)"
        $releaseArchiveInputs += $symbolsPackageFile.FullName
    }
    else {
        Write-Log -Level "WARN" -Message "  Symbols package (.snupkg) not found for version $version."
    }

    $sharedSettings | Add-Member -NotePropertyName PackageFile -NotePropertyValue $packageFile -Force
    $sharedSettings | Add-Member -NotePropertyName SymbolsPackageFile -NotePropertyValue $symbolsPackageFile -Force
    $sharedSettings | Add-Member -NotePropertyName ReleaseArchiveInputs -NotePropertyValue $releaseArchiveInputs -Force
}

Export-ModuleMember -Function Invoke-Plugin
