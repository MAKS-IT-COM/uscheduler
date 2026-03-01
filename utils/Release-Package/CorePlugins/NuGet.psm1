#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    NuGet publish plugin.

.DESCRIPTION
    This plugin publishes the package artifact from shared runtime
    context to the configured NuGet feed using the configured API key.
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

    $pluginSettings = $Settings
    $sharedSettings = $Settings.Context
    $nugetApiKeyEnvVar = $pluginSettings.nugetApiKey
    $packageFile = $sharedSettings.PackageFile

    Assert-Command dotnet

    if (-not $packageFile) {
        throw "NuGet plugin requires a NuGet package artifact. Ensure DotNetPack produced a .nupkg before running NuGet."
    }

    if ([string]::IsNullOrWhiteSpace($nugetApiKeyEnvVar)) {
        throw "NuGet plugin requires 'nugetApiKey' in scriptsettings.json."
    }

    $nugetApiKey = [System.Environment]::GetEnvironmentVariable($nugetApiKeyEnvVar)
    if ([string]::IsNullOrWhiteSpace($nugetApiKey)) {
        throw "NuGet API key is not set. Set '$nugetApiKeyEnvVar' and rerun."
    }

    $nugetSource = if ([string]::IsNullOrWhiteSpace($pluginSettings.source)) {
        "https://api.nuget.org/v3/index.json"
    }
    else {
        $pluginSettings.source
    }

    Write-Log -Level "STEP" -Message "Pushing to NuGet.org..."
    dotnet nuget push $packageFile.FullName -k $nugetApiKey -s $nugetSource --skip-duplicate

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push the package to NuGet."
    }

    Write-Log -Level "OK" -Message "  NuGet push completed."
    $sharedSettings | Add-Member -NotePropertyName PublishCompleted -NotePropertyValue $true -Force
}

Export-ModuleMember -Function Invoke-Plugin
