#requires -Version 7.0
#requires -PSEdition Core

function Import-EngineModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Release', 'Test')]
        [string]$Engine
    )

    $engineModuleDir = $PSScriptRoot
    $modulesDir = Split-Path $engineModuleDir -Parent
    $supportModules = @(
        (Join-Path $modulesDir 'ScriptConfig.psm1'),
        (Join-Path $modulesDir 'Logging.psm1'),
        (Join-Path $engineModuleDir 'PluginSupport.psm1'),
        (Join-Path $engineModuleDir 'EngineContext.psm1')
    )

    if ($Engine -eq 'Release') {
        $supportModules += (Join-Path $engineModuleDir 'ReleaseSupport.psm1')
    }
    else {
        $supportModules += (Join-Path $engineModuleDir 'TestSupport.psm1')
    }

    foreach ($modulePath in $supportModules) {
        if (-not (Test-Path $modulePath -PathType Leaf)) {
            throw "Required module not found at: $modulePath"
        }

        Import-Module $modulePath -Force
    }
}
