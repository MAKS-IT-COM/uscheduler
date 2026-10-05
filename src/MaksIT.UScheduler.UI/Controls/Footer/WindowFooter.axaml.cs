using System.Collections.ObjectModel;
using System.Collections.Specialized;
using Avalonia;
using Avalonia.Controls;


namespace MaksIT.UScheduler.UI.Controls.Footer;

public partial class WindowFooter : UserControl {
  public static readonly StyledProperty<IReadOnlyList<FooterItem>?> ItemsProperty =
    AvaloniaProperty.Register<WindowFooter, IReadOnlyList<FooterItem>?>(nameof(Items));

  public static readonly StyledProperty<double> SpacingProperty =
    AvaloniaProperty.Register<WindowFooter, double>(nameof(Spacing), 6);

  private INotifyCollectionChanged? _changes;

  public WindowFooter() {
    InitializeComponent();
    IsVisible = false;
  }

  public IReadOnlyList<FooterItem>? Items {
    get => GetValue(ItemsProperty);
    set => SetValue(ItemsProperty, value);
  }

  public double Spacing {
    get => GetValue(SpacingProperty);
    set => SetValue(SpacingProperty, value);
  }

  public ObservableCollection<FooterItem> Leading { get; } = [];

  public ObservableCollection<FooterItem> Trailing { get; } = [];

  protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change) {
    base.OnPropertyChanged(change);

    if (change.Property == ItemsProperty)
      Rewire();
  }

  private void Rewire() {
    if (_changes is not null)
      _changes.CollectionChanged -= OnItemsChanged;

    _changes = Items as INotifyCollectionChanged;

    if (_changes is not null)
      _changes.CollectionChanged += OnItemsChanged;

    Split();
  }

  private void OnItemsChanged(object? sender, NotifyCollectionChangedEventArgs e) =>
    Split();

  private void Split() {
    Leading.Clear();
    Trailing.Clear();

    if (Items is not null) {
      foreach (var item in Items) {
        if (item.Edge == FooterEdge.Trailing)
          Trailing.Add(item);
        else
          Leading.Add(item);
      }
    }

    var visible = Leading.Count > 0 || Trailing.Count > 0;
    if (IsVisible != visible)
      IsVisible = visible;
  }
}
