#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    npm/Jest test plugin for the test engine.

.DESCRIPTION
    Runs Jest with coverage via TestRunner.Invoke-NpmJestTestsWithCoverage and publishes
    normalized metrics on the shared engine context for downstream plugins.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "TestRunner" -RequiredCommand "Invoke-NpmJestTestsWithCoverage"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Resolve-RelativePaths"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir

    Assert-Command npm

    if (-not $pluginSettings.workspaceRoot) {
        throw "NpmJestTest plugin requires 'workspaceRoot' in scriptSettings.json."
    }

    $workspaceRoots = @(Resolve-RelativePaths -Value $pluginSettings.workspaceRoot -BasePath $scriptDir)
    $workspaceRoot = $workspaceRoots[0]

    $testScript = 'test'
    if (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.testScript)) {
        $testScript = [string]$pluginSettings.testScript
    }

    $coverageDirectory = 'coverage'
    if (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.coverageDirectory)) {
        $coverageDirectory = [string]$pluginSettings.coverageDirectory
    }

    $testResult = Invoke-NpmJestTestsWithCoverage -WorkspaceRoot $workspaceRoot -TestScript $testScript -CoverageDirectory $coverageDirectory

    if (-not $testResult.Success) {
        throw "Tests failed. $($testResult.Error)"
    }

    $sharedSettings | Add-Member -NotePropertyName npmWorkspaceRoot -NotePropertyValue $workspaceRoot -Force
    $sharedSettings | Add-Member -NotePropertyName testResult -NotePropertyValue $testResult -Force
    $sharedSettings | Add-Member -NotePropertyName qualityLineCoverage -NotePropertyValue $testResult.LineRate -Force
    $sharedSettings | Add-Member -NotePropertyName coverageLineRate -NotePropertyValue $testResult.LineRate -Force
    $sharedSettings | Add-Member -NotePropertyName coverageBranchRate -NotePropertyValue $testResult.BranchRate -Force
    $sharedSettings | Add-Member -NotePropertyName coverageMethodRate -NotePropertyValue $testResult.MethodRate -Force
    $sharedSettings | Add-Member -NotePropertyName coverageTotalMethods -NotePropertyValue $testResult.TotalMethods -Force
    $sharedSettings | Add-Member -NotePropertyName coverageCoveredMethods -NotePropertyValue $testResult.CoveredMethods -Force

    if (($testResult.PSObject.Properties.Name -contains 'ResultsDirectory') -and $testResult.ResultsDirectory) {
        $sharedSettings | Add-Member -NotePropertyName testResultsDirectory -NotePropertyValue $testResult.ResultsDirectory -Force
    }
    if (($testResult.PSObject.Properties.Name -contains 'CoverageSummaryFile') -and $testResult.CoverageSummaryFile) {
        $sharedSettings | Add-Member -NotePropertyName coverageSummaryFile -NotePropertyValue $testResult.CoverageSummaryFile -Force
    }

    Write-Log -Level "OK" -Message "  All tests passed!"
    Write-Log -Level "INFO" -Message "  Line Coverage:   $($testResult.LineRate)%"
    Write-Log -Level "INFO" -Message "  Branch Coverage: $($testResult.BranchRate)%"
    Write-Log -Level "INFO" -Message "  Method Coverage: $($testResult.MethodRate)%"
}

Export-ModuleMember -Function Invoke-Plugin
