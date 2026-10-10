using CommunityToolkit.Mvvm.ComponentModel;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.UI.ViewModels;

public partial class SupervisedProcessRow : ObservableObject {
  public SupervisedProcessRow() {
    PropertyChanged += (_, e) => {
      if (e.PropertyName is nameof(StatusText)
          or nameof(StatusColor)
          or nameof(ProcessIdText)
          or nameof(LastExitText)
          or nameof(StartedText)
          or nameof(ListTitle)
          or nameof(ListDetail))
        return;

      Edited?.Invoke();
    };
  }

  public event Action? Edited;

  [ObservableProperty]
  private string name = "";

  [ObservableProperty]
  private string path = "";

  [ObservableProperty]
  private string arguments = "";

  [ObservableProperty]
  private string directory = "";

  [ObservableProperty]
  private bool restartOnExit = true;

  [ObservableProperty]
  private int restartDelayMs;

  [ObservableProperty]
  private int throttleMs = 1500;

  [ObservableProperty]
  private bool disabled;

  [ObservableProperty]
  private string statusText = "Waiting";

  [ObservableProperty]
  private string statusColor = "Orange";

  [ObservableProperty]
  private string processIdText = "";

  [ObservableProperty]
  private string lastExitText = "";

  [ObservableProperty]
  private string startedText = "";

  public string ListTitle {
    get {
      if (!string.IsNullOrWhiteSpace(Name))
        return Name.Trim();

      return string.IsNullOrWhiteSpace(Path) ? "New program" : System.IO.Path.GetFileName(Path);
    }
  }

  public string ListDetail => StatusText;

  public double ListOpacity => Disabled ? 0.42 : 1;

  partial void OnNameChanged(string value) => OnPropertyChanged(nameof(ListTitle));

  partial void OnPathChanged(string value) => OnPropertyChanged(nameof(ListTitle));

  partial void OnStatusTextChanged(string value) => OnPropertyChanged(nameof(ListDetail));

  partial void OnDisabledChanged(bool value) => OnPropertyChanged(nameof(ListOpacity));

  public static SupervisedProcessRow From(ProcessConfiguration process) =>
    new() {
      Name = process.Name ?? "",
      Path = process.Path,
      Arguments = process.Args is null ? "" : string.Join(Environment.NewLine, process.Args),
      Directory = process.Directory ?? "",
      RestartOnExit = process.RestartOnFailure,
      RestartDelayMs = process.RestartDelayMs,
      ThrottleMs = process.ThrottleMs,
      Disabled = process.Disabled
    };

  public ProcessConfiguration ToConfiguration() =>
    new() {
      Name = string.IsNullOrWhiteSpace(Name) ? null : Name.Trim(),
      Path = Path.Trim(),
      Args = SplitArguments(Arguments),
      Directory = string.IsNullOrWhiteSpace(Directory) ? null : Directory.Trim(),
      RestartOnFailure = RestartOnExit,
      RestartDelayMs = Math.Max(0, RestartDelayMs),
      ThrottleMs = Math.Max(0, ThrottleMs),
      Disabled = Disabled
    };

  public void ApplyStatus(string text, string color, ProcessStatusEntry? entry) {
    StatusText = text;
    StatusColor = color;
    ProcessIdText = entry?.ProcessId?.ToString() ?? "";
    LastExitText = entry?.LastExitCode?.ToString() ?? "";
    StartedText = entry?.StartedUtc?.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss") ?? "";
  }

  private static string[]? SplitArguments(string text) {
    var lines = text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    return lines.Length == 0 ? null : lines;
  }
}
