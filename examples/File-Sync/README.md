# File Sync Script

**Version:** 1.0.0
**Last Updated:** 2026-01-24

## Overview

Production-ready automated file synchronization solution using FreeFileSync with scheduling, secure credential management, and remote storage support.

## Features

- ✅ **Automated File Sync** - Executes FreeFileSync batch jobs on schedule
- ✅ **Flexible Scheduling** - Schedule sync by month, weekday, and time with interval control
- ✅ **Remote Storage Support** - Sync to UNC shares with secure credential management
- ✅ **Prerequisite Validation** - Checks FreeFileSync installation before execution
- ✅ **Process Management** - Proper cleanup of FreeFileSync process on exit
- ✅ **Detailed Logging** - Comprehensive logging with timestamps and severity levels
- ✅ **Lock Files** - Prevents concurrent execution
- ✅ **Error Handling** - Proper exit codes and error reporting

## Requirements

### System Requirements
- Windows with PowerShell 5.1 or later
- FreeFileSync installed (free download from https://freefilesync.org/)
- Network access to target share (if using UNC paths)

### Dependencies
- `SchedulerTemplate.psm1` module (located in parent directory)
- `scriptsettings.json` configuration file
- `sync.ffs_batch` FreeFileSync batch configuration file

## File Structure

```
File-Sync/
├── file-sync.bat              # Batch launcher with admin check
├── file-sync.ps1              # Main PowerShell script
├── scriptsettings.json        # Configuration file
├── sync.ffs_batch             # FreeFileSync batch configuration
└── README.md                  # This file
```

## Installation

1. **Install FreeFileSync**

   Download and install from https://freefilesync.org/

   Default installation path: `C:\Program Files\FreeFileSync\FreeFileSync.exe`

2. **Copy Files**
   ```powershell
   # Copy the entire File-Sync folder to your desired location
   # Ensure SchedulerTemplate.psm1 is in the parent directory
   ```

3. **Create FreeFileSync Batch Configuration**

   Use FreeFileSync GUI to:
   - Configure source and destination folders
   - Set synchronization settings (Mirror, Two-way, Update, etc.)
   - Save as batch job: `sync.ffs_batch` in the File-Sync directory

4. **Configure Settings**

   Edit `scriptsettings.json` with your environment settings:
   ```json
   {
     "schedule": {
       "runMonth": [],
       "runWeekday": ["Monday"],
       "runTime": ["00:00"],
       "minIntervalMinutes": 10
     },
     "freeFileSyncExe": "C:\\Program Files\\FreeFileSync\\FreeFileSync.exe",
     "batchFile": "sync.ffs_batch",
     "nasRootShare": "\\\\your-nas\\share",
     "credentialEnvVar": "YOUR_ENV_VAR_NAME"
   }
   ```

5. **Setup Credentials (for UNC paths)**

   If syncing to a network share, create a Machine-level environment variable:
   ```powershell
   # Create Base64-encoded credentials
   $username = "DOMAIN\user"
   $password = "your-password"
   $creds = "$username:$password"
   $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($creds))

   # Set Machine-level environment variable
   [System.Environment]::SetEnvironmentVariable("YOUR_ENV_VAR_NAME", $encoded, "Machine")
   ```

6. **Test Manual Execution**
   ```powershell
   # Run as Administrator
   .\file-sync.bat
   # or
   .\file-sync.ps1
   ```

## Configuration Reference

### Schedule Settings

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `runMonth` | array | Month names to run. Empty = every month | `["January", "June", "December"]` or `[]` |
| `runWeekday` | array | Weekday names to run. Empty = every day | `["Monday", "Friday"]` |
| `runTime` | array | UTC times to run (HH:mm format) | `["00:00", "12:00"]` |
| `minIntervalMinutes` | number | Minimum minutes between runs | `10` |

### Sync Settings

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `freeFileSyncExe` | string | Yes | Full path to FreeFileSync.exe executable |
| `batchFile` | string | Yes | FreeFileSync batch file name (must be in same directory). Configure all sync paths directly in this file. |
| `nasRootShare` | string | Yes | UNC path to NAS root share for authentication only |
| `credentialEnvVar` | string | No* | Name of Machine-level environment variable with credentials (*Required for UNC paths) |

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
file-sync.bat
```

**Using PowerShell:**
```powershell
# Run as Administrator
.\file-sync.ps1

# With verbose output
.\file-sync.ps1 -Verbose
```

### Automated Execution

The script supports automated execution through the UScheduler service:

```powershell
# Called by scheduler with -Automated flag
.\file-sync.ps1 -Automated -CurrentDateTimeUtc "2026-01-24 00:00:00"
```

When `-Automated` is specified:
- Schedule is enforced (month, weekday, time)
- Lock files prevent concurrent execution
- Interval checking prevents duplicate runs
- Logs are formatted for service logger (no timestamps)

## How It Works

### Sync Process Flow

1. **Initialization**
   - Load SchedulerTemplate.psm1 module
   - Load and validate scriptsettings.json
   - Validate required settings
   - Construct batch file path

2. **Pre-flight Checks**
   - Verify FreeFileSync executable exists
   - Check FreeFileSync version
   - Verify batch configuration file exists
   - Authenticate to NAS share (if UNC)
   - Verify NAS reachability

3. **Sync Execution**
   - Launch FreeFileSync in silent mode
   - Capture stdout and stderr
   - Monitor process completion
   - Interpret exit code

4. **Cleanup**
   - Terminate FreeFileSync if script exits
   - Display sync summary

### FreeFileSync Exit Codes

| Code | Meaning | Script Action |
|------|---------|---------------|
| 0 | Success | Mark as successful, exit 0 |
| 1 | Warning (sync completed with warnings) | Mark as successful, exit 0 |
| 2 | Error | Mark as failed, exit 1 |
| 3 | Cancelled | Mark as failed, exit 1 |

### Lock and State Files

When running in automated mode, the script creates:
- `file-sync.lock` - Prevents concurrent execution
- `file-sync.lastRun` - Tracks last execution time for interval control

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
[2026-01-24 00:00:00] [Info] FreeFileSync Process Started
[2026-01-24 00:00:01] [Success] All prerequisites passed
[2026-01-24 00:05:30] [Success] FreeFileSync completed successfully
```

**Automated Execution:**
```
[Info] FreeFileSync Process Started
[Success] All prerequisites passed
[Success] FreeFileSync completed successfully
```

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success (including warnings) |
| `1` | Error occurred (module load, config, prerequisites, sync failure) |

## Troubleshooting

### Common Issues

**1. Module Not Found**
```
Error: Failed to load SchedulerTemplate.psm1
```
**Solution:** Ensure SchedulerTemplate.psm1 is in the parent directory (`../SchedulerTemplate.psm1`)

**2. FreeFileSync Not Found**
```
Error: FreeFileSync not found: C:\Program Files\FreeFileSync\FreeFileSync.exe
```
**Solution:**
- Install FreeFileSync from https://freefilesync.org/
- Update `freeFileSyncExe` path in scriptsettings.json if installed to custom location

**3. Batch File Not Found**
```
Error: Batch config not found
```
**Solution:**
- Create FreeFileSync batch configuration using FreeFileSync GUI
- Save as `sync.ffs_batch` in the File-Sync directory
- Update `batchFile` setting if using different name

**4. UNC Path Authentication Failed**
```
Error: Failed to connect to \\server\share
```
**Solution:**
- Verify `credentialEnvVar` is set in scriptsettings.json
- Verify environment variable exists at Machine level
- Verify credentials are Base64-encoded in format: `username:password`
- Test with: `net use \\server\share` manually

**5. Lock File Exists**
```
Guard: Lock file exists. Skipping.
```
**Solution:**
- Another instance is running, or previous run didn't complete
- Manually delete `.lock` file if stuck
- Check for hung PowerShell or FreeFileSync processes

**6. FreeFileSync Errors**
```
Error: FreeFileSync completed with errors (exit code 2)
```
**Solution:**
- Check FreeFileSync output in logs
- Verify source and destination paths are accessible
- Review FreeFileSync batch configuration
- Check file/folder permissions

### Debug Mode

Run with verbose output:
```powershell
.\file-sync.ps1 -Verbose
```

## Best Practices

1. **Test First** - Always test sync manually before scheduling
2. **Backup First** - Ensure you have backups before first sync
3. **Verify Paths** - Double-check source and destination paths in batch file
4. **Monitor Logs** - Check sync summaries regularly
5. **Secure Credentials** - Use Machine-level environment variables, never store passwords in scripts
6. **Schedule Wisely** - Run syncs during low-usage periods
7. **Review Settings** - Understand FreeFileSync sync mode (Mirror, Two-way, Update)
8. **Test Restores** - Periodically verify you can restore from synced data

## FreeFileSync Configuration

### Creating Batch Configuration

1. Launch FreeFileSync GUI
2. Configure left (source) and right (target) folders
3. Set comparison settings (File time and size, Content, File size)
4. Set filter rules (include/exclude patterns)
5. Choose sync variant:
   - **Mirror**: Make right folder identical to left
   - **Update**: Copy new/updated files to right
   - **Two-way**: Propagate changes both ways
   - **Custom**: Define custom rules
6. Click "Save as batch job"
7. Save as `sync.ffs_batch` in File-Sync directory

**Note:** All source and destination paths are configured directly in the FreeFileSync batch file. The script does not modify these paths - it only handles authentication to network shares before FreeFileSync executes.

## Security Considerations

- **Credentials** are stored Base64-encoded in Machine-level environment variables (not encryption, just encoding)
- Script requires **Administrator privileges** for network authentication
- **Network credentials** are passed to `net use` command
- Consider using **dedicated sync account** with minimal required permissions
- **Sync data** should be stored on secured network shares with appropriate ACLs
- **FreeFileSync** runs in silent mode without user interaction

## Performance Considerations

- **Sync time** depends on file count, size, and network speed
- **Network speed** is typically the bottleneck for UNC shares
- **FreeFileSync** is optimized for incremental syncs
- Use **filter rules** to exclude temporary/unnecessary files
- Consider **bandwidth throttling** in FreeFileSync settings for large syncs
- Run during **off-peak hours** to minimize network impact

## Version History

### 1.0.0 (2026-01-24)
- Initial production release
- Automated sync with scheduling
- FreeFileSync batch execution
- UNC share support with credential management
- Lock file and interval control
- Comprehensive error handling and logging
- Dynamic batch file path updates
- Prerequisite validation

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review script logs for error details
3. Verify all [Requirements](#requirements) are met
4. Check FreeFileSync documentation at https://freefilesync.org/manual.php

## License

See [LICENSE](../../LICENSE.md) in the root directory.

## Related Files

- `../SchedulerTemplate.psm1` - Shared scheduling and logging module
- `scriptsettings.json` - Configuration file
- `file-sync.bat` - Batch launcher
- `file-sync.ps1` - Main script
- `sync.ffs_batch` - FreeFileSync batch configuration

## Additional Resources

- **FreeFileSync Official Site:** https://freefilesync.org/
- **FreeFileSync Manual:** https://freefilesync.org/manual.php
- **FreeFileSync Forum:** https://freefilesync.org/forum/
