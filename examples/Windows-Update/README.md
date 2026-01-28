# Windows Update Script

**Version:** 1.0.0
**Last Updated:** 2026-01-28

## Overview

Production-ready Windows Update automation solution using PowerShell and PSWindowsUpdate module. Supports scheduled updates, category filtering, exclusions, pre/post checks, and auto-reboot with maintenance window control.

## Features

- ✅ **PSWindowsUpdate Integration** - Uses reliable PSWindowsUpdate module
- ✅ **Multiple Categories** - Critical, Security, Definition, and more
- ✅ **Smart Exclusions** - Exclude by KB number or title patterns
- ✅ **Pre-flight Checks** - Disk space, pending reboot, service status
- ✅ **Reboot Control** - Optional automatic reboot with delay
- ✅ **Update Reports** - Generate post-installation reports with optional email notifications
- ✅ **Dry Run Mode** - Test update detection without installation
- ✅ **Detailed Logging** - Comprehensive logging with timestamps and severity levels
- ✅ **Lock Files** - Prevents concurrent execution
- ✅ **Flexible Scheduling** - Schedule updates by month, weekday, and time

## Requirements

### System Requirements
- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- Administrator privileges
- Internet access for Windows Update

### Dependencies
- `PSWindowsUpdate` module (auto-installed if missing)
- `SchedulerTemplate.psm1` module (located in parent directory)
- `scriptsettings.json` configuration file

## File Structure

```
Windows-Update/
├── windows-update.bat           # Batch launcher with admin check
├── windows-update.ps1           # Main PowerShell script
├── scriptsettings.json          # Configuration file
├── README.md                    # This file
└── Utilities/
    └── windows-update-policy.ps1  # Configure Windows Update behavior
```

## Installation

1. **Copy Files**
   ```powershell
   # Copy the entire Windows-Update folder to your desired location
   # Ensure SchedulerTemplate.psm1 is in the parent directory
   ```

2. **Configure Settings**

   Edit `scriptsettings.json` with your preferences:
   ```json
   {
     "schedule": {
       "runWeekday": ["Wednesday"],
       "runTime": ["02:00"]
     },
     "updateCategories": [
       "Critical Updates",
       "Security Updates"
     ]
   }
   ```

3. **Test Manual Execution**
   ```powershell
   # Run as Administrator
   .\windows-update.bat
   # or
   .\windows-update.ps1

   # Test with dry run first (set dryRun: true in scriptsettings.json)
   ```

## Configuration Reference

### Schedule Settings

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `runMonth` | array | Month names to run. Empty = every month | `["January", "July"]` or `[]` |
| `runWeekday` | array | Weekday names to run. Empty = every day | `["Wednesday"]` |
| `runTime` | array | UTC times to run (HH:mm format) | `["02:00", "14:00"]` |
| `minIntervalMinutes` | number | Minimum minutes between runs | `60` |

### Update Categories

Available categories to install:

| Category | Description |
|----------|-------------|
| `Critical Updates` | Critical security and stability updates |
| `Security Updates` | Security-focused updates |
| `Definition Updates` | Antivirus and malware definition updates |
| `Update Rollups` | Cumulative update packages |
| `Feature Packs` | New feature additions |
| `Service Packs` | Major cumulative updates |
| `Tools` | System tools and utilities |
| `Drivers` | Hardware driver updates |

**Example:**
```json
{
  "updateCategories": [
    "Critical Updates",
    "Security Updates",
    "Definition Updates"
  ]
}
```

### Exclusions

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `kbNumbers` | array | KB numbers to exclude | `["KB5034441", "KB5034123"]` |
| `titlePatterns` | array | Wildcard patterns to exclude | `["*Preview*", "*Beta*"]` |

**Pattern Syntax:**
- Use wildcards with `-like` operator (e.g., `*Preview*`, `*Optional*`)
- KB numbers should include the `KB` prefix

> **Note:** Filter matching uses PowerShell's `-like` operator. Test with `dryRun: true` first to verify expected behavior.

### Pre-Checks

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `minDiskSpaceGB` | number | `10` | Minimum free disk space in GB |
| `checkPendingReboot` | bool | `true` | Check for pending reboot before updates |

### Options

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `rebootBehavior` | string | `"manual"` | Reboot behavior: `"never"`, `"manual"`, or `"auto"` |
| `rebootDelayMinutes` | number | `5` | Minutes to wait before auto-reboot (when `rebootBehavior` is `"auto"`) |
| `dryRun` | bool | `false` | Simulate without installing updates |

**Reboot Behavior Values:**
| Value | Description |
|-------|-------------|
| `"never"` | Abort if system has pending reboot or updates require reboot |
| `"manual"` | Continue with updates, log that reboot is needed, user reboots later |
| `"auto"` | Automatically reboot after configured delay when updates require it |

