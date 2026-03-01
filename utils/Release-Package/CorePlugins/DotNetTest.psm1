#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET test plugin for executing automated tests.

.DESCRIPTION
    This plugin resolves the configured .NET test project and optional
    results directory, runs tests through TestRunner, and stores
    the resulting test metrics in shared runtime context.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        # Same fallback pattern as the other plugins: use the existing shared module if it is already loaded.
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "TestRunner" -RequiredCommand "Invoke-TestsWithCoverage"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.Context
    $testProjectSetting = $pluginSettings.project
    $testResultsDirSetting = $pluginSettings.resultsDir
    $scriptDir = $sharedSettings.ScriptDir

    if ([string]::IsNullOrWhiteSpace($testProjectSetting)) {
        throw "DotNetTest plugin requires 'project' in scriptsettings.json."
    }

    $testProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $testProjectSetting))
    $testResultsDir = $null
    if (-not [string]::IsNullOrWhiteSpace($testResultsDirSetting)) {
        $testResultsDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $testResultsDirSetting))
    }

    Write-Log -Level "STEP" -Message "Running tests..."

    # Build a splatted hashtable so optional arguments can be added without duplicating the call site.
    $invokeTestParams = @{
        TestProjectPath = $testProjectPath
        Silent = $true
    }
    if ($testResultsDir) {
        $invokeTestParams.ResultsDirectory = $testResultsDir
    }

    $testResult = Invoke-TestsWithCoverage @invokeTestParams

    if (-not $testResult.Success) {
        throw "Tests failed. $($testResult.Error)"
    }

    $sharedSettings | Add-Member -NotePropertyName TestResult -NotePropertyValue $testResult -Force

    Write-Log -Level "OK" -Message "  All tests passed!"
    Write-Log -Level "INFO" -Message "  Line Coverage:   $($testResult.LineRate)%"
    Write-Log -Level "INFO" -Message "  Branch Coverage: $($testResult.BranchRate)%"
    Write-Log -Level "INFO" -Message "  Method Coverage: $($testResult.MethodRate)%"
}

Export-ModuleMember -Function Invoke-Plugin
