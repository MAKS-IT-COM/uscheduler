using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Default install and data locations. Binaries live under Program Files;
/// scripts, logs, and machine settings are outside Program Files so normal
/// users can read and write them after <c>--prepare-data</c> / <c>--install</c>.
/// </summary>
public static class HostPaths {
  public const string ProductFolder = "UScheduler";
  public const string Manufacturer = UserSettingsPath.Manufacturer;

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

  public static string DefaultScriptsDirectory =>
    OperatingSystem.IsWindows() ? @"C:\MaksIT\Scripts" : "/var/lib/maksit/scripts";

  public static string DefaultLogDirectory =>
    OperatingSystem.IsWindows() ? @"C:\MaksIT\Logs" : "/var/log/maksit";

  public static string DefaultDataRoot =>
    OperatingSystem.IsWindows() ? @"C:\MaksIT" : "/var/lib/maksit";

  /// <summary>
  /// Scripts folder to use at runtime: configured path if it exists, then
  /// <see cref="DefaultScriptsDirectory"/>, then a bundled/dev tree.
  /// </summary>
  public static string ResolveScriptsDirectory(string? configured = null) {
    if (!string.IsNullOrWhiteSpace(configured)) {
      var resolved = PathHelper.ResolvePath(configured);
      if (Directory.Exists(resolved))
        return resolved;
    }

    if (Directory.Exists(DefaultScriptsDirectory))
      return DefaultScriptsDirectory;

    var bundled = FindBundledScriptsDirectory();
    return bundled ?? DefaultScriptsDirectory;
  }

  public static string? FindBundledScriptsDirectory(string? startDirectory = null) {
    var current = startDirectory ?? AppContext.BaseDirectory;
    for (var i = 0; i < 10 && !string.IsNullOrEmpty(current); i++) {
      foreach (var candidate in new[] {
        Path.Combine(current, "Scripts"),
        Path.Combine(current, "src", "Scripts")
      }) {
        if (LooksLikeScriptsRoot(candidate))
          return candidate;
      }

      current = Directory.GetParent(current)?.FullName;
    }

    return null;
  }

  public static string DetectServiceBinPath() =>
    FindWorkerDirectory(AppContext.BaseDirectory)
    ?? FindWorkerDirectory(DefaultInstallDirectory)
    ?? DefaultInstallDirectory;

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

  private static bool LooksLikeScriptsRoot(string path) =>
    Directory.Exists(Path.Combine(path, "File-Sync"))
    || File.Exists(Path.Combine(path, "SchedulerTemplate.psm1"));
}
