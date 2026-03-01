#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET publish plugin for producing application release artifacts.

.DESCRIPTION
    This plugin publishes the configured .NET project into a release output
    directory and exposes that published directory to the shared release
    context so later release-stage plugins can archive and publish it.
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
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"

    $sharedSettings = $Settings.Context
    $projectFiles = $sharedSettings.ProjectFiles
    $artifactsDirectory = $sharedSettings.ArtifactsDirectory
    $publishProjectPath = $null

    Assert-Command dotnet

    if (-not $sharedSettings.PSObject.Properties['ProjectFiles'] -or $projectFiles.Count -eq 0) {
        throw "DotNetPublish plugin requires project files in the shared context."
    }

    if (!(Test-Path $artifactsDirectory)) {
        New-Item -ItemType Directory -Path $artifactsDirectory | Out-Null
    }

    # The first configured project remains the canonical release artifact source.
    $publishProjectPath = $projectFiles[0]
    $publishDir = Join-Path $artifactsDirectory ([System.IO.Path]::GetFileNameWithoutExtension($publishProjectPath))

    if (Test-Path $publishDir) {
        Remove-Item -Path $publishDir -Recurse -Force
    }

    Write-Log -Level "STEP" -Message "Publishing release artifact..."
    dotnet publish $publishProjectPath -c Release -o $publishDir --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed for $publishProjectPath."
    }

    $publishedItems = @(Get-ChildItem -Path $publishDir -Force -ErrorAction SilentlyContinue)
    if ($publishedItems.Count -eq 0) {
        throw "dotnet publish completed, but no files were produced in: $publishDir"
    }

    Write-Log -Level "OK" -Message "  Published artifact ready: $publishDir"

    $sharedSettings | Add-Member -NotePropertyName PackageFile -NotePropertyValue $null -Force
    $sharedSettings | Add-Member -NotePropertyName SymbolsPackageFile -NotePropertyValue $null -Force
    $sharedSettings | Add-Member -NotePropertyName ReleaseArchiveInputs -NotePropertyValue @($publishDir) -Force
}

Export-ModuleMember -Function Invoke-Plugin
