#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Quality gate plugin for validating release readiness.

.DESCRIPTION
    This plugin evaluates quality constraints using shared test
    results and project files. It enforces coverage thresholds
    and checks for vulnerable packages before release plugins run.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Test-VulnerablePackagesInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ProjectFiles
    )

    $findings = @()

    foreach ($projectPath in $ProjectFiles) {
        Write-Log -Level "STEP" -Message "Checking vulnerable packages: $([System.IO.Path]::GetFileName($projectPath))"

        $output = & dotnet list $projectPath package --vulnerable --include-transitive 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet list package --vulnerable failed for $projectPath."
        }

        $outputText = ($output | Out-String)
        if ($outputText -match "(?im)\bhas the following vulnerable packages\b" -or $outputText -match "(?im)^\s*>\s+[A-Za-z0-9_.-]+\s") {
            $findings += [pscustomobject]@{
                Project = $projectPath
                Output = $outputText.Trim()
            }
        }
    }

    return $findings
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.Context
    $coverageThresholdSetting = $pluginSettings.coverageThreshold
    $failOnVulnerabilitiesSetting = $pluginSettings.failOnVulnerabilities
    $projectFiles = $sharedSettings.ProjectFiles
    $testResult = $null
    if ($sharedSettings.PSObject.Properties['TestResult']) {
        $testResult = $sharedSettings.TestResult
    }

    if ($null -eq $testResult) {
        throw "QualityGate plugin requires test results. Run the DotNetTest plugin first."
    }

    $coverageThreshold = 0
    if ($null -ne $coverageThresholdSetting) {
        $coverageThreshold = [double]$coverageThresholdSetting
    }

    if ($coverageThreshold -gt 0) {
        Write-Log -Level "STEP" -Message "Checking coverage threshold..."
        if ([double]$testResult.LineRate -lt $coverageThreshold) {
            throw "Line coverage $($testResult.LineRate)% is below the configured threshold of $coverageThreshold%."
        }

        Write-Log -Level "OK" -Message "  Coverage threshold met: $($testResult.LineRate)% >= $coverageThreshold%"
    }
    else {
        Write-Log -Level "WARN" -Message "Skipping coverage threshold check (disabled)."
    }

    Assert-Command dotnet

    $failOnVulnerabilities = $true
    if ($null -ne $failOnVulnerabilitiesSetting) {
        $failOnVulnerabilities = [bool]$failOnVulnerabilitiesSetting
    }

    $vulnerabilities = Test-VulnerablePackagesInternal -ProjectFiles $projectFiles

    if ($vulnerabilities.Count -eq 0) {
        Write-Log -Level "OK" -Message "  No vulnerable packages detected."
        return
    }

    foreach ($finding in $vulnerabilities) {
        Write-Log -Level "WARN" -Message "  Vulnerable packages detected in $([System.IO.Path]::GetFileName($finding.Project))"
        $finding.Output -split "`r?`n" | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_)) {
                Write-Log -Level "WARN" -Message "    $_"
            }
        }
    }

    if ($failOnVulnerabilities) {
        throw "Vulnerable packages were detected and failOnVulnerabilities is enabled."
    }

    Write-Log -Level "WARN" -Message "Vulnerable packages detected, but failOnVulnerabilities is disabled."
}

Export-ModuleMember -Function Invoke-Plugin
