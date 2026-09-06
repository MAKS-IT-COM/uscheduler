using System.Diagnostics;
using System.Runtime.Versioning;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Creates machine-wide data folders (scripts, logs, shared settings) and
/// grants the Users group modify rights so the UI can run without elevation.
/// Call from an elevated <c>--install</c> / <c>--prepare-data</c> process.
/// </summary>
public static class HostDataDirectories {
  /// <summary>Windows Built-in Users (locale-independent).</summary>
  private const string BuiltinUsersSid = "*S-1-5-32-545";

  public static HostServiceOperationResult Prepare(string? installDirectory = null) {
    var installDir = string.IsNullOrWhiteSpace(installDirectory)
      ? AppContext.BaseDirectory
      : installDirectory;
    var messages = new List<string>();

    try {
      Directory.CreateDirectory(HostPaths.DefaultDataRoot);
      Directory.CreateDirectory(HostPaths.DefaultScriptsDirectory);
      Directory.CreateDirectory(HostPaths.DefaultLogDirectory);

      var settingsDir = Path.GetDirectoryName(HostPaths.SharedSettingsFile);
      if (!string.IsNullOrEmpty(settingsDir))
        Directory.CreateDirectory(settingsDir);

      if (OperatingSystem.IsWindows()) {
        GrantUsersModify(HostPaths.DefaultDataRoot, messages);
        if (!string.IsNullOrEmpty(settingsDir))
          GrantUsersModify(settingsDir, messages);
      }
      else if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS()) {
        GrantUnixGroupWrite(HostPaths.DefaultDataRoot, messages);
        GrantUnixGroupWrite(HostPaths.DefaultScriptsDirectory, messages);
        GrantUnixGroupWrite(HostPaths.DefaultLogDirectory, messages);
        if (!string.IsNullOrEmpty(settingsDir))
          GrantUnixGroupWrite(settingsDir, messages);
      }

      var source = HostPaths.FindBundledScriptsDirectory(installDir);
      if (source is null || !Directory.Exists(source)) {
        messages.Add(
          $"Bundled scripts were not found next to '{installDir}'; left {HostPaths.DefaultScriptsDirectory} unchanged.");
      }
      else if (PathsEqual(source, HostPaths.DefaultScriptsDirectory)) {
        messages.Add($"Scripts directory: {HostPaths.DefaultScriptsDirectory}");
      }
      else {
        var copy = CopySeedScriptsIfMissing(source, HostPaths.DefaultScriptsDirectory);
        if (copy.CopiedFiles > 0)
          messages.Add($"Copied {copy.CopiedFiles} new seed script file(s) to {HostPaths.DefaultScriptsDirectory}.");
        if (copy.SkippedItems > 0)
          messages.Add($"Left {copy.SkippedItems} existing script folder(s)/file(s) unchanged in {HostPaths.DefaultScriptsDirectory}.");
        if (copy.CopiedFiles == 0 && copy.SkippedItems == 0)
          messages.Add($"Scripts directory: {HostPaths.DefaultScriptsDirectory}");
      }

      messages.Add($"Logs directory: {HostPaths.DefaultLogDirectory}");
      messages.Add($"Shared settings: {HostPaths.SharedSettingsFile}");
      return new HostServiceOperationResult(true, string.Join(Environment.NewLine, messages));
    }
    catch (Exception ex) {
      return new HostServiceOperationResult(false, $"Failed to prepare data directories: {ex.Message}");
    }
  }

  /// <summary>
  /// Copies bundled example scripts only when the destination does not already
  /// have that file or script folder. Existing folders are left as-is (no merge),
  /// so user customizations are never overwritten.
  /// </summary>
  public static SeedCopyResult CopySeedScriptsIfMissing(string source, string destination) {
    Directory.CreateDirectory(destination);
    var copied = 0;
    var skipped = 0;

    foreach (var file in Directory.EnumerateFiles(source)) {
      var destFile = Path.Combine(destination, Path.GetFileName(file));
      if (File.Exists(destFile)) {
        skipped++;
        continue;
      }

      File.Copy(file, destFile);
      copied++;
    }

    foreach (var dir in Directory.EnumerateDirectories(source)) {
      var destDir = Path.Combine(destination, Path.GetFileName(dir));
      if (Directory.Exists(destDir)) {
        skipped++;
        continue;
      }

      copied += CopyNewDirectory(dir, destDir);
    }

    return new SeedCopyResult(copied, skipped);
  }

  private static int CopyNewDirectory(string source, string destination) {
    Directory.CreateDirectory(destination);
    var copied = 0;

    foreach (var file in Directory.EnumerateFiles(source)) {
      File.Copy(file, Path.Combine(destination, Path.GetFileName(file)));
      copied++;
    }

    foreach (var dir in Directory.EnumerateDirectories(source))
      copied += CopyNewDirectory(dir, Path.Combine(destination, Path.GetFileName(dir)));

    return copied;
  }

  private static void GrantUsersModify(string path, List<string> messages) {
    var icacls = Path.Combine(Environment.SystemDirectory, "icacls.exe");
    var arguments = $"\"{path}\" /grant {BuiltinUsersSid}:(OI)(CI)M /T";
    var result = RunProcess(icacls, arguments);
    if (result.ExitCode != 0)
      throw new InvalidOperationException($"icacls failed for '{path}': {result.Message}");

    messages.Add($"Granted Users modify on {path}.");
  }

  [SupportedOSPlatform("linux")]
  [SupportedOSPlatform("macos")]
  private static void GrantUnixGroupWrite(string path, List<string> messages) {
    try {
      var mode = File.GetUnixFileMode(path);
      File.SetUnixFileMode(
        path,
        mode
        | UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute
        | UnixFileMode.GroupRead | UnixFileMode.GroupWrite | UnixFileMode.GroupExecute
        | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
      messages.Add($"Set group-writable mode on {path}.");
    }
    catch (Exception ex) {
      messages.Add($"Warning: could not set permissions on '{path}': {ex.Message}");
    }
  }

  private static bool PathsEqual(string left, string right) =>
    string.Equals(
      Path.GetFullPath(left).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
      Path.GetFullPath(right).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
      OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);

  private static (int ExitCode, string Message) RunProcess(string fileName, string arguments) {
    using var process = Process.Start(new ProcessStartInfo {
      FileName = fileName,
      Arguments = arguments,
      UseShellExecute = false,
      RedirectStandardOutput = true,
      RedirectStandardError = true,
      CreateNoWindow = true
    });

    if (process is null)
      return (1, $"Failed to start {fileName}.");

    var stdout = process.StandardOutput.ReadToEnd();
    var stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();
    return (process.ExitCode, (stdout + stderr).Trim());
  }
}
