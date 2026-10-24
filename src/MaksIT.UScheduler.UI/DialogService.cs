using Avalonia.Controls;
using Avalonia.Threading;
using Avalonia.Platform.Storage;
using MaksIT.UScheduler.UI.Windows;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.UI;

public interface IDialogService {
  Window? Owner { get; set; }

  Task ShowMessageAsync(string title, string message);

  Task<bool> ConfirmAsync(string title, string message);

  Task<string?> PickExecutableAsync();

  /// <summary>
  /// Opens a window that follows a script log from <paramref name="startLength"/>.
  /// A second launch of the same log reuses the open window.
  /// </summary>
  void ShowScriptRun(string title, string logFilePath, long startLength);
}

public sealed class DialogService : IDialogService {
  private readonly Dictionary<string, ScriptExecutionWindow> _runs = new(PathComparer);

  private static StringComparer PathComparer =>
    OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

  public Window? Owner { get; set; }

  public async Task ShowMessageAsync(string title, string message) {
    if (Owner is null)
      return;

    await MessageDialog.ShowAsync(Owner, title, message);
  }

  public async Task<bool> ConfirmAsync(string title, string message) {
    if (Owner is null)
      return false;

    return await ConfirmDialog.ShowAsync(Owner, title, message);
  }

  public async Task<string?> PickExecutableAsync() {
    if (Owner is null)
      return null;

    var files = await Owner.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions {
      Title = "Program",
      AllowMultiple = false,
      FileTypeFilter = [
        new FilePickerFileType("Programs") {
          Patterns = OperatingSystem.IsWindows() ? ["*.exe"] : ["*"]
        },
        new FilePickerFileType("All files") { Patterns = ["*"] }
      ]
    });

    return files.Count == 0 ? null : files[0].TryGetLocalPath();
  }

  public void ShowScriptRun(string title, string logFilePath, long startLength) {
    if (!Dispatcher.UIThread.CheckAccess()) {
      Dispatcher.UIThread.Post(() => ShowScriptRun(title, logFilePath, startLength));

      return;
    }

    if (Owner is null || string.IsNullOrWhiteSpace(logFilePath))
      return;

    if (_runs.TryGetValue(logFilePath, out var existing)) {
      if (existing.WindowState == WindowState.Minimized)
        existing.WindowState = WindowState.Normal;

      existing.Follow(title, startLength);
      existing.Activate();

      return;
    }

    var window = new ScriptExecutionWindow(new ScriptExecutionViewModel(title, logFilePath, startLength)) {
      Icon = Owner.Icon
    };
    window.Closed += (_, _) => _runs.Remove(logFilePath);
    _runs[logFilePath] = window;
    window.Show(Owner);
  }
}
