[CmdletBinding()]
param (
    [switch]$Revert
)

#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configure Windows Update to Server 2025-style manual updates.
.DESCRIPTION
    Sets Windows Update behavior to notify-only mode with no automatic reboots.
    This gives you full control over when updates are downloaded, installed, and rebooted.
.PARAMETER Revert
    Remove the policy settings and restore Windows defaults.
.EXAMPLE
    .\windows-update-policy.ps1
    Apply server-style update policy.
.EXAMPLE
    .\windows-update-policy.ps1 -Revert
    Remove policy and restore defaults.
.VERSION
    1.0.0
.DATE
    2026-01-28
.NOTES
    - Requires Administrator privileges
    - Changes take effect after gpupdate or reboot
#>

# Registry paths
$WUBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$WU_AU = Join-Path $WUBase 'AU'

# Helper Functions =========================================================

function Set-ServerStyleUpdates {
    Write-Host "[INFO] Applying server-style Windows Update policy..." -ForegroundColor Cyan

    # Create policy keys
    New-Item -Path $WUBase -Force | Out-Null
    New-Item -Path $WU_AU -Force | Out-Null

    # AUOptions = 2: Notify for download and notify for install
    New-ItemProperty -Path $WU_AU -Name 'AUOptions' -PropertyType DWord -Value 2 -Force | Out-Null
    Write-Host "  - AUOptions = 2 (Notify for download and install)" -ForegroundColor Gray

    # Do not auto reboot with logged-on users
    New-ItemProperty -Path $WU_AU -Name 'NoAutoRebootWithLoggedOnUsers' -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Host "  - NoAutoRebootWithLoggedOnUsers = 1" -ForegroundColor Gray

    # Prevent any scheduled auto reboot
    New-ItemProperty -Path $WU_AU -Name 'AlwaysAutoRebootAtScheduledTime' -PropertyType DWord -Value 0 -Force | Out-Null
    Write-Host "  - AlwaysAutoRebootAtScheduledTime = 0" -ForegroundColor Gray

    # Disable automatic maintenance updates
    New-ItemProperty -Path $WU_AU -Name 'AutomaticMaintenanceEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
    Write-Host "  - AutomaticMaintenanceEnabled = 0" -ForegroundColor Gray

    # Disable auto restart reminders
    New-ItemProperty -Path $WU_AU -Name 'RebootWarningTimeoutEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $WU_AU -Name 'RebootRelaunchTimeoutEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
    Write-Host "  - RebootWarningTimeoutEnabled = 0" -ForegroundColor Gray
    Write-Host "  - RebootRelaunchTimeoutEnabled = 0" -ForegroundColor Gray

    # Set empty WUServer/WUStatusServer (use Microsoft Update)
    New-ItemProperty -Path $WUBase -Name 'WUServer' -PropertyType String -Value '' -Force | Out-Null
    New-ItemProperty -Path $WUBase -Name 'WUStatusServer' -PropertyType String -Value '' -Force | Out-Null
    Write-Host "  - WUServer/WUStatusServer = '' (Microsoft Update)" -ForegroundColor Gray

    Write-Host "[SUCCESS] Server-style Windows Update policy applied." -ForegroundColor Green
}

function Remove-ServerStyleUpdates {
    Write-Host "[INFO] Removing server-style Windows Update policy..." -ForegroundColor Cyan

    # Remove WUBase properties
    foreach ($name in @('WUServer', 'WUStatusServer')) {
        Remove-ItemProperty -Path $WUBase -Name $name -ErrorAction SilentlyContinue
    }

    # Remove AU properties
    foreach ($name in @(
        'AUOptions',
        'NoAutoRebootWithLoggedOnUsers',
        'AlwaysAutoRebootAtScheduledTime',
        'AutomaticMaintenanceEnabled',
        'RebootWarningTimeoutEnabled',
        'RebootRelaunchTimeoutEnabled'
    )) {
        Remove-ItemProperty -Path $WU_AU -Name $name -ErrorAction SilentlyContinue
    }

    # Clean up empty keys
    try {
        $auProps = Get-ItemProperty -Path $WU_AU -ErrorAction SilentlyContinue
        if ($auProps) {
            $members = $auProps | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notlike 'PS*' }
            if (-not $members) {
                Remove-Item $WU_AU -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch { }

    Write-Host "[SUCCESS] Server-style Windows Update policy removed." -ForegroundColor Green
}

function Invoke-PolicyRefresh {
    Write-Host "[INFO] Refreshing group policy..." -ForegroundColor Cyan

    try {
        gpupdate /force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SUCCESS] Group policy refreshed." -ForegroundColor Green
        }
        else {
            throw "gpupdate returned exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "[WARNING] gpupdate failed. Restarting Windows Update service..." -ForegroundColor Yellow
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Write-Host "[INFO] Windows Update service restarted." -ForegroundColor Cyan
    }
}

# Main =====================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Windows Update Policy Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($Revert) {
    Remove-ServerStyleUpdates
    Write-Host ""
    Invoke-PolicyRefresh
    Write-Host ""
    Write-Host "[INFO] Windows Update will now use default behavior." -ForegroundColor Cyan
    Write-Host "[INFO] You may need to reboot for all changes to take effect." -ForegroundColor Yellow
}
else {
    Set-ServerStyleUpdates
    Write-Host ""
    Invoke-PolicyRefresh
    Write-Host ""
    Write-Host "[INFO] Windows Update is now configured for manual control:" -ForegroundColor Cyan
    Write-Host "  - Updates will notify but not auto-download" -ForegroundColor Gray
    Write-Host "  - No automatic reboots will occur" -ForegroundColor Gray
    Write-Host "  - Use windows-update.ps1 to manually install updates" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] You may need to reboot for all changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
