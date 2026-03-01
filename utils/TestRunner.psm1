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
        Path to the test project directory.

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
        - CoverageFile: string

    .EXAMPLE
        $result = Invoke-TestsWithCoverage -TestProjectPath ".\Tests"
        if ($result.Success) { Write-TestRunnerLogInternal -Level "INFO" -Message "Line coverage: $($result.LineRate)%" }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestProjectPath,

        [switch]$Silent,

        [string]$ResultsDirectory,

        [switch]$KeepResults
    )

    $ErrorActionPreference = "Stop"

    # Resolve path
    $TestProjectDir = Resolve-Path $TestProjectPath -ErrorAction SilentlyContinue
    if (-not $TestProjectDir) {
        return [PSCustomObject]@{
            Success = $false
            Error = "Test project not found at: $TestProjectPath"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ResultsDirectory)) {
        $ResultsDir = Join-Path $TestProjectDir "TestResults"
    }
    else {
        $ResultsDir = [System.IO.Path]::GetFullPath($ResultsDirectory)
    }

    # Clean previous results
    if (Test-Path $ResultsDir) {
        Remove-Item -Recurse -Force $ResultsDir
    }

    if (-not $Silent) {
        Write-TestRunnerLogInternal -Level "STEP" -Message "Running tests with code coverage..."
        Write-TestRunnerLogInternal -Level "INFO" -Message "Test Project: $TestProjectDir"
    }

    # Run tests with coverage collection
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
        } else {
            & dotnet @dotnetArgs
        }

        $testExitCode = $LASTEXITCODE
        if ($testExitCode -ne 0) {
            return [PSCustomObject]@{
                Success = $false
                Error = "Tests failed with exit code $testExitCode"
            }
        }
    }
    finally {
        Pop-Location
    }

    # Find the coverage file
    $CoverageFile = Get-ChildItem -Path $ResultsDir -Filter "coverage.cobertura.xml" -Recurse | Select-Object -First 1

    if (-not $CoverageFile) {
        return [PSCustomObject]@{
            Success = $false
            Error = "Coverage file not found"
        }
    }

    if (-not $Silent) {
        Write-TestRunnerLogInternal -Level "OK" -Message "Coverage file found: $($CoverageFile.FullName)"
        Write-TestRunnerLogInternal -Level "STEP" -Message "Parsing coverage data..."
    }

    # Parse coverage data from Cobertura XML
    [xml]$coverageXml = Get-Content $CoverageFile.FullName

    $lineRate = [math]::Round([double]$coverageXml.coverage.'line-rate' * 100, 1)
    $branchRate = [math]::Round([double]$coverageXml.coverage.'branch-rate' * 100, 1)

    # Calculate method coverage from packages
    $totalMethods = 0
    $coveredMethods = 0
    foreach ($package in $coverageXml.coverage.packages.package) {
        foreach ($class in $package.classes.class) {
            foreach ($method in $class.methods.method) {
                $totalMethods++
                if ([double]$method.'line-rate' -gt 0) {
                    $coveredMethods++
                }
            }
        }
    }
    $methodRate = if ($totalMethods -gt 0) { [math]::Round(($coveredMethods / $totalMethods) * 100, 1) } else { 0 }

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
        CoverageFile = $CoverageFile.FullName
    }
}

Export-ModuleMember -Function Invoke-TestsWithCoverage
