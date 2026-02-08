using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;

namespace MaksIT.UScheduler.ScheduleManager.Services;

/// <summary>
/// Service for loading and managing appsettings.json from UScheduler.
/// </summary>
public class AppSettingsService
{
    private string? _appSettingsPath;
    private JsonNode? _rootDocument;

    /// <summary>
    /// Gets the path to the appsettings.json file.
    /// </summary>
    public string? AppSettingsPath => _appSettingsPath;

    /// <summary>
    /// Gets the directory containing appsettings.json (the service directory).
    /// </summary>
    public string? ServiceDirectory => string.IsNullOrEmpty(_appSettingsPath) 
        ? null 
        : System.IO.Path.GetDirectoryName(_appSettingsPath);

    /// <summary>
    /// Loads appsettings.json from the specified path.
    /// Returns null if path is null/empty or the file does not exist.
    /// </summary>
    public Configuration? LoadAppSettings(string? appSettingsPath = null)
    {
        _appSettingsPath = appSettingsPath;

        if (string.IsNullOrEmpty(_appSettingsPath) || !File.Exists(_appSettingsPath))
            return null;

        try
        {
            var json = File.ReadAllText(_appSettingsPath);
            _rootDocument = JsonNode.Parse(json);

            if (_rootDocument == null)
                return null;

            var configNode = _rootDocument["Configuration"];
            if (configNode == null)
                return new Configuration { LogDir = ".\\Logs" };

            var config = new Configuration
            {
                ServiceName = configNode["ServiceName"]?.GetValue<string>() ?? "MaksIT.UScheduler",
                LogDir = configNode["LogDir"]?.GetValue<string>() ?? ".\\Logs"
            };

            // Parse PowerShell scripts
            if (configNode["Powershell"] is JsonArray psArray)
            {
                foreach (var item in psArray)
                {
                    if (item == null) continue;
                    config.Powershell.Add(new PowershellScript
                    {
                        Path = item["Path"]?.GetValue<string>() ?? string.Empty,
                        Name = item["Name"]?.GetValue<string>(),
                        IsSigned = item["IsSigned"]?.GetValue<bool>() ?? true,
                        Disabled = item["Disabled"]?.GetValue<bool>() ?? false
                    });
                }
            }

            // Parse Processes
            if (configNode["Processes"] is JsonArray procArray)
            {
                foreach (var item in procArray)
                {
                    if (item == null) continue;
                    var proc = new ProcessConfiguration
                    {
                        Path = item["Path"]?.GetValue<string>() ?? string.Empty,
                        RestartOnFailure = item["RestartOnFailure"]?.GetValue<bool>() ?? false,
                        Disabled = item["Disabled"]?.GetValue<bool>() ?? false
                    };

                    if (item["Args"] is JsonArray argsArray)
                    {
                        proc.Args = argsArray.Select(a => a?.GetValue<string>() ?? "").ToArray();
                    }

                    config.Processes.Add(proc);
                }
            }

            return config;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Gets the resolved log directory path from the service config.
    /// LogDir may be relative (e.g. ".\Logs"); it is resolved against the service directory, same as script paths.
    /// </summary>
    public string GetLogDirectory(Configuration? config)
    {
        if (config == null || string.IsNullOrEmpty(ServiceDirectory))
            return string.Empty;

        if (!string.IsNullOrEmpty(config.LogDir))
            return ResolvePathRelativeToService(config.LogDir);

        // Default: Logs folder in service directory
        return System.IO.Path.Combine(ServiceDirectory, "Logs");
    }

    /// <summary>
    /// Gets the service executable path.
    /// </summary>
    public string GetExecutablePath()
    {
        if (string.IsNullOrEmpty(ServiceDirectory))
            return string.Empty;

        var exePath = System.IO.Path.Combine(ServiceDirectory, "MaksIT.UScheduler.exe");
        return File.Exists(exePath) ? exePath : string.Empty;
    }

    /// <summary>
    /// Reads the LogDir value from MaksIT.UScheduler's appsettings.json at the given path.
    /// The path should be the full path to appsettings.json (e.g. ServiceBinPath + "appsettings.json").
    /// Returns null if the file doesn't exist or Configuration.LogDir is missing.
    /// </summary>
    public static string? GetLogDirFromAppSettingsFile(string appSettingsFilePath)
    {
        if (string.IsNullOrEmpty(appSettingsFilePath) || !File.Exists(appSettingsFilePath))
            return null;

        try
        {
            var json = File.ReadAllText(appSettingsFilePath);
            var doc = JsonNode.Parse(json);
            var configNode = doc?["Configuration"];
            return configNode?["LogDir"]?.GetValue<string>();
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Updates Name, IsSigned and Disabled for a PowerShell script entry in appsettings and saves the file.
    /// The script is identified by its config path (e.g. ".\file-sync.ps1").
    /// Pass null for name to leave the existing Name value unchanged.
    /// </summary>
    public bool UpdatePowershellScriptEntry(string configScriptPath, string? name, bool isSigned, bool disabled)
    {
        if (string.IsNullOrEmpty(_appSettingsPath) || _rootDocument == null)
            return false;

        var configNode = _rootDocument["Configuration"];
        if (configNode?["Powershell"] is not JsonArray psArray)
            return false;

        for (var i = 0; i < psArray.Count; i++)
        {
            if (psArray[i] is not JsonObject item)
                continue;
            var path = item["Path"]?.GetValue<string>();
            if (path != configScriptPath)
                continue;

            if (name != null)
                item["Name"] = name;
            item["IsSigned"] = isSigned;
            item["Disabled"] = disabled;

            try
            {
                var options = new JsonWriterOptions { Indented = true };
                using var stream = File.Create(_appSettingsPath);
                using var writer = new Utf8JsonWriter(stream, options);
                _rootDocument.WriteTo(writer);
            }
            catch
            {
                return false;
            }

            return true;
        }

        return false;
    }

    /// <summary>
    /// Resolves a path relative to the service directory (where appsettings.json is located).
    /// If the path is already absolute, returns it as-is.
    /// </summary>
    public string ResolvePathRelativeToService(string path) =>
        PathHelper.ResolvePath(path, ServiceDirectory ?? string.Empty);
}
