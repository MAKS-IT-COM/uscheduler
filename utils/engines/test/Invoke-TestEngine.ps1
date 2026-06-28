#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Plugin-driven test and coverage engine entry script.
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir = (Resolve-Path (Join-Path $scriptDir '..\..')).Path

. (Join-Path $srcDir 'modules/Engine/Import-EngineModules.ps1')
Import-EngineModules -Engine Test

$settings = Get-ScriptSettings -ScriptDir $scriptDir
$configuredPlugins = Get-ConfiguredPlugins -Settings $settings

Write-Log -Level 'STEP' -Message '=================================================='
Write-Log -Level 'STEP' -Message 'TEST ENGINE'
Write-Log -Level 'STEP' -Message '=================================================='

$engineContext = New-EngineContext -ScriptDir $scriptDir -SrcDir $srcDir -Settings $settings

if ($configuredPlugins.Count -eq 0) {
    Write-Log -Level 'WARN' -Message 'No plugins configured in scriptSettings.json.'
    exit 0
}

$testHadPluginFailures = $false

foreach ($plugin in $configuredPlugins) {
    $pluginSucceeded = Invoke-ConfiguredPlugin -Plugin $plugin -SharedSettings $engineContext -EngineDirectory $scriptDir -ContinueOnError:$false
    if (-not $pluginSucceeded) {
        $testHadPluginFailures = $true
        break
    }
}

Write-Log -Level 'OK' -Message '=================================================='
if ($testHadPluginFailures) {
    Write-Log -Level 'ERROR' -Message 'TEST RUN FAILED'
}
else {
    Write-Log -Level 'OK' -Message 'TEST RUN COMPLETE'
}
Write-Log -Level 'OK' -Message '=================================================='

if ($testHadPluginFailures) {
    exit 1
}
