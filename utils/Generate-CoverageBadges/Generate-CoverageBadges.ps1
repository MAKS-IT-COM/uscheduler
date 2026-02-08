<#
.SYNOPSIS
    Generates SVG coverage badges for README.

.DESCRIPTION
    This script runs unit tests via TestRunner.psm1, then generates shields.io-style 
    SVG badges for line, branch, and method coverage.

    Configuration is stored in scriptsettings.json:
    - paths.testProject    : Relative path to test project
    - paths.badgesDir      : Relative path to badges output directory
    - badges               : Array of badges to generate (name, label, metric)
    - colorThresholds      : Coverage percentages for badge colors

    Badge colors based on coverage:
    - brightgreen (>=80%), green (>=60%), yellowgreen (>=40%)
    - yellow (>=20%), orange (>=10%), red (<10%)

.PARAMETER OpenReport
    Generate and open a full HTML coverage report in the default browser.
    Requires ReportGenerator: dotnet tool install -g dotnet-reportgenerator-globaltool

.EXAMPLE
    .\Generate-CoverageBadges.ps1
    Runs tests and generates coverage badges.

.EXAMPLE
    .\Generate-CoverageBadges.ps1 -OpenReport
    Runs tests, generates badges, and opens HTML report in browser.

.OUTPUTS
    SVG badge files in the configured badges directory.

.NOTES
    Author: MaksIT
    Requires: .NET SDK, Coverlet (included in test project)
#>
param(
    [switch]$OpenReport
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot

# Import TestRunner module
$ModulePath = Join-Path (Split-Path $ScriptDir -Parent) "TestRunner.psm1"
if (-not (Test-Path $ModulePath)) {
    Write-Host "TestRunner module not found at: $ModulePath" -ForegroundColor Red
    exit 1
}
Import-Module $ModulePath -Force

# Load settings
$SettingsFile = Join-Path $ScriptDir "scriptsettings.json"
if (-not (Test-Path $SettingsFile)) {
    Write-Host "Settings file not found: $SettingsFile" -ForegroundColor Red
    exit 1
}

$Settings = Get-Content $SettingsFile | ConvertFrom-Json

# Resolve paths from settings
$TestProjectPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $Settings.paths.testProject))
$BadgesDir = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $Settings.paths.badgesDir))

# Ensure badges directory exists
if (-not (Test-Path $BadgesDir)) {
    New-Item -ItemType Directory -Path $BadgesDir | Out-Null
}

# Run tests with coverage
$coverage = Invoke-TestsWithCoverage -TestProjectPath $TestProjectPath -KeepResults:$OpenReport

if (-not $coverage.Success) {
    Write-Host "Tests failed: $($coverage.Error)" -ForegroundColor Red
    exit 1
}

Write-Host "Tests passed!" -ForegroundColor Green

# Store metrics in a hashtable for easy lookup
$metrics = @{
    "line" = $coverage.LineRate
    "branch" = $coverage.BranchRate
    "method" = $coverage.MethodRate
}

# Function to get badge color based on coverage percentage and thresholds from settings
function Get-BadgeColor {
    param([double]$percentage)
    
    $thresholds = $Settings.colorThresholds
    
    if ($percentage -ge $thresholds.brightgreen) { return "brightgreen" }
    if ($percentage -ge $thresholds.green) { return "green" }
    if ($percentage -ge $thresholds.yellowgreen) { return "yellowgreen" }
    if ($percentage -ge $thresholds.yellow) { return "yellow" }
    if ($percentage -ge $thresholds.orange) { return "orange" }
    return "red"
}

# Function to create shields.io style SVG badge
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

# Generate badges from settings
Write-Host "Generating coverage badges..." -ForegroundColor Cyan

foreach ($badge in $Settings.badges) {
    $metricValue = $metrics[$badge.metric]
    $color = Get-BadgeColor $metricValue
    $svg = New-Badge -label $badge.label -value "$metricValue%" -color $color
    $path = Join-Path $BadgesDir $badge.name
    $svg | Out-File -FilePath $path -Encoding utf8
    Write-Host "  $($badge.name): $($badge.label) = $metricValue%" -ForegroundColor Green
}

# Display summary
Write-Host ""
Write-Host "=== Coverage Summary ===" -ForegroundColor Yellow
Write-Host "  Line Coverage:   $($coverage.LineRate)%"
Write-Host "  Branch Coverage: $($coverage.BranchRate)%"
Write-Host "  Method Coverage: $($coverage.MethodRate)% ($($coverage.CoveredMethods) of $($coverage.TotalMethods) methods)"
Write-Host "========================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Badges generated in: $BadgesDir" -ForegroundColor Green
Write-Host "Commit the badges/ folder to update README." -ForegroundColor Cyan

# Optionally generate full HTML report
if ($OpenReport -and $coverage.CoverageFile) {
    Write-Host ""
    Write-Host "Generating HTML report..." -ForegroundColor Cyan
    
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
    
    Write-Host "TestResults kept for HTML report viewing." -ForegroundColor Gray
}
