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

    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Set-EngineFact"
    Import-PluginDependency -ModuleName "TestRunner" -RequiredCommand "Publish-CoverageMetricsToSharedContext"
    Set-EngineFact -Context $sharedSettings -Namespace 'npm' -Name 'workspaceRoot' -Value $workspaceRoot -Overwrite Replace -LegacyProperty 'npmWorkspaceRoot'
    Publish-CoverageMetricsToSharedContext -SharedSettings $sharedSettings -TestResult $testResult
    if (($testResult.PSObject.Properties.Name -contains 'CoverageSummaryFile') -and $testResult.CoverageSummaryFile) {
        Set-EngineFact -Context $sharedSettings -Namespace 'test' -Name 'coverageSummaryFile' -Value $testResult.CoverageSummaryFile -Overwrite Replace -LegacyProperty 'coverageSummaryFile'
    }

    Write-Log -Level "OK" -Message "  All tests passed!"
    Write-Log -Level "INFO" -Message "  Line Coverage:   $($testResult.LineRate)%"
    Write-Log -Level "INFO" -Message "  Branch Coverage: $($testResult.BranchRate)%"
    Write-Log -Level "INFO" -Message "  Method Coverage: $($testResult.MethodRate)%"
}

Export-ModuleMember -Function Invoke-Plugin
