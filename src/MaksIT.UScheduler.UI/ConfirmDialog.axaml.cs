using Avalonia.Controls;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.UI.Controls.Footer;


namespace MaksIT.UScheduler.UI;

public partial class ConfirmDialog : Window {
  public ConfirmDialog() {
    InitializeComponent();
    WireFooter();
  }

  public ConfirmDialog(string title, string message) {
    InitializeComponent();
    Title = title;
    MessageText.Text = message;
    WireFooter();
  }

  public static async Task<bool> ShowAsync(Window owner, string title, string message) {
    var dialog = new ConfirmDialog(title, message);
    return await dialog.ShowDialog<bool>(owner);
  }

  private void WireFooter() {
    Actions.Items = [
      new FooterButton("OK", new RelayCommand(() => Close(true))) {
        Edge = FooterEdge.Trailing,
        IsDefault = true
      },
      new FooterButton("Cancel", new RelayCommand(() => Close(false))) {
        Edge = FooterEdge.Trailing,
        IsCancel = true
      }
    ];
  }
}
