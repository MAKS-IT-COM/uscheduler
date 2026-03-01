#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Generates SVG coverage badges for README.

.DESCRIPTION
    This script runs unit tests via TestRunner.psm1, then generates shields.io-style 
    SVG badges for line, branch, and method coverage.

    Configuration is stored in scriptsettings.json:
    - openReport           : Generate and open full HTML report (true/false)
    - paths.testProject    : Relative path to test project
    - paths.badgesDir      : Relative path to badges output directory
    - badges               : Array of badges to generate (name, label, metric)
    - colorThresholds      : Coverage percentages for badge colors

    Badge colors based on coverage:
    - brightgreen (>=80%), green (>=60%), yellowgreen (>=40%)
    - yellow (>=20%), orange (>=10%), red (<10%)
    If openReport is true, ReportGenerator is required:
    dotnet tool install -g dotnet-reportgenerator-globaltool

.EXAMPLE
    pwsh -File .\Generate-CoverageBadges.ps1
    Runs tests and generates coverage badges (and optionally HTML report if configured).

.OUTPUTS
    SVG badge files in the configured badges directory.

.NOTES
    Author: MaksIT
    Requires: .NET SDK, Coverlet (included in test project)
#>

$ErrorActionPreference = "Stop"

# Get the directory of the current script (for loading settings and relative paths)
$ScriptDir = $PSScriptRoot
$UtilsDir = Split-Path $ScriptDir -Parent

#region Import Modules

# Import TestRunner module (executes tests and collects coverage metrics)
$testRunnerModulePath = Join-Path $UtilsDir "TestRunner.psm1"
if (-not (Test-Path $testRunnerModulePath)) {
    Write-Error "TestRunner module not found at: $testRunnerModulePath"
    exit 1
}
Import-Module $testRunnerModulePath -Force

# Import shared ScriptConfig module (settings + command validation helpers)
$scriptConfigModulePath = Join-Path $UtilsDir "ScriptConfig.psm1"
if (-not (Test-Path $scriptConfigModulePath)) {
    Write-Error "ScriptConfig module not found at: $scriptConfigModulePath"
    exit 1
}
Import-Module $scriptConfigModulePath -Force

# Import shared Logging module (timestamped/aligned output)
$loggingModulePath = Join-Path $UtilsDir "Logging.psm1"
if (-not (Test-Path $loggingModulePath)) {
    Write-Error "Logging module not found at: $loggingModulePath"
    exit 1
}
Import-Module $loggingModulePath -Force

#endregion

#region Load Settings

$Settings = Get-ScriptSettings -ScriptDir $ScriptDir

$thresholds = $Settings.colorThresholds

#endregion

#region Configuration

# Runtime options from settings
$OpenReport = if ($null -ne $Settings.openReport) { [bool]$Settings.openReport } else { $false }

# Resolve configured paths to absolute paths
$TestProjectPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $Settings.paths.testProject))
$BadgesDir = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $Settings.paths.badgesDir))

# Ensure badges directory exists
if (-not (Test-Path $BadgesDir)) {
    New-Item -ItemType Directory -Path $BadgesDir | Out-Null
}

#endregion

#region Helpers

# Maps a coverage percentage to a shields.io color using configured thresholds.
function Get-BadgeColor {
    param([double]$percentage)

    if ($percentage -ge $thresholds.brightgreen) { return "brightgreen" }
    if ($percentage -ge $thresholds.green) { return "green" }
    if ($percentage -ge $thresholds.yellowgreen) { return "yellowgreen" }
    if ($percentage -ge $thresholds.yellow) { return "yellow" }
    if ($percentage -ge $thresholds.orange) { return "orange" }
    return "red"
}

