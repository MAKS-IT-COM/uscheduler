using System.Text.Json;
using System.Text.Json.Nodes;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>
/// Per-user UI prefs stored in roaming AppData (not next to the exe).
/// </summary>
public class UISettings {
  /// <summary>
  /// Path to the MaksIT.UScheduler bin folder containing the worker executable.
  /// Empty means auto-detect (same folder, Program Files, or sibling project).
  /// </summary>
  public string ServiceBinPath { get; set; } = string.Empty;
}

/// <summary>
/// Service for loading and saving UI settings under the current user's AppData.
/// Machine-wide schedule configuration lives in ProgramData via
/// <see cref="ConfigurationFileService"/>.
/// </summary>
public class UISettingsService {
  public const string ProductFolder = HostPaths.ProductFolder;

  private readonly string _settingsFilePath;

  public UISettingsService() {
    _settingsFilePath = UserSettingsPath.Get(ProductFolder);
  }

  public UISettings Load() {
    try {
      if (!File.Exists(_settingsFilePath))
        return new UISettings { ServiceBinPath = HostPaths.DetectServiceBinPath() };

      var json = File.ReadAllText(_settingsFilePath);
      var doc = JsonNode.Parse(json);
      if (doc == null)
        return new UISettings { ServiceBinPath = HostPaths.DetectServiceBinPath() };

      var settingsNode = doc["USchedulerSettings"];
      var saved = settingsNode?["ServiceBinPath"]?.GetValue<string>() ?? string.Empty;
      return new UISettings {
        ServiceBinPath = string.IsNullOrWhiteSpace(saved)
          ? HostPaths.DetectServiceBinPath()
          : saved
      };
    }
    catch {
      return new UISettings { ServiceBinPath = HostPaths.DetectServiceBinPath() };
    }
  }

  public void Save(UISettings settings) {
    try {
      var dir = Path.GetDirectoryName(_settingsFilePath);
      if (!string.IsNullOrEmpty(dir))
        Directory.CreateDirectory(dir);

      JsonNode? doc;
      if (File.Exists(_settingsFilePath)) {
        var json = File.ReadAllText(_settingsFilePath);
        doc = JsonNode.Parse(json) ?? new JsonObject();
      }
      else {
        doc = new JsonObject();
      }

      doc["USchedulerSettings"] = new JsonObject {
        ["ServiceBinPath"] = settings.ServiceBinPath
      };

      var options = new JsonWriterOptions { Indented = true };
      using var stream = File.Create(_settingsFilePath);
      using var writer = new Utf8JsonWriter(stream, options);
      doc.WriteTo(writer);
    }
    catch {
    }
  }

  public string SettingsFilePath => _settingsFilePath;

  public static string ResolvePath(string path) => PathHelper.ResolvePath(path);
}
