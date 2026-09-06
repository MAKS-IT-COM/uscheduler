using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.UI.Models;
using MaksIT.UScheduler.UI.Services;


namespace MaksIT.UScheduler.UI.ViewModels;

public partial class MainViewModel : ObservableObject {
  private readonly IDialogService _dialogs;
  private readonly ScriptSettingsService _scriptSettingsService;
  private readonly UISettingsService _uiSettingsService;
  private readonly AppSettingsService _appSettingsService;
  private readonly ScriptStatusService _scriptStatusService;
  private readonly LogViewerService _logViewerService;
  private HostServiceManager _serviceManager;
  private Configuration? _serviceConfig;
  private ScriptSchedule? _originalSchedule;

  public MainViewModel(IDialogService dialogs) {
    _dialogs = dialogs;
    _scriptSettingsService = new ScriptSettingsService();
    _uiSettingsService = new UISettingsService();
    _appSettingsService = new AppSettingsService();
    _scriptStatusService = new ScriptStatusService();
    _logViewerService = new LogViewerService();
    _serviceManager = new HostServiceManager();

    MonthOptions = [
      new MonthOption("January"), new MonthOption("February"), new MonthOption("March"),
      new MonthOption("April"), new MonthOption("May"), new MonthOption("June"),
      new MonthOption("July"), new MonthOption("August"), new MonthOption("September"),
      new MonthOption("October"), new MonthOption("November"), new MonthOption("December")
    ];

    WeekdayOptions = [
      new WeekdayOption("Monday"), new WeekdayOption("Tuesday"), new WeekdayOption("Wednesday"),
      new WeekdayOption("Thursday"), new WeekdayOption("Friday"), new WeekdayOption("Saturday"),
      new WeekdayOption("Sunday")
    ];

    foreach (var month in MonthOptions)
      month.PropertyChanged += OnScheduleOptionChanged;

    foreach (var weekday in WeekdayOptions)
      weekday.PropertyChanged += OnScheduleOptionChanged;

    LoadUISettings();
    RefreshScripts();
    RefreshServiceStatus();
    RefreshServiceLogs();
  }

  private void OnScheduleOptionChanged(object? sender, PropertyChangedEventArgs e) {
    if (e.PropertyName == nameof(MonthOption.IsChecked))
      MarkDirty();
  }

  private void LoadUISettings() {
    var uiSettings = _uiSettingsService.Load();
    ServiceBinPath = uiSettings.ServiceBinPath ?? string.Empty;
    LoadServiceAppSettings();
  }

  private string ResolvedServiceBinPath => UISettingsService.ResolvePath(ServiceBinPath);

  private string ResolvedExecutablePath => string.IsNullOrEmpty(ResolvedServiceBinPath)
    ? string.Empty
    : Path.Combine(ResolvedServiceBinPath, HostServiceManager.GetExecutableFileName());

  private void LoadServiceAppSettings() {
    var bin = ResolvedServiceBinPath;
    var seedPath = string.IsNullOrEmpty(bin)
      ? null
      : Path.Combine(bin, ConfigurationFileService.SeedFileName);
    var sharedExists = File.Exists(HostPaths.SharedSettingsFile);
    var seedExists = !string.IsNullOrEmpty(seedPath) && File.Exists(seedPath);

    if (!sharedExists && !seedExists) {
      _serviceConfig = null;
      AppSettingsLoadError = "Set Service Bin Path to the worker folder (seed appsettings.json), or register the service to create shared settings.";
      ServiceName = string.Empty;
      LogDirectory = string.Empty;
      ScriptsDirectory = HostPaths.DefaultScriptsDirectory;
      SharedSettingsPath = HostPaths.SharedSettingsFile;
      ProcessList.Clear();
      return;
    }

    _serviceConfig = _appSettingsService.Load(bin, seedPath);
    if (_serviceConfig != null) {
      AppSettingsLoadError = null;
      _serviceManager = new HostServiceManager(_serviceConfig.ServiceName);
      ServiceName = _serviceConfig.ServiceName;
      LogDirectory = _serviceConfig.GetEffectiveLogDirectory(bin);
      ScriptsDirectory = _serviceConfig.GetEffectiveScriptsDirectory();
      SharedSettingsPath = _appSettingsService.SettingsPath ?? HostPaths.SharedSettingsFile;
      ProcessList.Clear();
      foreach (var p in _serviceConfig.Processes)
        ProcessList.Add(p);
    }
    else {
      AppSettingsLoadError = "Failed to load shared settings. Register the service once to create writable data folders.";
      ServiceName = string.Empty;
      LogDirectory = string.Empty;
      ScriptsDirectory = HostPaths.DefaultScriptsDirectory;
      SharedSettingsPath = HostPaths.SharedSettingsFile;
      ProcessList.Clear();
    }
  }

