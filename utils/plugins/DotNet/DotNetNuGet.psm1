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
    $packageFile = $sharedSettings.packageFile

    $dryRun = Test-PluginSkipsRemoteMutation -Plugin $pluginSettings -SharedSettings $sharedSettings
    $nugetSecret = Resolve-PluginSecretName -PluginSettings $pluginSettings -PropertyName 'nugetSecret' -PluginDisplayName 'DotNetNuGet' -Required

    Assert-Command dotnet

    if (-not $packageFile) {
        throw "DotNetNuGet plugin requires a NuGet package artifact. Ensure DotNetPack produced a .nupkg before running DotNetNuGet."
    }

    if ($dryRun) {
        $nugetSource = if ([string]::IsNullOrWhiteSpace($pluginSettings.source)) {
            "https://api.nuget.org/v3/index.json"
        }
        else {
            $pluginSettings.source
        }

        Write-Log -Level "INFO" -Message "Dry run: would push $($packageFile.FullName) to $nugetSource"
        return
    }

    $nugetKey = Get-RepoUtilsSecretSlot -Name $nugetSecret -Settings $sharedSettings
    if ([string]::IsNullOrWhiteSpace($nugetKey)) {
        throw "NuGet API key is not set. Set RepoUtilsSecrets slot '$nugetSecret' (nugetSecret)."
    }

    $nugetSource = if ([string]::IsNullOrWhiteSpace($pluginSettings.source)) {
        "https://api.nuget.org/v3/index.json"
    }
    else {
        $pluginSettings.source
    }

    Write-Log -Level "STEP" -Message "Pushing package to NuGet feed..."
    dotnet nuget push $packageFile.FullName -k $nugetKey -s $nugetSource --skip-duplicate

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push the package to NuGet feed."
    }

    Write-Log -Level "OK" -Message "  NuGet push completed."
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Add-EnginePublishCompletion"
    Add-EnginePublishCompletion -Context $sharedSettings -Publisher 'DotNetNuGet'
}

function Get-PluginMetadata {
    [pscustomobject]@{ mutatesRemote = $true }
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata



