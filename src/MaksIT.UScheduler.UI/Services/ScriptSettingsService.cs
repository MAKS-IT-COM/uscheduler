using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using MaksIT.UScheduler.UI.Models;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>
/// Service for loading and saving scriptsettings.json files.
/// </summary>
public class ScriptSettingsService {
  private static readonly JsonSerializerOptions JsonOptions = new() {
    PropertyNameCaseInsensitive = true,
    WriteIndented = true
  };

  /// <summary>
  /// Scans a directory for scriptsettings.json files and loads their schedule configurations.
  /// </summary>
  public List<ScriptSchedule> LoadScriptsFromDirectory(string examplesPath) {
    var schedules = new List<ScriptSchedule>();

    if (!Directory.Exists(examplesPath))
      return schedules;

    var settingsFiles = Directory.GetFiles(examplesPath, "scriptsettings.json", SearchOption.AllDirectories);

    foreach (var filePath in settingsFiles) {
      try {
        var schedule = LoadScheduleFromFile(filePath);
        if (schedule != null)
          schedules.Add(schedule);
      }
      catch {
        // Skip files that can't be parsed
      }
    }

    return schedules;
  }

  /// <summary>
  /// Loads the schedule configuration from a single scriptsettings.json file.
  /// </summary>
  public ScriptSchedule? LoadScheduleFromFile(string filePath) {
    if (!File.Exists(filePath))
      return null;

    var json = File.ReadAllText(filePath);
    var doc = JsonNode.Parse(json);

    if (doc == null)
      return null;

    var title = doc["title"]?.GetValue<string>() ?? Path.GetDirectoryName(filePath) ?? "Unknown";
    var name = doc["name"]?.GetValue<string>();
    // Use name from JSON, or title with " Script Settings" suffix stripped for listbox display
    var displayName = !string.IsNullOrWhiteSpace(name)
        ? name
        : StripScriptSettingsSuffix(title);
    var schedule = new ScriptSchedule {
      FilePath = filePath,
      Name = displayName,
      Title = title,
      Description = doc["description"]?.GetValue<string>() ?? string.Empty
    };

    var scheduleNode = doc["schedule"];
    if (scheduleNode != null) {
      schedule.RunMonth = GetStringArray(scheduleNode["runMonth"]);
      schedule.RunWeekday = GetStringArray(scheduleNode["runWeekday"]);
      schedule.RunTime = GetStringArray(scheduleNode["runTime"]);
      schedule.MinIntervalMinutes = scheduleNode["minIntervalMinutes"]?.GetValue<int>() ?? 10;
    }

    return schedule;
  }

  /// <summary>
  /// Saves only the schedule section back to the scriptsettings.json file,
  /// preserving all other content.
  /// </summary>
  public void SaveScheduleToFile(ScriptSchedule schedule) {
    if (!File.Exists(schedule.FilePath))
      throw new FileNotFoundException("Script settings file not found.", schedule.FilePath);

    var json = File.ReadAllText(schedule.FilePath);
    var doc = JsonNode.Parse(json);

    if (doc == null)
      throw new InvalidOperationException("Failed to parse JSON file.");

    // Update or create the schedule section
    var scheduleNode = new JsonObject {
      ["runMonth"] = new JsonArray(schedule.RunMonth.Select(m => JsonValue.Create(m)).ToArray()),
      ["runWeekday"] = new JsonArray(schedule.RunWeekday.Select(d => JsonValue.Create(d)).ToArray()),
      ["runTime"] = new JsonArray(schedule.RunTime.Select(t => JsonValue.Create(t)).ToArray()),
      ["minIntervalMinutes"] = schedule.MinIntervalMinutes
    };

    doc["schedule"] = scheduleNode;

    // Write back with proper formatting
    var options = new JsonWriterOptions { Indented = true };
    using var stream = File.Create(schedule.FilePath);
    using var writer = new Utf8JsonWriter(stream, options);
    doc.WriteTo(writer);
  }

  /// <summary>Strips " Script Settings" (case-insensitive) from the end of a title for listbox display.</summary>
  private static string StripScriptSettingsSuffix(string title) {
    const string suffix = " Script Settings";
    if (title.Length > suffix.Length && title.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
      return title[..^suffix.Length].TrimEnd();
    return title;
  }

  private static List<string> GetStringArray(JsonNode? node) {
    if (node is not JsonArray array)
      return [];

    return array
        .Where(item => item != null)
        .Select(item => item!.GetValue<string>())
        .ToList();
  }
}
