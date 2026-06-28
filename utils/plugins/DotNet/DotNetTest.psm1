#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET test plugin for executing automated tests.

.DESCRIPTION
    Resolves one or more .NET test projects (`project` or `projects`), runs tests once
    via TestRunner, then publishes metrics on the shared engine context for any later
    plugin: `qualityLineCoverage`, `testResult`, `coverageLineRate` / `coverageBranchRate` / `coverageMethodRate`,
    method counts, `testResultsDirectory`, `coverageCoberturaPaths`. Quality gates read
    those keys generically (not tied to this plugin by name). Cobertura files are removed
    after parsing unless TestRunner gains KeepResults.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
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
    $sharedSettings = $Settings.context
    $testResultsDirSetting = $pluginSettings.resultsDir
    $scriptDir = $sharedSettings.scriptDir

    $testProjectPaths = [System.Collections.Generic.List[string]]::new()
    if ($pluginSettings.PSObject.Properties.Name -contains 'projects' -and $pluginSettings.projects) {
        foreach ($rel in @($pluginSettings.projects)) {
            if ([string]::IsNullOrWhiteSpace([string]$rel)) { continue }
            $testProjectPaths.Add([System.IO.Path]::GetFullPath((Join-Path $scriptDir $rel.Trim())))
        }
    }
    if ($testProjectPaths.Count -eq 0 -and $pluginSettings.project) {
        $testProjectPaths.Add([System.IO.Path]::GetFullPath((Join-Path $scriptDir $pluginSettings.project)))
    }
    if ($testProjectPaths.Count -eq 0) {
        throw "DotNetTest plugin requires 'project' or 'projects' in scriptSettings.json."
    }

    $testResultsDir = $null
    if (-not [string]::IsNullOrWhiteSpace($testResultsDirSetting)) {
        $testResultsDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $testResultsDirSetting))
    }
    elseif ($testProjectPaths.Count -gt 1) {
        $testResultsDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "TestResults"))
    }

    Write-Log -Level "STEP" -Message "Running tests..."

    # Build a splatted hashtable so optional arguments can be added without duplicating the call site.
    $invokeTestParams = @{
        TestProjectPath = @($testProjectPaths)
        Silent = $true
    }
    if ($testResultsDir) {
        $invokeTestParams.ResultsDirectory = $testResultsDir
    }

    $testResult = Invoke-TestsWithCoverage @invokeTestParams

    if (-not $testResult.Success) {
        throw "Tests failed. $($testResult.Error)"
    }

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
    if ($testResult.CoverageFiles) {
        $sharedSettings | Add-Member -NotePropertyName coverageCoberturaPaths -NotePropertyValue @($testResult.CoverageFiles) -Force
    }

    Write-Log -Level "OK" -Message "  All tests passed!"
    Write-Log -Level "INFO" -Message "  Line Coverage:   $($testResult.LineRate)%"
    Write-Log -Level "INFO" -Message "  Branch Coverage: $($testResult.BranchRate)%"
    Write-Log -Level "INFO" -Message "  Method Coverage: $($testResult.MethodRate)%"
}

Export-ModuleMember -Function Invoke-Plugin
