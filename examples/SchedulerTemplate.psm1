<#
.SYNOPSIS
    SchedulerTemplate.psm1 - Scheduling + Lock + Interval + Callback Runner
.DESCRIPTION
    Reusable PowerShell module for scheduled script execution with lock files,
    interval control, and credential management.
.VERSION
    1.0.2
.DATE
    2026-01-28
.NOTES
    - Provides Write-Log function with timestamp and level support
    - Provides Get-CredentialFromEnvVar for secure credential retrieval
    - Provides Test-UNCPath for UNC path validation
    - Provides Send-EmailNotification for SMTP email sending
    - Provides Invoke-ScheduledExecution for scheduled task management
#>

# Module Version (exported for external scripts to check version)
$script:ModuleVersion = "1.0.2"
$script:ModuleDate = "2026-01-28"

# Module load confirmation
Write-Verbose "SchedulerTemplate.psm1 v$ModuleVersion loaded ($ModuleDate)"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info',
        [switch]$Automated
    )

    $colors = @{
        'Info' = 'White'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
    }

    if ($Automated) {
        # Service logger adds timestamps, so only include level and message
        Write-Output "[$Level] $Message"
    }
    else {
        # Manual execution: include timestamp for better tracking
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
    }
}

function Get-CredentialFromEnvVar {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvVarName,
        [switch]$Automated
    )

    try {
        # Retrieve environment variable from Machine level
        $envVar = [System.Environment]::GetEnvironmentVariable($EnvVarName, "Machine")

        if (-not $envVar) {
            Write-Log "Environment variable '$EnvVarName' not found at Machine level!" -Level Error -Automated:$Automated
            return $null
        }

        # Decode Base64
        try {
            $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($envVar))
        }
        catch {
            Write-Log "Failed to decode '$EnvVarName' as Base64. Expected format: Base64('username:password')" -Level Error -Automated:$Automated
            return $null
        }

        # Split credentials
        $creds = $decoded -split ':', 2
        if ($creds.Count -ne 2) {
            Write-Log "Invalid credential format in '$EnvVarName'. Expected 'username:password'" -Level Error -Automated:$Automated
            return $null
        }

        return @{
            Username = $creds[0]
            Password = $creds[1]
        }
    }
    catch {
        Write-Log "Error retrieving credentials from '$EnvVarName': $_" -Level Error -Automated:$Automated
        return $null
    }
}

function Test-UNCPath {
    param([string]$Path)

    try {
        $uri = [System.Uri]$Path
        return $uri.IsUnc
    }
    catch {
        return $false
    }
}

function Get-CurrentUtcDateTime {
    param([string]$ExternalDateTime, [switch]$Automated)

    if ($ExternalDateTime) {
        try {
            return [datetime]::Parse($ExternalDateTime).ToUniversalTime()
        }
        catch {
            try {
                return [datetime]::ParseExact($ExternalDateTime, 'dd/MM/yyyy HH:mm:ss', $null).ToUniversalTime()
            }
            catch {
                Write-Log "Failed to parse CurrentDateTimeUtc ('$ExternalDateTime'). Using system time (UTC)." -Automated:$Automated -Level Error
                return (Get-Date).ToUniversalTime()
            }
        }
    }
    return (Get-Date).ToUniversalTime()
}

function Test-ScheduleMonth { param([datetime]$DateTime, [array]$Months)
    $name = $DateTime.ToString('MMMM')
    return ($Months.Count -eq 0) -or ($Months -contains $name)
}
function Test-ScheduleWeekday { param([datetime]$DateTime, [array]$Weekdays)
    $name = $DateTime.DayOfWeek.ToString()
    return ($Weekdays.Count -eq 0) -or ($Weekdays -contains $name)
}
function Test-ScheduleTime { param([datetime]$DateTime, [array]$Times)
    $t = $DateTime.ToString('HH:mm')
    return ($Times.Count -eq 0) -or ($Times -contains $t)
}

function Test-Schedule {
    param(
        [datetime]$DateTime,
        [array]$RunMonth,
        [array]$RunWeekday,
        [array]$RunTime
    )

    return (Test-ScheduleMonth -DateTime $DateTime -Months $RunMonth) -and
           (Test-ScheduleWeekday -DateTime $DateTime -Weekdays $RunWeekday) -and
           (Test-ScheduleTime -DateTime $DateTime -Times $RunTime)
}

function Test-Interval {
    param([datetime]$LastRun,[datetime]$Now,[int]$MinIntervalMinutes)
    return $Now -ge $LastRun.AddMinutes($MinIntervalMinutes)
}

