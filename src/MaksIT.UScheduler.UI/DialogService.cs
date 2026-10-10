using Avalonia.Controls;
using Avalonia.Platform.Storage;


namespace MaksIT.UScheduler.UI;

public interface IDialogService {
  Window? Owner { get; set; }

  Task ShowMessageAsync(string title, string message);

  Task<bool> ConfirmAsync(string title, string message);

  Task<string?> PickExecutableAsync();
}

public sealed class DialogService : IDialogService {
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
}
