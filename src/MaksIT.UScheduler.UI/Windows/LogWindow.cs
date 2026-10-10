using Avalonia.Controls;
using MaksIT.Core.UI.Logs;
using MaksIT.UScheduler.Shared;
using CoreLog = MaksIT.Core.UI.Logs.LogWindow;


namespace MaksIT.UScheduler.UI.Windows;

public static class LogWindow {
  public static Task ShowAsync(Window owner) =>
    Create(owner).ShowDialog(owner);

  public static Window Create(Window owner) {
    var options = new DesktopLogOptions {
      Directory = AppLog.Directory
    };
    var text = options.ResolveText();

    return new CoreLog {
      Title = text.Title,
      Icon = owner.Icon,
      DataContext = new LogViewModel(options.Directory, text),
      WindowStartupLocation = WindowStartupLocation.CenterOwner
    };
  }
}
