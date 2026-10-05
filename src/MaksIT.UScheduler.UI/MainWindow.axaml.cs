using Avalonia.Controls;
using Avalonia.Interactivity;
using MaksIT.UScheduler.UI.Windows;


namespace MaksIT.UScheduler.UI;

public partial class MainWindow : Window {
  public MainWindow() {
    InitializeComponent();
    var dialogs = new DialogService();
    var viewModel = new ViewModels.MainViewModel(dialogs);
    dialogs.Owner = this;
    DataContext = viewModel;
    Opened += async (_, _) => await WhatsNewWindow.ShowIfNeededAsync(this);
  }

  private void OnLogsClick(object? sender, RoutedEventArgs e) =>
    _ = LogWindow.ShowAsync(this);

  private void OnAboutClick(object? sender, RoutedEventArgs e) =>
    _ = AboutWindow.ShowAsync(this);
}
