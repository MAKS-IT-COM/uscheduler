using System.Text.Json;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Services;

/// <summary>
/// Publishes supervised-program state for the window. The service and the window
/// do not share a process, so the state is a file under the log directory.
/// </summary>
public interface IProcessStatusStore {
  void Upsert(ProcessStatusEntry entry);
}

public sealed class ProcessStatusFileStore : IProcessStatusStore {
  private static readonly JsonSerializerOptions Json = new() {
    WriteIndented = true
  };

  private readonly IOptionsMonitor<Configuration> _options;
  private readonly object _gate = new();

  public ProcessStatusFileStore(IOptionsMonitor<Configuration> options) {
    _options = options;
  }

  public void Upsert(ProcessStatusEntry entry) {
    try {
      var directory = _options.CurrentValue.GetEffectiveLogDirectory();
      if (string.IsNullOrWhiteSpace(directory))
        return;

      Directory.CreateDirectory(directory);
      var path = ProcessStatusSnapshot.ResolvePath(directory);

      lock (_gate) {
        var snapshot = ReadFile(path);
        var match = snapshot.Processes.FindIndex(item => SamePath(item.Path, entry.Path));
        if (match >= 0)
          snapshot.Processes[match] = entry;
        else
          snapshot.Processes.Add(entry);

        var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(snapshot, Json));
        File.Move(temp, path, overwrite: true);
      }
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) {
    }
  }

  public static ProcessStatusSnapshot Load(string? logDirectory) {
    if (string.IsNullOrWhiteSpace(logDirectory))
      return new ProcessStatusSnapshot();

    return ReadFile(ProcessStatusSnapshot.ResolvePath(logDirectory));
  }

  private static ProcessStatusSnapshot ReadFile(string path) {
    try {
      if (!File.Exists(path))
        return new ProcessStatusSnapshot();

      return JsonSerializer.Deserialize<ProcessStatusSnapshot>(File.ReadAllText(path), Json)
        ?? new ProcessStatusSnapshot();
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) {
      return new ProcessStatusSnapshot();
    }
  }

  private static bool SamePath(string left, string right) =>
    string.Equals(
      left,
      right,
      OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
}
