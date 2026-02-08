using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using MaksIT.UScheduler.Shared.Helpers;

namespace MaksIT.UScheduler.ScheduleManager.Services;

/// <summary>
/// UI-specific settings stored in the ScheduleManager's appsettings.json.
/// </summary>
public class UISettings
{
    /// <summary>
    /// Path to the MaksIT.UScheduler bin folder containing appsettings.json and MaksIT.UScheduler.exe.
    /// </summary>
    public string ServiceBinPath { get; set; } = string.Empty;
}

/// <summary>
/// Service for loading and saving the ScheduleManager's own appsettings.json.
/// </summary>
public class UISettingsService
{
    private readonly string _settingsFilePath;

    public UISettingsService()
    {
        _settingsFilePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "appsettings.json");
    }

    /// <summary>
    /// Loads the UI settings from appsettings.json.
    /// </summary>
    public UISettings Load()
    {
        try
        {
            if (!File.Exists(_settingsFilePath))
                return new UISettings();

            var json = File.ReadAllText(_settingsFilePath);
            var doc = JsonNode.Parse(json);

            if (doc == null)
                return new UISettings();

            var settingsNode = doc["USchedulerSettings"];
            if (settingsNode == null)
                return new UISettings();

            return new UISettings
            {
                ServiceBinPath = settingsNode["ServiceBinPath"]?.GetValue<string>() ?? string.Empty
            };
        }
        catch
        {
            return new UISettings();
        }
    }

    /// <summary>
    /// Saves the UI settings to appsettings.json.
    /// </summary>
    public void Save(UISettings settings)
    {
        try
        {
            JsonNode? doc;

            // Load existing file or create new
            if (File.Exists(_settingsFilePath))
            {
                var json = File.ReadAllText(_settingsFilePath);
                doc = JsonNode.Parse(json) ?? new JsonObject();
            }
            else
            {
                doc = new JsonObject();
            }

            // Update the USchedulerSettings section
            doc["USchedulerSettings"] = new JsonObject
            {
                ["ServiceBinPath"] = settings.ServiceBinPath
            };

            // Write back
            var options = new JsonWriterOptions { Indented = true };
            using var stream = File.Create(_settingsFilePath);
            using var writer = new Utf8JsonWriter(stream, options);
            doc.WriteTo(writer);
        }
        catch
        {
            // Ignore save errors
        }
    }

    /// <summary>
    /// Gets the path to the UI's appsettings.json file.
    /// </summary>
    public string SettingsFilePath => _settingsFilePath;

    /// <summary>
    /// Resolves a path relative to the application's base directory.
    /// If the path is already absolute, returns it as-is.
    /// </summary>
    public static string ResolvePath(string path) => PathHelper.ResolvePath(path);
}
