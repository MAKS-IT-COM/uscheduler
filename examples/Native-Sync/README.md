# Native PowerShell Sync Script

**Version:** 1.0.0
**Last Updated:** 2026-01-26

## Overview

Production-ready file synchronization solution using pure PowerShell with no external dependencies. Supports Mirror, Update, and TwoWay sync modes with filtering, progress reporting, and secure credential management.

## Features

- ✅ **No External Dependencies** - Pure PowerShell implementation
- ✅ **Multiple Sync Modes** - Mirror, Update, and TwoWay synchronization
- ✅ **Flexible Comparison** - Compare by modification time and file size
- ✅ **Deletion Policies** - Recycle Bin, Permanent delete, or Versioning
- ✅ **Filter Support** - Include/exclude patterns for files and folders
- ✅ **Remote Storage Support** - Sync to UNC shares with secure credential management
- ✅ **Progress Reporting** - File-by-file progress output
- ✅ **Dry Run Mode** - Test sync without making changes
- ✅ **Detailed Logging** - Comprehensive logging with timestamps and severity levels
- ✅ **Lock Files** - Prevents concurrent execution
- ✅ **Flexible Scheduling** - Schedule sync by month, weekday, and time

## Requirements

### System Requirements
- Windows with PowerShell 5.1 or later
- Administrator privileges (for network share authentication)
- Network access to target share (if using UNC paths)

### Dependencies
- `SchedulerTemplate.psm1` module (located in parent directory)
- `scriptsettings.json` configuration file

## File Structure

```
Native-Sync/
├── native-sync.bat              # Batch launcher with admin check
├── native-sync.ps1              # Main PowerShell script
├── scriptsettings.json          # Configuration file
└── README.md                    # This file
```

## Installation

1. **Copy Files**
   ```powershell
   # Copy the entire Native-Sync folder to your desired location
   # Ensure SchedulerTemplate.psm1 is in the parent directory
   ```

2. **Configure Settings**

   Edit `scriptsettings.json` with your environment settings:
   ```json
   {
     "syncMode": "Mirror",
     "folderPairs": [
       {
         "left": "C:\\Source",
         "right": "D:\\Backup"
       }
     ]
   }
   ```

3. **Setup Credentials (for UNC paths)**

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

4. **Test Manual Execution**
   ```powershell
   # Run as Administrator
   .\native-sync.bat
   # or
   .\native-sync.ps1

   # Test with dry run first (set dryRun: true in scriptsettings.json)
   ```

## Configuration Reference

### Sync Modes

| Mode | Description | LeftOnly | LeftNewer | RightNewer | RightOnly |
|------|-------------|----------|-----------|------------|-----------|
| `Mirror` | Make right identical to left | Copy to right | Update right | Update right | Delete from right |
| `Update` | Copy new/updated to right only | Copy to right | Update right | Skip | Skip |
| `TwoWay` | Propagate changes both ways | Copy to right | Update right | Update left | Copy to left |

### Schedule Settings

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `runMonth` | array | Month names to run. Empty = every month | `["January", "June"]` or `[]` |
| `runWeekday` | array | Weekday names to run. Empty = every day | `["Monday", "Friday"]` |
| `runTime` | array | UTC times to run (HH:mm format) | `["00:00", "12:00"]` |
| `minIntervalMinutes` | number | Minimum minutes between runs | `10` |

### Sync Settings

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `syncMode` | string | Yes | Sync mode: `Mirror`, `Update`, or `TwoWay` |
| `compareMethod` | string | No | Comparison method: `TimeAndSize` (default) |
| `deletionPolicy` | string | No | Deletion handling: `RecycleBin` (default), `Permanent`, `Versioning` |
| `versioningFolder` | string | No | Path for versioning when deletionPolicy is `Versioning` |
| `folderPairs` | array | Yes | Array of `{left, right}` folder pairs to sync |

### Filter Settings

| Property | Type | Description |
|----------|------|-------------|
| `filters.include` | array | Patterns to include (use `["*"]` for all) |
| `filters.exclude` | array | Patterns to exclude |

