using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.UI.ViewModels;

public partial class MainViewModel {
  public ObservableCollection<SupervisedProcessRow> Processes { get; } = [];

  [ObservableProperty]
  [NotifyCanExecuteChangedFor(nameof(RemoveProcessCommand))]
  [NotifyCanExecuteChangedFor(nameof(BrowseProcessCommand))]
  private SupervisedProcessRow? selectedProcess;

  private bool CanChangeSelectedProcess() => SelectedProcess is not null;

  private bool _holdProcessSnapshot;

  [ObservableProperty]
  private bool processDirty;

  public bool HasSelectedProcess => SelectedProcess is not null;

  partial void OnSelectedProcessChanged(SupervisedProcessRow? value) {
    OnPropertyChanged(nameof(HasSelectedProcess));
    NotifyProcessCommands();
  }

  partial void OnProcessDirtyChanged(bool value) =>
    NotifyProcessCommands();

  private void LoadProcesses() {
    var selectedPath = SelectedProcess?.Path;
    foreach (var row in Processes)
      row.Edited -= OnProcessEdited;

    Processes.Clear();

    if (_serviceConfig is not null) {
      foreach (var process in _serviceConfig.Processes) {
        if (string.IsNullOrWhiteSpace(process.Path))
          continue;

        var row = SupervisedProcessRow.From(process);
        row.Edited += OnProcessEdited;
        Processes.Add(row);
      }
    }

    SelectedProcess = Processes.FirstOrDefault(row => SameProcessPath(row.Path, selectedPath ?? ""))
      ?? Processes.FirstOrDefault();
    ProcessDirty = false;
    RefreshProcessStatuses();
  }

  private void OnProcessEdited() =>
    ProcessDirty = true;

  /// <summary>
  /// Selects the Processes page content for a screenshot. An empty list gets one
  /// sample row so the editor is visible. That row is not written to settings.
  /// </summary>
  public void PrepareProcessesForSnapshot() {
    if (Processes.Count == 0) {
      var row = SupervisedProcessRow.From(new ProcessConfiguration {
        Name = "My app",
        Path = @"C:\Tools\MyApp.exe",
        Args = ["--option"],
        Directory = @"C:\Tools",
        RestartOnFailure = true,
        ThrottleMs = 1500
      });
      row.ApplyStatus("Running", "Green", new ProcessStatusEntry {
        Path = row.Path,
        State = ProcessStates.Running,
        ProcessId = 4128,
        StartedUtc = DateTimeOffset.UtcNow
      });
      Processes.Add(row);
      SelectedProcess = row;
      ProcessDirty = false;
      _holdProcessSnapshot = true;
      return;
    }

    SelectedProcess ??= Processes[0];
    RefreshProcessStatuses();
  }

  [RelayCommand]
  public void RefreshProcessStatuses() {
    if (_holdProcessSnapshot)
      return;

    var serviceRunning = ServiceStatus == HostServiceStatus.Running;
    var snapshot = ProcessStatusFileStore.Load(LogDirectory);

    foreach (var row in Processes) {
      if (string.IsNullOrWhiteSpace(row.Path)) {
        row.ApplyStatus(row.Disabled ? "Disabled" : "Set a path", "Gray", null);
        continue;
      }

      var resolved = PathHelper.ResolvePath(row.Path.Trim());
      var entry = snapshot.Processes.FirstOrDefault(item => SameProcessPath(item.Path, resolved));
      var (text, color) = ProcessRuntimeStatus.Describe(serviceRunning, row.Disabled, entry);
      row.ApplyStatus(text, color, serviceRunning ? entry : null);
    }

    NotifyProcessCommands();
  }

  [RelayCommand(CanExecute = nameof(CanStartProcess))]
  private Task StartProcess() =>
    ControlSelectedProcessAsync(ProcessControlChannel.Start, "Start program");

  [RelayCommand(CanExecute = nameof(CanStopProcess))]
  private Task StopProcess() =>
    ControlSelectedProcessAsync(ProcessControlChannel.Stop, "Stop program");

  [RelayCommand(CanExecute = nameof(CanRestartProcess))]
  private Task RestartProcess() =>
    ControlSelectedProcessAsync(ProcessControlChannel.Restart, "Restart program");

