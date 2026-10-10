#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Pins UScheduler to one window size and position for screenshots.

.DESCRIPTION
    Writes WindowWidth, WindowHeight, WindowX, WindowY, and WindowState in
    %AppData%\MaksIT\UScheduler\settings.json under USchedulerSettings.

    The app reads that file when it opens and writes it again when it closes.
    Close UScheduler before running this script. The first run keeps a backup
    next to settings.json. -Restore copies that backup back.

    Sizes are Avalonia device-independent pixels. At 100% Windows display scale
    they match physical pixels. A higher scale makes the captured bitmap larger.

    For an automatic tour of the main screens, run Invoke-Screenshots.ps1.
    That script applies this layout, launches the app, and restores your settings.

.PARAMETER Width
    Window width. Default 1100.

.PARAMETER Height
    Window height. Default 800.

.PARAMETER X
    Window left edge in screen pixels. Default 80.

.PARAMETER Y
    Window top edge in screen pixels. Default 48.

.PARAMETER Restore
    Put the backup back and remove it.

.EXAMPLE
    pwsh -File .\utils\tools\Set-ScreenshotLayout.ps1

.EXAMPLE
    pwsh -File .\utils\tools\Set-ScreenshotLayout.ps1 -Restore
#>

[CmdletBinding()]
param(
    [int]$Width = 1100,
    [int]$Height = 800,
    [int]$X = 80,
    [int]$Y = 48,
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

$settingsDir = Join-Path $env:APPDATA "MaksIT\UScheduler"
$settingsPath = Join-Path $settingsDir "settings.json"
$backupPath = Join-Path $settingsDir "settings.screenshot-backup.json"

function Assert-AppClosed {
    $running = Get-Process -Name "MaksIT.UScheduler.UI" -ErrorAction SilentlyContinue

    if ($running) {
        Write-Error "Close UScheduler first. It overwrites settings.json when it exits."
    }
}

function Write-Settings([System.Text.Json.Nodes.JsonNode]$Root) {
    $options = [System.Text.Json.JsonSerializerOptions]::new()
    $options.WriteIndented = $true
    $json = $Root.ToJsonString($options) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($settingsPath, $json)
}

Assert-AppClosed

if ($Restore) {
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Write-Error "No screenshot backup at $backupPath"
    }

    Copy-Item -LiteralPath $backupPath -Destination $settingsPath -Force
    Remove-Item -LiteralPath $backupPath -Force
    Write-Host "Restored $settingsPath"
    exit 0
}

if ($Width -lt 900 -or $Height -lt 600) {
    Write-Error "Window must be at least 900 by 600."
}

New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

if ((Test-Path -LiteralPath $settingsPath) -and -not (Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath
    Write-Host "Backup: $backupPath"
}

if (Test-Path -LiteralPath $settingsPath) {
    $root = [System.Text.Json.Nodes.JsonNode]::Parse([System.IO.File]::ReadAllText($settingsPath))
}
else {
    $root = [System.Text.Json.Nodes.JsonObject]::new()
}

if ($null -eq $root["USchedulerSettings"]) {
    $root["USchedulerSettings"] = [System.Text.Json.Nodes.JsonObject]::new()
}

$settings = $root["USchedulerSettings"].AsObject()
$settings["WindowWidth"] = [System.Text.Json.Nodes.JsonValue]::Create([double]$Width)
$settings["WindowHeight"] = [System.Text.Json.Nodes.JsonValue]::Create([double]$Height)
$settings["WindowX"] = [System.Text.Json.Nodes.JsonValue]::Create($X)
$settings["WindowY"] = [System.Text.Json.Nodes.JsonValue]::Create($Y)
$settings["WindowState"] = [System.Text.Json.Nodes.JsonValue]::Create("Normal")

Write-Settings $root

Write-Host "Screenshot layout written to $settingsPath"
Write-Host "  Window ${Width}x${Height} at ${X},${Y} (Normal)"
Write-Host "Start UScheduler and take the shots. Do not resize or move the window."
Write-Host "When you are done, close the app and run this script with -Restore."
