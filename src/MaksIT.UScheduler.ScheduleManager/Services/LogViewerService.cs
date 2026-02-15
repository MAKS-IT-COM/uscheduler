using System.IO;

namespace MaksIT.UScheduler.ScheduleManager.Services;

/// <summary>
/// Represents a log file with metadata.
/// </summary>
public class LogFileInfo
{
    public string FileName { get; set; } = string.Empty;
    public string FullPath { get; set; } = string.Empty;
    public DateTime LastModified { get; set; }
    public long SizeBytes { get; set; }

    /// <summary>Script folder name for script logs (e.g. file-sync); empty for service logs.</summary>
    public string ScriptFolder { get; set; } = string.Empty;

    public string SizeDisplay => SizeBytes switch
    {
        < 1024 => $"{SizeBytes} B",
        < 1024 * 1024 => $"{SizeBytes / 1024.0:F1} KB",
        _ => $"{SizeBytes / (1024.0 * 1024.0):F1} MB"
    };

    /// <summary>Display label for list: script folder + file name for script logs, else file name.</summary>
    public string DisplayLabel => string.IsNullOrEmpty(ScriptFolder) ? FileName : $"{ScriptFolder} \\ {FileName}";
}

/// <summary>
/// Service for viewing log files.
/// </summary>
public class LogViewerService
{
    /// <summary>
    /// Gets all log files from the specified log directory.
    /// </summary>
    public List<LogFileInfo> GetServiceLogs(string logDir)
    {
        var logs = new List<LogFileInfo>();

        if (string.IsNullOrEmpty(logDir) || !Directory.Exists(logDir))
            return logs;

        try
        {
            // Get log files from root directory (service logs)
            var rootLogs = Directory.GetFiles(logDir, "*.log", SearchOption.TopDirectoryOnly);
            foreach (var file in rootLogs)
            {
                logs.Add(CreateLogFileInfo(file));
            }

            // Also check for .txt log files
            var txtLogs = Directory.GetFiles(logDir, "*.txt", SearchOption.TopDirectoryOnly);
            foreach (var file in txtLogs)
            {
                logs.Add(CreateLogFileInfo(file));
            }
        }
        catch
        {
            // Ignore access errors
        }

        return logs.OrderByDescending(l => l.LastModified).ToList();
    }

