using Avalonia.Media;
using Avalonia;
using CommunityToolkit.Mvvm.ComponentModel;
using MaksIT.UScheduler.UI.Controls.Footer;


namespace MaksIT.UScheduler.UI.ViewModels;

public sealed partial class ScriptsPage : ObservableObject, IShellPage {
  private readonly MainViewModel _shell;
  private string _shape = "";

  public ScriptsPage(MainViewModel shell) {
    _shell = shell;
    _shell.PropertyChanged += (_, e) => {
      if (e.PropertyName is nameof(MainViewModel.HasSelectedScript)
          or nameof(MainViewModel.IsDirty)
          or nameof(MainViewModel.HasLockFile)
          or nameof(MainViewModel.SelectedScript))
        Sync();
    };
    Sync();
  }

  public string Header => "Main";

  [ObservableProperty]
  private IReadOnlyList<FooterItem> footerItems = [];

  private void Sync() {
    var next = Build();
    var shape = string.Join('|', next.Select(ShapeOf));
    if (shape == _shape)
      return;

    _shape = shape;
    FooterItems = next;
  }

  private List<FooterItem> Build() {
    var items = new List<FooterItem> {
      new FooterButton("Refresh", _shell.RefreshScriptsCommand)
    };

    if (!_shell.HasSelectedScript)
      return items;

    if (_shell.IsDirty) {
      items.Add(new FooterLabel("* Unsaved changes") {
        Edge = FooterEdge.Trailing,
        Foreground = new SolidColorBrush(Color.Parse("#ff4d6d")),
        FontWeight = FontWeight.SemiBold,
        Margin = new Avalonia.Thickness(0, 0, 12, 0)
      });
    }

    items.Add(new FooterButton("Revert", _shell.RevertScheduleCommand) { Edge = FooterEdge.Trailing });
    items.Add(new FooterButton("Save", _shell.SaveScheduleCommand) {
      Edge = FooterEdge.Trailing,
      FontWeight = FontWeight.Bold
    });

    if (_shell.HasLockFile)
      items.Add(new FooterButton("Remove Lock", _shell.RemoveLockFileCommand) { Edge = FooterEdge.Trailing });

    items.Add(new FooterButton("Refresh Status", _shell.RefreshScriptStatusCommand) { Edge = FooterEdge.Trailing });

    if (_shell.SelectedScript is { IsCompatibleWithHost: true }) {
      items.Add(new FooterButton("Launch", _shell.LaunchScriptCommand) {
        Edge = FooterEdge.Trailing,
        ToolTip = "Ask the running service to start this script"
      });
    }

    return items;
  }

  private static string ShapeOf(FooterItem item) =>
    item switch {
      FooterButton button => "button:" + button.Text,
      FooterLabel label => "label:" + label.Text,
      _ => item.GetType().Name
    };
}

public sealed partial class LogsPage : ObservableObject, IShellPage {
  private readonly MainViewModel _shell;
  private string _shape = "";

  public LogsPage(MainViewModel shell) {
    _shell = shell;
    _shell.PropertyChanged += (_, e) => {
      if (e.PropertyName == nameof(MainViewModel.SelectedLogFile))
        Sync();
    };
    Sync();
  }

  public string Header => "Logs";

  [ObservableProperty]
  private IReadOnlyList<FooterItem> footerItems = [];

  private void Sync() {
    var next = Build();
    var shape = string.Join('|', next.Select(item => item is FooterButton button ? button.Text : item.GetType().Name));
    if (shape == _shape)
      return;

    _shape = shape;
    FooterItems = next;
  }

  private List<FooterItem> Build() {
    var items = new List<FooterItem> {
      new FooterButton("Refresh", _shell.RefreshServiceLogsCommand),
      new FooterButton("Open Folder", _shell.OpenLogDirectoryCommand)
    };

    if (_shell.SelectedLogFile is null)
      return items;

    items.Add(new FooterButton("Refresh", _shell.RefreshLogContentCommand) { Edge = FooterEdge.Trailing });
    items.Add(new FooterButton("Show in folder", _shell.OpenLogInExplorerCommand) { Edge = FooterEdge.Trailing });
    return items;
  }
}

public sealed partial class ProcessesPage : ObservableObject, IShellPage {
  private readonly MainViewModel _shell;
  private string _shape = "";

  public ProcessesPage(MainViewModel shell) {
    _shell = shell;
    _shell.PropertyChanged += (_, e) => {
      if (e.PropertyName is nameof(MainViewModel.HasSelectedProcess) or nameof(MainViewModel.ProcessDirty))
        Sync();
    };
    Sync();
  }

  public string Header => "Processes";

  [ObservableProperty]
  private IReadOnlyList<FooterItem> footerItems = [];

  private void Sync() {
    var next = Build();
    var shape = string.Join('|', next.Select(item => item switch {
      FooterButton button => "button:" + button.Text,
      FooterLabel label => "label:" + label.Text,
      _ => item.GetType().Name
    }));
    if (shape == _shape)
      return;

    _shape = shape;
    FooterItems = next;
  }

  private List<FooterItem> Build() {
    var items = new List<FooterItem> {
      new FooterButton("Add", _shell.AddProcessCommand),
      new FooterButton("Remove", _shell.RemoveProcessCommand),
      new FooterButton("Save", _shell.SaveProcessesCommand) { FontWeight = FontWeight.Bold }
    };

    if (_shell.ProcessDirty) {
      items.Add(new FooterLabel("* Unsaved changes") {
        Edge = FooterEdge.Trailing,
        Foreground = new SolidColorBrush(Color.Parse("#ff4d6d")),
        FontWeight = FontWeight.SemiBold,
        Margin = new Avalonia.Thickness(0, 0, 12, 0)
      });
    }

    items.Add(new FooterButton("Refresh", _shell.RefreshProcessStatusesCommand) { Edge = FooterEdge.Trailing });

    if (!_shell.HasSelectedProcess)
      return items;

    items.Add(new FooterButton("Start", _shell.StartProcessCommand) {
      Edge = FooterEdge.Trailing,
      ToolTip = "Ask the running service to start this program"
    });
    items.Add(new FooterButton("Stop", _shell.StopProcessCommand) {
      Edge = FooterEdge.Trailing,
      ToolTip = "Stop this program until you start it"
    });
    items.Add(new FooterButton("Restart", _shell.RestartProcessCommand) {
      Edge = FooterEdge.Trailing,
      ToolTip = "Stop this program and start it again"
    });
    return items;
  }
}

public sealed partial class SettingsPage : ObservableObject, IShellPage {
  public SettingsPage(MainViewModel shell) {
    FooterItems = [
      new FooterButton("Register", shell.RegisterServiceCommand),
      new FooterButton("Unregister", shell.UnregisterServiceCommand),
      new FooterButton("Start", shell.StartServiceCommand),
      new FooterButton("Stop", shell.StopServiceCommand),
      new FooterButton("Refresh", shell.RefreshServiceStatusCommand),
      new FooterButton("Open logs", shell.OpenLogDirectoryCommand) { Edge = FooterEdge.Trailing }
    ];
  }

  public string Header => "Settings";

  public IReadOnlyList<FooterItem> FooterItems { get; }
}
