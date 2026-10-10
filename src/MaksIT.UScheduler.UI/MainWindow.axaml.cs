using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Interactivity;
using MaksIT.Core.Desktop.Snapshots;
using MaksIT.UScheduler.UI.Services;
using MaksIT.UScheduler.UI.ViewModels;
using MaksIT.UScheduler.UI.Windows;


namespace MaksIT.UScheduler.UI;

public partial class MainWindow : Window {
  public MainWindow() : this(null) {
  }

  public MainWindow(AppViewSnapshotOptions? snapshots) {
    InitializeComponent();
    new WindowLayout(this).Attach();
    var dialogs = new DialogService();
    var viewModel = new MainViewModel(dialogs);
    dialogs.Owner = this;
    DataContext = viewModel;
    Opened += async (_, _) => {
      if (snapshots is not null) {
        var desktop = Application.Current?.ApplicationLifetime as IClassicDesktopStyleApplicationLifetime;
        await SnapshotTour.RunAsync(this, viewModel, snapshots, code => desktop?.Shutdown(code));

        return;
      }

      await WhatsNewWindow.ShowIfNeededAsync(this);
    };
  }

  private void OnLogsClick(object? sender, RoutedEventArgs e) =>
    _ = LogWindow.ShowAsync(this);

  private void OnAboutClick(object? sender, RoutedEventArgs e) =>
    _ = AboutWindow.ShowAsync(this);
}
