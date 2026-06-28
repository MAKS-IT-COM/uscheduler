#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Quality gate plugin (coverage threshold + optional .NET vulnerability scan).

.DESCRIPTION
    Does not run tests or collect coverage. It reads whatever prior plugins left on the
    shared engine context (same object passed to every plugin as .context).

    Line coverage for threshold checks is resolved in order (first present wins):
      - qualityLineCoverage  (generic; any plugin may set this)
      - coverageLineRate     (conventional flat metric)
      - testResult.LineRate  (object from a test plugin; property name is conventional)

    Configure coverageThreshold > 0 to require one of those inputs. With coverageThreshold 0
    and scanVulnerabilities false, the plugin is a no-op.

    When scanVulnerabilities is true, runs dotnet list package --vulnerable on projectFiles.

    Use stageLabel "qualityGate" in scriptSettings.json; plugin: plugins/Platform/QualityGate.psm1 (`"name": "QualityGate"`).
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
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

function Get-LineCoveragePercentFromSharedContext {
    param(
        [Parameter(Mandatory = $true)]
        $Shared
    )

    foreach ($prop in @('qualityLineCoverage', 'coverageLineRate')) {
        if ($Shared.PSObject.Properties.Name -contains $prop) {
            $raw = $Shared.$prop
            if ($null -eq $raw) { continue }
            $asString = [string]$raw
            if ([string]::IsNullOrWhiteSpace($asString)) { continue }
            return [double]$asString
        }
    }

    if ($Shared.PSObject.Properties.Name -contains 'testResult' -and $null -ne $Shared.testResult) {
        $tr = $Shared.testResult
        if ($tr.PSObject.Properties.Name -contains 'LineRate') {
            return [double]$tr.LineRate
        }
    }

    return $null
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Resolve-RelativePaths"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $coverageThresholdSetting = $pluginSettings.coverageThreshold
    $failOnVulnerabilitiesSetting = $pluginSettings.failOnVulnerabilities
    $scanVulnerabilities = $true
    if ($null -ne $pluginSettings.scanVulnerabilities) {
        $scanVulnerabilities = [bool]$pluginSettings.scanVulnerabilities
    }

    if ($pluginSettings.PSObject.Properties['projectFiles'] -and $null -ne $pluginSettings.projectFiles) {
        $projectFiles = @(Resolve-RelativePaths -Value $pluginSettings.projectFiles -BasePath $scriptDir)
    }
    elseif ($sharedSettings.PSObject.Properties['projectFiles'] -and $null -ne $sharedSettings.projectFiles) {
        $projectFiles = @($sharedSettings.projectFiles)
    }
    else {
        $projectFiles = @()
    }

    $coverageThreshold = 0
    if ($null -ne $coverageThresholdSetting) {
        $coverageThreshold = [double]$coverageThresholdSetting
    }

    $needCoverageCheck = $coverageThreshold -gt 0
    if (-not $needCoverageCheck -and -not $scanVulnerabilities) {
        Write-Log -Level "INFO" -Message "  Quality gate: no checks enabled (coverageThreshold 0, scanVulnerabilities false)."
        return
    }

    $lineRate = $null
    if ($needCoverageCheck) {
        $lineRate = Get-LineCoveragePercentFromSharedContext -Shared $sharedSettings
        if ($null -eq $lineRate) {
            throw "coverageThreshold is $coverageThreshold but shared context has no line coverage. Set one of: qualityLineCoverage, coverageLineRate, or testResult.LineRate (from an earlier plugin)."
        }

        Write-Log -Level "STEP" -Message "Checking line coverage threshold against shared context..."
        if ($lineRate -lt $coverageThreshold) {
            throw "Line coverage $lineRate% is below the configured threshold of $coverageThreshold%."
        }

        Write-Log -Level "OK" -Message "  Coverage threshold met: $lineRate% >= $coverageThreshold%"
    }
    else {
        Write-Log -Level "INFO" -Message "  Coverage threshold check not required (coverageThreshold is 0)."
    }

    if (-not $scanVulnerabilities) {
        Write-Log -Level "INFO" -Message "  Vulnerability scan skipped (scanVulnerabilities is false)."
        return
    }

    Assert-Command dotnet

    $failOnVulnerabilities = $true
    if ($null -ne $failOnVulnerabilitiesSetting) {
        $failOnVulnerabilities = [bool]$failOnVulnerabilitiesSetting
    }

    if ($projectFiles.Count -eq 0) {
        throw "QualityGate requires projectFiles when scanVulnerabilities is true."
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
