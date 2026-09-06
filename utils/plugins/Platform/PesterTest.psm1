#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Pester test plugin for the RepoUtils test engine.

.DESCRIPTION
    Runs the RepoUtils Pester suite and publishes normalized coverage metrics on the
    shared engine context for QualityGate.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $pluginSupportModulePath = Join-Path $srcDir 'modules/Engine/PluginSupport.psm1'
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-JaCoCoCoverageMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportPath
    )

    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        return [PSCustomObject]@{
            Success = $false
            Error   = "JaCoCo coverage report not found at: $ReportPath"
        }
    }

    [xml]$reportXml = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8
    $reportNode = $reportXml.report
    if ($null -eq $reportNode) {
        return [PSCustomObject]@{
            Success = $false
            Error   = "Invalid JaCoCo report (missing root <report>): $ReportPath"
        }
    }

    function Get-CounterRate {
        param(
            [Parameter(Mandatory = $true)]
            [string]$CounterType
        )

        $counter = @($reportNode.counter) | Where-Object { $_.type -eq $CounterType } | Select-Object -First 1
        if ($null -eq $counter) {
            return 0.0
        }

        $missed = [long]$counter.missed
        $covered = [long]$counter.covered
        $total = $missed + $covered
        if ($total -le 0) {
            return 0.0
        }

        return [math]::Round(($covered / $total) * 100, 1)
    }

    function Get-CounterTotal {
        param(
            [Parameter(Mandatory = $true)]
            [string]$CounterType
        )

        $counter = @($reportNode.counter) | Where-Object { $_.type -eq $CounterType } | Select-Object -First 1
        if ($null -eq $counter) {
            return 0
        }

        return [long]$counter.missed + [long]$counter.covered
    }

    function Get-CounterCovered {
        param(
            [Parameter(Mandatory = $true)]
            [string]$CounterType
        )

        $counter = @($reportNode.counter) | Where-Object { $_.type -eq $CounterType } | Select-Object -First 1
        if ($null -eq $counter) {
            return 0
        }

        return [long]$counter.covered
    }

    return [PSCustomObject]@{
        Success         = $true
        LineRate        = Get-CounterRate -CounterType 'LINE'
        BranchRate      = Get-CounterRate -CounterType 'BRANCH'
        MethodRate      = Get-CounterRate -CounterType 'METHOD'
        TotalMethods    = Get-CounterTotal -CounterType 'METHOD'
        CoveredMethods  = Get-CounterCovered -CounterType 'METHOD'
        CoverageFile    = $ReportPath
        CoverageFiles   = @($ReportPath)
    }
}

function Import-PesterModuleIfNeeded {
    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 })) {
        Write-Log -Level 'INFO' -Message 'Installing Pester 5...'
        Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
    }

    Import-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Force
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName 'Logging' -RequiredCommand 'Write-Log'
    Import-PluginDependency -ModuleName 'EngineContext' -RequiredCommand 'Resolve-RelativePaths'

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir

    if (-not $pluginSettings.testsDir) {
        throw "PesterTest plugin requires 'testsDir' in scriptSettings.json."
    }

    $testsDirs = @(Resolve-RelativePaths -Value $pluginSettings.testsDir -BasePath $scriptDir)
    $testsDir = $testsDirs[0]

    $configFileSetting = 'pester.config.ps1'
    if (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.configFile)) {
        $configFileSetting = [string]$pluginSettings.configFile
    }

    $configPaths = @(Resolve-RelativePaths -Value $configFileSetting -BasePath $scriptDir)
    $configPath = $configPaths[0]

    if (-not (Test-Path -LiteralPath $testsDir -PathType Container)) {
        throw "Pester tests directory not found at: $testsDir"
    }

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Pester config not found at: $configPath"
    }

    Import-PesterModuleIfNeeded

    Write-Log -Level 'STEP' -Message 'Running Pester tests...'
    Write-Log -Level 'INFO' -Message "  Tests:  $testsDir"
    Write-Log -Level 'INFO' -Message "  Config: $configPath"

    Push-Location $testsDir
    try {
        $config = & $configPath
        if ($null -eq $config) {
            throw "Pester config did not return a configuration object: $configPath"
        }

        $config.Run.PassThru = $true
        $config.Run.Exit = $false

        $resultsDirSetting = [string]$pluginSettings.resultsDir
        if ([string]::IsNullOrWhiteSpace($resultsDirSetting)) {
            $resultsDirSetting = '..\..\..\test-results'
        }
        $resultsDirectory = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $resultsDirSetting))
        New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null

        # Point Pester report outputs at the resolved results dir (overrides pester.config relative paths).
        if ($null -ne $config.TestResult -and $config.TestResult.Enabled) {
            $config.TestResult.OutputPath = Join-Path $resultsDirectory 'pester-results.xml'
        }
        if ($null -ne $config.CodeCoverage -and $config.CodeCoverage.Enabled) {
            $config.CodeCoverage.OutputPath = Join-Path $resultsDirectory 'coverage.xml'
        }

        Write-Log -Level 'INFO' -Message "  Results: $resultsDirectory"

        $result = Invoke-Pester -Configuration $config
        if ($result.FailedCount -gt 0) {
            throw "Pester tests failed: $($result.FailedCount) failed, $($result.PassedCount) passed, $($result.SkippedCount) skipped."
        }

        $coveragePath = Join-Path $resultsDirectory 'coverage.xml'
        $coverageMetrics = $null
        if (Test-Path -LiteralPath $coveragePath -PathType Leaf) {
            $coverageMetrics = Get-JaCoCoCoverageMetrics -ReportPath $coveragePath
            if (-not $coverageMetrics.Success) {
                throw $coverageMetrics.Error
            }
        }
        else {
            $coverageMetrics = [PSCustomObject]@{
                Success        = $true
                LineRate       = 0.0
                BranchRate     = 0.0
                MethodRate     = 0.0
                TotalMethods   = 0
                CoveredMethods = 0
                CoverageFile   = $null
                CoverageFiles  = @()
            }
        }

        $testResult = [PSCustomObject]@{
            Success           = $true
            LineRate          = $coverageMetrics.LineRate
            BranchRate        = $coverageMetrics.BranchRate
            MethodRate        = $coverageMetrics.MethodRate
            TotalMethods      = $coverageMetrics.TotalMethods
            CoveredMethods    = $coverageMetrics.CoveredMethods
            CoverageFile      = $coverageMetrics.CoverageFile
            CoverageFiles     = @($coverageMetrics.CoverageFiles)
            ResultsDirectory  = $resultsDirectory
            PesterResult      = $result
        }

        Import-PluginDependency -ModuleName 'TestRunner' -RequiredCommand 'Publish-CoverageMetricsToSharedContext'
        Publish-CoverageMetricsToSharedContext -SharedSettings $sharedSettings -TestResult $testResult

        Write-Log -Level 'OK' -Message "  All tests passed! ($($result.PassedCount) passed)"
        Write-Log -Level 'INFO' -Message "  Line Coverage:   $($testResult.LineRate)%"
        Write-Log -Level 'INFO' -Message "  Branch Coverage: $($testResult.BranchRate)%"
        Write-Log -Level 'INFO' -Message "  Method Coverage: $($testResult.MethodRate)%"
    }
    finally {
        Pop-Location
    }
}

function Get-PluginMetadata {
    [pscustomobject]@{ mutatesRemote = $false }
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata, Get-JaCoCoCoverageMetrics
