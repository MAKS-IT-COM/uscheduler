using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>
/// Loads and saves machine-wide service configuration (ProgramData settings.json).
/// Shipped appsettings.json next to the worker is seed-only.
/// </summary>
public class AppSettingsService {
  private ConfigurationFileService? _files;
  private string? _serviceDirectory;

  public string? SettingsPath => _files?.FilePath;

  public string? ServiceDirectory => _serviceDirectory;

  public string ScriptsDirectory { get; private set; } = HostPaths.DefaultScriptsDirectory;

  public Configuration? Load(string? serviceDirectory = null, string? seedPath = null) {
    _serviceDirectory = serviceDirectory;
    var seed = seedPath;
    if (string.IsNullOrEmpty(seed) && !string.IsNullOrEmpty(serviceDirectory))
      seed = Path.Combine(serviceDirectory, ConfigurationFileService.SeedFileName);

    _files = new ConfigurationFileService(HostPaths.SharedSettingsFile, seed);
    var config = _files.Current;
    config.EnsureDefaults();
    ScriptsDirectory = config.GetEffectiveScriptsDirectory();
    return config;
  }

  public bool Save(Configuration configuration) {
    if (_files is null)
      return false;

    try {
      _files.Save(configuration);
      ScriptsDirectory = configuration.GetEffectiveScriptsDirectory();
      return true;
    }
    catch {
      return false;
    }
  }

  public string GetExecutablePath() {
    if (string.IsNullOrEmpty(_serviceDirectory))
      return string.Empty;

    var exePath = Path.Combine(_serviceDirectory, HostServiceManager.GetExecutableFileName());
    return File.Exists(exePath) ? exePath : string.Empty;
  }

  public bool UpdatePowershellScriptEntry(string configScriptPath, string? name, bool isSigned, bool disabled) {
    if (_files is null)
      return false;

    var config = _files.Current;
    var entry = config.Powershell.FirstOrDefault(p => p.Path == configScriptPath);
    if (entry is null)
      return false;

    if (name != null)
      entry.Name = name;
    entry.IsSigned = isSigned;
    entry.Disabled = disabled;
    return Save(config);
  }

  public string ResolvePathRelativeToScripts(string path) =>
    PathHelper.ResolvePath(path, ScriptsDirectory);
}
