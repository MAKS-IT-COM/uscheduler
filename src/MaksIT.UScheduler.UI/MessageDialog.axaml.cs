using Avalonia.Controls;
using Avalonia.Interactivity;


namespace MaksIT.UScheduler.UI;

public partial class MessageDialog : Window {
  public MessageDialog() {
    InitializeComponent();
  }

  public MessageDialog(string title, string message) {
    InitializeComponent();
    Title = title;
    MessageText.Text = message;
  }

  public static async Task ShowAsync(Window owner, string title, string message) {
    var dialog = new MessageDialog(title, message);
    await dialog.ShowDialog(owner);
  }

  private void Ok_Click(object? sender, RoutedEventArgs e) =>
    Close();
}
