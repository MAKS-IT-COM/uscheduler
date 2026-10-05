using System.Text.Json;
using System.Text.Json.Nodes;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>
/// Per-user UI prefs stored in roaming AppData (not next to the exe), or under
/// the portable Data folder when a portable layout is used.
/// </summary>
public class UISettings {
  /// <summary>
  /// Folder that contains MaksIT.UScheduler.UI.
  /// Empty means auto-detect (same folder, Program Files, or sibling project).
  /// </summary>
  public string ServiceBinPath { get; set; } = string.Empty;

  /// <summary>
  /// Last version whose What's New notes the user chose not to show again.
  /// </summary>
  public string? WhatsNewSeenVersion { get; set; }
}

/// <summary>
/// Service for loading and saving UI settings under the current user's AppData
/// (or the portable Data folder). Machine-wide schedule configuration lives in
/// ProgramData (or that same Data folder) via <see cref="ConfigurationFileService"/>.
/// </summary>
public class UISettingsService {
  public const string ProductFolder = HostPaths.ProductFolder;

  private readonly string _settingsFilePath;

  public bool FileExisted { get; private set; }

  public UISettingsService(string? settingsFilePath = null) {
    _settingsFilePath = string.IsNullOrWhiteSpace(settingsFilePath)
      ? HostPaths.ResolveUiSettingsFile()
      : settingsFilePath;
  }

  public UISettings Load() {
    try {
      FileExisted = File.Exists(_settingsFilePath);
      if (!FileExisted)
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
          : saved,
        WhatsNewSeenVersion = settingsNode?["WhatsNewSeenVersion"]?.GetValue<string>()
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

      var node = doc["USchedulerSettings"] as JsonObject ?? new JsonObject();
      node["ServiceBinPath"] = settings.ServiceBinPath;
      if (!string.IsNullOrWhiteSpace(settings.WhatsNewSeenVersion))
        node["WhatsNewSeenVersion"] = settings.WhatsNewSeenVersion;
      doc["USchedulerSettings"] = node;

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
