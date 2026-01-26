@{
    RootModule = 'SchedulerTemplate.psm1'
    ModuleVersion = '1.0.1'
    GUID = 'a3b2c1d0-e4f5-6a7b-8c9d-0e1f2a3b4c5d'
    Author = 'MaksIT'
    CompanyName = 'MaksIT'
    Copyright = '(c) 2026 MaksIT. All rights reserved.'
    Description = 'Reusable PowerShell module for scheduled script execution with lock files, interval control, and credential management.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Write-Log',
        'Get-CredentialFromEnvVar',
        'Test-UNCPath',
        'Get-CurrentUtcDateTime',
        'Test-ScheduleMonth',
        'Test-ScheduleWeekday',
        'Test-ScheduleTime',
        'Test-Schedule',
        'Test-Interval',
        'Test-ScheduledExecution',
        'New-LockGuard',
        'Remove-LockGuard',
        'Invoke-ScheduledExecution'
    )
    CmdletsToExport = @()
    VariablesToExport = @('ModuleVersion', 'ModuleDate')
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Scheduler', 'Automation', 'Lock', 'Logging', 'Credentials')
            LicenseUri = ''
            ProjectUri = 'https://github.com/MaksIT/uscheduler'
            ReleaseNotes = @'
## 1.0.1 (2026-01-26)
- Improved UNC path validation (Test-UNCPath function)
- Enhanced credential management
- Comprehensive logging with timestamp support
- Scheduled execution with lock files and interval control
- Schedule validation (month, weekday, time)
- Write-Log function with severity levels and color support
- Get-CredentialFromEnvVar for secure Base64-encoded credential retrieval
- Invoke-ScheduledExecution for automated scheduled task management
'@
        }
    }
}
