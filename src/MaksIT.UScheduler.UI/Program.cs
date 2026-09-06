using Avalonia;
using Avalonia.Logging;


namespace MaksIT.UScheduler.UI;

internal static class Program {
  [STAThread]
  public static void Main(string[] args) =>
    BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);

  public static AppBuilder BuildAvaloniaApp() =>
    AppBuilder.Configure<App>()
      .UsePlatformDetect()
      .LogToTrace(LogEventLevel.Warning);
}
