using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Default install and data locations. Standard layout keeps binaries under
/// Program Files and scripts, logs, and machine settings outside Program Files
/// so normal users can read and write them after <c>--prepare-data</c> /
/// <c>--install</c>. A <see cref="PortableMarkerFileName"/> file next to the
/// worker (or in a parent folder) switches to a portable layout: scripts, logs,
/// and settings stay under that folder.
/// </summary>
public static class HostPaths {
  public const string ProductFolder = "UScheduler";
  public const string Manufacturer = UserSettingsPath.Manufacturer;
  public const string PortableMarkerFileName = "portable";
  public const string PortableScriptsFolderName = "Scripts";
  public const string PortableLogsFolderName = "Logs";
  public const string PortableDataFolderName = "Data";
  public const string PortableMarkerContent = "MaksIT.UScheduler portable layout";

  public static string SharedSettingsFile =>
    UserSettingsPath.GetShared(ProductFolder);

  public static string DefaultInstallDirectory {
    get {
      if (OperatingSystem.IsWindows())
        return Path.Combine(
          Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
          Manufacturer,
          ProductFolder);

      return "/opt/maksit/uscheduler";
    }
  }

  public static IEnumerable<string> InstallDirectoryCandidates {
    get {
      if (!OperatingSystem.IsWindows()) {
        yield return "/opt/maksit/uscheduler";
        yield break;
      }

      yield return DefaultInstallDirectory;
      var x86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
      if (!string.IsNullOrWhiteSpace(x86)) {
        var x86Dir = Path.Combine(x86, Manufacturer, ProductFolder);
        if (!x86Dir.Equals(DefaultInstallDirectory, StringComparison.OrdinalIgnoreCase))
          yield return x86Dir;
      }
    }
  }

  public static string DefaultScriptsDirectory =>
    OperatingSystem.IsWindows() ? @"C:\MaksIT\Scripts" : "/var/lib/maksit/scripts";

  public static string DefaultLogDirectory =>
    OperatingSystem.IsWindows() ? @"C:\MaksIT\Logs" : "/var/log/maksit";

  public static string DefaultDataRoot =>
    OperatingSystem.IsWindows() ? @"C:\MaksIT" : "/var/lib/maksit";

  public static bool IsPortableLayout(string? startDirectory = null) =>
    FindPortableRoot(startDirectory) is not null;

  /// <summary>
  /// Directory that contains <see cref="PortableMarkerFileName"/>, walking up
  /// from <paramref name="startDirectory"/> (or the current app base).
  /// </summary>
  public static string? FindPortableRoot(string? startDirectory = null) {
    var current = startDirectory ?? AppContext.BaseDirectory;
    if (string.IsNullOrWhiteSpace(current))
      return null;

    try {
      current = Path.GetFullPath(current);
    }
    catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException) {
      return null;
    }

    if (File.Exists(current))
      current = Path.GetDirectoryName(current) ?? current;

    for (var i = 0; i < 10 && !string.IsNullOrEmpty(current); i++) {
      if (File.Exists(Path.Combine(current, PortableMarkerFileName)))
        return current;

      current = Directory.GetParent(current)?.FullName;
    }