**Pattern Syntax:**
- Directory patterns end with `\` (e.g., `\System Volume Information\`)
- File patterns use wildcards (e.g., `*.tmp`, `thumbs.db`)
- Prefix with `*\` to match in any subdirectory (e.g., `*\thumbs.db`)

**Default Excludes:**
- `\System Volume Information\`
- `\$Recycle.Bin\`
- `\RECYCLE?\`
- `\Recovery\`
- `*\thumbs.db`

> **Note:** Filter matching uses PowerShell's `-like` operator. For complex filtering needs, test with `dryRun: true` first to verify expected behavior.

### Options

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `excludeSymlinks` | bool | `true` | Skip symbolic links |
| `ignoreTimeShift` | bool | `false` | Ignore 1-hour DST time differences |
| `showProgress` | bool | `true` | Display file-by-file progress |
| `dryRun` | bool | `false` | Simulate sync without changes |

### Network Settings

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `nasRootShare` | string | No | UNC path for authentication |
| `credentialEnvVar` | string | No* | Environment variable name (*Required for UNC paths) |

## Usage

### Manual Execution

**Using Batch File (Recommended):**
```batch
REM Right-click and select "Run as administrator"
native-sync.bat
```

**Using PowerShell:**
```powershell
# Run as Administrator
.\native-sync.ps1

# With verbose output
.\native-sync.ps1 -Verbose
```

### Automated Execution

The script supports automated execution through the UScheduler service:

```powershell
# Called by scheduler with -Automated flag
.\native-sync.ps1 -Automated -CurrentDateTimeUtc "2026-01-26 00:00:00"
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
   - Parse sync mode, filters, and options

2. **Pre-flight Checks**
   - Authenticate to NAS share (if UNC)
   - Verify source paths exist
   - Create destination directories if needed

3. **Scan Phase**
   - Recursively scan source directory
   - Recursively scan destination directory
   - Apply include/exclude filters
   - Skip symlinks if configured

4. **Comparison Phase**
   - Compare files by modification time and size
   - Determine file status: Same, LeftOnly, LeftNewer, RightNewer, RightOnly
   - Build list of sync actions based on sync mode

5. **Execution Phase**
   - Sort actions: copies → updates → file deletes → directory deletes
   - Execute each action with progress reporting
   - Handle deletion policy (RecycleBin, Permanent, Versioning)

6. **Summary**
   - Display sync statistics
   - Report errors and warnings

### Deletion Policies

| Policy | Description |
|--------|-------------|
| `RecycleBin` | Move deleted files to Windows Recycle Bin (recoverable) |
| `Permanent` | Delete files permanently (not recoverable) |
| `Versioning` | Move deleted files to versioning folder |

### Progress Output

```
[INFO] Processing Folder Pair 1
[INFO]   Left:  E:\Users\maksym\source
[INFO]   Right: \\server\share\source
[INFO] Scanning source directory...
[INFO]   Found 1234 files, 56 directories
[INFO] Scanning destination directory...
[INFO]   Found 1200 files, 54 directories
[INFO] Calculating sync actions...
[INFO]   45 actions to perform
[INFO] Executing sync actions...
[INFO] [COPY] docs/newfile.txt (15.2 KB)
[INFO] [UPDATE] src/main.cs (8.5 KB)
[WARNING] [DELETE] old/removed.txt (1.2 KB)
```

### Sync Summary

```
========================================
SYNC SUMMARY
========================================
Start Time    : 2026-01-26 00:00:00
End Time      : 2026-01-26 00:05:30
Duration      : 0h 5m 30s
Status        : SUCCESS

Files Scanned : 1,234
Files Copied  : 45
Files Updated : 12
Files Deleted : 3
Files Skipped : 1,174
Bytes Copied  : 156.7 MB

Errors        : 0
Warnings      : 3
========================================
```

## Logging

### Log Levels

| Level | Description | Color (Manual) |
|-------|-------------|----------------|
| `Info` | Informational messages | White |
| `Success` | Successful operations | Green |
| `Warning` | Non-critical issues (deletions) | Yellow |
| `Error` | Critical errors | Red |

