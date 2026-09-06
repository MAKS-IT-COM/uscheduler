#requires -Version 7.0
#requires -PSEdition Core

function Get-ScriptSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptDir,

        [Parameter(Mandatory = $false)]
        [string]$SettingsFileName = 'scriptSettings.json'
    )

    $settingsPath = Join-Path $ScriptDir $SettingsFileName

    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw "Settings file not found: $settingsPath"
    }

    return Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
}

function Assert-Command {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command '$Command' is missing. Aborting."
    }
}

Export-ModuleMember -Function Get-ScriptSettings, Assert-Command
