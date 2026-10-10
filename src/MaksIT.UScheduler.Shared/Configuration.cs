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
/// A program kept running under the service. It starts with the service and stops with it.
/// </summary>
public class ProcessConfiguration : TaskConfiguration {
  /// <summary>
  /// Display name in the Processes list. Empty uses the executable file name.
  /// </summary>
  public string? Name { get; set; }

  /// <summary>
  /// Gets or sets the command-line arguments to pass to the process.
  /// </summary>
  public string[]? Args { get; set; }

  /// <summary>
  /// Working directory. Empty uses the executable's own directory.
  /// </summary>
  public string? Directory { get; set; }

  /// <summary>
  /// When true, any exit starts the program again. When false, it stays stopped after it exits.
  /// </summary>
  public bool RestartOnFailure { get; set; } = true;

  /// <summary>
  /// Milliseconds to wait before a restart after a run that lasted at least <see cref="ThrottleMs"/>.
  /// </summary>
  public int RestartDelayMs { get; set; }

  /// <summary>
  /// A run shorter than this is treated as a crash. The next start waits at least this long,
  /// and longer while crashes continue, up to one minute. Default 1500.
  /// </summary>
  public int ThrottleMs { get; set; } = 1500;
}

/// <summary>
/// Root configuration class for the UScheduler service.
/// Stored in machine-wide settings.json (ProgramData), or under the install
/// folder when a portable layout is used.
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

  public string GetEffectiveScriptsDirectory(string? baseDirectory = null) =>
    HostPaths.ResolveScriptsDirectory(ScriptsDir, baseDirectory);

  public string GetEffectiveLogDirectory(string? baseDirectory = null) {
    var start = baseDirectory ?? AppContext.BaseDirectory;
    if (string.IsNullOrWhiteSpace(LogDir)) {
      var root = HostPaths.FindPortableRoot(start);
      return root is null ? HostPaths.DefaultLogDirectory : HostPaths.GetPortableLogDirectory(root);
    }

    return PathHelper.ResolvePath(LogDir, start);
  }

  public string ResolveScriptPath(string path) =>
    PathHelper.ResolvePath(path, GetEffectiveScriptsDirectory());
}
