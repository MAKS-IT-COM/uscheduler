using Avalonia.Controls;


namespace MaksIT.UScheduler.UI;

public partial class MainWindow : Window {
  public MainWindow() {
    InitializeComponent();
    var dialogs = new DialogService();
    var viewModel = new ViewModels.MainViewModel(dialogs);
    dialogs.Owner = this;
    DataContext = viewModel;
  }
}
