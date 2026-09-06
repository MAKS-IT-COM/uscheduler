#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    PowerShell module for running tests with code coverage.

.DESCRIPTION
    Provides the Invoke-TestsWithCoverage function for running .NET tests
    with Microsoft.Testing.Platform and coverlet.MTP code coverage.

.NOTES
    Author: MaksIT
    Usage: pwsh -Command "Import-Module .\TestRunner.psm1"
#>

function Import-ExternalCommandSupportInternal {
    if (Get-Command Invoke-ExternalCommand -ErrorAction SilentlyContinue) {
        return
    }

    $candidates = @(
        (Join-Path $PSScriptRoot 'ExternalCommandSupport.psm1')
    )
    foreach ($modulePath in $candidates) {
        if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
            Import-Module $modulePath -Force -Global
            break
        }
    }

    if (-not (Get-Command Invoke-ExternalCommand -ErrorAction SilentlyContinue)) {
        throw "ExternalCommandSupport module not found. Expected: $($candidates -join ', ')"
    }
}

function Import-LoggingModuleInternal {
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        return
    }

    $modulePath = Join-Path $PSScriptRoot "Logging.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
}

function Write-TestRunnerLogInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "STEP", "DEBUG")]
        [string]$Level = "INFO"
    )

    Import-LoggingModuleInternal

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level $Level -Message $Message
        return
    }

    Write-Host $Message -ForegroundColor Gray
}

function Get-CoberturaCoverageFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResultsDirectory
    )

    # coverlet.MTP: [prefix.]coverage.cobertura[.timestamp].xml
    $files = @(
        Get-ChildItem -Path $ResultsDirectory -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*coverage.cobertura*.xml' }
    )
    return @($files | Sort-Object FullName -Unique)
}

