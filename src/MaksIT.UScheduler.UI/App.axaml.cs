using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using MaksIT.Core.Desktop.Snapshots;


namespace MaksIT.UScheduler.UI;

public partial class App : Application {
  public override void Initialize() =>
    AvaloniaXamlLoader.Load(this);

  public override void OnFrameworkInitializationCompleted() {
    if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop) {
      if (!AppViewSnapshotOptions.TryParse(desktop.Args, out var snapshots, out var error))
        FailSnapshots(error);

      desktop.MainWindow = new MainWindow(snapshots);
    }

    base.OnFrameworkInitializationCompleted();
  }

  private static void FailSnapshots(string? error) {
    try {
      if (OperatingSystem.IsWindows())
        AttachConsole(uint.MaxValue);

      Console.Error.WriteLine(error ?? "Invalid snapshot arguments.");
    }
    catch (Exception) {
      // A windowed process may have no console.
    }

    Environment.Exit(2);
  }

  [System.Runtime.InteropServices.DllImport("kernel32.dll")]
  private static extern bool AttachConsole(uint processId);
}
