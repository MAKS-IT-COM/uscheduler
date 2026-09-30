using Avalonia;
using Avalonia.Logging;
using Avalonia.Threading;
using MaksIT.UScheduler.UI.Dialogs;


namespace MaksIT.UScheduler.UI;

internal static class Program {
  [STAThread]
  public static void Main(string[] args) {
    AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandled;
    TaskScheduler.UnobservedTaskException += OnUnobservedTask;
    try {
      BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }
    catch (Exception ex) {
      ErrorDialog.ReportBlocking(ex);
    }
  }

  // Linux: X11/XWayland. Avalonia 12.1.2 native Wayland still hangs on GNOME's
  // xdg_toplevel.configure(0, 0) and never maps a window (GNOME app icon).
  public static AppBuilder BuildAvaloniaApp() =>
    AppBuilder.Configure<App>()
      .UsePlatformDetect()
      .LogToTrace(LogEventLevel.Warning)
      .AfterSetup(_ => Dispatcher.UIThread.UnhandledException += OnDispatcherUnhandled);

  private static void OnDispatcherUnhandled(object? sender, DispatcherUnhandledExceptionEventArgs e) {
    e.Handled = true;
    ErrorDialog.Report(e.Exception);
  }

  private static void OnDomainUnhandled(object? sender, UnhandledExceptionEventArgs e) {
    if (e.ExceptionObject is not Exception ex)
      return;
    if (e.IsTerminating)
      ErrorDialog.ReportBlocking(ex);
    else
      ErrorDialog.Report(ex);
  }

  private static void OnUnobservedTask(object? sender, UnobservedTaskExceptionEventArgs e) {
    e.SetObserved();
    ErrorDialog.Report(e.Exception);
  }
}
