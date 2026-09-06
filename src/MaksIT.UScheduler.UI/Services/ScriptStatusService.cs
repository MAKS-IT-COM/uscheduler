using System.IO;
using MaksIT.UScheduler.UI.Models;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>
/// Service for managing script status files (lock files, last run).
/// </summary>
public class ScriptStatusService {
  /// <summary>
  /// Gets the status of a script from its scriptsettings.json path.
  /// </summary>
  public ScriptStatus GetScriptStatus(string scriptSettingsPath) {
    var directory = Path.GetDirectoryName(scriptSettingsPath) ?? string.Empty;
    var scriptName = Path.GetFileName(directory);

    // Find the .ps1 file in the same directory
    var scriptFiles = Directory.GetFiles(directory, "*.ps1", SearchOption.TopDirectoryOnly);
    var scriptPath = scriptFiles.FirstOrDefault() ?? string.Empty;

    if (string.IsNullOrEmpty(scriptPath)) {
      return new ScriptStatus {
        ScriptPath = string.Empty,
        ScriptName = scriptName,
        HasLockFile = false,
        LastRun = null
      };
    }

    var lockFilePath = Path.ChangeExtension(scriptPath, ".lock");
    var lastRunFilePath = Path.ChangeExtension(scriptPath, ".lastRun");

    return new ScriptStatus {
      ScriptPath = scriptPath,
      ScriptName = scriptName,
      HasLockFile = File.Exists(lockFilePath),
      LockFilePath = lockFilePath,
      LastRun = GetLastRunTime(lastRunFilePath),
      LastRunFilePath = lastRunFilePath
    };
  }

  /// <summary>
  /// Removes the lock file for a script.
  /// </summary>
  public bool RemoveLockFile(string lockFilePath) {
    try {
      if (File.Exists(lockFilePath)) {
        File.Delete(lockFilePath);
        return true;
      }
      return false;
    }
    catch {
      return false;
    }
  }

  /// <summary>
  /// Reads the last run time from the .lastRun file.
  /// </summary>
  private static DateTime? GetLastRunTime(string lastRunFilePath) {
    try {
      if (!File.Exists(lastRunFilePath))
        return null;

      var content = File.ReadAllText(lastRunFilePath).Trim();
      if (DateTime.TryParse(
          content,
          null,
          System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal,
          out var lastRun)) {
        return lastRun;
      }
      return null;
    }
    catch {
      return null;
    }
  }
}
