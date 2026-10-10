using System.Text.Json;
using System.Text.Json.Nodes;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>
/// Per-user UI prefs stored in roaming AppData (not next to the exe), or under
/// the portable Data folder when a portable layout is used.
/// </summary>
public class UISettings {
  public const double DefaultWindowWidth = 1100;

  public const double DefaultWindowHeight = 800;

  /// <summary>
  /// Last version whose What's New notes the user chose not to show again.
  /// </summary>
  public string? WhatsNewSeenVersion { get; set; }

  public double WindowWidth { get; set; } = DefaultWindowWidth;

  public double WindowHeight { get; set; } = DefaultWindowHeight;

  public int? WindowX { get; set; }

  public int? WindowY { get; set; }

  public string WindowState { get; set; } = "Normal";
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
        return new UISettings();

      var json = File.ReadAllText(_settingsFilePath);
      var doc = JsonNode.Parse(json);

      if (doc == null)
        return new UISettings();

      var settingsNode = doc["USchedulerSettings"];

      return new UISettings {
        WhatsNewSeenVersion = settingsNode?["WhatsNewSeenVersion"]?.GetValue<string>(),
        WindowWidth = ReadDouble(settingsNode, "WindowWidth", UISettings.DefaultWindowWidth),
        WindowHeight = ReadDouble(settingsNode, "WindowHeight", UISettings.DefaultWindowHeight),
        WindowX = ReadInt(settingsNode, "WindowX"),
        WindowY = ReadInt(settingsNode, "WindowY"),
        WindowState = settingsNode?["WindowState"]?.GetValue<string>() is { Length: > 0 } state
          ? state
          : "Normal"
      };
    }
    catch {
      return new UISettings();
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
      node.Remove("ServiceBinPath");

      if (!string.IsNullOrWhiteSpace(settings.WhatsNewSeenVersion))
        node["WhatsNewSeenVersion"] = settings.WhatsNewSeenVersion;

      node["WindowWidth"] = settings.WindowWidth;
      node["WindowHeight"] = settings.WindowHeight;
      node["WindowState"] = string.IsNullOrWhiteSpace(settings.WindowState) ? "Normal" : settings.WindowState;

      if (settings.WindowX is int x)
        node["WindowX"] = x;
      else
        node.Remove("WindowX");

      if (settings.WindowY is int y)
        node["WindowY"] = y;
      else
        node.Remove("WindowY");

      doc["USchedulerSettings"] = node;

      var options = new JsonWriterOptions { Indented = true };
      using var stream = File.Create(_settingsFilePath);
      using var writer = new Utf8JsonWriter(stream, options);
      doc.WriteTo(writer);
    }
    catch {
    }
  }

  public string SettingsFilePath =>
    _settingsFilePath;

  private static double ReadDouble(JsonNode? node, string name, double fallback) {
    try {
      var value = node?[name]?.GetValue<double>();

      return value is null || double.IsNaN(value.Value) || double.IsInfinity(value.Value)
        ? fallback
        : value.Value;
    }
    catch (Exception ex) when (ex is InvalidOperationException or FormatException) {
      return fallback;
    }
  }

  private static int? ReadInt(JsonNode? node, string name) {
    try {
      return node?[name]?.GetValue<int>();
    }
    catch (Exception ex) when (ex is InvalidOperationException or FormatException) {
      return null;
    }
  }
}