  private void SaveUISettings() {
    _uiSettingsService.Save(new UISettings {
      ServiceBinPath = ServiceBinPath
    });
  }

  #region AppSettings

  [ObservableProperty]
  private string _serviceBinPath = string.Empty;

  [ObservableProperty]
  private string _serviceName = "MaksIT.UScheduler";

  [ObservableProperty]
  private string _scriptsDirectory = HostPaths.DefaultScriptsDirectory;

  [ObservableProperty]
  private string _sharedSettingsPath = HostPaths.SharedSettingsFile;

  [ObservableProperty]
  [NotifyPropertyChangedFor(nameof(HasAppSettingsLoadError))]
  private string? _appSettingsLoadError;

  public bool HasAppSettingsLoadError =>
    !string.IsNullOrEmpty(AppSettingsLoadError);

  [RelayCommand]
  private async Task BrowseServiceBinPath() {
    var folder = await _dialogs.PickFolderAsync("Select MaksIT.UScheduler bin folder");
    if (string.IsNullOrEmpty(folder))
      return;

    ServiceBinPath = folder;
    SaveUISettings();
    LoadServiceAppSettings();
    RefreshScripts();
    RefreshServiceStatus();
    RefreshServiceLogs();
  }

  [RelayCommand]
  private void ReloadAppSettings() {
    LoadServiceAppSettings();
    RefreshScripts();
    RefreshServiceStatus();
    RefreshServiceLogs();
  }

  #endregion

  #region Service Management

  [ObservableProperty]
  private HostServiceStatus _serviceStatus = HostServiceStatus.Unknown;

  [ObservableProperty]
  private string _serviceStatusText = "Unknown";

  [ObservableProperty]
  private string _serviceStatusColor = "Gray";

  [RelayCommand]
  private void RefreshServiceStatus() {
    ServiceStatus = _serviceManager.GetStatus(ResolvedExecutablePath);
    (ServiceStatusText, ServiceStatusColor) = GetServiceStatusDisplay(ServiceStatus);
  }

  [RelayCommand]
  private async Task StartService() {
    var result = _serviceManager.Start(ResolvedExecutablePath);
    if (!result.Success)
      await _dialogs.ShowMessageAsync("Start Service", result.Message);

    RefreshServiceStatus();
  }

  [RelayCommand]
  private async Task StopService() {
    var result = _serviceManager.Stop(ResolvedExecutablePath);
    if (!result.Success)
      await _dialogs.ShowMessageAsync("Stop Service", result.Message);

    RefreshServiceStatus();
  }

  [RelayCommand]
  private async Task RegisterService() {
    if (string.IsNullOrWhiteSpace(ResolvedExecutablePath) || !File.Exists(ResolvedExecutablePath)) {
      await _dialogs.ShowMessageAsync(
        "Register Service",
        "Could not find MaksIT.UScheduler.exe. Set Service Bin Path to the Program Files install folder.");
      return;
    }

    var result = _serviceManager.Register(ResolvedExecutablePath);
    await _dialogs.ShowMessageAsync("Register Service", result.Message);
    LoadServiceAppSettings();
    RefreshScripts();
    RefreshServiceStatus();
    RefreshServiceLogs();
  }

  [RelayCommand]
  private async Task UnregisterService() {
    if (!await _dialogs.ConfirmAsync("Unregister Service", "Are you sure you want to unregister the service?"))
      return;

    var result = _serviceManager.Unregister(ResolvedExecutablePath);
    await _dialogs.ShowMessageAsync("Unregister Service", result.Message);
    RefreshServiceStatus();
  }

