using Avalonia;
using Avalonia.Controls;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.UI.Controls.Footer;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.UI.Windows;

public partial class AboutWindow : Window {
  private bool _footerReady;

  public AboutWindow() {
    InitializeComponent();
    DataContextChanged += (_, _) => WireFooter();
  }

  public static Task ShowAsync(Window owner) {
    var window = new AboutWindow {
      DataContext = new AboutViewModel(),
      WindowStartupLocation = WindowStartupLocation.CenterOwner
    };

    return window.ShowDialog(owner);
  }

  private void WireFooter() {
    if (_footerReady || DataContext is not AboutViewModel about)
      return;

    _footerReady = true;
    Actions.Items = [
      new FooterButton(about.Site, about.OpenSiteCommand) {
        Edge = FooterEdge.Trailing,
        Padding = new Thickness(12, 7)
      },
      new FooterButton("Close", new RelayCommand(Close)) {
        Edge = FooterEdge.Trailing,
        IsDefault = true,
        IsCancel = true,
        Padding = new Thickness(12, 7)
      }
    ];
  }
}