### Reporting

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `generateReport` | bool | `true` | Generate text report after updates |
| `emailNotification` | bool | `false` | Send email notification after updates |
| `emailSettings` | object | - | SMTP configuration for email notifications |

**Email Settings:**
| Property | Type | Description |
|----------|------|-------------|
| `smtpServer` | string | SMTP server hostname |
| `smtpPort` | number | SMTP port (587 for TLS, 465 for SSL, 25 for plain) |
| `from` | string | Sender email address |
| `to` | array | Recipient email addresses |
| `useSSL` | bool | Use SSL/TLS for connection |
| `credentialEnvVar` | string | Machine-level env var with Base64(`username:password`). Empty for no auth. |

**Example:**
```json
{
  "reporting": {
    "generateReport": true,
    "emailNotification": true,
    "emailSettings": {
      "smtpServer": "smtp.office365.com",
      "smtpPort": 587,
      "from": "updates@example.com",
      "to": ["admin@example.com"],
      "useSSL": true,
      "credentialEnvVar": "SMTP_CREDENTIALS"
    }
  }
}
```

## Usage

### Manual Execution

**Using Batch File (Recommended):**
```batch
REM Right-click and select "Run as administrator"
windows-update.bat
```

**Using PowerShell:**
```powershell
# Run as Administrator
.\windows-update.ps1

# With verbose output
.\windows-update.ps1 -Verbose
```

### Automated Execution

The script supports automated execution through the UScheduler service:

```powershell
# Called by scheduler with -Automated flag
.\windows-update.ps1 -Automated -CurrentDateTimeUtc "2026-01-28 02:00:00"
```

When `-Automated` is specified:
- Schedule is enforced (month, weekday, time)
- Lock files prevent concurrent execution
- Interval checking prevents duplicate runs
- Logs are formatted for service logger (no timestamps)

## How It Works

### Update Process Flow

1. **Initialization**
   - Load SchedulerTemplate.psm1 module
   - Load and validate scriptsettings.json
   - Check/install PSWindowsUpdate module

2. **Pre-flight Checks**
   - Verify disk space availability
   - Check for pending reboot
   - Verify Windows Update service is running

3. **Scan Phase**
   - Query available updates from Windows Update
   - Filter by configured categories
   - Apply exclusions (KB numbers, title patterns)

4. **Installation Phase**
   - Display list of updates to install
   - Execute update installation
   - Track installation results (success/failure)
   - Monitor reboot requirements

5. **Post-Update Actions**
   - Handle reboot if required and configured
   - Generate update report

6. **Summary**
   - Display installation statistics
   - Report errors and warnings

### Reboot Behavior

| rebootBehavior | Behavior |
|----------------|----------|
| `"never"` | Abort if reboot pending/required |
| `"manual"` | Continue, log that reboot is needed |
| `"auto"` | Automatically reboot after delay |

### Progress Output

```
[INFO] ==========================================
[INFO] Windows Update Process Started
[INFO] Script Version: 1.0.0 (2026-01-28)
[INFO] ==========================================
[SUCCESS] PSWindowsUpdate module loaded
[INFO] Running pre-update checks...
[INFO] Free space on C: : 125.50 GB
[SUCCESS] Pre-update checks passed
[INFO] Scanning for available updates...
[INFO] Found 5 update(s) to install
[INFO] ========================================
[INFO]   [KB5034441] 2024-01 Cumulative Update (15234.50 KB)
[INFO]   [KB5034123] Security Intelligence Update (8765.25 KB)
[INFO] ========================================
[INFO] Installing updates...
[SUCCESS] Installed: 2024-01 Cumulative Update for Windows 11
[SUCCESS] Installed: Security Intelligence Update
```

### Update Summary

```
========================================
UPDATE SUMMARY
========================================
Start Time    : 2026-01-28 02:00:00
End Time      : 2026-01-28 02:15:32
Duration      : 0h 15m 32s
Status        : SUCCESS

Installed     : 5
Failed        : 0
Skipped       : 0
Reboot Needed : True
========================================
```

## Logging

### Log Levels

| Level | Description | Color (Manual) |
|-------|-------------|----------------|
| `Info` | Informational messages | White |
| `Success` | Successful operations | Green |
| `Warning` | Non-critical issues | Yellow |
| `Error` | Critical errors | Red |

### Log Format

**Manual Execution:**
```
[2026-01-28 02:00:00] [Info] Windows Update Process Started
[2026-01-28 02:15:32] [Success] Updates completed successfully
```

**Automated Execution:**
```
[Info] Windows Update Process Started
[Success] Updates completed successfully
```

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success (no errors) |
| `1` | Error occurred (config, checks, installation errors) |

## Troubleshooting

### Common Issues

