#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Plugin-driven release engine entry script.

.NOTES
    Per-plugin dryRun on mutatesRemote plugins validates without remote mutation.
    There is no engine-wide dryRun switch — set dryRun on each plugin as needed.
#>

# Keep a plain param block so unbound launcher arguments remain in $args for
# optional Initialize-ReleaseExtension (advanced binding would reject them).
param()

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$srcDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

. (Join-Path $srcDir 'modules/Engine/Import-EngineModules.ps1')
Import-EngineModules -Engine Release

$releaseExtension = $null
if (Get-Command Initialize-ReleaseExtension -ErrorAction SilentlyContinue) {
    $releaseExtension = Initialize-ReleaseExtension -ScriptDir $PSScriptRoot -ArgumentList $args
}

$settings = if ($null -ne $releaseExtension) {
    $releaseExtension.Settings
}
else {
    Get-ScriptSettings -ScriptDir $PSScriptRoot
}

$configuredPlugins = Get-ConfiguredPlugins -Settings $settings
Initialize-RepoUtilsVaultSecrets -Settings $settings -Plugins $configuredPlugins

$releaseBanner = if ($null -ne $releaseExtension) {
    $releaseExtension.StepBanner
}
else {
    'RELEASE ENGINE'
}

Write-Log -Level 'STEP' -Message '=================================================='
Write-Log -Level 'STEP' -Message $releaseBanner
Write-Log -Level 'STEP' -Message '=================================================='

$plugins = $configuredPlugins
$newContextParams = @{
    Plugins = $plugins
    ScriptDir = $PSScriptRoot
    SrcDir = $srcDir
    Settings = $settings
}
if ($null -ne $releaseExtension) {
    $newContextParams['ExtensionData'] = $releaseExtension.ContextData
}

$engineContext = New-EngineContext @newContextParams

Write-Log -Level 'OK' -Message 'All pre-flight checks passed!'
$sharedPluginSettings = $engineContext

$releaseStageInitialized = $false
$releaseHadPluginFailures = $false

if ($plugins.Count -eq 0) {
    Write-Log -Level 'WARN' -Message 'No plugins configured in scriptSettings.json.'
}
else {
    for ($pluginIndex = 0; $pluginIndex -lt $plugins.Count; $pluginIndex++) {
        $plugin = $plugins[$pluginIndex]

        if ((Test-IsPublishPlugin -Plugin $plugin -EngineDirectory $PSScriptRoot) -and -not $releaseStageInitialized) {
            if (Test-PluginRunnable -Plugin $plugin -SharedSettings $sharedPluginSettings -EngineDirectory $PSScriptRoot -WriteLogs:$false) {
                Initialize-ReleaseStageContext -SharedSettings $sharedPluginSettings -ArtifactsDirectory $engineContext.artifactsDirectory
                $releaseStageInitialized = $true
            }
        }

        $pluginSucceeded = Invoke-ConfiguredPlugin -Plugin $plugin -SharedSettings $sharedPluginSettings -EngineDirectory $PSScriptRoot
        # Exact $true only: polluted arrays (CLI stdout + $false) are truthy under -not.
        if ($pluginSucceeded -ne $true) {
            $releaseHadPluginFailures = $true
            break
        }
    }
}

if (-not $releaseStageInitialized) {
    $noReleasePluginsLogLevel = if ($engineContext.isNonReleaseBranch) { 'INFO' } else { 'WARN' }
    Write-Log -Level $noReleasePluginsLogLevel -Message 'No release-stage initialization ran (no enabled remote-mutation plugins reached, or none runnable).'
}

Write-Log -Level 'OK' -Message '=================================================='
if ($releaseHadPluginFailures) {
    Write-Log -Level 'ERROR' -Message 'RELEASE FAILED'
}
elseif ($engineContext.PSObject.Properties.Name -contains 'skipPublishPlugins' -and $engineContext.skipPublishPlugins) {
    Write-Log -Level 'OK' -Message 'RUN COMPLETE (publish skipped by ReleasePublishGuard)'
}
elseif ($engineContext.isNonReleaseBranch) {
    Write-Log -Level 'OK' -Message 'NON-RELEASE RUN COMPLETE'
}
else {
    Write-Log -Level 'OK' -Message 'RELEASE COMPLETE'
}
Write-Log -Level 'OK' -Message '=================================================='

if ($engineContext.isNonReleaseBranch -and -not ($engineContext.PSObject.Properties.Name -contains 'skipPublishPlugins' -and $engineContext.skipPublishPlugins)) {
    $preferredReleaseBranch = Get-PreferredReleaseBranch -EngineContext $engineContext
    Write-Log -Level 'INFO' -Message "For publish, use an allowed branch (see ReleasePublishGuard.branches), e.g. '$preferredReleaseBranch', and satisfy the guard requirements."
}

if ($releaseHadPluginFailures) {
    exit 1
}
