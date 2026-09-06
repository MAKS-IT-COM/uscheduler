#requires -Version 7.0
#requires -PSEdition Core

<#
  Runs native CLIs (dotnet, git, helm, …) and keeps $LASTEXITCODE intact.
  By default throws on non-zero exit so callers cannot forget to check.
  Pass -ThrowOnError:$false when you need the exit code / output yourself
  (e.g. TestRunner Success objects, logging full container build output first).

  Test hooks: Set-ExternalCommandTestHandler / Set-ExternalCommandAvailability
  let Pester stub CLIs without touching PATH.
#>

$script:ExternalCommandTestHandler = $null
$script:ExternalCommandAvailability = @{}

function Set-ExternalCommandTestHandler {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Handler
    )

    $script:ExternalCommandTestHandler = $Handler
}

function Clear-ExternalCommandTestHandler {
    $script:ExternalCommandTestHandler = $null
}

function Set-ExternalCommandAvailability {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Availability
    )

    $script:ExternalCommandAvailability = @{}
    foreach ($key in $Availability.Keys) {
        $script:ExternalCommandAvailability[[string]$key] = [bool]$Availability[$key]
    }
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string[]]$ArgumentList = @(),

        [string]$WorkingDirectory,

        [string]$InputObject,

        [switch]$MergeErrorOutput,

        # Default true: fail fast. Soft callers (tests, nested loggers) pass $false.
        [bool]$ThrowOnError = $true
    )

    $previousLocation = $null
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $previousLocation = Get-Location
        Push-Location $WorkingDirectory
    }

    try {
        $effectiveWorkingDirectory = (Get-Location).Path
        $output = @()

        if ($null -ne $script:ExternalCommandTestHandler) {
            $handlerResult = & $script:ExternalCommandTestHandler `
                -Name $Name `
                -ArgumentList $ArgumentList `
                -WorkingDirectory $effectiveWorkingDirectory `
                -InputObject $InputObject `
                -MergeErrorOutput:$MergeErrorOutput.IsPresent

            $global:LASTEXITCODE = [int]$handlerResult.ExitCode
            if ($null -eq $handlerResult.Output) {
                $output = @()
            }
            elseif ($handlerResult.Output -is [System.Collections.IEnumerable] -and -not ($handlerResult.Output -is [string])) {
                $output = @($handlerResult.Output)
            }
            else {
                $output = @([string]$handlerResult.Output)
            }
        }
        else {
            if ($script:ExternalCommandAvailability.ContainsKey($Name) -and -not $script:ExternalCommandAvailability[$Name]) {
                throw "External command '$Name' is marked unavailable."
            }

            if (-not [string]::IsNullOrWhiteSpace($InputObject)) {
                $raw = $InputObject | & $Name @ArgumentList 2>&1
            }
            elseif ($MergeErrorOutput) {
                $raw = & $Name @ArgumentList 2>&1
            }
            else {
                $raw = & $Name @ArgumentList
            }

            $output = @($raw)
        }

        $exitCode = [int]$global:LASTEXITCODE
        if ($ThrowOnError -and $exitCode -ne 0) {
            $preview = ($output | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
                } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 12) -join ' '
            if ([string]::IsNullOrWhiteSpace($preview)) {
                throw "External command '$Name' failed with exit code $exitCode."
            }

            throw "External command '$Name' failed with exit code $exitCode. $preview"
        }

        return $output
    }
    finally {
        if ($null -ne $previousLocation) {
            Pop-Location
        }
    }
}

Export-ModuleMember -Function `
    Invoke-ExternalCommand, `
    Set-ExternalCommandTestHandler, `
    Clear-ExternalCommandTestHandler, `
    Set-ExternalCommandAvailability
