#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Collects coverage metrics from an existing test results directory.

.DESCRIPTION
    Stack-agnostic parser for recovered container or host test output. Auto-detects .NET
    Cobertura (coverage.cobertura.xml) or Jest (coverage-summary.json) and publishes the
    same shared-context keys as DotNetTest / NpmJestTest for QualityGate.
    Use after DockerContainerBuilder / PodmanContainerBuilder when tests run inside a container image.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $pluginSupportModulePath = Join-Path $srcDir 'modules/Engine/PluginSupport.psm1'
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName 'Logging' -RequiredCommand 'Write-Log'
    Import-PluginDependency -ModuleName 'TestRunner' -RequiredCommand 'Get-CoverageFromResultsDirectory'
    Import-PluginDependency -ModuleName 'TestRunner' -RequiredCommand 'Publish-CoverageMetricsToSharedContext'

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir

    $resultsDirSetting = $pluginSettings.resultsDir
    if ([string]::IsNullOrWhiteSpace($resultsDirSetting)) {
        if ($sharedSettings.PSObject.Properties.Name -contains 'testResultsDirectory' -and $sharedSettings.testResultsDirectory) {
            $resultsDirSetting = $sharedSettings.testResultsDirectory
        }
        else {
            throw "CollectCoverage requires 'resultsDir' in plugin settings or testResultsDirectory on shared context (from ContainerBuilder)."
        }
    }

    $resultsDirectory = if ([System.IO.Path]::IsPathRooted([string]$resultsDirSetting)) {
        [string]$resultsDirSetting
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$resultsDirSetting)))
    }

    $format = 'auto'
    if ($pluginSettings.PSObject.Properties.Name -contains 'format' -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.format)) {
        $format = [string]$pluginSettings.format
    }

    Write-Log -Level 'STEP' -Message "Collecting coverage from $resultsDirectory ..."
    $testResult = Get-CoverageFromResultsDirectory -ResultsDirectory $resultsDirectory -Format $format -Silent:$true
    if (-not $testResult.Success) {
        throw $testResult.Error
    }

    Publish-CoverageMetricsToSharedContext -SharedSettings $sharedSettings -TestResult $testResult

    $formatLabel = if ($testResult.CoverageFormat) { $testResult.CoverageFormat } else { 'unknown' }
    Write-Log -Level 'OK' -Message "  Coverage collected ($formatLabel)."
    Write-Log -Level 'INFO' -Message "  Line Coverage:   $($testResult.LineRate)%"
    Write-Log -Level 'INFO' -Message "  Branch Coverage: $($testResult.BranchRate)%"
    Write-Log -Level 'INFO' -Message "  Method Coverage: $($testResult.MethodRate)%"
}

function Get-PluginMetadata {
    [pscustomobject]@{ mutatesRemote = $false }
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata
