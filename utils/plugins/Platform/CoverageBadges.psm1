#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Coverage badge plugin for the test engine.

.DESCRIPTION
    Reads line/branch/method coverage from shared engine context and writes SVG badges.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-BadgeColorInternal {
    param(
        [double]$percentage,
        [psobject]$thresholds
    )

    if ($percentage -ge $thresholds.brightgreen) { return 'brightgreen' }
    if ($percentage -ge $thresholds.green) { return 'green' }
    if ($percentage -ge $thresholds.yellowgreen) { return 'yellowgreen' }
    if ($percentage -ge $thresholds.yellow) { return 'yellow' }
    if ($percentage -ge $thresholds.orange) { return 'orange' }
    return 'red'
}

function New-BadgeSvgInternal {
    param(
        [string]$label,
        [string]$value,
        [string]$color
    )

    $labelWidth = [math]::Max(($label.Length * 6.5) + 10, 50)
    $valueWidth = [math]::Max(($value.Length * 6.5) + 10, 40)
    $totalWidth = $labelWidth + $valueWidth
    $labelX = $labelWidth / 2
    $valueX = $labelWidth + ($valueWidth / 2)

    $colorMap = @{
        brightgreen = '#4c1'
        green = '#97ca00'
        yellowgreen = '#a4a61d'
        yellow = '#dfb317'
        orange = '#fe7d37'
        red = '#e05d44'
    }
    $hexColor = $colorMap[$color]
    if (-not $hexColor) { $hexColor = '#9f9f9f' }

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

function Get-CoverageMetricsFromSharedContext {
    param(
        [Parameter(Mandatory = $true)]
        $Shared
    )

    $line = $null
    $branch = $null
    $method = $null

    if ($Shared.PSObject.Properties.Name -contains 'coverageLineRate') {
        $line = [double]$Shared.coverageLineRate
    }
    if ($Shared.PSObject.Properties.Name -contains 'coverageBranchRate') {
        $branch = [double]$Shared.coverageBranchRate
    }
    if ($Shared.PSObject.Properties.Name -contains 'coverageMethodRate') {
        $method = [double]$Shared.coverageMethodRate
    }

    if ($null -eq $line -and $Shared.PSObject.Properties.Name -contains 'testResult' -and $null -ne $Shared.testResult) {
        $line = [double]$Shared.testResult.LineRate
        $branch = [double]$Shared.testResult.BranchRate
        $method = [double]$Shared.testResult.MethodRate
    }

    if ($null -eq $line) {
        throw 'CoverageBadges requires coverage metrics on shared context. Run NpmJestTest or DotNetTest first.'
    }

    return @{
        line = $line
        branch = $branch
        method = $method
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Resolve-RelativePaths"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $metrics = Get-CoverageMetricsFromSharedContext -Shared $sharedSettings

    $badgesDir = $sharedSettings.badgesDir
    if ($pluginSettings.badgesDir) {
        $badgesDirs = @(Resolve-RelativePaths -Value $pluginSettings.badgesDir -BasePath $scriptDir)
        $badgesDir = $badgesDirs[0]
    }
    if ([string]::IsNullOrWhiteSpace([string]$badgesDir)) {
        throw "CoverageBadges requires badgesDir in plugin settings or paths.badgesDir in scriptSettings.json."
    }

    if (-not (Test-Path $badgesDir)) {
        New-Item -ItemType Directory -Path $badgesDir | Out-Null
    }

    $thresholds = $pluginSettings.colorThresholds
    if ($null -eq $thresholds) {
        $thresholds = [pscustomobject]@{
            brightgreen = 80
            green = 60
            yellowgreen = 40
            yellow = 20
            orange = 10
            red = 0
        }
    }

    Write-Log -Level "STEP" -Message "Generating coverage badges..."

    foreach ($badge in @($pluginSettings.badges)) {
        $metricValue = $metrics[[string]$badge.metric]
        if ($null -eq $metricValue) {
            throw "Unknown or missing coverage metric '$($badge.metric)' for badge '$($badge.name)'."
        }

        $color = Get-BadgeColorInternal -percentage $metricValue -thresholds $thresholds
        $svg = New-BadgeSvgInternal -label $badge.label -value "$metricValue%" -color $color
        $path = Join-Path $badgesDir $badge.name
        $svg | Out-File -FilePath $path -Encoding utf8NoBOM
        Write-Log -Level "OK" -Message "$($badge.name): $($badge.label) = $metricValue%"
    }

    Write-Log -Level "OK" -Message "Badges generated in: $badgesDir"
    Write-Log -Level "STEP" -Message "Commit the badges folder to update README."
}

Export-ModuleMember -Function Invoke-Plugin
