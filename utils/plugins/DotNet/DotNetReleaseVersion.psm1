#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Loads release version into shared context.

.DESCRIPTION
    Dedicated version-loading plugin. It reads .csproj version via
    EngineContext helpers and writes Version into the shared runtime context.
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
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Resolve-DotNetReleaseVersion"

    $shared = $Settings.context
    $resolved = Resolve-DotNetReleaseVersion -Plugins @($Settings) -ScriptDir $shared.scriptDir
    $projectFiles = @(Resolve-RelativePaths -Value $Settings.projectFiles -BasePath $shared.scriptDir)

    $shared | Add-Member -NotePropertyName version -NotePropertyValue $resolved.version -Force
    $shared | Add-Member -NotePropertyName projectFiles -NotePropertyValue $projectFiles -Force
    Write-Log -Level "OK" -Message "  Release version loaded by DotNetReleaseVersion plugin: $($shared.version)"
}

Export-ModuleMember -Function Invoke-Plugin


