namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Base configuration class for scheduled tasks.
/// </summary>
public abstract class TaskConfiguration
{
    /// <summary>
    /// Gets or sets the path to the executable or script.
    /// </summary>
    public required string Path { get; set; }

    /// <summary>
    /// Gets or sets whether this task is disabled. Disabled tasks will not be executed.
    /// </summary>
    public bool Disabled { get; set; }
}

/// <summary>
/// Configuration for a scheduled PowerShell script.
/// </summary>
public class PowershellScript : TaskConfiguration
{
    /// <summary>
    /// Gets or sets the display name for the script in the UI.
    /// When set in appsettings, overrides the name from scriptsettings.json.
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
public class ProcessConfiguration : TaskConfiguration
{
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
/// </summary>
public class Configuration
{
    /// <summary>
    /// Gets or sets the Windows service name used for registration.
    /// </summary>
    public string ServiceName { get; set; } = "MaksIT.UScheduler";

    /// <summary>
    /// Gets or sets the directory path for log files (required).
    /// May be relative to the application base directory (e.g. ".\Logs") or absolute.
    /// </summary>
    public required string LogDir { get; set; }

    /// <summary>
    /// Gets or sets the list of PowerShell scripts to execute.
    /// </summary>
    public List<PowershellScript> Powershell { get; set; } = [];

    /// <summary>
    /// Gets or sets the list of processes/executables to run.
    /// </summary>
    public List<ProcessConfiguration> Processes { get; set; } = [];
}