    /// <summary>
    /// Gets the names of all script log subfolders under logDir (e.g. file-sync, hyper-v-backup).
    /// </summary>
    public List<string> GetScriptLogFolderNames(string logDir)
    {
        var names = new List<string>();

        if (string.IsNullOrEmpty(logDir))
            return names;

        var logDirFull = Path.GetFullPath(logDir);
        if (!Directory.Exists(logDirFull))
            return names;

        try
        {
            foreach (var subDir in Directory.GetDirectories(logDirFull))
            {
                var name = Path.GetFileName(subDir);
                if (!string.IsNullOrEmpty(name))
                    names.Add(name);
            }
        }
        catch
        {
            // Ignore access errors
        }

        return names.OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// <summary>
    /// Gets log files from all script subfolders under logDir (e.g. logs\file-sync, logs\hyper-v-backup).
    /// Does not require a script to be selected. Each subfolder of logDir is treated as a script log folder.
    /// </summary>
    public List<LogFileInfo> GetAllScriptLogs(string logDir)
    {
        var logs = new List<LogFileInfo>();

        if (string.IsNullOrEmpty(logDir))
            return logs;

        var logDirFull = Path.GetFullPath(logDir);
        if (!Directory.Exists(logDirFull))
            return logs;

        try
        {
            foreach (var subDir in Directory.GetDirectories(logDirFull))
            {
                var scriptFolder = Path.GetFileName(subDir) ?? string.Empty;
                var logFiles = Directory.GetFiles(subDir, "*.*", SearchOption.TopDirectoryOnly)
                    .Where(f => f.EndsWith(".log", StringComparison.OrdinalIgnoreCase) ||
                                f.EndsWith(".txt", StringComparison.OrdinalIgnoreCase));

                foreach (var file in logFiles)
                {
                    var info = CreateLogFileInfo(file);
                    info.ScriptFolder = scriptFolder;
                    logs.Add(info);
                }
            }
        }
        catch
        {
            // Ignore access errors
        }

        return logs.OrderByDescending(l => l.LastModified).ToList();
    }

    /// <summary>
    /// Gets log files for a specific script. Script logs live under LogDir in a subfolder
    /// named by the script filename without extension (from Configuration.Powershell[].Path).
    /// E.g. Path=...\file-sync.ps1, LogDir=.\logs → .\logs\file-sync. Tries candidate names, case-insensitive.
    /// </summary>
    public List<LogFileInfo> GetScriptLogs(string logDir, string scriptName)
    {
        var logs = new List<LogFileInfo>();

        if (string.IsNullOrEmpty(logDir) || string.IsNullOrEmpty(scriptName))
            return logs;

        var logDirFull = Path.GetFullPath(logDir);
        if (!Directory.Exists(logDirFull))
            return logs;

        var scriptLogDir = FindScriptLogSubfolder(logDirFull, scriptName);
        if (string.IsNullOrEmpty(scriptLogDir))
            return logs;

        try
        {
            var logFiles = Directory.GetFiles(scriptLogDir, "*.*", SearchOption.TopDirectoryOnly)
                .Where(f => f.EndsWith(".log", StringComparison.OrdinalIgnoreCase) ||
                            f.EndsWith(".txt", StringComparison.OrdinalIgnoreCase));

            foreach (var file in logFiles)
            {
                logs.Add(CreateLogFileInfo(file));
            }
        }
        catch
        {
            // Ignore access errors
        }

        return logs.OrderByDescending(l => l.LastModified).ToList();
    }

    /// <summary>
    /// Finds the script log subfolder under logDir: exact scriptName first, then case-insensitive match.
    /// </summary>
    private static string? FindScriptLogSubfolder(string logDir, string scriptName)
    {
        var exact = Path.Combine(logDir, scriptName);
        if (Directory.Exists(exact))
            return exact;

        try
        {
            foreach (var subDir in Directory.GetDirectories(logDir))
            {
                var name = Path.GetFileName(subDir);
                if (string.Equals(name, scriptName, StringComparison.OrdinalIgnoreCase))
                    return subDir;
            }
        }
        catch
        {
            // Ignore access errors
        }

        return null;
    }

    /// <summary>
    /// Reads the content of a log file.
    /// </summary>
    public string ReadLogFile(string filePath, int maxLines = 1000)
    {
        try
        {
            if (!File.Exists(filePath))
                return "Log file not found.";

            var lines = File.ReadLines(filePath).TakeLast(maxLines).ToList();
            
            if (lines.Count == maxLines)
            {
                return $"[Showing last {maxLines} lines...]\n\n" + string.Join("\n", lines);
            }

            return string.Join("\n", lines);
        }
        catch (Exception ex)
        {
            return $"Error reading log file: {ex.Message}";
        }
    }

    /// <summary>
    /// Reads the tail of a log file (last N lines).
    /// </summary>
    public string ReadLogTail(string filePath, int lines = 100)
    {
        try
        {
            if (!File.Exists(filePath))
                return "Log file not found.";

            var allLines = File.ReadLines(filePath).TakeLast(lines).ToList();
            return string.Join("\n", allLines);
        }
        catch (Exception ex)
        {
            return $"Error reading log file: {ex.Message}";
        }
    }

    private static LogFileInfo CreateLogFileInfo(string filePath)
    {
        var fileInfo = new FileInfo(filePath);
        return new LogFileInfo
        {
            FileName = fileInfo.Name,
            FullPath = filePath,
            LastModified = fileInfo.LastWriteTime,
            SizeBytes = fileInfo.Length
        };
    }
}
