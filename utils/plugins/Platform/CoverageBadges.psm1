#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Coverage badge plugin for the test engine.

.DESCRIPTION
    Reads line/branch/method coverage from shared engine context.

    badgeFormat "svg" (default): writes SVG files under badgesDir.
    badgeFormat "shields": updates readmePath (string or array) with img.shields.io markdown
    (no local assets).
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

function New-ShieldsIoBadgeUrlInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [double]$Percentage,

        [Parameter(Mandatory = $true)]
        [string]$Color
    )

    $labelToken = ($Label -replace ' ', '%20')
    $valueToken = "$Percentage%25"
    return "https://img.shields.io/badge/$labelToken-$valueToken-$Color"
}

function New-ShieldsIoBadgeMarkdownInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [double]$Percentage,

        [Parameter(Mandatory = $true)]
        [string]$Color
    )

    $url = New-ShieldsIoBadgeUrlInternal -Label $Label -Percentage $Percentage -Color $Color
    return "![$Label]($url)"
}

function Update-ReadmeShieldsBadgesInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReadmePath,

        [Parameter(Mandatory = $true)]
        [object[]]$Badges,

        [Parameter(Mandatory = $true)]
        [hashtable]$Metrics,

        [Parameter(Mandatory = $true)]
        [psobject]$Thresholds
    )

    if (-not (Test-Path -LiteralPath $ReadmePath -PathType Leaf)) {
        throw "CoverageBadges readmePath not found: $ReadmePath"
    }

    $content = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8

    foreach ($badge in @($Badges)) {
        $metricValue = $Metrics[[string]$badge.metric]
        if ($null -eq $metricValue) {
            throw "Unknown or missing coverage metric '$($badge.metric)' for badge label '$($badge.label)'."
        }

        $color = Get-BadgeColorInternal -percentage $metricValue -thresholds $Thresholds
        $markdown = New-ShieldsIoBadgeMarkdownInternal -Label $badge.label -Percentage $metricValue -Color $color
        # Horizontal whitespace only; optional CR for CRLF. Do not let \s* eat the following blank line.
        $pattern = "(?m)^!\[$([regex]::Escape([string]$badge.label))\]\([^)]*\)[^\S\r\n]*\r?$"
        if ($content -notmatch $pattern) {
            throw "README badge line not found for label '$($badge.label)' in: $ReadmePath"
        }

        $content = [regex]::Replace($content, $pattern, $markdown)
    }

    $content | Out-File -LiteralPath $ReadmePath -Encoding utf8NoBOM -NoNewline
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

    $badgeFormat = 'svg'
    if (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.badgeFormat)) {
        $badgeFormat = [string]$pluginSettings.badgeFormat
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

    if ($badgeFormat -eq 'shields') {
        $readmePathSetting = $null
        if ($sharedSettings.PSObject.Properties.Name -contains 'readmePath' -and $sharedSettings.readmePath) {
            $readmePathSetting = $sharedSettings.readmePath
        }
        if ($pluginSettings.PSObject.Properties.Name -contains 'readmePath' -and $pluginSettings.readmePath) {
            $readmePathSetting = $pluginSettings.readmePath
        }

        $readmePaths = @()
        if ($null -ne $readmePathSetting) {
            $readmePaths = @(Resolve-RelativePaths -Value $readmePathSetting -BasePath $scriptDir)
        }
        if ($readmePaths.Count -eq 0) {
            throw "CoverageBadges badgeFormat 'shields' requires readmePath in plugin settings or paths.readmePath in scriptSettings.json."
        }

        foreach ($readmePath in $readmePaths) {
            Update-ReadmeShieldsBadgesInternal -ReadmePath $readmePath -Badges @($pluginSettings.badges) -Metrics $metrics -Thresholds $thresholds
            Write-Log -Level "OK" -Message "README shields updated: $readmePath"
        }

        foreach ($badge in @($pluginSettings.badges)) {
            $metricValue = $metrics[[string]$badge.metric]
            $color = Get-BadgeColorInternal -percentage $metricValue -thresholds $thresholds
            Write-Log -Level "OK" -Message "$($badge.label): $metricValue% ($color)"
        }

        Write-Log -Level "STEP" -Message "Commit README.md to publish badge URLs."
        return
    }

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

    foreach ($badge in @($pluginSettings.badges)) {
        $metricValue = $metrics[[string]$badge.metric]
        if ($null -eq $metricValue) {
            $badgeName = if ($badge.PSObject.Properties.Name -contains 'name') { $badge.name } else { $badge.label }
            throw "Unknown or missing coverage metric '$($badge.metric)' for badge '$badgeName'."
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
