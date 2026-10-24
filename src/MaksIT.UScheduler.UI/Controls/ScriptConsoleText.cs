using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Threading;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.UI.Controls;

/// <summary>
/// One script log line. The color is set on this text block so the list cannot paint every line with the window foreground.
/// </summary>
public class ScriptConsoleText : TextBlock {
  private bool _applying;

  protected override void OnDataContextChanged(EventArgs e) {
    base.OnDataContextChanged(e);
    Apply();
  }

  protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e) {
    base.OnAttachedToVisualTree(e);
    Apply();
    Dispatcher.UIThread.Post(() => {
      if (VisualRoot is not null)
        Apply();
    }, DispatcherPriority.Render);
  }

  protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change) {
    base.OnPropertyChanged(change);

    if (change.Property == ForegroundProperty && !_applying)
      Apply();
  }

  private void Apply() {
    if (_applying || DataContext is not ScriptConsoleLine line)
      return;

    _applying = true;
    Text = line.Text;

    if (Foreground is not SolidColorBrush brush || brush.Color != line.Color)
      Foreground = new SolidColorBrush(line.Color);

    _applying = false;
  }
}
