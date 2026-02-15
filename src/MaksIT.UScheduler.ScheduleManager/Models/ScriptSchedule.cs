namespace MaksIT.UScheduler.ScheduleManager.Models;

/// <summary>
/// Represents the schedule configuration from a scriptsettings.json file.
/// </summary>
public class ScriptSchedule
{
    /// <summary>
    /// Full path to the scriptsettings.json file.
    /// </summary>
    public string FilePath { get; set; } = string.Empty;

    /// <summary>
    /// Display name for the script in the UI (from JSON "name" or "title", or derived from path).
    /// </summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Script title from the JSON "title" field.
    /// </summary>
    public string Title { get; set; } = string.Empty;

    /// <summary>
    /// Array of month names to run (empty = every month).
    /// Valid values: January, February, March, April, May, June, July, August, September, October, November, December
    /// </summary>
    public List<string> RunMonth { get; set; } = [];

    /// <summary>
    /// Array of weekday names to run (empty = every day).
    /// Valid values: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday
    /// </summary>
    public List<string> RunWeekday { get; set; } = [];

    /// <summary>
    /// Array of UTC times in HH:mm format when script should run.
    /// </summary>
    public List<string> RunTime { get; set; } = [];

    /// <summary>
    /// Minimum minutes between runs to prevent duplicate executions.
    /// </summary>
    public int MinIntervalMinutes { get; set; } = 10;

    /// <summary>
    /// Script path as stored in service appsettings (e.g. ".\file-sync.ps1"). Used to find and update the config entry.
    /// </summary>
    public string ConfigScriptPath { get; set; } = string.Empty;

    /// <summary>
    /// Whether the script must be digitally signed (from service Configuration.Powershell).
    /// </summary>
    public bool IsSigned { get; set; } = true;

    /// <summary>
    /// Whether the script is disabled and will not be executed (from service Configuration.Powershell).
    /// </summary>
    public bool Disabled { get; set; }
}
