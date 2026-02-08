using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.ScheduleManager.Models;
using MaksIT.UScheduler.ScheduleManager.Services;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;

namespace MaksIT.UScheduler.ScheduleManager.ViewModels;

public partial class MainViewModel : ObservableObject
{
    /// <summary>
    /// Returns true if the current process is running as administrator.
    /// </summary>
    public bool IsAdmin
    {
        get
        {
            try
            {
                var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
                var principal = new System.Security.Principal.WindowsPrincipal(identity);
                return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }
            catch
            {
                return false;
            }
        }
    }
    private readonly ScriptSettingsService _scriptSettingsService;
    private readonly UISettingsService _uiSettingsService;
    private readonly AppSettingsService _appSettingsService;
    private readonly ScriptStatusService _scriptStatusService;
    private readonly LogViewerService _logViewerService;
    private WindowsServiceManager _serviceManager;
    private Configuration? _serviceConfig;
    private ScriptSchedule? _originalSchedule;

    public MainViewModel()
    {
        _scriptSettingsService = new ScriptSettingsService();
        _uiSettingsService = new UISettingsService();
        _appSettingsService = new AppSettingsService();
        _scriptStatusService = new ScriptStatusService();
        _logViewerService = new LogViewerService();
        _serviceManager = new WindowsServiceManager();

        // Initialize month/weekday options
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

        // Load UI settings first (stored paths)
        LoadUISettings();

        // Initial load
        RefreshScripts();
        RefreshServiceStatus();
        RefreshServiceLogs();
    }

    /// <summary>
    /// Loads UI settings from the ScheduleManager's appsettings.json.
    /// If paths are empty, tries auto-detection.
    /// </summary>
    private void LoadUISettings()
    {
        var uiSettings = _uiSettingsService.Load();

        // Use stored bin path - no auto-detection, user will configure manually if empty
        ServiceBinPath = uiSettings.ServiceBinPath ?? string.Empty;

        // Load the UScheduler's appsettings.json to get service config
        LoadServiceAppSettings();
    }

    /// <summary>
    /// Gets the resolved service bin path (absolute path).
    /// </summary>
    private string ResolvedServiceBinPath => UISettingsService.ResolvePath(ServiceBinPath);

    /// <summary>
    /// Gets the resolved appsettings.json path from the service bin folder.
    /// </summary>
    private string ResolvedAppSettingsPath => string.IsNullOrEmpty(ResolvedServiceBinPath) 
        ? string.Empty 
        : Path.Combine(ResolvedServiceBinPath, "appsettings.json");

    /// <summary>
    /// Gets the resolved executable path from the service bin folder.
    /// </summary>
    private string ResolvedExecutablePath => string.IsNullOrEmpty(ResolvedServiceBinPath) 
        ? string.Empty 
        : Path.Combine(ResolvedServiceBinPath, "MaksIT.UScheduler.exe");

    /// <summary>
    /// Loads the UScheduler's appsettings.json from the path in ScheduleManager appsettings (ServiceBinPath).
    /// LogDir is read from that file and evaluated against the UScheduler program path (ServiceBinPath).
    /// </summary>
    private void LoadServiceAppSettings()
    {
        // Path to UScheduler appsettings = path from ScheduleManager appsettings (ServiceBinPath) + appsettings.json
        var uschedulerAppSettingsPath = ResolvedAppSettingsPath;

        if (!string.IsNullOrEmpty(uschedulerAppSettingsPath) && File.Exists(uschedulerAppSettingsPath))
        {
            _serviceConfig = _appSettingsService.LoadAppSettings(uschedulerAppSettingsPath);
        }
        else
        {
            _serviceConfig = null;
        }

        if (_serviceConfig != null)
        {
            AppSettingsLoadError = null;
            // Update service manager with correct service name
            _serviceManager = new WindowsServiceManager(_serviceConfig.ServiceName);
            ServiceName = _serviceConfig.ServiceName;
            // Log dir: retrieve from MaksIT.UScheduler appsettings.json, show relative path in UI (e.g. ".\Logs")
            // Configuration.LogDir is required, so it is always set when _serviceConfig is loaded.
            LogDirectory = AppSettingsService.GetLogDirFromAppSettingsFile(uschedulerAppSettingsPath)
                ?? _serviceConfig.LogDir;
            // Refresh process list for Processes Management tab
            ProcessList.Clear();
            foreach (var p in _serviceConfig.Processes)
                ProcessList.Add(p);
        }
        else
        {
            // appsettings.json not loaded — surface error; do not use fake defaults
            AppSettingsLoadError = string.IsNullOrEmpty(uschedulerAppSettingsPath) || !File.Exists(uschedulerAppSettingsPath)
                ? "Service Bin Path must be set and must point to a folder that contains appsettings.json."
                : "Failed to load appsettings.json. Ensure the file is valid and contains required settings (e.g. LogDir).";
            ServiceName = string.Empty;
            LogDirectory = string.Empty;
            ProcessList.Clear();
        }
    }

