using Avalonia.Controls;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.UI.Services;
using CoreWhatsNew = MaksIT.Core.UI.WhatsNew.WhatsNewWindow;


namespace MaksIT.UScheduler.UI.Windows;

public static class WhatsNewWindow {
  public static Task ShowIfNeededAsync(Window owner) {
    var settings = new UISettingsService();
    var ui = settings.Load();

    return CoreWhatsNew.ShowIfNeededAsync(
      owner,
      ReleaseNotes.Text(),
      AppInfo.Version,
      ui.WhatsNewSeenVersion,
      settings.FileExisted,
      version => Remember(settings, ui, version));
  }

  private static void Remember(UISettingsService settings, UISettings ui, string version) {
    if (string.Equals(ui.WhatsNewSeenVersion, version, StringComparison.Ordinal))
      return;

    ui.WhatsNewSeenVersion = version;
    settings.Save(ui);
  }
}
