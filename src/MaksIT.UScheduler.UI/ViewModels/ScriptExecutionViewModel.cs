using System.Collections.ObjectModel;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using MaksIT.UScheduler.UI.Services;


namespace MaksIT.UScheduler.UI.ViewModels;

/// <summary>
/// Follows one script log from the byte offset captured when Launch was requested.
/// </summary>
public partial class ScriptExecutionViewModel : ObservableObject, IDisposable {
  private readonly string _logFile;
  private readonly DispatcherTimer _timer;
  private long _position;
  private string _pending = "";
  private string _level = "";
  private bool _finished;

  public ObservableCollection<ScriptConsoleLine> Lines { get; } = [];

  public ScriptExecutionViewModel(string title, string logFile, long startPosition) {
    _logFile = logFile;
    _position = startPosition;
    Title = string.IsNullOrWhiteSpace(title) ? "Script" : title;
    Status = "Running";
    _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
    _timer.Tick += OnTick;
    _timer.Start();
    Pull();
  }

  [ObservableProperty]
  private string title;

  [ObservableProperty]
  private string status;

  [ObservableProperty]
  private string output = "";

  public bool HasOutput =>
    Lines.Count > 0;

  public void Follow(string title, long startPosition) {
    Title = string.IsNullOrWhiteSpace(title) ? "Script" : title;
    _position = startPosition;
    _pending = "";
    _level = "";
    _finished = false;
    Lines.Clear();
    Output = "";
    OnPropertyChanged(nameof(HasOutput));
    Status = "Running";

    if (!_timer.IsEnabled)
      _timer.Start();

    Pull();
  }

  public void Dispose() {
    _timer.Stop();
    _timer.Tick -= OnTick;
  }

  private void OnTick(object? sender, EventArgs e) =>
    Pull();

  private void Pull() {
    if (_finished)
      return;

    var added = ScriptLogFollow.ReadNewText(_logFile, ref _position);

    if (added.Length == 0)
      return;

    var lines = ScriptLogFollow.FormatPowerShell(added, ref _pending, ref _level, out var finished);

    if (lines.Count > 0) {
      var wasEmpty = Lines.Count == 0;

      foreach (var line in lines) {
        Lines.Add(new ScriptConsoleLine(line.Text, line.Level));
        Output += line.Text + "\n";
      }

      if (wasEmpty)
        OnPropertyChanged(nameof(HasOutput));
    }

    if (!finished)
      return;

    _finished = true;
    Status = "Finished";
    _timer.Stop();
  }
}