    /// <summary>
    /// Saves the current paths to the UI's appsettings.json.
    /// </summary>
    private void SaveUISettings()
    {
        var settings = new UISettings
        {
            ServiceBinPath = ServiceBinPath
        };
        _uiSettingsService.Save(settings);
    }

    #region AppSettings

    [ObservableProperty]
    private string _serviceBinPath = string.Empty;

    [ObservableProperty]
    private string _serviceName = "MaksIT.UScheduler";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(AppSettingsLoadErrorVisibility))]
    private string? _appSettingsLoadError;

    /// <summary>
    /// Visibility for the app settings load error message (Visible when <see cref="AppSettingsLoadError"/> is set).
    /// </summary>
    public Visibility AppSettingsLoadErrorVisibility =>
        string.IsNullOrEmpty(AppSettingsLoadError) ? Visibility.Collapsed : Visibility.Visible;

    [RelayCommand]
    private void BrowseServiceBinPath()
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = "Select MaksIT.UScheduler bin folder"
        };

        if (dialog.ShowDialog() == true)
        {
            ServiceBinPath = dialog.FolderName;
            SaveUISettings();
            LoadServiceAppSettings();
            RefreshScripts();
            RefreshServiceStatus();
            RefreshServiceLogs();
        }
    }

    [RelayCommand]
    private void ReloadAppSettings()
    {
        LoadServiceAppSettings();
        RefreshScripts();
        RefreshServiceStatus();
        RefreshServiceLogs();
    }

    [RelayCommand]
    private void SavePaths()
    {
        SaveUISettings();
        MessageBox.Show("Paths saved successfully.", "Save", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    #endregion

    #region Service Management

    [ObservableProperty]
    private ServiceStatus _serviceStatus = ServiceStatus.Unknown;

    [ObservableProperty]
    private string _serviceStatusText = "Unknown";

    [ObservableProperty]
    private string _serviceStatusColor = "Gray";

    [RelayCommand]
    private void RefreshServiceStatus()
    {
        ServiceStatus = _serviceManager.GetStatus(ResolvedExecutablePath);
        (ServiceStatusText, ServiceStatusColor) = GetServiceStatusDisplay(ServiceStatus);
    }

    [RelayCommand]
    private void StartService()
    {
        var result = _serviceManager.Start(ResolvedExecutablePath);
        if (!result.Success)
        {
            MessageBox.Show(result.Message, "Start Service", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        RefreshServiceStatus();
    }

    [RelayCommand]
    private void StopService()
    {
        var result = _serviceManager.Stop(ResolvedExecutablePath);
        if (!result.Success)
        {
            MessageBox.Show(result.Message, "Stop Service", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        RefreshServiceStatus();
    }

    [RelayCommand]
    private void RegisterService()
    {
        if (string.IsNullOrWhiteSpace(ServiceBinPath))
        {
            MessageBox.Show("Please specify the path to MaksIT.UScheduler bin folder", "Register Service", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var result = _serviceManager.Register(ResolvedExecutablePath);
        MessageBox.Show(result.Message, "Register Service", 
            MessageBoxButton.OK, result.Success ? MessageBoxImage.Information : MessageBoxImage.Warning);
        RefreshServiceStatus();
    }

    [RelayCommand]
    private void UnregisterService()
    {
        var confirm = MessageBox.Show(
            "Are you sure you want to unregister the service?", 
            "Unregister Service", 
            MessageBoxButton.YesNo, 
            MessageBoxImage.Question);

        if (confirm != MessageBoxResult.Yes)
            return;

        var result = _serviceManager.Unregister(ResolvedExecutablePath);
        MessageBox.Show(result.Message, "Unregister Service", 
            MessageBoxButton.OK, result.Success ? MessageBoxImage.Information : MessageBoxImage.Warning);
        RefreshServiceStatus();
    }

    private static (string statusText, string statusColor) GetServiceStatusDisplay(ServiceStatus status)
    {
        return status switch
        {
            ServiceStatus.Running => ("Running", "Green"),
            ServiceStatus.Stopped => ("Stopped", "Red"),
            ServiceStatus.StartPending => ("Starting...", "Orange"),
            ServiceStatus.StopPending => ("Stopping...", "Orange"),
            ServiceStatus.Paused => ("Paused", "Orange"),
            ServiceStatus.NotInstalled => ("Not Installed", "Gray"),
            _ => ("Unknown", "Gray")
        };
    }

    #endregion

    #region Schedule Management

    [ObservableProperty]
    private ObservableCollection<ScriptSchedule> _scripts = [];

    /// <summary>
    /// Process entries from service config (for Processes Management tab).
    /// </summary>
    [ObservableProperty]
    private ObservableCollection<ProcessConfiguration> _processList = [];

    [ObservableProperty]
    private ScriptSchedule? _selectedScript;

    [ObservableProperty]
    private bool _hasSelectedScript;

    /// <summary>Require script to be digitally signed (from service config).</summary>
    [ObservableProperty]
    private bool _scriptIsSigned = true;

    /// <summary>Script disabled and will not be executed (from service config).</summary>
    [ObservableProperty]
    private bool _scriptDisabled;

    /// <summary>Display name for the selected script (from service config; editable).</summary>
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

    partial void OnSelectedScriptChanged(ScriptSchedule? value)
    {
        HasSelectedScript = value != null;
        LaunchScriptCommand.NotifyCanExecuteChanged();

        _isSyncingSelection = true;
        ScriptIsSigned = value?.IsSigned ?? true;
        ScriptDisabled = value?.Disabled ?? false;
        ScriptName = value?.Name ?? string.Empty;
        _isSyncingSelection = false;

        if (value != null)
        {
            LoadScheduleToUI(value);
            _originalSchedule = CloneSchedule(value);
            RefreshScriptStatus();
        }
        else
        {
            ClearUI();
            _originalSchedule = null;
            CurrentScriptStatus = null;
        }
        
        IsDirty = false;
    }

    partial void OnScriptIsSignedChanged(bool value)
    {
        if (_isSyncingSelection || SelectedScript == null)
            return;
        SelectedScript.IsSigned = value;
        UpdateServiceConfigScriptEntry(SelectedScript.ConfigScriptPath, SelectedScript.Name, value, SelectedScript.Disabled);
    }

    partial void OnScriptDisabledChanged(bool value)
    {
        if (_isSyncingSelection || SelectedScript == null)
            return;
        SelectedScript.Disabled = value;
        UpdateServiceConfigScriptEntry(SelectedScript.ConfigScriptPath, SelectedScript.Name, SelectedScript.IsSigned, value);
    }

    partial void OnScriptNameChanged(string? value)
    {
        if (_isSyncingSelection || SelectedScript == null)
            return;
        var name = value ?? string.Empty;
        SelectedScript.Name = name;
        UpdateServiceConfigScriptEntry(SelectedScript.ConfigScriptPath, name, SelectedScript.IsSigned, SelectedScript.Disabled);
    }

    private void UpdateServiceConfigScriptEntry(string configScriptPath, string? name, bool isSigned, bool disabled)
    {
        if (_serviceConfig == null)
            return;
        var entry = _serviceConfig.Powershell.FirstOrDefault(p => p.Path == configScriptPath);
        if (entry != null)
        {
            if (name != null)
                entry.Name = name;
            entry.IsSigned = isSigned;
            entry.Disabled = disabled;
        }
        _appSettingsService.UpdatePowershellScriptEntry(configScriptPath, name, isSigned, disabled);
    }

    partial void OnMinIntervalMinutesChanged(int value)
    {
        MarkDirty();
    }

    [RelayCommand]
    private void RefreshScripts()
    {
        Scripts.Clear();
        
        // Load scripts from service configuration (MaksIT.UScheduler appsettings.json)
        if (_serviceConfig != null)
        {
            foreach (var psConfig in _serviceConfig.Powershell)
            {
                if (string.IsNullOrEmpty(psConfig.Path))
                    continue;

                // Resolve relative path against service directory
                var resolvedScriptPath = _appSettingsService.ResolvePathRelativeToService(psConfig.Path);
                var scriptDir = Path.GetDirectoryName(resolvedScriptPath);
                
                if (string.IsNullOrEmpty(scriptDir))
                    continue;

                // scriptsettings.json should be in the same folder as the script
                var settingsPath = Path.Combine(scriptDir, "scriptsettings.json");
                
                if (File.Exists(settingsPath))
                {
                    var schedule = _scriptSettingsService.LoadScheduleFromFile(settingsPath);
                    if (schedule != null)
                    {
                        schedule.ConfigScriptPath = psConfig.Path;
                        if (!string.IsNullOrWhiteSpace(psConfig.Name))
                            schedule.Name = psConfig.Name;
                        schedule.IsSigned = psConfig.IsSigned;
                        schedule.Disabled = psConfig.Disabled;
                        Scripts.Add(schedule);
                    }
                }
            }
        }
    }

    /// <summary>
    /// Launches the selected script via its .bat file in a separate window.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanLaunchScript))]
    private void LaunchScript()
    {
        if (SelectedScript == null)
            return;

        var scriptDir = Path.GetDirectoryName(SelectedScript.FilePath);
        if (string.IsNullOrEmpty(scriptDir) || !Directory.Exists(scriptDir))
        {
            MessageBox.Show("Script directory not found.", "Launch Script",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var batFiles = Directory.GetFiles(scriptDir, "*.bat");
        if (batFiles.Length == 0)
        {
            MessageBox.Show($"No .bat file found in script folder.\n{scriptDir}", "Launch Script",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            var batPath = batFiles[0];
            var startInfo = new ProcessStartInfo
            {
                FileName = batPath,
                WorkingDirectory = scriptDir,
                UseShellExecute = true,
                CreateNoWindow = false
            };
            Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to launch script: {ex.Message}", "Launch Script",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private bool CanLaunchScript() => SelectedScript != null;

    [RelayCommand]
    private void AddRunTime()
    {
        if (string.IsNullOrWhiteSpace(NewRunTime))
            return;

        // Validate time format
        if (!TimeOnly.TryParse(NewRunTime, out var time))
        {
            MessageBox.Show("Invalid time format. Please use HH:mm format.", "Invalid Time", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var formattedTime = time.ToString("HH:mm");
        
        if (!RunTimes.Contains(formattedTime))
        {
            RunTimes.Add(formattedTime);
            MarkDirty();
        }
        
        NewRunTime = "00:00";
    }

    [RelayCommand]
    private void RemoveRunTime()
    {
        if (SelectedRunTime != null)
        {
            RunTimes.Remove(SelectedRunTime);
            MarkDirty();
        }
    }

    [RelayCommand]
    private void SaveSchedule()
    {
        if (SelectedScript == null)
            return;

        try
        {
            // Update the selected script from UI
            UpdateScheduleFromUI(SelectedScript);
            
            // Save to file
            _scriptSettingsService.SaveScheduleToFile(SelectedScript);
            
            // Update original for dirty tracking
            _originalSchedule = CloneSchedule(SelectedScript);
            IsDirty = false;

            MessageBox.Show("Schedule saved successfully.", "Save", 
                MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to save schedule: {ex.Message}", "Save Error", 
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    [RelayCommand]
    private void RevertSchedule()
    {
        if (_originalSchedule != null && SelectedScript != null)
        {
            // Copy original values back
            SelectedScript.RunMonth = new List<string>(_originalSchedule.RunMonth);
            SelectedScript.RunWeekday = new List<string>(_originalSchedule.RunWeekday);
            SelectedScript.RunTime = new List<string>(_originalSchedule.RunTime);
            SelectedScript.MinIntervalMinutes = _originalSchedule.MinIntervalMinutes;
            
            LoadScheduleToUI(SelectedScript);
            IsDirty = false;
        }
    }

    public void OnMonthCheckedChanged()
    {
        MarkDirty();
    }

    public void OnWeekdayCheckedChanged()
    {
        MarkDirty();
    }

    private void LoadScheduleToUI(ScriptSchedule schedule)
    {
        // Load months
        foreach (var month in MonthOptions)
        {
            month.IsChecked = schedule.RunMonth.Contains(month.Name);
        }

        // Load weekdays
        foreach (var weekday in WeekdayOptions)
        {
            weekday.IsChecked = schedule.RunWeekday.Contains(weekday.Name);
        }

        // Load times
        RunTimes = new ObservableCollection<string>(schedule.RunTime);

        // Load interval
        MinIntervalMinutes = schedule.MinIntervalMinutes;
    }

    private void UpdateScheduleFromUI(ScriptSchedule schedule)
    {
        schedule.RunMonth = MonthOptions.Where(m => m.IsChecked).Select(m => m.Name).ToList();
        schedule.RunWeekday = WeekdayOptions.Where(w => w.IsChecked).Select(w => w.Name).ToList();
        schedule.RunTime = RunTimes.ToList();
        schedule.MinIntervalMinutes = MinIntervalMinutes;
    }

    private void ClearUI()
    {
        foreach (var month in MonthOptions) month.IsChecked = false;
        foreach (var weekday in WeekdayOptions) weekday.IsChecked = false;
        RunTimes.Clear();
        MinIntervalMinutes = 10;
    }

    private void MarkDirty()
    {
        if (SelectedScript != null)
        {
            IsDirty = true;
        }
    }

    private static ScriptSchedule CloneSchedule(ScriptSchedule source)
    {
        return new ScriptSchedule
        {
            FilePath = source.FilePath,
            Name = source.Name,
            Title = source.Title,
            ConfigScriptPath = source.ConfigScriptPath,
            IsSigned = source.IsSigned,
            Disabled = source.Disabled,
            RunMonth = new List<string>(source.RunMonth),
            RunWeekday = new List<string>(source.RunWeekday),
            RunTime = new List<string>(source.RunTime),
            MinIntervalMinutes = source.MinIntervalMinutes
        };
    }

    #endregion

    #region Script Status (Lock File, Last Run)

    [ObservableProperty]
    private ScriptStatus? _currentScriptStatus;

    [ObservableProperty]
    private bool _hasLockFile;

    [RelayCommand]
    private void RefreshScriptStatus()
    {
        if (SelectedScript == null)
        {
            CurrentScriptStatus = null;
            HasLockFile = false;
            return;
        }

        CurrentScriptStatus = _scriptStatusService.GetScriptStatus(SelectedScript.FilePath);
        HasLockFile = CurrentScriptStatus?.HasLockFile ?? false;
    }

    [RelayCommand]
    private void RemoveLockFile()
    {
        if (CurrentScriptStatus == null || !CurrentScriptStatus.HasLockFile)
        {
            MessageBox.Show("No lock file exists.", "Remove Lock File", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var confirm = MessageBox.Show(
            "Are you sure you want to remove the lock file?\n\n" +
            "This should only be done if the script crashed or was interrupted.\n" +
            "Removing the lock while the script is running may cause issues.",
            "Remove Lock File",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes)
            return;

        if (_scriptStatusService.RemoveLockFile(CurrentScriptStatus.LockFilePath))
        {
            MessageBox.Show("Lock file removed successfully.", "Remove Lock File", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            RefreshScriptStatus();
        }
        else
        {
            MessageBox.Show("Failed to remove lock file.", "Remove Lock File", 
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    #endregion

    #region Log Viewer

    [ObservableProperty]
    private string _logDirectory = string.Empty;

    [ObservableProperty]
    private ObservableCollection<LogFileInfo> _serviceLogs = [];

    /// <summary>Script log folder names (e.g. file-sync, hyper-v-backup) under LogDir.</summary>
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

    partial void OnSelectedScriptLogFolderChanged(string? value)
    {
        ScriptLogFiles.Clear();
        SelectedLogFile = null;

        if (string.IsNullOrEmpty(value))
            return;

        var resolvedLogDir = ResolvedLogDirectory;
        if (string.IsNullOrEmpty(resolvedLogDir))
            return;

        var logs = _logViewerService.GetScriptLogs(resolvedLogDir, value);
        foreach (var log in logs)
        {
            ScriptLogFiles.Add(log);
        }
    }

    partial void OnSelectedLogFileChanged(LogFileInfo? value)
    {
        if (value != null)
        {
            LoadLogContent(value.FullPath);
        }
        else
        {
            LogContent = string.Empty;
        }
    }

    [RelayCommand]
    private void BrowseLogDirectory()
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = "Select Log Directory"
        };

        if (dialog.ShowDialog() == true)
        {
            LogDirectory = dialog.FolderName;
            RefreshServiceLogs();
            RefreshScriptLogs();
        }
    }

    /// <summary>
    /// Gets the resolved log directory path for reading logs. LogDir (e.g. .\logs) is always resolved
    /// against ServiceBinPath so the result is e.g. ..\..\..\..\MaksIT.UScheduler\bin\Debug\net10.0\win-x64\logs.
    /// </summary>
    private string ResolvedLogDirectory
    {
        get
        {
            if (string.IsNullOrEmpty(ResolvedServiceBinPath))
                return string.Empty;
            // Configuration.LogDir is required; fallback only when config is not loaded.
            var logDir = _serviceConfig != null ? _serviceConfig.LogDir : ".\\logs";
            return PathHelper.ResolvePath(logDir, ResolvedServiceBinPath);
        }
    }

    [RelayCommand]
    private void RefreshServiceLogs()
    {
        ServiceLogs.Clear();

        var resolvedLogDir = ResolvedLogDirectory;
        if (string.IsNullOrEmpty(resolvedLogDir))
            return;

        var logs = _logViewerService.GetServiceLogs(resolvedLogDir);
        foreach (var log in logs)
        {
            ServiceLogs.Add(log);
        }

        // Also refresh script logs so the Script Logs tab stays in sync
        RefreshScriptLogs();
    }

    [RelayCommand]
    private void RefreshScriptLogs()
    {
        ScriptLogFolders.Clear();
        SelectedScriptLogFolder = null;
        ScriptLogFiles.Clear();
        SelectedLogFile = null;

        var resolvedLogDir = ResolvedLogDirectory;
        if (string.IsNullOrEmpty(resolvedLogDir))
            return;

        var folderNames = _logViewerService.GetScriptLogFolderNames(resolvedLogDir);
        foreach (var name in folderNames)
        {
            ScriptLogFolders.Add(name);
        }

        if (ScriptLogFolders.Count > 0)
        {
            SelectedScriptLogFolder = ScriptLogFolders[0];
        }
    }

    [RelayCommand]
    private void RefreshLogContent()
    {
        if (SelectedLogFile != null)
        {
            LoadLogContent(SelectedLogFile.FullPath);
        }
    }

    [RelayCommand]
    private void OpenLogInExplorer()
    {
        if (SelectedLogFile == null)
            return;

        try
        {
            System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{SelectedLogFile.FullPath}\"");
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to open explorer: {ex.Message}", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    [RelayCommand]
    private void OpenLogDirectory()
    {
        var resolvedLogDir = ResolvedLogDirectory;
        if (string.IsNullOrEmpty(resolvedLogDir) || !Directory.Exists(resolvedLogDir))
        {
            MessageBox.Show("Log directory not found.", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            System.Diagnostics.Process.Start("explorer.exe", resolvedLogDir);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to open explorer: {ex.Message}", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void LoadLogContent(string filePath)
    {
        LogContent = _logViewerService.ReadLogFile(filePath);
    }

    #endregion

}

/// <summary>
/// Represents a month checkbox option.
/// </summary>
public partial class MonthOption : ObservableObject
{
    public string Name { get; }

    [ObservableProperty]
    private bool _isChecked;

    public MonthOption(string name)
    {
        Name = name;
    }
}

/// <summary>
/// Represents a weekday checkbox option.
/// </summary>
public partial class WeekdayOption : ObservableObject
{
    public string Name { get; }

    [ObservableProperty]
    private bool _isChecked;

    public WeekdayOption(string name)
    {
        Name = name;
    }
}
