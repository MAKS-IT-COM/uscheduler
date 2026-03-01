#requires -Version 7.0
#requires -PSEdition Core

function Get-ScriptSettings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptDir,

        [Parameter(Mandatory = $false)]
        [string]$SettingsFileName = "scriptsettings.json"
    )

    $settingsPath = Join-Path $ScriptDir $SettingsFileName

    if (-not (Test-Path $settingsPath -PathType Leaf)) {
        Write-Error "Settings file not found: $settingsPath"
        exit 1
    }

    return Get-Content $settingsPath -Raw | ConvertFrom-Json
}

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Write-Error "Required command '$Command' is missing. Aborting."
        exit 1
    }
}

Export-ModuleMember -Function Get-ScriptSettings, Assert-Command
