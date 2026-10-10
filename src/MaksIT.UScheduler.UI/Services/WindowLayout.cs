using Avalonia;
using Avalonia.Controls;
using Avalonia.Threading;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>
/// Remembers the main window size, position, and state in the per-user UI settings.
/// </summary>
internal sealed class WindowLayout {
  private readonly Window _window;
  private readonly UISettingsService _settings;
  private readonly DispatcherTimer _saveTimer;
  private int _applyDepth;

  public WindowLayout(Window window, UISettingsService? settings = null) {
    _window = window;
    _settings = settings ?? new UISettingsService();
    _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
    _saveTimer.Tick += (_, _) => {
      _saveTimer.Stop();
      SaveNow();
    };
  }

  public void Attach() {
    Apply(_settings.Load());
    _window.Resized += (_, _) => ScheduleSave();
    _window.PositionChanged += (_, _) => ScheduleSave();
    _window.PropertyChanged += (_, e) => {
      if (e.Property.Name == nameof(Window.WindowState))
        ScheduleSave();
    };
    _window.Closing += (_, _) => {
      _saveTimer.Stop();
      SaveNow();
    };
  }

  private void Apply(UISettings settings) {
    _applyDepth++;

    try {
      _window.Width = Clamp(settings.WindowWidth, _window.MinWidth, UISettings.DefaultWindowWidth);
      _window.Height = Clamp(settings.WindowHeight, _window.MinHeight, UISettings.DefaultWindowHeight);

      if (settings.WindowX is int x && settings.WindowY is int y && IsOnScreen(x, y)) {
        _window.WindowStartupLocation = WindowStartupLocation.Manual;
        _window.Position = new PixelPoint(x, y);
      }

      if (Enum.TryParse<WindowState>(settings.WindowState, true, out var state) && state != WindowState.Minimized)
        _window.WindowState = state;
    }
    finally {
      _applyDepth--;
    }
  }

  private void ScheduleSave() {
    if (_applyDepth > 0)
      return;

    _saveTimer.Stop();
    _saveTimer.Start();
  }

  private void SaveNow() {
    if (_applyDepth > 0)
      return;

    var settings = _settings.Load();

    if (_window.WindowState == WindowState.Normal) {
      settings.WindowWidth = _window.Width;
      settings.WindowHeight = _window.Height;
      settings.WindowX = _window.Position.X;
      settings.WindowY = _window.Position.Y;
    }

    settings.WindowState = _window.WindowState == WindowState.Minimized
      ? WindowState.Normal.ToString()
      : _window.WindowState.ToString();
    _settings.Save(settings);
  }

  private bool IsOnScreen(int x, int y) {
    var screens = _window.Screens?.All;

    if (screens is null || screens.Count == 0)
      return true;

    return screens.Any(screen => screen.WorkingArea.Contains(new PixelPoint(x, y)));
  }

  private static double Clamp(double value, double min, double fallback) =>
    value < min || value > 10000 || double.IsNaN(value) ? fallback : value;
}