function Invoke-TestsWithCoverage {
    <#
    .SYNOPSIS
        Runs unit tests with code coverage and returns coverage metrics.

    .PARAMETER TestProjectPath
        One or more paths to test project directories (or .csproj files). Each project
        is tested in order; coverage metrics are aggregated across all Cobertura outputs.

    .PARAMETER Silent
        Suppress console output (for JSON consumption).

    .PARAMETER ResultsDirectory
        Optional fixed directory where test result files are written.

    .PARAMETER KeepResults
        Keep the TestResults folder after execution.

    .OUTPUTS
        PSCustomObject with properties:
        - Success: bool
        - Error: string (if failed)
        - LineRate: double
        - BranchRate: double
        - MethodRate: double
        - TotalMethods: int
        - CoveredMethods: int
        - CoverageFile: string (ReportGenerator reports arg: one file, or semicolon-separated)
        - CoverageFiles: string[] (individual Cobertura paths)
        - ResultsDirectory: string (absolute folder used for dotnet test output; may be removed after run unless -KeepResults)

    .EXAMPLE
        $result = Invoke-TestsWithCoverage -TestProjectPath ".\Tests"
        if ($result.Success) { Write-TestRunnerLogInternal -Level "INFO" -Message "Line coverage: $($result.LineRate)%" }

    .EXAMPLE
        $result = Invoke-TestsWithCoverage -TestProjectPath @(".\ProjA.Tests", ".\ProjB.Tests")
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TestProjectPath,

        [switch]$Silent,

        [string]$ResultsDirectory,

        [switch]$KeepResults
    )

    $ErrorActionPreference = "Stop"

    # Normalize to a non-empty list of absolute working directories (folder containing the test project).
    $resolvedProjectDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in $TestProjectPath) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $full = [System.IO.Path]::GetFullPath($raw.Trim())
        if (-not (Test-Path $full)) {
            return [PSCustomObject]@{
                Success = $false
                Error = "Test project not found at: $raw"
            }
        }
        $item = Get-Item -LiteralPath $full
        $dir = if ($item.PSIsContainer) { $item.FullName } else { $item.Directory.FullName }
        if ($resolvedProjectDirs -notcontains $dir) {
            [void]$resolvedProjectDirs.Add($dir)
        }
    }

    if ($resolvedProjectDirs.Count -eq 0) {
        return [PSCustomObject]@{
            Success = $false
            Error = "No valid test project paths were provided."
        }
    }

    if ([string]::IsNullOrWhiteSpace($ResultsDirectory)) {
        $ResultsDir = Join-Path $resolvedProjectDirs[0] "TestResults"
    }
    else {
        $ResultsDir = [System.IO.Path]::GetFullPath($ResultsDirectory)
    }

    # Clean previous results once (shared output for all test runs).
    if (Test-Path $ResultsDir) {
        Remove-Item -Recurse -Force $ResultsDir
    }
    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null

    if (-not $Silent) {
        Write-TestRunnerLogInternal -Level "STEP" -Message "Running tests with code coverage (Microsoft.Testing.Platform / coverlet.MTP)..."
        foreach ($d in $resolvedProjectDirs) {
            Write-TestRunnerLogInternal -Level "INFO" -Message "Test Project: $d"
        }
    }

    foreach ($TestProjectDir in $resolvedProjectDirs) {
        Push-Location $TestProjectDir
        try {
            $projectName = [System.IO.Path]::GetFileName($TestProjectDir)
            $dotnetArgs = @(
                "test"
                "--results-directory", $ResultsDir
                "--verbosity", $(if ($Silent) { "quiet" } else { "normal" })
                "--coverlet"
                "--coverlet-output-format", "cobertura"
                "--coverlet-file-prefix", $projectName
                "--coverlet-include", "[MaksIT.*]*"
            )

            Import-ExternalCommandSupportInternal
            if ($Silent) {
                $null = Invoke-ExternalCommand -Name dotnet -ArgumentList $dotnetArgs -MergeErrorOutput -ThrowOnError:$false
            }
            else {
                Invoke-ExternalCommand -Name dotnet -ArgumentList $dotnetArgs -ThrowOnError:$false | Out-Default
            }

            $testExitCode = $LASTEXITCODE
            if ($testExitCode -ne 0) {
                return [PSCustomObject]@{
                    Success = $false
                    Error = "Tests failed in '$TestProjectDir' with exit code $testExitCode"
                }
            }
        }
        finally {
            Pop-Location
        }
    }

    $coverageFiles = @(Get-CoberturaCoverageFiles -ResultsDirectory $ResultsDir)

    if ($coverageFiles.Count -eq 0) {
        return [PSCustomObject]@{
            Success = $false
            Error = "Coverage file not found under: $ResultsDir"
        }
    }

    if (-not $Silent) {
        foreach ($cf in $coverageFiles) {
            Write-TestRunnerLogInternal -Level "OK" -Message "Coverage file found: $($cf.FullName)"
        }
        Write-TestRunnerLogInternal -Level "STEP" -Message "Parsing coverage data..."
    }

    # Aggregate line/branch from Cobertura counters; methods by walking all files.
    $linesCoveredTotal = 0L
    $linesValidTotal = 0L
    $branchesCoveredTotal = 0L
    $branchesValidTotal = 0L
    $totalMethods = 0
    $coveredMethods = 0

    foreach ($cf in $coverageFiles) {
        [xml]$coverageXml = Get-Content -LiteralPath $cf.FullName -Raw
        $root = $coverageXml.coverage
        $lcAttr = $root.'lines-covered'
        $lvAttr = $root.'lines-valid'
        if ($null -ne $lcAttr -and $null -ne $lvAttr -and [long]$lvAttr -gt 0) {
            $linesCoveredTotal += [long]$lcAttr
            $linesValidTotal += [long]$lvAttr
        }

        $bcAttr = $root.'branches-covered'
        $bvAttr = $root.'branches-valid'
        if ($null -ne $bcAttr -and $null -ne $bvAttr -and [long]$bvAttr -gt 0) {
            $branchesCoveredTotal += [long]$bcAttr
            $branchesValidTotal += [long]$bvAttr
        }

        foreach ($package in @($root.packages.package)) {
            foreach ($class in @($package.classes.class)) {
                $methodNodes = $class.methods
                if ($null -eq $methodNodes) { continue }
                foreach ($method in @($methodNodes.method)) {
                    if ($null -eq $method) { continue }
                    $totalMethods++
                    if ([double]$method.'line-rate' -gt 0) {
                        $coveredMethods++
                    }
                }
            }
        }
    }

    if ($linesValidTotal -gt 0) {
        $lineRate = [math]::Round(($linesCoveredTotal / $linesValidTotal) * 100, 1)
    }
    else {
        # Fallback: average of per-file line-rate when counters are missing (older Cobertura).
        $acc = 0.0
        $n = 0
        foreach ($cf in $coverageFiles) {
            [xml]$coverageXml = Get-Content -LiteralPath $cf.FullName -Raw
            $acc += [double]$coverageXml.coverage.'line-rate'
            $n++
        }
        $lineRate = [math]::Round(($acc / [math]::Max($n, 1)) * 100, 1)
    }

    if ($branchesValidTotal -gt 0) {
        $branchRate = [math]::Round(($branchesCoveredTotal / $branchesValidTotal) * 100, 1)
    }
    else {
        $acc = 0.0
        $n = 0
        foreach ($cf in $coverageFiles) {
            [xml]$coverageXml = Get-Content -LiteralPath $cf.FullName -Raw
            $acc += [double]$coverageXml.coverage.'branch-rate'
            $n++
        }
        $branchRate = [math]::Round(($acc / [math]::Max($n, 1)) * 100, 1)
    }

    $methodRate = if ($totalMethods -gt 0) { [math]::Round(($coveredMethods / $totalMethods) * 100, 1) } else { 0 }

    $coveragePaths = @($coverageFiles | ForEach-Object { $_.FullName })
    $coverageFileReportArg = $coveragePaths -join ";"
    $resultsDirectoryFull = [System.IO.Path]::GetFullPath($ResultsDir)

    # Cleanup unless KeepResults is specified
    if (-not $KeepResults) {
        if (Test-Path $ResultsDir) {
            Remove-Item -Recurse -Force $ResultsDir
        }
    }

    # Return results
    return [PSCustomObject]@{
        Success = $true
        LineRate = $lineRate
        BranchRate = $branchRate
        MethodRate = $methodRate
        TotalMethods = $totalMethods
        CoveredMethods = $coveredMethods
        CoverageFile = $coverageFileReportArg
        CoverageFiles = $coveragePaths
        ResultsDirectory = $resultsDirectoryFull
    }
}