  private static (string statusText, string statusColor) GetServiceStatusDisplay(HostServiceStatus status) =>
    status switch {
      HostServiceStatus.Running => ("Running", "Green"),
      HostServiceStatus.Stopped => ("Stopped", "Red"),
      HostServiceStatus.StartPending => ("Starting...", "Orange"),
      HostServiceStatus.StopPending => ("Stopping...", "Orange"),
      HostServiceStatus.Paused => ("Paused", "Orange"),
      HostServiceStatus.NotInstalled => ("Not Installed", "Gray"),
      _ => ("Unknown", "Gray")
    };

  #endregion

  #region Schedule Management

  [ObservableProperty]
  private ObservableCollection<ScriptSchedule> _scripts = [];

  [ObservableProperty]
  private ObservableCollection<ProcessConfiguration> _processList = [];

  [ObservableProperty]
  private ScriptSchedule? _selectedScript;

  [ObservableProperty]
  private bool _hasSelectedScript;

  [ObservableProperty]
  private bool _scriptIsSigned = true;

  [ObservableProperty]
  private bool _scriptDisabled;

  [ObservableProperty]
  private string? _scriptName;

  private bool _isSyncingSelection;

  [ObservableProperty]
  private bool _isDirty;

  [ObservableProperty]
  private ObservableCollection<MonthOption> _monthOptions = [];

  [ObservableProperty]
  private ObservableCollection<WeekdayOption> _weekdayOptions = [];

  [ObservableProperty]
  private ObservableCollection<string> _runTimes = [];

  [ObservableProperty]
  private string? _selectedRunTime;

  [ObservableProperty]
  private string _newRunTime = "00:00";

  [ObservableProperty]
  private int _minIntervalMinutes = 10;

  partial void OnSelectedScriptChanged(ScriptSchedule? value) {
    HasSelectedScript = value != null;
    LaunchScriptCommand.NotifyCanExecuteChanged();

    _isSyncingSelection = true;
    ScriptIsSigned = value?.IsSigned ?? true;
    ScriptDisabled = value?.Disabled ?? false;
    ScriptName = value?.Name ?? string.Empty;
    _isSyncingSelection = false;

    if (value != null) {
      LoadScheduleToUI(value);
      _originalSchedule = CloneSchedule(value);
      RefreshScriptStatus();
    }
    else {
      ClearUI();
      _originalSchedule = null;
      CurrentScriptStatus = null;
    }

    IsDirty = false;
  }

  partial void OnScriptIsSignedChanged(bool value) {
    if (_isSyncingSelection || SelectedScript == null)
      return;

    SelectedScript.IsSigned = value;
    UpdateServiceConfigScriptEntry(SelectedScript.ConfigScriptPath, SelectedScript.Name, value, SelectedScript.Disabled);
  }

  partial void OnScriptDisabledChanged(bool value) {
    if (_isSyncingSelection || SelectedScript == null)
      return;

    SelectedScript.Disabled = value;
    UpdateServiceConfigScriptEntry(SelectedScript.ConfigScriptPath, SelectedScript.Name, SelectedScript.IsSigned, value);
  }

  partial void OnScriptNameChanged(string? value) {
    if (_isSyncingSelection || SelectedScript == null)
      return;

    var name = value ?? string.Empty;
    SelectedScript.Name = name;
    UpdateServiceConfigScriptEntry(SelectedScript.ConfigScriptPath, name, SelectedScript.IsSigned, SelectedScript.Disabled);
  }

  private void UpdateServiceConfigScriptEntry(string configScriptPath, string? name, bool isSigned, bool disabled) {
    if (_serviceConfig == null)
      return;

    var entry = _serviceConfig.Powershell.FirstOrDefault(p => p.Path == configScriptPath);
    if (entry != null) {
      if (name != null)
        entry.Name = name;

      entry.IsSigned = isSigned;
      entry.Disabled = disabled;
    }

    TryPersistServiceConfig();
  }

  private bool TryPersistServiceConfig() {
    if (_serviceConfig is null)
      return false;

    if (_appSettingsService.Save(_serviceConfig))
      return true;

    var prepare = _serviceManager.PrepareData(ResolvedExecutablePath);
    if (!prepare.Success)
      return false;

    return _appSettingsService.Save(_serviceConfig);
  }

  partial void OnMinIntervalMinutesChanged(int value) =>
    MarkDirty();

