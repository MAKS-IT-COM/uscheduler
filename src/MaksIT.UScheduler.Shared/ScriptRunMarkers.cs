namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Lines the scheduler writes into a script log so a manual run can be followed in the desktop window.
/// </summary>
public static class ScriptRunMarkers {
  /// <summary>PowerShell-shaped line hidden in the launch window. The file log stores <see cref="FinishedMessage"/>.</summary>
  public const string FinishedLine = "[Info] Scheduler finished this run";

  /// <summary>
  /// Appended when the launch that owns the pipeline has ended.
  /// Scheduled checks do not write this; they already return on their own.
  /// </summary>
  public const string FinishedMessage = "[PS Output] " + FinishedLine;
}