function Invoke-NpmJestTestsWithCoverage {
    <#
    .SYNOPSIS
        Runs npm/Jest tests with coverage and returns normalized metrics.

    .PARAMETER WorkspaceRoot
        npm workspace root (folder containing package.json and jest.config).

    .PARAMETER TestScript
        npm script name to run (default: test). Coverage flags are appended via `--`.

    .PARAMETER CoverageDirectory
        Relative path under WorkspaceRoot where Jest writes coverage output.

    .PARAMETER Silent
        Suppress console output from npm.

    .OUTPUTS
        Same metric shape as Invoke-TestsWithCoverage, plus CoverageSummaryFile when available.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [string]$TestScript = 'test',

        [string]$CoverageDirectory = 'coverage',

        [switch]$Silent
    )

    $ErrorActionPreference = 'Stop'
    $workspaceFull = [System.IO.Path]::GetFullPath($WorkspaceRoot)
    if (-not (Test-Path (Join-Path $workspaceFull 'package.json') -PathType Leaf)) {
        return [PSCustomObject]@{
            Success = $false
            Error = "package.json not found in workspace root: $workspaceFull"
        }
    }

    if (-not $Silent) {
        Write-TestRunnerLogInternal -Level 'STEP' -Message 'Running npm/Jest tests with coverage...'
        Write-TestRunnerLogInternal -Level 'INFO' -Message "Workspace: $workspaceFull"
    }

    Push-Location $workspaceFull
    try {
        $npmArgs = @('run', $TestScript, '--', '--coverage', '--coverageReporters=json-summary', '--coverageReporters=text')
        Import-ExternalCommandSupportInternal
        if ($Silent) {
            $null = Invoke-ExternalCommand -Name npm -ArgumentList $npmArgs -MergeErrorOutput -ThrowOnError:$false
        }
        else {
            Invoke-ExternalCommand -Name npm -ArgumentList $npmArgs -ThrowOnError:$false | Out-Default
        }

        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{
                Success = $false
                Error = "npm run $TestScript failed with exit code $LASTEXITCODE"
            }
        }
    }
    finally {
        Pop-Location
    }

    $summaryPath = Join-Path $workspaceFull (Join-Path $CoverageDirectory 'coverage-summary.json')
    if (-not (Test-Path $summaryPath -PathType Leaf)) {
        return [PSCustomObject]@{
            Success = $false
            Error = "Jest coverage summary not found at: $summaryPath"
        }
    }

    $summaryJson = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $total = $summaryJson.total
    if ($null -eq $total) {
        return [PSCustomObject]@{
            Success = $false
            Error = "Jest coverage summary is missing 'total' metrics in: $summaryPath"
        }
    }

    $lineRate = [math]::Round([double]$total.lines.pct, 1)
    $branchRate = [math]::Round([double]$total.branches.pct, 1)
    $methodRate = [math]::Round([double]$total.functions.pct, 1)
    $totalMethods = [int]$total.functions.total
    $coveredMethods = [int]$total.functions.covered
    $resultsDirectory = [System.IO.Path]::GetFullPath((Join-Path $workspaceFull $CoverageDirectory))

    if (-not $Silent) {
        Write-TestRunnerLogInternal -Level 'OK' -Message "Coverage summary: $summaryPath"
    }

    return [PSCustomObject]@{
        Success = $true
        LineRate = $lineRate
        BranchRate = $branchRate
        MethodRate = $methodRate
        TotalMethods = $totalMethods
        CoveredMethods = $coveredMethods
        CoverageSummaryFile = $summaryPath
        ResultsDirectory = $resultsDirectory
    }
}

function Get-NpmCoverageFromSummaryFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SummaryPath,

        [switch]$Silent
    )

    if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
        return [PSCustomObject]@{
            Success = $false
            Error   = "Jest coverage summary not found at: $SummaryPath"
        }
    }

    $summaryJson = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $total = $summaryJson.total
    if ($null -eq $total) {
        return [PSCustomObject]@{
            Success = $false
            Error   = "Jest coverage summary is missing 'total' metrics in: $SummaryPath"
        }
    }

    return [PSCustomObject]@{
        Success        = $true
        LineRate       = [math]::Round([double]$total.lines.pct, 1)
        BranchRate     = [math]::Round([double]$total.branches.pct, 1)
        MethodRate     = [math]::Round([double]$total.functions.pct, 1)
        TotalMethods   = [int]$total.functions.total
        CoveredMethods = [int]$total.functions.covered
        CoverageFormat = 'npm'
        CoverageSummaryFile = $SummaryPath
    }
}

function Get-DotNetCoverageFromResultsDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResultsDirectory,

        [switch]$Silent
    )

    $coverageFiles = @(Get-CoberturaCoverageFiles -ResultsDirectory $ResultsDirectory)
    if ($coverageFiles.Count -eq 0) {
        return [PSCustomObject]@{
            Success = $false
            Error   = "Coverage file not found under: $ResultsDirectory"
        }
    }

    $linesCoveredTotal = 0L
    $linesValidTotal = 0L
    $branchesCoveredTotal = 0L
    $branchesValidTotal = 0L
    $totalMethods = 0
    $coveredMethods = 0

    foreach ($cf in $coverageFiles) {
        [xml]$coverageXml = Get-Content -LiteralPath $cf.FullName -Raw
        $root = $coverageXml.coverage
        $lcAttr = $root.'lines-covered'
        $lvAttr = $root.'lines-valid'
        if ($null -ne $lcAttr -and $null -ne $lvAttr -and [long]$lvAttr -gt 0) {
            $linesCoveredTotal += [long]$lcAttr
            $linesValidTotal += [long]$lvAttr
        }

        $bcAttr = $root.'branches-covered'
        $bvAttr = $root.'branches-valid'
        if ($null -ne $bcAttr -and $null -ne $bvAttr -and [long]$bvAttr -gt 0) {
            $branchesCoveredTotal += [long]$bcAttr
            $branchesValidTotal += [long]$bvAttr
        }

        foreach ($package in @($root.packages.package)) {
            foreach ($class in @($package.classes.class)) {
                $methodNodes = $class.methods
                if ($null -eq $methodNodes) { continue }
                foreach ($method in @($methodNodes.method)) {
                    if ($null -eq $method) { continue }
                    $totalMethods++
                    if ([double]$method.'line-rate' -gt 0) {
                        $coveredMethods++
                    }
                }
            }
        }
    }

    if ($linesValidTotal -gt 0) {
        $lineRate = [math]::Round(($linesCoveredTotal / $linesValidTotal) * 100, 1)
    }
    else {
        $acc = 0.0
        $n = 0
        foreach ($cf in $coverageFiles) {
            [xml]$coverageXml = Get-Content -LiteralPath $cf.FullName -Raw
            $acc += [double]$coverageXml.coverage.'line-rate'
            $n++
        }
        $lineRate = [math]::Round(($acc / [math]::Max($n, 1)) * 100, 1)
    }

    if ($branchesValidTotal -gt 0) {
        $branchRate = [math]::Round(($branchesCoveredTotal / $branchesValidTotal) * 100, 1)
    }
    else {
        $acc = 0.0
        $n = 0
        foreach ($cf in $coverageFiles) {
            [xml]$coverageXml = Get-Content -LiteralPath $cf.FullName -Raw
            $acc += [double]$coverageXml.coverage.'branch-rate'
            $n++
        }
        $branchRate = [math]::Round(($acc / [math]::Max($n, 1)) * 100, 1)
    }

    $methodRate = if ($totalMethods -gt 0) { [math]::Round(($coveredMethods / $totalMethods) * 100, 1) } else { 0 }
    $coveragePaths = @($coverageFiles | ForEach-Object { $_.FullName })

    return [PSCustomObject]@{
        Success           = $true
        LineRate          = $lineRate
        BranchRate        = $branchRate
        MethodRate        = $methodRate
        TotalMethods      = $totalMethods
        CoveredMethods    = $coveredMethods
        CoverageFile      = ($coveragePaths -join ';')
        CoverageFiles     = $coveragePaths
        ResultsDirectory  = [System.IO.Path]::GetFullPath($ResultsDirectory)
        CoverageFormat    = 'dotnet'
    }
}

