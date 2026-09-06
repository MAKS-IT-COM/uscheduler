using Avalonia.Controls;
using Avalonia.Platform.Storage;


namespace MaksIT.UScheduler.UI;

public interface IDialogService {
  Window? Owner { get; set; }

  Task ShowMessageAsync(string title, string message);

  Task<bool> ConfirmAsync(string title, string message);

  Task<string?> PickFolderAsync(string title);
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

  public async Task<string?> PickFolderAsync(string title) {
    if (Owner is null)
      return null;

    var folders = await Owner.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions {
      Title = title,
      AllowMultiple = false
    });

    if (folders.Count == 0)
      return null;

    return folders[0].TryGetLocalPath();
  }
}
