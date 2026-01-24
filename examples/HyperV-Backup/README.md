# Hyper-V Backup Script

**Version:** 1.0.0
**Last Updated:** 2026-01-24

## Overview

Production-ready automated backup solution for Hyper-V virtual machines with scheduling, checkpoints, retention management, and remote storage support.

## Features

- ✅ **Automated VM Backup** - Exports all VMs on the host using Hyper-V checkpoints
- ✅ **Flexible Scheduling** - Schedule backups by month, weekday, and time with interval control
- ✅ **Remote Storage Support** - Backup to UNC shares with secure credential management
- ✅ **Retention Management** - Automatically cleanup old backups based on retention count
- ✅ **Checkpoint Management** - Automatic cleanup of backup checkpoints
- ✅ **Space Validation** - Pre-flight checks for available disk space
- ✅ **VM Exclusion** - Exclude specific VMs from backup
- ✅ **Detailed Logging** - Comprehensive logging with timestamps and severity levels
- ✅ **Lock Files** - Prevents concurrent execution
- ✅ **Error Handling** - Proper exit codes and error reporting

## Requirements

### System Requirements
- Windows Server with Hyper-V role installed
- PowerShell 5.1 or later
- Administrator privileges
- Hyper-V PowerShell module

### Dependencies
- `SchedulerTemplate.psm1` module (located in parent directory)
- `scriptsettings.json` configuration file

## File Structure

```
HyperV-Backup/
├── hyper-v-backup.bat          # Batch launcher with admin check
├── hyper-v-backup.ps1          # Main PowerShell script
├── scriptsettings.json         # Configuration file
└── README.md                   # This file
```

## Installation

1. **Copy Files**
   ```powershell
   # Copy the entire HyperV-Backup folder to your desired location
   # Ensure SchedulerTemplate.psm1 is in the parent directory
   ```

2. **Configure Settings**

   Edit `scriptsettings.json` with your environment settings:
   ```json
   {
     "schedule": {
       "runMonth": [],
       "runWeekday": ["Monday"],
       "runTime": ["00:00"],
       "minIntervalMinutes": 10
     },
     "backupRoot": "\\\\your-nas\\backups",
     "credentialEnvVar": "YOUR_ENV_VAR_NAME",
     "tempExportRoot": "D:\\Temp\\HyperVExport",
     "retentionCount": 3,
     "minFreeSpaceGB": 100,
     "excludeVMs": ["vm-to-exclude"]
   }
   ```

3. **Setup Credentials (for UNC paths)**

   If backing up to a network share, create a Machine-level environment variable:
   ```powershell
   # Create Base64-encoded credentials
   $username = "DOMAIN\user"
   $password = "your-password"
   $creds = "$username:$password"
   $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($creds))

   # Set Machine-level environment variable
   [System.Environment]::SetEnvironmentVariable("YOUR_ENV_VAR_NAME", $encoded, "Machine")
   ```

4. **Test Manual Execution**
   ```powershell
   # Run as Administrator
   .\hyper-v-backup.bat
   # or
   .\hyper-v-backup.ps1
   ```

## Configuration Reference

### Schedule Settings

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `runMonth` | array | Month names to run. Empty = every month | `["January", "June", "December"]` or `[]` |
| `runWeekday` | array | Weekday names to run. Empty = every day | `["Monday", "Friday"]` |
| `runTime` | array | UTC times to run (HH:mm format) | `["00:00", "12:00"]` |
| `minIntervalMinutes` | number | Minimum minutes between runs | `10` |

### Backup Settings

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `backupRoot` | string | Yes | UNC or local path for backups. Hostname is appended automatically. |
| `credentialEnvVar` | string | No* | Name of Machine-level environment variable with credentials (*Required for UNC paths) |
| `tempExportRoot` | string | Yes | Local directory for temporary VM exports |
| `retentionCount` | number | Yes | Number of backup generations to keep (1-365) |
| `minFreeSpaceGB` | number | No | Minimum required free space in GB (0 = disable check) |
| `excludeVMs` | array | No | VM names to exclude from backup |

### Version Tracking

| Property | Type | Description |
|----------|------|-------------|
| `version` | string | Configuration schema version |
| `lastModified` | string | Last modification date (YYYY-MM-DD) |

## Usage

### Manual Execution

**Using Batch File (Recommended):**
```batch
REM Right-click and select "Run as administrator"
hyper-v-backup.bat
```

**Using PowerShell:**
```powershell
# Run as Administrator
.\hyper-v-backup.ps1

# With verbose output
.\hyper-v-backup.ps1 -Verbose
```

### Automated Execution

The script supports automated execution through the UScheduler service:

```powershell
# Called by scheduler with -Automated flag
.\hyper-v-backup.ps1 -Automated -CurrentDateTimeUtc "2026-01-24 00:00:00"
```

When `-Automated` is specified:
- Schedule is enforced (month, weekday, time)
- Lock files prevent concurrent execution
- Interval checking prevents duplicate runs
- Logs are formatted for service logger (no timestamps)

## How It Works

### Backup Process Flow

