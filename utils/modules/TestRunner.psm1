#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    PowerShell module for running tests with code coverage.

.DESCRIPTION
    Provides the Invoke-TestsWithCoverage function for running .NET tests
    with Coverlet code coverage collection and parsing results.

.NOTES
    Author: MaksIT
    Usage: pwsh -Command "Import-Module .\TestRunner.psm1"
#>

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
        Write-TestRunnerLogInternal -Level "STEP" -Message "Running tests with code coverage..."
        foreach ($d in $resolvedProjectDirs) {
            Write-TestRunnerLogInternal -Level "INFO" -Message "Test Project: $d"
        }
    }

    foreach ($TestProjectDir in $resolvedProjectDirs) {
        Push-Location $TestProjectDir
        try {
            $dotnetArgs = @(
                "test"
                "--collect:XPlat Code Coverage"
                "--results-directory", $ResultsDir
                "--verbosity", $(if ($Silent) { "quiet" } else { "normal" })
            )

            if ($Silent) {
                $null = & dotnet @dotnetArgs 2>&1
            }
            else {
                & dotnet @dotnetArgs
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

    $coverageFiles = @(Get-ChildItem -Path $ResultsDir -Filter "coverage.cobertura.xml" -Recurse | Sort-Object FullName)

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
        if ($Silent) {
            $null = & npm @npmArgs 2>&1
        }
        else {
            & npm @npmArgs
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

Export-ModuleMember -Function Invoke-TestsWithCoverage, Invoke-NpmJestTestsWithCoverage
