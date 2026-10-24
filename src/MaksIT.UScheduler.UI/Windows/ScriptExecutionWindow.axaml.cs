using System.ComponentModel;
using System.Collections.Specialized;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.Input.Platform;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.UI.ViewModels;
using MaksIT.UScheduler.UI.Controls.Footer;


namespace MaksIT.UScheduler.UI.Windows;

public partial class ScriptExecutionWindow : Window {
  private readonly ScriptExecutionViewModel _model;
  private readonly FooterLabel _status;
  private bool _scrollQueued;

  public ScriptExecutionWindow() : this(new ScriptExecutionViewModel("Script", "", 0)) {
  }

  public ScriptExecutionWindow(ScriptExecutionViewModel model) {
    _model = model;
    DataContext = model;
    InitializeComponent();
    _status = new FooterLabel(model.Status) {
      Foreground = new SolidColorBrush(Color.Parse("#E8F4FC"))
    };
    WireFooter();
    model.PropertyChanged += OnModelPropertyChanged;
    model.Lines.CollectionChanged += OnLinesChanged;
    Closed += (_, _) => {
      model.PropertyChanged -= OnModelPropertyChanged;
      model.Lines.CollectionChanged -= OnLinesChanged;
      model.Dispose();
    };
  }

  public void Follow(string title, long startLength) =>
    _model.Follow(title, startLength);

  private void OnModelPropertyChanged(object? sender, PropertyChangedEventArgs e) {
    if (e.PropertyName == nameof(ScriptExecutionViewModel.Status))
      _status.Text = _model.Status;
  }

  private void OnLinesChanged(object? sender, NotifyCollectionChangedEventArgs e) {
    if (_scrollQueued || _model.Lines.Count == 0)
      return;

    _scrollQueued = true;
    Dispatcher.UIThread.Post(() => {
      _scrollQueued = false;

      if (_model.Lines.Count > 0)
        OutputList.ScrollIntoView(_model.Lines[^1]);
    }, DispatcherPriority.Background);
  }

  private void WireFooter() {
    Actions.Items = [
      _status,
      new FooterButton("Copy", new AsyncRelayCommand(CopyAsync)) { Edge = FooterEdge.Trailing },
      new FooterButton("Close", new RelayCommand(Close)) {
        Edge = FooterEdge.Trailing,
        IsCancel = true
      }
    ];
  }

  private async Task CopyAsync() {
    var clipboard = Clipboard;

    if (clipboard is null)
      return;

    try {
      await clipboard.SetTextAsync(_model.Output);
      _status.Text = "Copied";
    }
    catch (Exception ex) {
      _status.Text = ex.Message;
    }
  }
}
