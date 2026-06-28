#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET NuGet publish plugin.

.DESCRIPTION
    This plugin publishes the package artifact from shared runtime
    context to the configured NuGet feed using the configured API key.
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
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $nugetApiKeyEnvVar = $pluginSettings.nugetApiKey
    $packageFile = $sharedSettings.packageFile

    Assert-Command dotnet

    if (-not $packageFile) {
        throw "DotNetNuGet plugin requires a NuGet package artifact. Ensure DotNetPack produced a .nupkg before running DotNetNuGet."
    }

    if ([string]::IsNullOrWhiteSpace($nugetApiKeyEnvVar)) {
        throw "DotNetNuGet plugin requires 'nugetApiKey' in scriptSettings.json."
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

    Write-Log -Level "STEP" -Message "Pushing package to NuGet feed..."
    dotnet nuget push $packageFile.FullName -k $nugetApiKey -s $nugetSource --skip-duplicate

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push the package to NuGet feed."
    }

    Write-Log -Level "OK" -Message "  NuGet push completed."
    $sharedSettings | Add-Member -NotePropertyName publishCompleted -NotePropertyValue $true -Force
}

Export-ModuleMember -Function Invoke-Plugin