function Get-CoverageFromResultsDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResultsDirectory,

        [ValidateSet('auto', 'dotnet', 'npm')]
        [string]$Format = 'auto',

        [switch]$Silent
    )

    $resolvedDirectory = [System.IO.Path]::GetFullPath($ResultsDirectory)
    if (-not (Test-Path -LiteralPath $resolvedDirectory -PathType Container)) {
        return [PSCustomObject]@{
            Success = $false
            Error   = "Results directory not found: $resolvedDirectory"
        }
    }

    $hasDotNet = @(Get-CoberturaCoverageFiles -ResultsDirectory $resolvedDirectory).Count -gt 0
    $jestSummary = Join-Path $resolvedDirectory 'coverage-summary.json'
    $hasNpm = Test-Path -LiteralPath $jestSummary -PathType Leaf

    $effectiveFormat = $Format
    if ($effectiveFormat -eq 'auto') {
        if ($hasDotNet -and -not $hasNpm) {
            $effectiveFormat = 'dotnet'
        }
        elseif ($hasNpm -and -not $hasDotNet) {
            $effectiveFormat = 'npm'
        }
        elseif ($hasDotNet) {
            $effectiveFormat = 'dotnet'
        }
        elseif ($hasNpm) {
            $effectiveFormat = 'npm'
        }
        else {
            return [PSCustomObject]@{
                Success = $false
                Error   = "Coverage file not found under: $resolvedDirectory"
            }
        }
    }

    if ($effectiveFormat -eq 'dotnet') {
        return Get-DotNetCoverageFromResultsDirectory -ResultsDirectory $resolvedDirectory -Silent:$Silent
    }

    if ($effectiveFormat -eq 'npm') {
        $npmResult = Get-NpmCoverageFromSummaryFile -SummaryPath $jestSummary -Silent:$Silent
        if (-not $npmResult.Success) {
            return $npmResult
        }

        $npmResult | Add-Member -NotePropertyName ResultsDirectory -NotePropertyValue $resolvedDirectory -Force
        return $npmResult
    }

    return [PSCustomObject]@{
        Success = $false
        Error   = "Unsupported coverage format '$Format'."
    }
}

