using System.Text.Json;
using System.Text.Json.Serialization;
using Avalonia.Controls;
using Avalonia.Threading;
using MaksIT.Core.Desktop.Snapshots;
using MaksIT.Core.UI.Snapshots;
using MaksIT.UScheduler.UI.ViewModels;
using MaksIT.UScheduler.UI.Windows;


namespace MaksIT.UScheduler.UI.Services;

internal static class SnapshotTour {
  private static readonly JsonSerializerOptions Json = new() {
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
  };

  public static async Task RunAsync(
    Window window,
    MainViewModel model,
    AppViewSnapshotOptions options,
    Action<int> shutdown) {
    var manifest = new Manifest();
    var code = 0;

    try {
      Directory.CreateDirectory(options.Directory);

      foreach (var view in SnapshotViews.Resolve(options.Views)) {
        if (!SnapshotViews.IsKnown(view)) {
          manifest.Skipped.Add(new SkippedRecord { Id = view, Reason = "Unknown view." });

          continue;
        }

        await CaptureAsync(window, model, options, manifest, view);
      }
    }
    catch (Exception ex) {
      manifest.Error = ex.Message;
      code = 1;
    }

    try {
      var path = Path.Combine(options.Directory, "manifest.json");
      await File.WriteAllTextAsync(path, JsonSerializer.Serialize(manifest, Json) + Environment.NewLine);
    }
    catch (Exception ex) {
      manifest.Error ??= ex.Message;
      code = 1;
    }

    await Dispatcher.UIThread.InvokeAsync(() => shutdown(code));
  }

  private static async Task CaptureAsync(
    Window window,
    MainViewModel model,
    AppViewSnapshotOptions options,
    Manifest manifest,
    string view) {
    if (view.Equals("about", StringComparison.OrdinalIgnoreCase)
        || view.Equals("program-log", StringComparison.OrdinalIgnoreCase)) {
      await CaptureDialogAsync(window, options, manifest, view);

      return;
    }

    await Dispatcher.UIThread.InvokeAsync(() => ShowPage(model, view));
    await AppViewSnapshot.SettleAsync(options.SettleMilliseconds);
    manifest.Shots.Add(Shot(window, options, view));
  }

  private static void ShowPage(MainViewModel model, string view) {
    if (view.Equals("processes", StringComparison.OrdinalIgnoreCase)) {
      model.SelectedPageIndex = 1;
      model.PrepareProcessesForSnapshot();

      return;
    }

    if (view.Equals("logs", StringComparison.OrdinalIgnoreCase)
        || view.Equals("script-logs", StringComparison.OrdinalIgnoreCase)) {
      model.SelectedPageIndex = 2;
      model.SelectedLogTab = view.Equals("script-logs", StringComparison.OrdinalIgnoreCase) ? 1 : 0;

      return;
    }

    if (view.Equals("settings", StringComparison.OrdinalIgnoreCase)) {
      model.SelectedPageIndex = 3;

      return;
    }

    model.SelectedPageIndex = 0;

    if (model.SelectedScript is null && model.Scripts.Count > 0)
      model.SelectedScript = model.Scripts[0];
  }

  private static async Task CaptureDialogAsync(
    Window owner,
    AppViewSnapshotOptions options,
    Manifest manifest,
    string view) {
    var dialog = view.Equals("about", StringComparison.OrdinalIgnoreCase)
      ? AboutWindow.Create(owner)
      : LogWindow.Create(owner);

    dialog.Show(owner);
    await AppViewSnapshot.SettleAsync(options.SettleMilliseconds);
    manifest.Shots.Add(Shot(dialog, options, view));
    dialog.Close();
  }

  private static ShotRecord Shot(Control control, AppViewSnapshotOptions options, string id) =>
    new() {
      Id = id,
      File = AppViewSnapshot.Save(control, Path.Combine(options.Directory, AppViewSnapshot.FileToken(id) + ".png"))
    };

  private sealed class Manifest {
    public List<ShotRecord> Shots { get; set; } = [];

    public List<SkippedRecord> Skipped { get; set; } = [];

    public string? Error { get; set; }
  }

  private sealed class ShotRecord {
    public string Id { get; set; } = "";

    public string? File { get; set; }
  }

  private sealed class SkippedRecord {
    public string Id { get; set; } = "";

    public string Reason { get; set; } = "";
  }
}
