using System.Windows.Input;
using Avalonia;
using Avalonia.Media;
using CommunityToolkit.Mvvm.ComponentModel;


namespace MaksIT.UScheduler.UI.Controls.Footer;

public enum FooterEdge {
  Leading,
  Trailing
}

/// <summary>
/// One piece of a page footer. The page composes these; the shell only displays them.
/// </summary>
public abstract class FooterItem : ObservableObject {
  public FooterEdge Edge { get; init; } = FooterEdge.Leading;

  public Thickness Margin { get; init; }
}

public sealed partial class FooterButton : FooterItem {
  public FooterButton(string label, ICommand command) {
    Text = label;
    Command = command;
  }

  public ICommand Command { get; }

  public object? CommandParameter { get; init; }

  public string? ToolTip { get; init; }

  public bool IsDefault { get; init; }

  public bool IsCancel { get; init; }

  public FontWeight FontWeight { get; init; } = FontWeight.Normal;

  public Thickness Padding { get; init; } = new(10, 4);

  [ObservableProperty]
  private string text;
}

public sealed partial class FooterLabel : FooterItem {
  public FooterLabel(string label) {
    Text = label;
  }

  public IBrush? Foreground { get; init; }

  public FontWeight FontWeight { get; init; } = FontWeight.Normal;

  [ObservableProperty]
  private string text;

  [ObservableProperty]
  private bool isVisible = true;
}

public sealed partial class FooterCheck : FooterItem {
  public FooterCheck(string text, bool isChecked = false) {
    Text = text;
    IsChecked = isChecked;
  }

  public string Text { get; }

  [ObservableProperty]
  private bool isChecked;
}
