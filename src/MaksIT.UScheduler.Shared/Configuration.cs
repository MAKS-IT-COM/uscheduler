using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Base configuration class for scheduled tasks.
/// </summary>
public abstract class TaskConfiguration {
  /// <summary>
  /// Gets or sets the path to the executable or script.
  /// </summary>
  public required string Path { get; set; }

  /// <summary>
  /// Gets or sets whether this task is disabled. Disabled tasks will not be executed.
  /// </summary>
  public bool Disabled { get; set; }

  /// <summary>
  /// Gets or sets a short description shown in the UI list.
  /// </summary>
  public string? Description { get; set; }

  /// <summary>
  /// Hosts this task may run on (<see cref="HostPlatforms"/> names). Empty = Windows and Linux.
  /// </summary>
  public List<string> Platforms { get; set; } = [];
}

/// <summary>
/// Configuration for a scheduled PowerShell script.
/// </summary>
public class PowershellScript : TaskConfiguration {
  /// <summary>
  /// Gets or sets the display name for the script in the UI.
  /// When set in settings, overrides the name from scriptsettings.json.
  /// </summary>
  public string? Name { get; set; }

  /// <summary>
  /// Gets or sets whether the script must be digitally signed.
  /// When true, only scripts with valid Authenticode signatures will be executed.
  /// </summary>
  public bool IsSigned { get; set; } = true;
}

/// <summary>
/// Configuration for a scheduled process/executable.
/// </summary>
public class ProcessConfiguration : TaskConfiguration {
  /// <summary>
  /// Gets or sets the command-line arguments to pass to the process.
  /// </summary>
  public string[]? Args { get; set; }

  /// <summary>
  /// Gets or sets whether the process should automatically restart on failure.
  /// </summary>
  public bool RestartOnFailure { get; set; }
}

/// <summary>
/// Root configuration class for the UScheduler service.
/// Stored in machine-wide settings.json (ProgramData), not next to the exe.
/// </summary>
public class Configuration {
  /// <summary>
  /// Gets or sets the service name used for Windows SCM / systemd registration.
  /// </summary>
  public string ServiceName { get; set; } = "MaksIT.UScheduler";

  /// <summary>
  /// Gets or sets the directory path for log files.
  /// Default: <c>C:\MaksIT\Logs</c> on Windows.
  /// </summary>
  public string LogDir { get; set; } = HostPaths.DefaultLogDirectory;

  /// <summary>
  /// Gets or sets the directory that contains scheduled scripts.
  /// Default: <c>C:\MaksIT\Scripts</c> on Windows. Relative script paths resolve against this folder.
  /// </summary>
  public string ScriptsDir { get; set; } = HostPaths.DefaultScriptsDirectory;

  /// <summary>
  /// Gets or sets the list of PowerShell scripts to execute.
  /// </summary>
  public List<PowershellScript> Powershell { get; set; } = [];

  /// <summary>
  /// Gets or sets the list of processes/executables to run.
  /// </summary>
  public List<ProcessConfiguration> Processes { get; set; } = [];

  public void EnsureDefaults() {
    if (string.IsNullOrWhiteSpace(ServiceName))
      ServiceName = "MaksIT.UScheduler";
    if (string.IsNullOrWhiteSpace(LogDir))
      LogDir = HostPaths.DefaultLogDirectory;
    if (string.IsNullOrWhiteSpace(ScriptsDir))
      ScriptsDir = HostPaths.DefaultScriptsDirectory;
    Powershell ??= [];
    Processes ??= [];
  }

  public string GetEffectiveScriptsDirectory() =>
    HostPaths.ResolveScriptsDirectory(ScriptsDir);

  public string GetEffectiveLogDirectory(string? baseDirectory = null) {
    var logDir = string.IsNullOrWhiteSpace(LogDir) ? HostPaths.DefaultLogDirectory : LogDir;
    return PathHelper.ResolvePath(logDir, baseDirectory ?? AppContext.BaseDirectory);
  }

  public string ResolveScriptPath(string path) =>
    PathHelper.ResolvePath(path, GetEffectiveScriptsDirectory());
}
