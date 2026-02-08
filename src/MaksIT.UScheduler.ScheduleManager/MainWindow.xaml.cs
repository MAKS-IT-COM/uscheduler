using System.Windows;
using MaksIT.UScheduler.ScheduleManager.ViewModels;

namespace MaksIT.UScheduler.ScheduleManager;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private void OnScheduleChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel vm)
        {
            vm.OnMonthCheckedChanged();
        }
    }
}
