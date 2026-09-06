using System.Text.Json;
using System.Text.Json.Nodes;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Loads and saves machine-wide <c>Configuration</c> under ProgramData
/// (all-users AppData). Shipped <c>appsettings.json</c> next to the worker is
/// seed-only; host logging stays in that file and is never copied.
/// </summary>
public sealed class ConfigurationFileService {
  public const string ProductFolder = HostPaths.ProductFolder;
  public const string SeedFileName = "appsettings.json";

  private static readonly JsonSerializerOptions SerializerOptions = new() {
    WriteIndented = true,
    PropertyNamingPolicy = null
  };

  private readonly string? _seedPath;
  private Configuration _current;

  public string FilePath { get; }

  public Configuration Current => _current;

  public ConfigurationFileService(string? configurationPath = null, string? seedPath = null) {
    FilePath = string.IsNullOrWhiteSpace(configurationPath)
      ? HostPaths.SharedSettingsFile
      : configurationPath;

    if (!string.IsNullOrWhiteSpace(seedPath))
      _seedPath = seedPath;
    else if (string.IsNullOrWhiteSpace(configurationPath))
      _seedPath = Path.Combine(AppContext.BaseDirectory, SeedFileName);
    else
      _seedPath = null;

    _current = LoadFromDisk();
    CopySeedIfNeeded();
  }

  public Configuration Reload() {
    _current = LoadFromDisk();
    return _current;
  }

  public void Save(Configuration configuration) {
    ArgumentNullException.ThrowIfNull(configuration);
    configuration.EnsureDefaults();

    var dir = Path.GetDirectoryName(FilePath);
    if (!string.IsNullOrEmpty(dir))
      Directory.CreateDirectory(dir);

    var root = ReadRoot(File.Exists(FilePath) ? FilePath : null) ?? [];
    root["Configuration"] = JsonSerializer.SerializeToNode(configuration, SerializerOptions);
    File.WriteAllText(FilePath, root.ToJsonString(SerializerOptions));
    _current = configuration;
  }

  private Configuration LoadFromDisk() {
    var path = ResolveReadPath();
    if (path is null)
      return CreateDefault();

    using var document = JsonDocument.Parse(File.ReadAllText(path));
    if (!document.RootElement.TryGetProperty("Configuration", out var value))
      return CreateDefault();

    var configuration = JsonSerializer.Deserialize<Configuration>(value.GetRawText(), SerializerOptions)
      ?? CreateDefault();
    configuration.EnsureDefaults();
    return configuration;
  }

  private static Configuration CreateDefault() {
    var configuration = new Configuration();
    configuration.EnsureDefaults();
    return configuration;
  }

  private static JsonObject? ReadRoot(string? path) {
    if (path is null || !File.Exists(path))
      return null;

    return JsonNode.Parse(File.ReadAllText(path)) as JsonObject;
  }

  private void CopySeedIfNeeded() {
    if (File.Exists(FilePath) || _seedPath is null || !File.Exists(_seedPath) || !HasConfiguration(_seedPath))
      return;

    try {
      Save(_current);
    }
    catch (UnauthorizedAccessException) {
    }
    catch (IOException) {
    }
  }

  private static bool HasConfiguration(string path) {
    using var document = JsonDocument.Parse(File.ReadAllText(path));
    return document.RootElement.TryGetProperty("Configuration", out _);
  }

  private string? ResolveReadPath() {
    if (File.Exists(FilePath))
      return FilePath;
    if (_seedPath is not null && File.Exists(_seedPath))
      return _seedPath;
    return null;
  }
}
