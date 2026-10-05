using Avalonia;
using Avalonia.Controls;
using Avalonia.Input.Platform;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.UI.Controls.Footer;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.UI.Windows;

public partial class LogWindow : Window {
  private bool _footerReady;

  public LogWindow() {
    InitializeComponent();
    DataContextChanged += (_, _) => WireFooter();
  }

  public static Task ShowAsync(Window owner) {
    var window = new LogWindow {
      DataContext = new LogViewModel(),
      WindowStartupLocation = WindowStartupLocation.CenterOwner
    };

    return window.ShowDialog(owner);
  }

  private void WireFooter() {
    if (_footerReady || DataContext is not LogViewModel logs)
      return;

    _footerReady = true;
    var status = new FooterLabel("") {
      Edge = FooterEdge.Trailing,
      IsVisible = false
    };
    logs.PropertyChanged += (_, e) => {
      if (e.PropertyName != nameof(LogViewModel.CopyStatus))
        return;

      status.Text = logs.CopyStatus;
      status.IsVisible = logs.CopyStatus.Length > 0;
    };
    Actions.Items = [
      status,
      new FooterButton("Copy", new AsyncRelayCommand(CopyAsync)) { Edge = FooterEdge.Trailing },
      new FooterButton("Close", new RelayCommand(Close)) {
        Edge = FooterEdge.Trailing,
        IsDefault = true,
        IsCancel = true,
        Padding = new Thickness(16, 8)
      }
    ];
  }

  private async Task CopyAsync() {
    if (DataContext is not LogViewModel logs)
      return;

    var clipboard = Clipboard;

    if (clipboard is null)
      return;

    try {
      await clipboard.SetTextAsync(logs.Report);
      logs.MarkCopied();
    }
    catch {
    }
  }
}
