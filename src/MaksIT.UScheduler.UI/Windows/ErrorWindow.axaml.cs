using Avalonia;
using Avalonia.Controls;
using Avalonia.Input.Platform;
using Avalonia.Media;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.UI.Controls.Footer;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.UI.Windows;

public partial class ErrorWindow : Window {
  private bool _footerReady;

  public ErrorWindow() {
    InitializeComponent();
    DataContextChanged += (_, _) => WireFooter();
  }

  private void WireFooter() {
    if (_footerReady || DataContext is not ErrorReportViewModel report)
      return;

    _footerReady = true;
    var status = new FooterLabel("") {
      Edge = FooterEdge.Trailing,
      IsVisible = false,
      Foreground = new SolidColorBrush(Color.Parse("#9aa0a6"))
    };
    report.PropertyChanged += (_, e) => {
      if (e.PropertyName != nameof(ErrorReportViewModel.CopyStatus))
        return;

      status.Text = report.CopyStatus;
      status.IsVisible = report.CopyStatus.Length > 0;
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
    if (DataContext is not ErrorReportViewModel report)
      return;

    var clipboard = Clipboard;
    if (clipboard is null)
      return;

    try {
      await clipboard.SetTextAsync(report.Report);
      report.MarkCopied();
    }
    catch {
    }
  }
}
