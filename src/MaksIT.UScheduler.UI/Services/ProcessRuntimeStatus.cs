using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Services;

/// <summary>
/// Text and color for one program row in the window.
/// </summary>
public static class ProcessRuntimeStatus {
  public static (string Text, string Color) Describe(
    bool serviceRunning,
    bool disabled,
    ProcessStatusEntry? entry,
    Func<int, bool>? isAlive = null) {
    if (string.IsNullOrWhiteSpace(entry?.Path) && disabled)
      return ("Disabled", "Gray");

    if (disabled)
      return ("Disabled", "Gray");

    if (!serviceRunning)
      return ("Service stopped", "Gray");

    if (entry is null || string.IsNullOrWhiteSpace(entry.Path))
      return ("Waiting", "Orange");

    if (entry.State == ProcessStates.Running && (isAlive is null || entry.ProcessId is not int pid || isAlive(pid)))
      return ("Running", "Green");

    if (entry.State == ProcessStates.Restarting)
      return ("Restarting", "Orange");

    return ("Stopped", "Gray");
  }
}
