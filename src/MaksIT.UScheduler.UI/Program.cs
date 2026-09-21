using Avalonia;
using Avalonia.Logging;


namespace MaksIT.UScheduler.UI;

internal static class Program {
  [STAThread]
  public static void Main(string[] args) =>
    BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);

  // Linux: X11/XWayland. Avalonia 12.1.2 native Wayland still hangs on GNOME's
  // xdg_toplevel.configure(0, 0) and never maps a window (GNOME app icon).
  public static AppBuilder BuildAvaloniaApp() =>
    AppBuilder.Configure<App>()
      .UsePlatformDetect()
      .LogToTrace(LogEventLevel.Warning);
}