### Log Format

**Manual Execution:**
```
[2026-01-26 00:00:00] [Info] Native PowerShell Sync Started
[2026-01-26 00:00:01] [Success] All files synchronized
```

**Automated Execution:**
```
[Info] Native PowerShell Sync Started
[Success] All files synchronized
```

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success (no errors) |
| `1` | Error occurred (config, paths, sync errors) |

## Troubleshooting

### Common Issues

**1. Module Not Found**
```
Error: Failed to load SchedulerTemplate.psm1
```
**Solution:** Ensure SchedulerTemplate.psm1 is in the parent directory (`../SchedulerTemplate.psm1`)

**2. Source Path Not Found**
```
Error: Source path does not exist
```
**Solution:** Verify the `left` path in folderPairs exists and is accessible

**3. UNC Path Authentication Failed**
```
Error: Failed to connect to \\server\share
```
**Solution:**
- Verify `credentialEnvVar` is set in scriptsettings.json
- Verify environment variable exists at Machine level
- Verify credentials are Base64-encoded in format: `username:password`
- Test with: `net use \\server\share` manually

**4. Lock File Exists**
```
Guard: Lock file exists. Skipping.
```
**Solution:**
- Another instance is running, or previous run didn't complete
- Manually delete `.lock` file if stuck
- Check for hung PowerShell processes

**5. Permission Denied**
```
Error: Access to the path is denied
```
**Solution:**
- Run as Administrator
- Verify file/folder permissions
- Check if files are locked by other processes

### Debug Mode

Run with verbose output:
```powershell
.\native-sync.ps1 -Verbose
```

Test with dry run (set in scriptsettings.json):
```json
{
  "options": {
    "dryRun": true
  }
}
```

## Best Practices

1. **Test First** - Always test sync with `dryRun: true` in settings before actual execution
2. **Backup First** - Ensure you have backups before first sync
3. **Verify Paths** - Double-check source and destination paths
4. **Monitor Logs** - Check sync summaries regularly
5. **Secure Credentials** - Use Machine-level environment variables
6. **Schedule Wisely** - Run syncs during low-usage periods
7. **Review Settings** - Understand your sync mode implications
8. **Test Restores** - Periodically verify you can restore from synced data

## Security Considerations

- **Credentials** are stored Base64-encoded in Machine-level environment variables
- Script requires **Administrator privileges** for network authentication
- **Network credentials** are passed to `net use` command
- Consider using **dedicated sync account** with minimal required permissions
- **Sync data** should be stored on secured network shares with appropriate ACLs

## Performance Considerations

- **Sync time** depends on file count, size, and network speed
- **Network speed** is typically the bottleneck for UNC shares
- **File scanning** can take time for large directories
- Use **filter rules** to exclude unnecessary files
- **Memory usage** increases with file count during scanning
- Run during **off-peak hours** to minimize network impact

### Scalability Limitations

This script performs full directory scans into in-memory hashtables before comparing files. This design means:

- **High memory usage** on very large directory trees (millions of files)
- **No streaming or batching** - all file metadata is loaded before sync begins
- **Recommended limit** - works well for typical backup scenarios (tens of thousands of files)

Future versions may introduce streaming/batching to improve scalability for very large datasets.

## Version History

### 1.0.0 (2026-01-26)
- Initial release
- Pure PowerShell implementation
- Mirror, Update, TwoWay sync modes
- TimeAndSize comparison method
- RecycleBin, Permanent, Versioning deletion policies
- Include/exclude filter patterns
- Symlink exclusion option
- DST time shift handling
- Progress reporting with file-by-file output
- Dry run mode
- UNC share support with credential management
- Integration with SchedulerTemplate.psm1

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review script logs for error details
3. Verify all [Requirements](#requirements) are met

## License

See [LICENSE](../../LICENSE.md) in the root directory.

## Related Files

- `../SchedulerTemplate.psm1` - Shared scheduling and logging module
- `scriptsettings.json` - Configuration file
- `native-sync.bat` - Batch launcher
- `native-sync.ps1` - Main script
