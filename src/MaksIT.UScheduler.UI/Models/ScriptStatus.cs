namespace MaksIT.UScheduler.UI.Models;

/// <summary>
/// Represents the runtime status of a script (lock file, last run).
/// </summary>
public class ScriptStatus {
  /// <summary>
  /// Path to the script's .ps1 file.
  /// </summary>
  public string ScriptPath { get; set; } = string.Empty;

  /// <summary>
  /// Script name (derived from folder name).
  /// </summary>
  public string ScriptName { get; set; } = string.Empty;

  /// <summary>
  /// Whether a lock file exists (script is currently running or was interrupted).
  /// </summary>
  public bool HasLockFile { get; set; }

  /// <summary>
  /// Path to the lock file.
  /// </summary>
  public string LockFilePath { get; set; } = string.Empty;

  /// <summary>
  /// Last execution time (from .lastRun file).
  /// </summary>
  public DateTime? LastRun { get; set; }

  /// <summary>
  /// Path to the last run file.
  /// </summary>
  public string LastRunFilePath { get; set; } = string.Empty;

  /// <summary>
  /// Formatted last run time for display.
  /// </summary>
  public string LastRunDisplay => LastRun.HasValue
      ? LastRun.Value.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
      : "Never";

  /// <summary>
  /// Status indicator for display.
  /// </summary>
  public string StatusDisplay => HasLockFile ? "Locked" : "Ready";
}