function Test-ScheduledExecution {
    param(
        [switch]$Automated,
        [string]$CurrentDateTimeUtc,
        [hashtable]$Config,
        [string]$LastRunFilePath
    )

    $now = Get-CurrentUtcDateTime -ExternalDateTime $CurrentDateTimeUtc -Automated:$Automated
    $shouldRun = $true

    if ($Automated) {
        Write-Log "Automated: $Automated" -Automated:$Automated -Level Success
        Write-Log "Current UTC Time: $now" -Automated:$Automated -Level Success

        if (-not (Test-Schedule -DateTime $now -RunMonth $Config.RunMonth -RunWeekday $Config.RunWeekday -RunTime $Config.RunTime)) {
            Write-Log "Execution skipped due to schedule." -Automated:$Automated -Level Warning
            $shouldRun = $false
        }
    }

    if ($shouldRun -and $LastRunFilePath -and (Test-Path $LastRunFilePath)) {
        $lastRun = Get-Content $LastRunFilePath | Select-Object -First 1
        if ($lastRun) {
            [datetime]$lr = $lastRun
            if (-not (Test-Interval -LastRun $lr -Now $now -MinIntervalMinutes $Config.MinIntervalMinutes)) {
                Write-Log "Last run at $lr. Interval not reached." -Automated:$Automated -Level Warning
                $shouldRun = $false
            }
        }
    }

    return @{
        ShouldExecute = $shouldRun
        Now = $now
    }
}

function New-LockGuard {
    param([string]$LockFile,[switch]$Automated)

    if (Test-Path $LockFile) {
        Write-Log "Guard: Lock file exists ($LockFile). Skipping." -Automated:$Automated -Level Error
        return $false
    }
    try {
        New-Item -Path $LockFile -ItemType File -Force | Out-Null
        return $true
    }
    catch {
        Write-Log "Guard: Cannot create lock file ($LockFile)." -Automated:$Automated -Level Error
        return $false
    }
}

function Remove-LockGuard {
    param([string]$LockFile,[switch]$Automated)
    if (Test-Path $LockFile) {
        Remove-Item $LockFile -Force
        Write-Log "Lock removed: $LockFile" -Automated:$Automated -Level Info
    }
}

# ======================================================================
# Email Notification
# ======================================================================
function Send-EmailNotification {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$EmailSettings,
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $true)]
        [string]$Body,
        [switch]$Automated
    )

    # Validate required settings
    $required = @('smtpServer', 'smtpPort', 'from', 'to')
    foreach ($key in $required) {
        if (-not $EmailSettings.$key) {
            Write-Log "Email setting '$key' is required but missing" -Level Error -Automated:$Automated
            return $false
        }
    }

    try {
        $mailParams = @{
            SmtpServer = $EmailSettings.smtpServer
            Port = $EmailSettings.smtpPort
            From = $EmailSettings.from
            To = $EmailSettings.to
            Subject = $Subject
            Body = $Body
            BodyAsHtml = $false
        }

        # Add SSL if configured
        if ($EmailSettings.useSSL) {
            $mailParams['UseSsl'] = $true
        }

        # Add credentials if configured
        if ($EmailSettings.credentialEnvVar) {
            $creds = Get-CredentialFromEnvVar -EnvVarName $EmailSettings.credentialEnvVar -Automated:$Automated
            if ($creds) {
                $securePassword = ConvertTo-SecureString $creds.Password -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential($creds.Username, $securePassword)
                $mailParams['Credential'] = $credential
            }
            else {
                Write-Log "Failed to retrieve email credentials from '$($EmailSettings.credentialEnvVar)'" -Level Error -Automated:$Automated
                return $false
            }
        }

        Send-MailMessage @mailParams -ErrorAction Stop
        Write-Log "Email sent successfully to $($EmailSettings.to -join ', ')" -Level Success -Automated:$Automated
        return $true
    }
    catch {
        Write-Log "Failed to send email: $_" -Level Error -Automated:$Automated
        return $false
    }
}

# ======================================================================
# Main unified executor (callback-based)
# ======================================================================
function Invoke-ScheduledExecution {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$Config,
        [switch]$Automated,
        [string]$CurrentDateTimeUtc
    )

    # Get the calling script's path (not the module path)
    $scriptPath = (Get-PSCallStack)[1].ScriptName
    if (-not $scriptPath) {
        Write-Log "Unable to determine calling script path" -Level Error -Automated:$Automated
        return
    }

    $lastRunFile = [IO.Path]::ChangeExtension($scriptPath, ".lastRun")
    $lockFile    = [IO.Path]::ChangeExtension($scriptPath, ".lock")

    # Check schedule
    $schedule = Test-ScheduledExecution -Automated:$Automated -CurrentDateTimeUtc $CurrentDateTimeUtc -Config $Config -LastRunFilePath $lastRunFile
    if (-not $schedule.ShouldExecute) {
        Write-Log "Execution skipped." -Automated:$Automated -Level Warning
        return
    }

    # Lock
    if (-not (New-LockGuard -LockFile $lockFile -Automated:$Automated)) {
        return
    }

    try {
        $schedule.Now.ToString("o") | Set-Content $lastRunFile
        & $ScriptBlock
    }
    finally {
        Remove-LockGuard -LockFile $lockFile -Automated:$Automated
    }
}

Export-ModuleMember -Function * -Alias * -Variable ModuleVersion, ModuleDate