  [RelayCommand]
  private void RefreshScripts() {
    Scripts.Clear();
    if (_serviceConfig == null)
      return;

    foreach (var psConfig in _serviceConfig.Powershell) {
      if (string.IsNullOrEmpty(psConfig.Path))
        continue;

      var resolvedScriptPath = _appSettingsService.ResolvePathRelativeToScripts(psConfig.Path);
      var scriptDir = Path.GetDirectoryName(resolvedScriptPath);
      if (string.IsNullOrEmpty(scriptDir))
        continue;

      var settingsPath = Path.Combine(scriptDir, "scriptsettings.json");
      if (!File.Exists(settingsPath))
        continue;

      var schedule = _scriptSettingsService.LoadScheduleFromFile(settingsPath);
      if (schedule is null)
        continue;

      schedule.ConfigScriptPath = psConfig.Path;
      if (!string.IsNullOrWhiteSpace(psConfig.Name))
        schedule.Name = psConfig.Name;

      schedule.IsSigned = psConfig.IsSigned;
      schedule.Disabled = psConfig.Disabled;
      schedule.Platforms = [.. psConfig.Platforms];
      schedule.Description = !string.IsNullOrWhiteSpace(psConfig.Description)
        ? psConfig.Description
        : schedule.Description;
      Scripts.Add(schedule);
    }
  }

  [RelayCommand(CanExecute = nameof(CanLaunchScript))]
  private async Task LaunchScript() {
    if (SelectedScript == null)
      return;

    var scriptDir = Path.GetDirectoryName(SelectedScript.FilePath);
    if (string.IsNullOrEmpty(scriptDir) || !Directory.Exists(scriptDir)) {
      await _dialogs.ShowMessageAsync("Launch Script", "Script directory not found.");
      return;
    }

    try {
      var startInfo = ResolveLaunchStartInfo(scriptDir);
      if (startInfo is null) {
        await _dialogs.ShowMessageAsync(
          "Launch Script",
          $"No .bat, .sh, or .ps1 launcher found in:{Environment.NewLine}{scriptDir}");
        return;
      }

      Process.Start(startInfo);
    }
    catch (Exception ex) {
      await _dialogs.ShowMessageAsync("Launch Script", $"Failed to launch script: {ex.Message}");
    }
  }

  private static ProcessStartInfo? ResolveLaunchStartInfo(string scriptDir) {
    if (OperatingSystem.IsWindows()) {
      var bat = Directory.GetFiles(scriptDir, "*.bat").FirstOrDefault();
      if (bat is not null) {
        return new ProcessStartInfo {
          FileName = bat,
          WorkingDirectory = scriptDir,
          UseShellExecute = true
        };
      }
    }
    else {
      var sh = Directory.GetFiles(scriptDir, "*.sh").FirstOrDefault();
      if (sh is not null) {
        return new ProcessStartInfo {
          FileName = "bash",
          Arguments = sh,
          WorkingDirectory = scriptDir,
          UseShellExecute = false
        };
      }
    }

    var ps1 = Directory.GetFiles(scriptDir, "*.ps1").FirstOrDefault();
    if (ps1 is null)
      return null;

    var shell = OperatingSystem.IsWindows() ? "pwsh.exe" : "pwsh";
    return new ProcessStartInfo {
      FileName = shell,
      Arguments = $"-NoProfile -File \"{ps1}\"",
      WorkingDirectory = scriptDir,
      UseShellExecute = false
    };
  }

  private bool CanLaunchScript() =>
    SelectedScript is { IsCompatibleWithHost: true };

  [RelayCommand]
  private async Task AddRunTime() {
    if (string.IsNullOrWhiteSpace(NewRunTime))
      return;

    if (!TimeOnly.TryParse(NewRunTime, out var time)) {
      await _dialogs.ShowMessageAsync("Invalid Time", "Invalid time format. Please use HH:mm.");
      return;
    }

    var formattedTime = time.ToString("HH:mm");
    if (!RunTimes.Contains(formattedTime)) {
      RunTimes.Add(formattedTime);
      MarkDirty();
    }

    NewRunTime = "00:00";
  }

  [RelayCommand]
  private void RemoveRunTime() {
    if (SelectedRunTime is null)
      return;

    RunTimes.Remove(SelectedRunTime);
    MarkDirty();
  }