    return null;
  }

  public static string GetPortableScriptsDirectory(string portableRoot) =>
    Path.Combine(portableRoot, PortableScriptsFolderName);

  public static string GetPortableLogDirectory(string portableRoot) =>
    Path.Combine(portableRoot, PortableLogsFolderName);

  public static string GetPortableDataDirectory(string portableRoot) =>
    Path.Combine(portableRoot, PortableDataFolderName);

  public static string GetPortableSharedSettingsFile(string portableRoot) =>
    Path.Combine(GetPortableDataDirectory(portableRoot), "settings.json");

  public static string GetPortableUiSettingsFile(string portableRoot) =>
    Path.Combine(GetPortableDataDirectory(portableRoot), "ui-settings.json");

  public static string ResolveSharedSettingsFile(string? startDirectory = null) {
    var root = FindPortableRoot(startDirectory);
    return root is null ? SharedSettingsFile : GetPortableSharedSettingsFile(root);
  }

  public static string ResolveUiSettingsFile(string? startDirectory = null) {
    var root = FindPortableRoot(startDirectory);
    return root is null ? UserSettingsPath.Get(ProductFolder) : GetPortableUiSettingsFile(root);
  }

  public static void WritePortableMarker(string portableRoot) {
    Directory.CreateDirectory(portableRoot);
    var path = Path.Combine(portableRoot, PortableMarkerFileName);
    if (!File.Exists(path))
      File.WriteAllText(path, PortableMarkerContent + Environment.NewLine);
  }

  /// <summary>
  /// When a portable root is present, replace machine-wide default script/log
  /// paths with folders under that root. Custom paths are left unchanged.
  /// </summary>
  public static void ApplyPortableDefaults(Configuration configuration, string? startDirectory = null) {
    ArgumentNullException.ThrowIfNull(configuration);
    var root = FindPortableRoot(startDirectory);
    if (root is null)
      return;

    if (string.IsNullOrWhiteSpace(configuration.LogDir) || PathsEqual(configuration.LogDir, DefaultLogDirectory))
      configuration.LogDir = GetPortableLogDirectory(root);

    if (string.IsNullOrWhiteSpace(configuration.ScriptsDir) || PathsEqual(configuration.ScriptsDir, DefaultScriptsDirectory))
      configuration.ScriptsDir = GetPortableScriptsDirectory(root);
  }

  /// <summary>
  /// Scripts folder to use at runtime: configured path if it exists, then a
  /// portable <c>Scripts</c> folder, then <see cref="DefaultScriptsDirectory"/>,
  /// then a bundled/dev tree.
  /// </summary>
  public static string ResolveScriptsDirectory(string? configured = null, string? startDirectory = null) {
    var start = startDirectory ?? AppContext.BaseDirectory;
    if (!string.IsNullOrWhiteSpace(configured)) {
      var resolved = PathHelper.ResolvePath(configured, start);
      if (Directory.Exists(resolved))
        return resolved;
    }

    var portableRoot = FindPortableRoot(start);
    if (portableRoot is not null) {
      var portableScripts = GetPortableScriptsDirectory(portableRoot);
      if (Directory.Exists(portableScripts))
        return portableScripts;
    }

    if (Directory.Exists(DefaultScriptsDirectory))
      return DefaultScriptsDirectory;

    var bundled = FindBundledScriptsDirectory(start);
    return bundled ?? DefaultScriptsDirectory;
  }

  public static string? FindBundledScriptsDirectory(string? startDirectory = null) {
    var current = startDirectory ?? AppContext.BaseDirectory;
    for (var i = 0; i < 10 && !string.IsNullOrEmpty(current); i++) {
      foreach (var candidate in new[] {
        Path.Combine(current, PortableScriptsFolderName),
        Path.Combine(current, "src", PortableScriptsFolderName)
      }) {
        if (LooksLikeScriptsRoot(candidate))
          return candidate;
      }

      current = Directory.GetParent(current)?.FullName;
    }

    return null;
  }

  public static string DetectServiceBinPath() {
    var fromUi = FindWorkerDirectory(AppContext.BaseDirectory);
    if (fromUi is not null)
      return fromUi;

    foreach (var candidate in InstallDirectoryCandidates) {
      var found = FindWorkerDirectory(candidate);
      if (found is not null)
        return found;
    }

    return DefaultInstallDirectory;
  }

  public static string? FindWorkerDirectory(string? startDirectory) {
    if (string.IsNullOrWhiteSpace(startDirectory))
      return null;

    var fileName = HostServiceManager.GetExecutableFileName();
    var start = Path.GetFullPath(startDirectory);
    if (File.Exists(Path.Combine(start, fileName)))
      return start;

    var current = start;
    for (var i = 0; i < 10; i++) {
      var parent = Directory.GetParent(current);
      if (parent is null)
        break;

      current = parent.FullName;
      var sibling = Path.Combine(current, HostServiceManager.DefaultExecutableFileName);
      if (File.Exists(Path.Combine(sibling, fileName)))
        return sibling;

      var siblingBin = Path.Combine(sibling, "bin");
      if (!Directory.Exists(siblingBin))
        continue;

      try {
        var match = Directory.EnumerateFiles(siblingBin, fileName, SearchOption.AllDirectories).FirstOrDefault();
        if (match is not null)
          return Path.GetDirectoryName(match);
      }
      catch (UnauthorizedAccessException) {
      }
      catch (DirectoryNotFoundException) {
      }
    }

    return null;
  }

  internal static bool PathsEqual(string left, string right) =>
    string.Equals(
      Path.GetFullPath(left).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
      Path.GetFullPath(right).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
      OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);

  private static bool LooksLikeScriptsRoot(string path) =>
    Directory.Exists(path)
    && (Directory.Exists(Path.Combine(path, "File-Sync"))
      || Directory.Exists(Path.Combine(path, "Native-Sync"))
      || Directory.Exists(Path.Combine(path, "HyperV-Backup"))
      || Directory.Exists(Path.Combine(path, "Windows-Update"))
      || File.Exists(Path.Combine(path, "SchedulerTemplate.psm1")));
}
