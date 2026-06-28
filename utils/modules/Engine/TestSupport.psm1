#requires -Version 7.0
#requires -PSEdition Core

$modulesDir = Split-Path $PSScriptRoot -Parent

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggingModulePath = Join-Path $modulesDir "Logging.psm1"
    if (Test-Path $loggingModulePath -PathType Leaf) {
        Import-Module $loggingModulePath -Force
    }
}

function New-EngineContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptDir,

        [Parameter(Mandatory = $true)]
        [string]$SrcDir,

        [Parameter(Mandatory = $false)]
        [psobject]$Settings
    )

    $badgesDir = $null
    if ($Settings -and $Settings.PSObject.Properties['paths'] -and $Settings.paths.badgesDir) {
        $badgesDir = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ([string]$Settings.paths.badgesDir)))
    }

    return [pscustomobject]@{
        scriptDir = $ScriptDir
        srcDir = $SrcDir
        utilsDir = $SrcDir
        badgesDir = $badgesDir
    }
}

Export-ModuleMember -Function New-EngineContext
