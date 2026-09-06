using Avalonia.Controls;
using Avalonia.Interactivity;


namespace MaksIT.UScheduler.UI;

public partial class ConfirmDialog : Window {
  public ConfirmDialog() {
    InitializeComponent();
  }

  public ConfirmDialog(string title, string message) {
    InitializeComponent();
    Title = title;
    MessageText.Text = message;
  }

  public static async Task<bool> ShowAsync(Window owner, string title, string message) {
    var dialog = new ConfirmDialog(title, message);
    return await dialog.ShowDialog<bool>(owner);
  }

  private void Ok_Click(object? sender, RoutedEventArgs e) =>
    Close(true);

  private void Cancel_Click(object? sender, RoutedEventArgs e) =>
    Close(false);
}
