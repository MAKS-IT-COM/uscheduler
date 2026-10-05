using Avalonia;
using Avalonia.Controls;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.UI.Controls.Footer;
using MaksIT.UScheduler.UI.Services;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.UI.Windows;

public partial class WhatsNewWindow : Window {
  private bool _footerReady;

  public WhatsNewWindow() {
    InitializeComponent();
    DataContextChanged += (_, _) => WireFooter();
  }

  public static async Task ShowIfNeededAsync(Window owner) {
    var current = AppInfo.Version;

    if (string.IsNullOrWhiteSpace(current))
      return;

    var settings = new UISettingsService();
    var ui = settings.Load();

    if (!settings.FileExisted) {
      Remember(settings, ui, current);

      return;
    }

    var notes = ReleaseNotes.AddedSince(ReleaseNotes.Text(), ui.WhatsNewSeenVersion, current);

    if (notes.Count == 0)
      return;

    var model = new WhatsNewViewModel(notes);
    var window = new WhatsNewWindow {
      DataContext = model,
      WindowStartupLocation = WindowStartupLocation.CenterOwner
    };
    await window.ShowDialog(owner);

    if (model.DoNotShowAgain)
      Remember(settings, ui, current);
  }

  private static void Remember(UISettingsService settings, UISettings ui, string version) {
    if (string.Equals(ui.WhatsNewSeenVersion, version, StringComparison.Ordinal))
      return;

    ui.WhatsNewSeenVersion = version;
    settings.Save(ui);
  }

  private void WireFooter() {
    if (_footerReady || DataContext is not WhatsNewViewModel model)
      return;

    _footerReady = true;
    var remember = new FooterCheck("Do not show again");
    remember.PropertyChanged += (_, e) => {
      if (e.PropertyName == nameof(FooterCheck.IsChecked))
        model.DoNotShowAgain = remember.IsChecked;
    };
    Actions.Items = [
      remember,
      new FooterButton("Close", new RelayCommand(Close)) {
        Edge = FooterEdge.Trailing,
        IsDefault = true,
        IsCancel = true,
        Padding = new Thickness(12, 7)
      }
    ];
  }
}
