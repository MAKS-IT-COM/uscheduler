#requires -Version 7.0
#requires -PSEdition Core

function Get-LogTimestampInternal {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

function Get-LogColorInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Level
    )

    switch ($Level.ToUpperInvariant()) {
        "OK" { return "Green" }
        "INFO" { return "Gray" }
        "WARN" { return "Yellow" }
        "ERROR" { return "Red" }
        "STEP" { return "Cyan" }
        "DEBUG" { return "DarkGray" }
        default { return "White" }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "OK", "WARN", "ERROR", "STEP", "DEBUG")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $false)]
        [switch]$NoTimestamp
    )

    $levelToken = "[$($Level.ToUpperInvariant())]"
    $padding = " " * [Math]::Max(1, (10 - $levelToken.Length))
    $prefix = if ($NoTimestamp) { "" } else { "[$(Get-LogTimestampInternal)] " }
    $line = "$prefix$levelToken$padding$Message"

    Write-Host $line -ForegroundColor (Get-LogColorInternal -Level $Level)
}

function Write-LogStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Log -Level "STEP" -Message $Message
}

function Write-LogStepResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("OK", "FAIL")]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    $level = if ($Status -eq "FAIL") { "ERROR" } else { "OK" }
    $text = if ([string]::IsNullOrWhiteSpace($Message)) { $Status } else { $Message }
    Write-Log -Level $level -Message $text
}

Export-ModuleMember -Function Write-Log, Write-LogStep, Write-LogStepResult