  private bool CanStartProcess() =>
    ProcessCanBeControlled()
    && SelectedProcess is { Disabled: false } row
    && row.StatusText is not ("Running" or "Restarting");

  private bool CanStopProcess() =>
    ProcessCanBeControlled()
    && SelectedProcess?.StatusText is "Running" or "Restarting";

  private bool CanRestartProcess() =>
    ProcessCanBeControlled() && SelectedProcess is { Disabled: false };

  private bool ProcessCanBeControlled() =>
    SelectedProcess is { } row
    && !ProcessDirty
    && !string.IsNullOrWhiteSpace(row.Path)
    && row.StatusText != "Service stopped";

  private async Task ControlSelectedProcessAsync(string action, string title) {
    if (SelectedProcess is null)
      return;

    if (ProcessDirty) {
      await _dialogs.ShowMessageAsync(title, "Save the program first.");
      return;
    }

    var path = SelectedProcess.Path.Trim();
    if (string.IsNullOrWhiteSpace(path)) {
      await _dialogs.ShowMessageAsync(title, "Enter a path for this program.");
      return;
    }

    var result = await ProcessControlChannel.RequestAsync(path, action);
    await _dialogs.ShowMessageAsync(title, result.Message);
    RefreshProcessStatuses();
  }

  private void NotifyProcessCommands() {
    StartProcessCommand.NotifyCanExecuteChanged();
    StopProcessCommand.NotifyCanExecuteChanged();
    RestartProcessCommand.NotifyCanExecuteChanged();
  }

  [RelayCommand]
  private void AddProcess() {
    var row = new SupervisedProcessRow();
    row.Edited += OnProcessEdited;
    Processes.Add(row);
    SelectedProcess = row;
    ProcessDirty = true;
  }

  [RelayCommand(CanExecute = nameof(CanChangeSelectedProcess))]
  private async Task BrowseProcess() {
    if (SelectedProcess is null)
      return;

    var path = await _dialogs.PickExecutableAsync();
    if (string.IsNullOrWhiteSpace(path))
      return;

    SelectedProcess.Path = path;
  }

  [RelayCommand(CanExecute = nameof(CanChangeSelectedProcess))]
  private async Task RemoveProcess() {
    if (SelectedProcess is null)
      return;

    var name = SelectedProcess.ListTitle;

    if (!await _dialogs.ConfirmAsync("Remove program", $"Remove {name} from the service?"))
      return;

    var removed = SelectedProcess;
    removed.Edited -= OnProcessEdited;
    Processes.Remove(removed);
    SelectedProcess = Processes.FirstOrDefault();

    if (await SaveProcesses())
      return;

    removed.Edited += OnProcessEdited;
    Processes.Add(removed);
    SelectedProcess = removed;
  }

  [RelayCommand]
  private async Task<bool> SaveProcesses() {
    if (_serviceConfig is null) {
      await _dialogs.ShowMessageAsync("Programs", "Shared settings were not found. Register the service to create them.");
      return false;
    }

    var configurations = new List<ProcessConfiguration>();
    var seen = new HashSet<string>(PathComparison);

    foreach (var row in Processes) {
      var configuration = row.ToConfiguration();
      if (string.IsNullOrWhiteSpace(configuration.Path)) {
        await _dialogs.ShowMessageAsync("Programs", "Enter a path for each program.");
        return false;
      }

      var resolved = PathHelper.ResolvePath(configuration.Path);
      if (!seen.Add(resolved)) {
        await _dialogs.ShowMessageAsync("Programs", $"{configuration.Path} is listed more than once.");
        return false;
      }

      configurations.Add(configuration);
    }

    _serviceConfig.Processes = configurations;

    if (!TryPersistServiceConfig()) {
      await _dialogs.ShowMessageAsync("Programs", "Could not save shared settings.");
      return false;
    }

    ProcessDirty = false;
    RefreshProcessStatuses();
    return true;
  }

  private static StringComparer PathComparison =>
    OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

  private static bool SameProcessPath(string left, string right) =>
    string.Equals(left, right, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
}