  [RelayCommand]
  private async Task SaveSchedule() {
    if (SelectedScript == null)
      return;

    try {
      UpdateScheduleFromUI(SelectedScript);
      _scriptSettingsService.SaveScheduleToFile(SelectedScript);
      _originalSchedule = CloneSchedule(SelectedScript);
      IsDirty = false;
      await _dialogs.ShowMessageAsync("Save", "Schedule saved successfully.");
    }
    catch (Exception ex) {
      await _dialogs.ShowMessageAsync("Save Error", $"Failed to save schedule: {ex.Message}");
    }
  }

  [RelayCommand]
  private void RevertSchedule() {
    if (_originalSchedule is null || SelectedScript is null)
      return;

    SelectedScript.RunMonth = [.. _originalSchedule.RunMonth];
    SelectedScript.RunWeekday = [.. _originalSchedule.RunWeekday];
    SelectedScript.RunTime = [.. _originalSchedule.RunTime];
    SelectedScript.MinIntervalMinutes = _originalSchedule.MinIntervalMinutes;
    LoadScheduleToUI(SelectedScript);
    IsDirty = false;
  }

  private void LoadScheduleToUI(ScriptSchedule schedule) {
    foreach (var month in MonthOptions)
      month.IsChecked = schedule.RunMonth.Contains(month.Name);

    foreach (var weekday in WeekdayOptions)
      weekday.IsChecked = schedule.RunWeekday.Contains(weekday.Name);

    RunTimes = new ObservableCollection<string>(schedule.RunTime);
    MinIntervalMinutes = schedule.MinIntervalMinutes;
  }

  private void UpdateScheduleFromUI(ScriptSchedule schedule) {
    schedule.RunMonth = MonthOptions.Where(m => m.IsChecked).Select(m => m.Name).ToList();
    schedule.RunWeekday = WeekdayOptions.Where(w => w.IsChecked).Select(w => w.Name).ToList();
    schedule.RunTime = RunTimes.ToList();
    schedule.MinIntervalMinutes = MinIntervalMinutes;
  }

  private void ClearUI() {
    foreach (var month in MonthOptions)
      month.IsChecked = false;

    foreach (var weekday in WeekdayOptions)
      weekday.IsChecked = false;

    RunTimes.Clear();
    MinIntervalMinutes = 10;
  }

  private void MarkDirty() {
    if (SelectedScript != null)
      IsDirty = true;
  }

  private static ScriptSchedule CloneSchedule(ScriptSchedule source) =>
    new() {
      FilePath = source.FilePath,
      Name = source.Name,
      Title = source.Title,
      ConfigScriptPath = source.ConfigScriptPath,
      IsSigned = source.IsSigned,
      Disabled = source.Disabled,
      Description = source.Description,
      Platforms = [.. source.Platforms],
      RunMonth = [.. source.RunMonth],
      RunWeekday = [.. source.RunWeekday],
      RunTime = [.. source.RunTime],
      MinIntervalMinutes = source.MinIntervalMinutes
    };

  #endregion

  #region Script Status

  [ObservableProperty]
  [NotifyPropertyChangedFor(nameof(LockStatusColor))]
  private ScriptStatus? _currentScriptStatus;

  [ObservableProperty]
  [NotifyPropertyChangedFor(nameof(LockStatusColor))]
  private bool _hasLockFile;

  public string LockStatusColor =>
    HasLockFile ? "Orange" : "Green";

  [RelayCommand]
  private void RefreshScriptStatus() {
    if (SelectedScript == null) {
      CurrentScriptStatus = null;
      HasLockFile = false;
      return;
    }

    CurrentScriptStatus = _scriptStatusService.GetScriptStatus(SelectedScript.FilePath);
    HasLockFile = CurrentScriptStatus?.HasLockFile ?? false;
  }

  [RelayCommand]
  private async Task RemoveLockFile() {
    if (CurrentScriptStatus == null || !CurrentScriptStatus.HasLockFile) {
      await _dialogs.ShowMessageAsync("Remove Lock File", "No lock file exists.");
      return;
    }

    if (!await _dialogs.ConfirmAsync(
          "Remove Lock File",
          "Remove the lock file? Only do this if the script crashed or was interrupted."))
      return;

    if (_scriptStatusService.RemoveLockFile(CurrentScriptStatus.LockFilePath)) {
      await _dialogs.ShowMessageAsync("Remove Lock File", "Lock file removed successfully.");
      RefreshScriptStatus();
    }
    else {
      await _dialogs.ShowMessageAsync("Remove Lock File", "Failed to remove lock file.");
    }
  }

