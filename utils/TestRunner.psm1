<#
.SYNOPSIS
    PowerShell module for running tests with code coverage.

.DESCRIPTION
    Provides the Invoke-TestsWithCoverage function for running .NET tests
    with Coverlet code coverage collection and parsing results.

.NOTES
    Author: MaksIT
    Usage: Import-Module .\TestRunner.psm1
#>

function Invoke-TestsWithCoverage {
    <#
    .SYNOPSIS
        Runs unit tests with code coverage and returns coverage metrics.

    .PARAMETER TestProjectPath
        Path to the test project directory.

    .PARAMETER Silent
        Suppress console output (for JSON consumption).

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
        if ($result.Success) { Write-Host "Line coverage: $($result.LineRate)%" }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestProjectPath,

        [switch]$Silent,

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

    $ResultsDir = Join-Path $TestProjectDir "TestResults"

    # Clean previous results
    if (Test-Path $ResultsDir) {
        Remove-Item -Recurse -Force $ResultsDir
    }

    if (-not $Silent) {
        Write-Host "Running tests with code coverage..." -ForegroundColor Cyan
        Write-Host "  Test Project: $TestProjectDir" -ForegroundColor Gray
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
        Write-Host "Coverage file found: $($CoverageFile.FullName)" -ForegroundColor Green
        Write-Host "Parsing coverage data..." -ForegroundColor Cyan
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
