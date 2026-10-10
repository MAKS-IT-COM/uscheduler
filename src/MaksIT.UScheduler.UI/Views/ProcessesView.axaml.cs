using Avalonia.Controls;
using Avalonia.Threading;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.UI.Views;

public partial class ProcessesView : UserControl {
  private DispatcherTimer? _timer;

  public ProcessesView() {
    InitializeComponent();
    AttachedToVisualTree += (_, _) => StartTimer();
    DetachedFromVisualTree += (_, _) => _timer?.Stop();
  }

  private void StartTimer() {
    _timer?.Stop();
    _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
    _timer.Tick += (_, _) => {
      if (DataContext is MainViewModel model)
        model.RefreshProcessStatuses();
    };
    _timer.Start();
  }
}