# Builds a shields.io-like SVG badge string for one metric.
function New-Badge {
    param(
        [string]$label,
        [string]$value,
        [string]$color
    )
    
    # Calculate widths (approximate character width of 6.5px for the font)
    $labelWidth = [math]::Max(($label.Length * 6.5) + 10, 50)
    $valueWidth = [math]::Max(($value.Length * 6.5) + 10, 40)
    $totalWidth = $labelWidth + $valueWidth
    $labelX = $labelWidth / 2
    $valueX = $labelWidth + ($valueWidth / 2)
    
    $colorMap = @{
        "brightgreen" = "#4c1"
        "green" = "#97ca00"
        "yellowgreen" = "#a4a61d"
        "yellow" = "#dfb317"
        "orange" = "#fe7d37"
        "red" = "#e05d44"
    }
    $hexColor = $colorMap[$color]
    if (-not $hexColor) { $hexColor = "#9f9f9f" }

    return @"
<svg xmlns="http://www.w3.org/2000/svg" width="$totalWidth" height="20" role="img" aria-label="$label`: $value">
  <title>$label`: $value</title>
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="r">
    <rect width="$totalWidth" height="20" rx="3" fill="#fff"/>
  </clipPath>
  <g clip-path="url(#r)">
    <rect width="$labelWidth" height="20" fill="#555"/>
    <rect x="$labelWidth" width="$valueWidth" height="20" fill="$hexColor"/>
    <rect width="$totalWidth" height="20" fill="url(#s)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="11">
    <text aria-hidden="true" x="$labelX" y="15" fill="#010101" fill-opacity=".3">$label</text>
    <text x="$labelX" y="14" fill="#fff">$label</text>
    <text aria-hidden="true" x="$valueX" y="15" fill="#010101" fill-opacity=".3">$value</text>
    <text x="$valueX" y="14" fill="#fff">$value</text>
  </g>
</svg>
"@
}

#endregion

#region Main

#region Test And Coverage

$coverage = Invoke-TestsWithCoverage -TestProjectPath $TestProjectPath -KeepResults:$OpenReport
if (-not $coverage.Success) {
    Write-Error "Tests failed: $($coverage.Error)"
    exit 1
}

Write-Log -Level "OK" -Message "Tests passed!"

$metrics = @{
    "line" = $coverage.LineRate
    "branch" = $coverage.BranchRate
    "method" = $coverage.MethodRate
}

#endregion

#region Generate Badges

Write-LogStep -Message "Generating coverage badges..."

foreach ($badge in $Settings.badges) {
    $metricValue = $metrics[$badge.metric]
    $color = Get-BadgeColor $metricValue
    $svg = New-Badge -label $badge.label -value "$metricValue%" -color $color
    $path = Join-Path $BadgesDir $badge.name
    $svg | Out-File -FilePath $path -Encoding utf8NoBOM
    Write-Log -Level "OK" -Message "$($badge.name): $($badge.label) = $metricValue%"
}

#endregion

#region Summary

Write-Log -Level "INFO" -Message "Coverage Summary:"
Write-Log -Level "INFO" -Message "Line Coverage:   $($coverage.LineRate)%"
Write-Log -Level "INFO" -Message "Branch Coverage: $($coverage.BranchRate)%"
Write-Log -Level "INFO" -Message "Method Coverage: $($coverage.MethodRate)% ($($coverage.CoveredMethods) of $($coverage.TotalMethods) methods)"
Write-Log -Level "OK" -Message "Badges generated in: $BadgesDir"
Write-Log -Level "STEP" -Message "Commit the badges/ folder to update README."

#endregion

#region Optional Html Report

if ($OpenReport -and $coverage.CoverageFile) {
    Write-LogStep -Message "Generating HTML report..."
    Assert-Command reportgenerator
    
    $ResultsDir = Split-Path (Split-Path $coverage.CoverageFile -Parent) -Parent
    $ReportDir = Join-Path $ResultsDir "report"
    
    $reportGenArgs = @(
        "-reports:$($coverage.CoverageFile)"
        "-targetdir:$ReportDir"
        "-reporttypes:Html"
    )
    & reportgenerator @reportGenArgs
    
    $IndexFile = Join-Path $ReportDir "index.html"
    if (Test-Path $IndexFile) {
        Start-Process $IndexFile
    }
    
    Write-Log -Level "INFO" -Message "TestResults kept for HTML report viewing."
}

#endregion

#endregion
