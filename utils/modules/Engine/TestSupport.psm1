#requires -Version 7.0
#requires -PSEdition Core

$modulesDir = Split-Path $PSScriptRoot -Parent

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggingModulePath = Join-Path $modulesDir "Logging.psm1"
    if (Test-Path $loggingModulePath -PathType Leaf) {
        Import-Module $loggingModulePath -Force
    }
}

if (-not (Get-Command Initialize-EngineFactsBag -ErrorAction SilentlyContinue)) {
    $engineContextModulePath = Join-Path $PSScriptRoot "EngineContext.psm1"
    if (Test-Path $engineContextModulePath -PathType Leaf) {
        Import-Module $engineContextModulePath -Force
    }
}

function New-EngineContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptDir,

        [Parameter(Mandatory = $true)]
        [string]$SrcDir,

        [Parameter(Mandatory = $false)]
        [psobject]$Settings,

        [Parameter(Mandatory = $false)]
        [psobject]$ExtensionData
    )

    $context = [pscustomobject]@{
        scriptDir = $ScriptDir
        srcDir = $SrcDir
        utilsDir = $SrcDir
        facts = [ordered]@{}
    }
    $context = Copy-RepoUtilsSecretsEnvNamesToContext -Context $context -Settings $Settings

    $expandContext = Get-Command Expand-ExtensionEngineContext -ErrorAction SilentlyContinue
    if ($expandContext) {
        $expandParams = @{
            Context = $context
            ScriptDir = $ScriptDir
            Settings = $Settings
        }
        if ($PSBoundParameters.ContainsKey('ExtensionData')) {
            $expandParams['ExtensionData'] = $ExtensionData
        }

        return & $expandContext @expandParams
    }

    return $context
}

Export-ModuleMember -Function New-EngineContext
