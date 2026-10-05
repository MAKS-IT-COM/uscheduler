using Avalonia;
using Avalonia.Controls;
using Avalonia.Input.Platform;
using Avalonia.Media;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.UI.Controls.Footer;


namespace MaksIT.UScheduler.UI;

public partial class MessageDialog : Window {
  public MessageDialog() {
    InitializeComponent();
    WireFooter();
  }

  public MessageDialog(string title, string message) {
    InitializeComponent();
    Title = title;
    MessageText.Text = message;
    WireFooter();
  }

  public static async Task ShowAsync(Window owner, string title, string message) {
    var dialog = new MessageDialog(title, message);
    await dialog.ShowDialog(owner);
  }

  private void WireFooter() {
    var status = new FooterLabel("") {
      Edge = FooterEdge.Trailing,
      IsVisible = false,
      Foreground = new SolidColorBrush(Color.Parse("#9aa0a6"))
    };
    Actions.Items = [
      status,
      new FooterButton("Copy", new AsyncRelayCommand(() => CopyAsync(status))) { Edge = FooterEdge.Trailing },
      new FooterButton("OK", new RelayCommand(Close)) {
        Edge = FooterEdge.Trailing,
        IsDefault = true,
        IsCancel = true
      }
    ];
  }

  private async Task CopyAsync(FooterLabel status) {
    var clipboard = Clipboard;
    if (clipboard is null)
      return;

    try {
      await clipboard.SetTextAsync(MessageText.Text ?? string.Empty);
      status.Text = "Copied";
      status.IsVisible = true;
    }
    catch (Exception ex) {
      status.Text = ex.Message;
      status.IsVisible = true;
    }
  }
}