**1. PSWindowsUpdate Module Not Found**
```
Error: Failed to import PSWindowsUpdate module
```
**Solution:**
```powershell
# Install manually
Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers
```

**2. Insufficient Permissions**
```
Error: This script must be run as Administrator
```
**Solution:** Right-click the batch file and select "Run as administrator"

**3. Insufficient Disk Space**
```
Error: Insufficient disk space. Required: 10 GB, Available: 8.5 GB
```
**Solution:**
- Free up disk space
- Reduce `minDiskSpaceGB` in configuration (not recommended)

**4. Windows Update Service Not Running**
```
Error: Failed to start Windows Update service
```
**Solution:**
```powershell
# Start service manually
Start-Service -Name wuauserv

# Check service status
Get-Service -Name wuauserv
```

**5. Updates Fail to Install**
```
Error: Failed: 2024-01 Cumulative Update
```
**Solution:**
- Check Windows Update logs: `C:\Windows\Logs\WindowsUpdate`
- Run Windows Update Troubleshooter
- Check for conflicting software (antivirus, etc.)
- Review exclusions - update might be excluded by pattern

**6. Lock File Exists**
```
Guard: Lock file exists. Skipping.
```
**Solution:**
- Another instance is running, or previous run didn't complete
- Manually delete `.lock` file if stuck
- Check for hung PowerShell processes

**7. Pending Reboot Blocks Updates**
```
Error: Reboot required but rebootBehavior is 'never'
```
**Solution:**
- Set `rebootBehavior: "manual"` or `"auto"` in configuration
- Manually reboot system before running updates

### Debug Mode

Run with verbose output:
```powershell
.\windows-update.ps1 -Verbose
```

Test without installing updates (set in scriptsettings.json):
```json
{
  "options": {
    "dryRun": true
  }
}
```

## Best Practices

1. **Test First** - Always test with `dryRun: true` before actual execution
2. **Schedule Wisely** - Run during maintenance windows (nights, weekends)
3. **Start Conservative** - Begin with Critical/Security updates only
4. **Monitor Results** - Review update reports and logs regularly
5. **Backup First** - Ensure system backups before major updates
6. **Reboot Testing** - Test `rebootBehavior: "auto"` in non-production environment first
7. **Exclusion Management** - Keep exclusions list minimal and documented
8. **Review Failures** - Investigate and resolve failed updates promptly

## Security Considerations

- Script requires **Administrator privileges** for update installation
- Updates are downloaded from **Microsoft Update** servers only
- Consider using **dedicated service account** for automated execution
- **Lock files** prevent concurrent execution and potential conflicts
- **Audit logs** maintain record of all update activities

## Performance Considerations

- **Update scanning** typically takes 1-5 minutes
- **Download speed** depends on update size and internet connection
- **Installation time** varies by update type (minutes to hours)
- **Reboot time** adds 2-10 minutes to total duration
- **Definition updates** are typically fast (<1 minute)
- **Feature updates** can take 30+ minutes

### Typical Update Times

| Update Type | Download | Install | Reboot |
|-------------|----------|---------|--------|
| Definition Updates | <1 min | <1 min | No |
| Security Updates | 2-5 min | 5-10 min | Sometimes |
| Cumulative Updates | 5-15 min | 10-30 min | Yes |
| Feature Updates | 15-60 min | 30-120 min | Yes |

## Version History

### 1.0.0 (2026-01-28)
- Initial release
- PSWindowsUpdate integration
- Category-based filtering
- KB number and title pattern exclusions
- Pre-flight checks (disk space, pending reboot, service)
- Auto-reboot with configurable delay
- Update report generation
- Dry run mode
- Integration with SchedulerTemplate.psm1

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review script logs for error details
3. Verify all [Requirements](#requirements) are met

## License

See [LICENSE](../../LICENSE.md) in the root directory.

## Utilities

### windows-update-policy.ps1

Located in `Utilities/`, this script configures Windows Update to use server-style manual updates (notify-only mode with no automatic reboots).

**Apply server-style policy:**
```powershell
.\Utilities\windows-update-policy.ps1
```

**Revert to Windows defaults:**
```powershell
.\Utilities\windows-update-policy.ps1 -Revert
```

**What it does:**
- Sets `AUOptions = 2` (notify for download and install)
- Disables automatic reboots with logged-on users
- Disables scheduled auto-reboot
- Disables automatic maintenance updates
- Uses Microsoft Update servers

This is useful when you want full control over when updates are downloaded, installed, and when the system reboots - particularly for workstations that should behave like servers.

## Related Files

- `../SchedulerTemplate.psm1` - Shared scheduling and logging module
- `scriptsettings.json` - Configuration file
- `windows-update.bat` - Batch launcher
- `windows-update.ps1` - Main script
- `Utilities/windows-update-policy.ps1` - Windows Update policy configuration
