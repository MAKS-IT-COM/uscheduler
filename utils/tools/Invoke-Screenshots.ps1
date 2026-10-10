#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Opens UScheduler and saves PNGs of the main screens.

.DESCRIPTION
    Applies the screenshot window layout, launches the UI with --screenshots,
    and writes one folder of PNGs plus manifest.json. Closes the app when the
    tour finishes. Unless -KeepLayout is set, settings.json is put back to the
    bytes from before this script ran, so the tour does not leave a different
    window size or position behind.

    Close UScheduler first. It overwrites settings.json when it exits.

    Each view produces <id>.png for that window.
    With no -Views, the tour saves main, processes, logs, script-logs, settings,
    about, and program-log. main selects the first script when one is listed.
    processes selects the first program, or shows a sample row when the list is empty.
    -Views limits the run to those ids.

    Sizes are Avalonia device-independent pixels. PNGs are 96 DPI device pixels.
    At 100% Windows display scale they match. A higher scale makes the bitmap larger.

.PARAMETER Views
    Comma-separated view ids. Omit for the default tour.

.PARAMETER OutDir
    Folder for the PNGs. Relative paths are under the repo root.
    Default assets/screenshots.

.PARAMETER SettleMs
    Pause after each view loads, so the window can paint. Default 600.

.PARAMETER Exe
    Path to MaksIT.UScheduler.UI.exe. Omit to use the newest build under src.

.PARAMETER Build
    Build the UI project before launching.

.PARAMETER SkipLayout
    Do not rewrite window size and position before launch.

.PARAMETER KeepLayout
    Leave settings.json as the tour finished. By default this script restores
    the file it copied at startup.

.PARAMETER Width
    Window width written before launch. Default 1100.

.PARAMETER Height
    Window height written before launch. Default 800.

.EXAMPLE
    pwsh -File .\utils\tools\Invoke-Screenshots.ps1

.EXAMPLE
    pwsh -File .\utils\tools\Invoke-Screenshots.ps1 -Views "main,settings"
#>

[CmdletBinding()]
param(
    [string]$Views,
    [string]$OutDir = "assets/screenshots",
    [int]$SettleMs = 600,
    [string]$Exe,
    [switch]$Build,
    [switch]$SkipLayout,
    [switch]$KeepLayout,
    [int]$Width = 1100,
    [int]$Height = 800
)

$ErrorActionPreference = "Stop"

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$project = Join-Path $repo "src\MaksIT.UScheduler.UI\MaksIT.UScheduler.UI.csproj"
$layoutScript = Join-Path $PSScriptRoot "Set-ScreenshotLayout.ps1"
$settingsPath = Join-Path $env:APPDATA "MaksIT\UScheduler\settings.json"

function Resolve-UiExe {
    if (-not [string]::IsNullOrWhiteSpace($Exe)) {
        if (-not (Test-Path -LiteralPath $Exe)) {
            Write-Error "Exe not found: $Exe"
        }

        return (Resolve-Path -LiteralPath $Exe).Path
    }

    $bin = Join-Path $repo "src\MaksIT.UScheduler.UI\bin"
    $found = @()

    if (Test-Path -LiteralPath $bin) {
        $found = @(Get-ChildItem -Path $bin -Filter "MaksIT.UScheduler.UI.exe" -Recurse -File -ErrorAction SilentlyContinue)
    }

    $newest = $found | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $stale = $newest -and (Test-UiSourcesNewer $newest.FullName)

    if ($stale) {
        Write-Host "UI sources are newer than $($newest.FullName). Rebuilding."
    }

    if ($Build -or $found.Count -eq 0 -or $stale) {
        & dotnet build $project -c Debug --nologo | Out-Host

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Build failed."
        }

        $found = @(Get-ChildItem -Path $bin -Filter "MaksIT.UScheduler.UI.exe" -Recurse -File)
    }

    if ($found.Count -eq 0) {
        Write-Error "Could not find MaksIT.UScheduler.UI.exe. Pass -Build or -Exe."
    }

    return ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Test-UiSourcesNewer([string]$exePath) {
    $exeTime = (Get-Item -LiteralPath $exePath).LastWriteTimeUtc
    $src = Join-Path $repo "src"

    foreach ($file in (Get-ChildItem -Path $src -Recurse -File)) {
        if ($file.FullName -match '\\(bin|obj)\\') {
            continue
        }

        if ($file.Extension -notin ".cs", ".axaml") {
            continue
        }

        if ($file.LastWriteTimeUtc -gt $exeTime) {
            return $true
        }
    }

    return $false
}

if ($SettleMs -lt 0) {
    Write-Error "SettleMs must be zero or greater."
}

if (-not [System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir = Join-Path $repo $OutDir
}

$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$running = Get-Process -Name "MaksIT.UScheduler.UI" -ErrorAction SilentlyContinue

if ($running) {
    Write-Error "Close UScheduler first. It overwrites settings.json when it exits."
}

$snapshot = $null
$settingsExisted = Test-Path -LiteralPath $settingsPath

if ($settingsExisted -and -not $KeepLayout) {
    $snapshot = Join-Path ([System.IO.Path]::GetTempPath()) ("uscheduler-settings-" + [guid]::NewGuid().ToString("n") + ".json")
    Copy-Item -LiteralPath $settingsPath -Destination $snapshot
}

$code = 1

try {
    if (-not $SkipLayout) {
        & $layoutScript -Width $Width -Height $Height
    }

    $exePath = Resolve-UiExe
    $argList = @("--screenshots", $OutDir, "--settle-ms", "$SettleMs")

    if (-not [string]::IsNullOrWhiteSpace($Views)) {
        $argList += @("--views", $Views)
    }

    Write-Host "Launching $exePath"
    Write-Host "Saving screenshots to $OutDir"
    $proc = Start-Process -FilePath $exePath -ArgumentList $argList -Wait -PassThru
    $code = $proc.ExitCode
}
finally {
    if ($snapshot -and (Test-Path -LiteralPath $snapshot)) {
        $stillRunning = Get-Process -Name "MaksIT.UScheduler.UI" -ErrorAction SilentlyContinue

        if (-not $stillRunning) {
            Copy-Item -LiteralPath $snapshot -Destination $settingsPath -Force
            Remove-Item -LiteralPath $snapshot -Force
            Write-Host "Restored $settingsPath"
        }
        else {
            Write-Warning "UScheduler is still running, so settings were left in place. Snapshot: $snapshot"
        }
    }
    elseif (-not $settingsExisted -and -not $KeepLayout -and (Test-Path -LiteralPath $settingsPath)) {
        $stillRunning = Get-Process -Name "MaksIT.UScheduler.UI" -ErrorAction SilentlyContinue

        if (-not $stillRunning) {
            Remove-Item -LiteralPath $settingsPath -Force
        }
    }
}

$manifestPath = Join-Path $OutDir "manifest.json"

if (Test-Path -LiteralPath $manifestPath) {
    Write-Host (Get-Content -LiteralPath $manifestPath -Raw)
}

if ($code -ne 0) {
    Write-Error "UScheduler exited with code $code."
}

Write-Host "Screenshots are in $OutDir"
