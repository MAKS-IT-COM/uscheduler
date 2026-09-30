using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.UI.ViewModels;
using MaksIT.UScheduler.UI.Windows;


namespace MaksIT.UScheduler.UI.Dialogs;


internal static class ErrorDialog {
  private static int _open;

  public static void Report(Exception? exception) =>
    Present(exception, wait: false);

  public static void ReportBlocking(Exception? exception) =>
    Present(exception, wait: true);

  private static void Present(Exception? exception, bool wait) {
    if (exception is null)
      return;
    var report = ErrorReport.Capture(exception);
    var dispatcher = TryDispatcher();
    if (dispatcher is null) {
      if (wait)
        ShowStandalone(report);
      return;
    }

    if (dispatcher.CheckAccess()) {
      if (wait)
        ShowUntilClosed(report);
      else
        _ = ShowAsync(report);
      return;
    }

    if (wait)
      dispatcher.Invoke(() => ShowUntilClosed(report));
    else
      dispatcher.Post(() => _ = ShowAsync(report));
  }

  private static Dispatcher? TryDispatcher() {
    try {
      return Dispatcher.UIThread;
    }
    catch {
      return null;
    }
  }

  private static async Task ShowAsync(string report) {
    if (Interlocked.Exchange(ref _open, 1) != 0)
      return;
    try {
      var window = Create(report);
      var owner = ActiveWindow();
      if (owner is { IsVisible: true }) {
        window.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        await window.ShowDialog(owner);
        return;
      }

      window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
      var closed = new TaskCompletionSource();
      window.Closed += (_, _) => closed.TrySetResult();
      window.Show();
      await closed.Task;
    }
    catch {
    }
    finally {
      Interlocked.Exchange(ref _open, 0);
    }
  }

  private static void ShowUntilClosed(string report) {
    if (Interlocked.Exchange(ref _open, 1) != 0)
      return;
    try {
      var window = Create(report);
      var owner = ActiveWindow();
      var closed = false;
      window.Closed += (_, _) => closed = true;
      if (owner is { IsVisible: true }) {
        window.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        window.Show(owner);
      }
      else {
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        window.Show();
      }

      var dispatcher = Dispatcher.UIThread;
      while (!closed)
        dispatcher.RunJobs();
    }
    catch {
    }
    finally {
      Interlocked.Exchange(ref _open, 0);
    }
  }

  private static void ShowStandalone(string report) {
    if (Interlocked.Exchange(ref _open, 1) != 0)
      return;
    try {
      AppBuilder.Configure<Application>()
        .UsePlatformDetect()
        .AfterSetup(builder => {
          if (builder.Instance?.ApplicationLifetime is not IClassicDesktopStyleApplicationLifetime life)
            return;
          life.ShutdownMode = ShutdownMode.OnMainWindowClose;
          life.MainWindow = Create(report);
        })
        .StartWithClassicDesktopLifetime([]);
    }
    catch {
    }
    finally {
      Interlocked.Exchange(ref _open, 0);
    }
  }

  private static ErrorWindow Create(string report) =>
    new() {
      DataContext = new ErrorReportViewModel(report),
      WindowStartupLocation = WindowStartupLocation.CenterScreen
    };

  private static Window? ActiveWindow() {
    if (Application.Current?.ApplicationLifetime is not IClassicDesktopStyleApplicationLifetime life)
      return null;
    foreach (var window in life.Windows) {
      if (window.IsActive && window is not ErrorWindow)
        return window;
    }

    return life.MainWindow is ErrorWindow ? null : life.MainWindow;
  }
}