  #endregion

  #region Log Viewer

  [ObservableProperty]
  private string _logDirectory = string.Empty;

  [ObservableProperty]
  private ObservableCollection<LogFileInfo> _serviceLogs = [];

  [ObservableProperty]
  private ObservableCollection<string> _scriptLogFolders = [];

  [ObservableProperty]
  private string? _selectedScriptLogFolder;

  [ObservableProperty]
  private ObservableCollection<LogFileInfo> _scriptLogFiles = [];

  [ObservableProperty]
  private LogFileInfo? _selectedLogFile;

  [ObservableProperty]
  private string _logContent = string.Empty;

  [ObservableProperty]
  private int _selectedLogTab;

  partial void OnSelectedScriptLogFolderChanged(string? value) {
    ScriptLogFiles.Clear();
    SelectedLogFile = null;
    if (string.IsNullOrEmpty(value))
      return;

    var resolvedLogDir = ResolvedLogDirectory;
    if (string.IsNullOrEmpty(resolvedLogDir))
      return;

    foreach (var log in _logViewerService.GetScriptLogs(resolvedLogDir, value))
      ScriptLogFiles.Add(log);
  }

  partial void OnSelectedLogFileChanged(LogFileInfo? value) {
    LogContent = value is null ? string.Empty : _logViewerService.ReadLogFile(value.FullPath);
  }

  private string ResolvedLogDirectory =>
    _serviceConfig?.GetEffectiveLogDirectory(ResolvedServiceBinPath) ?? string.Empty;

  [RelayCommand]
  private void RefreshServiceLogs() {
    ServiceLogs.Clear();
    var resolvedLogDir = ResolvedLogDirectory;
    if (string.IsNullOrEmpty(resolvedLogDir))
      return;

    foreach (var log in _logViewerService.GetServiceLogs(resolvedLogDir))
      ServiceLogs.Add(log);

    RefreshScriptLogs();
  }

  [RelayCommand]
  private void RefreshScriptLogs() {
    ScriptLogFolders.Clear();
    SelectedScriptLogFolder = null;
    ScriptLogFiles.Clear();
    SelectedLogFile = null;

    var resolvedLogDir = ResolvedLogDirectory;
    if (string.IsNullOrEmpty(resolvedLogDir))
      return;

    foreach (var name in _logViewerService.GetScriptLogFolderNames(resolvedLogDir))
      ScriptLogFolders.Add(name);

    if (ScriptLogFolders.Count > 0)
      SelectedScriptLogFolder = ScriptLogFolders[0];
  }

  [RelayCommand]
  private void RefreshLogContent() {
    if (SelectedLogFile != null)
      LogContent = _logViewerService.ReadLogFile(SelectedLogFile.FullPath);
  }

  [RelayCommand]
  private async Task OpenLogInExplorer() {
    if (SelectedLogFile == null)
      return;

    try {
      ShellOpen.RevealFile(SelectedLogFile.FullPath);
    }
    catch (Exception ex) {
      await _dialogs.ShowMessageAsync("Error", $"Failed to open folder: {ex.Message}");
    }
  }

  [RelayCommand]
  private async Task OpenLogDirectory() {
    var resolvedLogDir = ResolvedLogDirectory;
    if (string.IsNullOrEmpty(resolvedLogDir) || !Directory.Exists(resolvedLogDir)) {
      await _dialogs.ShowMessageAsync("Error", "Log directory not found.");
      return;
    }

    try {
      ShellOpen.OpenDirectory(resolvedLogDir);
    }
    catch (Exception ex) {
      await _dialogs.ShowMessageAsync("Error", $"Failed to open folder: {ex.Message}");
    }
  }

  #endregion
}

public partial class MonthOption : ObservableObject {
  public string Name { get; }

  [ObservableProperty]
  private bool _isChecked;

  public MonthOption(string name) {
    Name = name;
  }
}

public partial class WeekdayOption : ObservableObject {
  public string Name { get; }

  [ObservableProperty]
  private bool _isChecked;

  public WeekdayOption(string name) {
    Name = name;
  }
}