function Publish-CoverageMetricsToSharedContext {
    param(
        [Parameter(Mandatory = $true)]
        $SharedSettings,

        [Parameter(Mandatory = $true)]
        $TestResult
    )

    if (-not (Get-Command Set-EngineFact -ErrorAction SilentlyContinue)) {
        $engineContextPath = Join-Path $PSScriptRoot 'Engine' 'EngineContext.psm1'
        if (Test-Path -LiteralPath $engineContextPath -PathType Leaf) {
            Import-Module $engineContextPath -Force -Global
        }
    }

    if (Get-Command Set-EngineFact -ErrorAction SilentlyContinue) {
        Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'testResult' -Value $TestResult -Overwrite Replace -LegacyProperty 'testResult'
        Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'coverageLineRate' -Value $TestResult.LineRate -Overwrite Replace -LegacyProperty 'coverageLineRate'
        Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'qualityLineCoverage' -Value $TestResult.LineRate -Overwrite Replace -LegacyProperty 'qualityLineCoverage'
        Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'coverageBranchRate' -Value $TestResult.BranchRate -Overwrite Replace -LegacyProperty 'coverageBranchRate'
        Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'coverageMethodRate' -Value $TestResult.MethodRate -Overwrite Replace -LegacyProperty 'coverageMethodRate'
        Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'coverageTotalMethods' -Value $TestResult.TotalMethods -Overwrite Replace -LegacyProperty 'coverageTotalMethods'
        Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'coverageCoveredMethods' -Value $TestResult.CoveredMethods -Overwrite Replace -LegacyProperty 'coverageCoveredMethods'

        if ($TestResult.PSObject.Properties.Name -contains 'CoverageFormat') {
            Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'coverageFormat' -Value $TestResult.CoverageFormat -Overwrite Replace -LegacyProperty 'coverageFormat'
        }

        if (($TestResult.PSObject.Properties.Name -contains 'ResultsDirectory') -and $TestResult.ResultsDirectory) {
            Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'testResultsDirectory' -Value $TestResult.ResultsDirectory -Overwrite Replace -LegacyProperty 'testResultsDirectory'
        }

        if ($TestResult.CoverageFiles) {
            Set-EngineFact -Context $SharedSettings -Namespace 'test' -Name 'coverageCoberturaPaths' -Value @($TestResult.CoverageFiles) -Overwrite Replace -LegacyProperty 'coverageCoberturaPaths'
        }

        return
    }

    $SharedSettings | Add-Member -NotePropertyName testResult -NotePropertyValue $TestResult -Force
    $SharedSettings | Add-Member -NotePropertyName qualityLineCoverage -NotePropertyValue $TestResult.LineRate -Force
    $SharedSettings | Add-Member -NotePropertyName coverageLineRate -NotePropertyValue $TestResult.LineRate -Force
    $SharedSettings | Add-Member -NotePropertyName coverageBranchRate -NotePropertyValue $TestResult.BranchRate -Force
    $SharedSettings | Add-Member -NotePropertyName coverageMethodRate -NotePropertyValue $TestResult.MethodRate -Force
    $SharedSettings | Add-Member -NotePropertyName coverageTotalMethods -NotePropertyValue $TestResult.TotalMethods -Force
    $SharedSettings | Add-Member -NotePropertyName coverageCoveredMethods -NotePropertyValue $TestResult.CoveredMethods -Force

    if ($TestResult.PSObject.Properties.Name -contains 'CoverageFormat') {
        $SharedSettings | Add-Member -NotePropertyName coverageFormat -NotePropertyValue $TestResult.CoverageFormat -Force
    }

    if (($TestResult.PSObject.Properties.Name -contains 'ResultsDirectory') -and $TestResult.ResultsDirectory) {
        $SharedSettings | Add-Member -NotePropertyName testResultsDirectory -NotePropertyValue $TestResult.ResultsDirectory -Force
    }

    if ($TestResult.CoverageFiles) {
        $SharedSettings | Add-Member -NotePropertyName coverageCoberturaPaths -NotePropertyValue @($TestResult.CoverageFiles) -Force
    }
}

Export-ModuleMember -Function `
    Invoke-TestsWithCoverage, `
    Invoke-NpmJestTestsWithCoverage, `
    Get-NpmCoverageFromSummaryFile, `
    Get-DotNetCoverageFromResultsDirectory, `
    Get-CoverageFromResultsDirectory, `
    Publish-CoverageMetricsToSharedContext
