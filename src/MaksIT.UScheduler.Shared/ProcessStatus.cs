namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Last state the service published for one supervised program.
/// </summary>
public sealed class ProcessStatusEntry {
  public string Path { get; set; } = "";

  public string State { get; set; } = ProcessStates.Stopped;

  public int? ProcessId { get; set; }

  public int? LastExitCode { get; set; }

  public DateTimeOffset? StartedUtc { get; set; }

  public int Restarts { get; set; }
}

/// <summary>
/// File the service writes under the log directory and the window reads.
/// </summary>
public sealed class ProcessStatusSnapshot {
  public const string FileName = "process-status.json";

  public List<ProcessStatusEntry> Processes { get; set; } = [];

  public static string ResolvePath(string logDirectory) =>
    System.IO.Path.Combine(logDirectory, FileName);
}

public static class ProcessStates {
  public const string Running = "Running";

  public const string Restarting = "Restarting";

  public const string Stopped = "Stopped";
}