1. **Initialization**
   - Load SchedulerTemplate.psm1 module
   - Load and validate scriptsettings.json
   - Validate required settings
   - Set up backup paths

2. **Pre-flight Checks**
   - Verify Administrator privileges
   - Check Hyper-V module availability
   - Verify Hyper-V service is running
   - Check temp directory and free space
   - Authenticate to backup share (if UNC)
   - Create backup destination directory

3. **Backup Execution**
   - Retrieve all VMs on the host
   - Filter excluded VMs
   - For each VM:
     - Create checkpoint with timestamp
     - Export VM to temp location
     - Copy to final backup location
     - Cleanup temp export

4. **Cleanup**
   - Remove all backup checkpoints
   - Delete old backup folders beyond retention count

5. **Summary**
   - Display backup statistics
   - Report success/failure counts
   - List any errors encountered

### Directory Structure Created

```
\\backupRoot\Hyper-V\Backups\hostname\
├── 20260124000000\              # Backup folder (timestamp)
│   ├── VM-Name-1\
│   ├── VM-Name-2\
│   └── VM-Name-3\
├── 20260117000000\              # Previous backup
└── 20260110000000\              # Older backup (will be deleted if retentionCount=2)
```

### Lock and State Files

When running in automated mode, the script creates:
- `hyper-v-backup.lock` - Prevents concurrent execution
- `hyper-v-backup.lastRun` - Tracks last execution time for interval control

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
[2026-01-24 00:00:00] [Info] Hyper-V Backup Process Started
[2026-01-24 00:00:01] [Success] All prerequisites passed
[2026-01-24 00:05:30] [Success] Backup completed successfully for VM: server01
```

**Automated Execution:**
```
[Info] Hyper-V Backup Process Started
[Success] All prerequisites passed
[Success] Backup completed successfully for VM: server01
```

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success or no VMs found |
| `1` | Error occurred (module load, config, prerequisites, backup failure) |

## Troubleshooting

### Common Issues

**1. Module Not Found**
```
Error: Failed to load SchedulerTemplate.psm1
```
**Solution:** Ensure SchedulerTemplate.psm1 is in the parent directory (`../SchedulerTemplate.psm1`)

**2. UNC Path Authentication Failed**
```
Error: Failed to connect to \\server\share
```
**Solution:**
- Verify `credentialEnvVar` is set in scriptsettings.json
- Verify environment variable exists at Machine level
- Verify credentials are Base64-encoded in format: `username:password`
- Test with: `net use \\server\share` manually

**3. Insufficient Space**
```
Error: Insufficient free space on drive D:
```
**Solution:**
- Free up space on temp drive
- Reduce `minFreeSpaceGB` setting (not recommended)
- Use different temp location

**4. Lock File Exists**
```
Guard: Lock file exists. Skipping.
```
**Solution:**
- Another instance is running, or previous run didn't complete
- Manually delete `.lock` file if stuck
- Check for hung PowerShell processes

**5. Checkpoint Creation Failed**
```
Error: Failed to create checkpoint for VM
```
**Solution:**
- Verify VM is in a valid state
- Check Hyper-V event logs
- Ensure sufficient disk space for checkpoints

### Debug Mode

Run with verbose output:
```powershell
.\hyper-v-backup.ps1 -Verbose
```

## Best Practices

1. **Test First** - Always test backups manually before scheduling
2. **Monitor Space** - Ensure adequate space on both temp and backup locations
3. **Verify Backups** - Periodically test restore from backups
4. **Secure Credentials** - Use Machine-level environment variables, never store passwords in scripts
5. **Schedule Wisely** - Run backups during low-usage periods
6. **Review Logs** - Check backup summaries regularly
7. **Update Retention** - Adjust `retentionCount` based on storage capacity
8. **Exclude Carefully** - Only exclude VMs that don't need backup

## Security Considerations

- **Credentials** are stored Base64-encoded in Machine-level environment variables (not encryption, just encoding)
- Script requires **Administrator privileges**
- **Network credentials** are passed to `net use` command
- Consider using **dedicated backup account** with minimal required permissions
- **Backup data** should be stored on secured network shares with appropriate ACLs

## Performance Considerations

- **Export time** depends on VM size and disk I/O performance
- **Temp location** should be on fast local storage (SSD recommended)
- **Network speed** affects copy time to remote shares
- **Checkpoints** consume disk space temporarily
- Multiple VMs are processed **sequentially** (not parallel)

## Version History

### 1.0.0 (2026-01-24)
- Initial production release
- Automated backup with scheduling
- Checkpoint-based export
- Retention management
- UNC share support with credential management
- Lock file and interval control
- Comprehensive error handling and logging

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review script logs for error details
3. Verify all [Requirements](#requirements) are met
4. Check Hyper-V event logs for VM-related issues

## License

See [LICENSE](../../LICENSE.md) in the root directory.

## Related Files

- `../SchedulerTemplate.psm1` - Shared scheduling and logging module
- `scriptsettings.json` - Configuration file
- `hyper-v-backup.bat` - Batch launcher
- `hyper-v-backup.ps1` - Main script
