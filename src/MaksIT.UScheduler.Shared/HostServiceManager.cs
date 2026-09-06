using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text.RegularExpressions;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Installs, starts, stops, and queries the UScheduler worker (Windows SCM or systemd).
/// </summary>
public sealed class HostServiceManager {
  public const string DefaultExecutableFileName = "MaksIT.UScheduler";

  public string ServiceName { get; }

  public HostServiceManager(string? serviceName = null) {
    ServiceName = string.IsNullOrWhiteSpace(serviceName)
      ? "MaksIT.UScheduler"
      : serviceName.Trim();
  }

  public static bool IsProcessElevated() {
    if (OperatingSystem.IsWindows()) {
      using var identity = WindowsIdentity.GetCurrent();
      return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS()) {
      try {
        return GetEuid() == 0;
      }
      catch {
        return string.Equals(Environment.UserName, "root", StringComparison.Ordinal);
      }
    }

    return false;
  }

  public static string GetExecutableFileName() =>
    OperatingSystem.IsWindows() ? DefaultExecutableFileName + ".exe" : DefaultExecutableFileName;

  public static string? ResolveExecutablePath(string? baseDirectory = null) {
    var fileName = GetExecutableFileName();
    var roots = new List<string>();
    if (!string.IsNullOrWhiteSpace(baseDirectory))
      roots.Add(baseDirectory);
    roots.Add(AppContext.BaseDirectory);
    roots.AddRange(HostPaths.InstallDirectoryCandidates);

    foreach (var root in roots.Distinct(StringComparer.OrdinalIgnoreCase)) {
      var candidates = new[] {
        Path.Combine(root, fileName),
        Path.Combine(root, "..", DefaultExecutableFileName, fileName)
      };

      foreach (var candidate in candidates) {
        var fullPath = Path.GetFullPath(candidate);
        if (File.Exists(fullPath))
          return fullPath;
      }
    }

    var detected = HostPaths.FindWorkerDirectory(baseDirectory ?? AppContext.BaseDirectory);
    if (detected is null)
      return null;

    var detectedExe = Path.Combine(detected, fileName);
    return File.Exists(detectedExe) ? detectedExe : null;
  }

  public HostServiceStatus GetStatus(string? executablePath = null) {
    if (OperatingSystem.IsWindows())
      return GetWindowsStatus();

    if (OperatingSystem.IsLinux())
      return GetLinuxStatus();

    return HostServiceStatus.Unknown;
  }

  public HostServiceOperationResult Start(string? executablePath = null) {
    if (!string.IsNullOrEmpty(executablePath) && File.Exists(executablePath))
      return RunExecutable(executablePath, "--start");

    return OperatingSystem.IsWindows()
      ? RunScCommand($"start \"{ServiceName}\"")
      : RunSystemctl("start", ServiceName);
  }

  public HostServiceOperationResult Stop(string? executablePath = null) {
    if (!string.IsNullOrEmpty(executablePath) && File.Exists(executablePath))
      return RunExecutable(executablePath, "--stop");

    return OperatingSystem.IsWindows()
      ? RunScCommand($"stop \"{ServiceName}\"")
      : RunSystemctl("stop", ServiceName);
  }

  public HostServiceOperationResult PrepareData(string? executablePath = null) {
    if (!string.IsNullOrEmpty(executablePath) && File.Exists(executablePath))
      return RunExecutable(executablePath, "--prepare-data");

    if (IsProcessElevated())
      return HostDataDirectories.Prepare(AppContext.BaseDirectory);

    return new HostServiceOperationResult(
      false,
      "Preparing data directories requires elevation. Register the service or run MaksIT.UScheduler --prepare-data.");
  }

  public HostServiceOperationResult Register(string executablePath) {
    if (string.IsNullOrWhiteSpace(executablePath))
      return new HostServiceOperationResult(false, "Executable path is required.");

    if (!File.Exists(executablePath))
      return new HostServiceOperationResult(false, $"Executable not found: {executablePath}");

    if (GetStatus() != HostServiceStatus.NotInstalled)
      return new HostServiceOperationResult(false, "Service is already installed.");

    return RunExecutable(executablePath, "--install");
  }

  public HostServiceOperationResult Unregister(string? executablePath = null) {
    if (GetStatus() == HostServiceStatus.NotInstalled)
      return new HostServiceOperationResult(false, "Service is not installed.");

    if (!string.IsNullOrEmpty(executablePath) && File.Exists(executablePath))
      return RunExecutable(executablePath, "--uninstall");

    if (OperatingSystem.IsWindows()) {
      if (GetStatus() == HostServiceStatus.Running)
        RunScCommand($"stop \"{ServiceName}\"");

      return RunScCommand($"delete \"{ServiceName}\"");
    }

    return UnregisterLinuxUnit();
  }

  private HostServiceOperationResult UnregisterLinuxUnit() {
    RunSystemctl("stop", ServiceName);
    RunSystemctl("disable", ServiceName);
    var unitPath = HostServiceRegistration.GetSystemdUnitPath(ServiceName);
    try {
      if (File.Exists(unitPath))
        File.Delete(unitPath);
    }
    catch (Exception ex) {
      return new HostServiceOperationResult(false, $"Failed to remove unit file: {ex.Message}");
    }

    return RunProcessAsResult("systemctl", "daemon-reload");
  }

  private HostServiceStatus GetWindowsStatus() {
    var query = RunScCommand($"query \"{ServiceName}\"");
    if (!query.Success) {
      if (query.Message.Contains("1060", StringComparison.Ordinal)
          || query.Message.Contains("does not exist", StringComparison.OrdinalIgnoreCase))
        return HostServiceStatus.NotInstalled;

      return HostServiceStatus.Unknown;
    }

    var match = Regex.Match(query.Message, @"STATE\s*:\s*(\d+)", RegexOptions.IgnoreCase);
    if (!match.Success || !int.TryParse(match.Groups[1].Value, out var state))
      return HostServiceStatus.Unknown;

    return state switch {
      1 => HostServiceStatus.Stopped,
      2 => HostServiceStatus.StartPending,
      3 => HostServiceStatus.StopPending,
      4 => HostServiceStatus.Running,
      5 => HostServiceStatus.ContinuePending,
      6 => HostServiceStatus.PausePending,
      7 => HostServiceStatus.Paused,
      _ => HostServiceStatus.Unknown
    };
  }

  private HostServiceStatus GetLinuxStatus() {
    var enabled = RunProcess("systemctl", $"is-enabled {ServiceName}");
    if (LooksUninstalled(enabled))
      return HostServiceStatus.NotInstalled;

    var active = RunProcess("systemctl", $"is-active {ServiceName}").Message.Trim();
    if (string.Equals(active, "active", StringComparison.OrdinalIgnoreCase))
      return HostServiceStatus.Running;

    if (string.Equals(active, "activating", StringComparison.OrdinalIgnoreCase))
      return HostServiceStatus.StartPending;

    if (string.Equals(active, "deactivating", StringComparison.OrdinalIgnoreCase))
      return HostServiceStatus.StopPending;

    if (string.Equals(active, "inactive", StringComparison.OrdinalIgnoreCase)
        || string.Equals(active, "failed", StringComparison.OrdinalIgnoreCase))
      return HostServiceStatus.Stopped;

    if (RunProcess("systemctl", $"cat {ServiceName}").ExitCode != 0)
      return HostServiceStatus.NotInstalled;

    return HostServiceStatus.Stopped;
  }

  private static bool LooksUninstalled((int ExitCode, string Message) result) {
    var message = result.Message;
    return message.Contains("not-found", StringComparison.OrdinalIgnoreCase)
      || message.Contains("could not be found", StringComparison.OrdinalIgnoreCase)
      || (result.ExitCode != 0 && message.Contains("No such file", StringComparison.OrdinalIgnoreCase));
  }

  private static HostServiceOperationResult RunExecutable(string executablePath, string arguments) {
    try {
      using var process = Process.Start(CreateExecutableStartInfo(executablePath, arguments));
      if (process is null)
        return new HostServiceOperationResult(false, "Failed to start process.");

      string message;
      if (process.StartInfo.RedirectStandardOutput) {
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        message = string.IsNullOrEmpty(stderr) ? stdout.Trim() : $"{stdout}\n{stderr}".Trim();
      }
      else {
        message = string.Empty;
      }

      if (!process.WaitForExit(60000)) {
        process.Kill(entireProcessTree: true);
        return new HostServiceOperationResult(false, "Timed out waiting for the service executable.");
      }

      if (string.IsNullOrWhiteSpace(message))
        message = process.ExitCode == 0 ? "OK" : $"Command failed (exit code {process.ExitCode}).";

      return new HostServiceOperationResult(process.ExitCode == 0, message);
    }
    catch (Win32Exception ex) when (ex.NativeErrorCode == 1223) {
      return new HostServiceOperationResult(false, "The elevation prompt was cancelled.");
    }
    catch (Exception ex) {
      return new HostServiceOperationResult(false, $"Failed to execute: {ex.Message}");
    }
  }

  private static ProcessStartInfo CreateExecutableStartInfo(string executablePath, string arguments) {
    var workingDirectory = Path.GetDirectoryName(executablePath) ?? string.Empty;

    if (OperatingSystem.IsWindows() && !IsProcessElevated()) {
      return new ProcessStartInfo {
        FileName = executablePath,
        Arguments = arguments,
        UseShellExecute = true,
        Verb = "runas",
        ErrorDialog = true,
        WorkingDirectory = workingDirectory
      };
    }

    if ((OperatingSystem.IsLinux() || OperatingSystem.IsMacOS()) && !IsProcessElevated()) {
      return new ProcessStartInfo {
        FileName = "pkexec",
        Arguments = $"\"{executablePath}\" {arguments}",
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true,
        WorkingDirectory = workingDirectory
      };
    }

    return new ProcessStartInfo {
      FileName = executablePath,
      Arguments = arguments,
      UseShellExecute = false,
      RedirectStandardOutput = true,
      RedirectStandardError = true,
      CreateNoWindow = true,
      WorkingDirectory = workingDirectory
    };
  }

  private static HostServiceOperationResult RunScCommand(string arguments) {
    var result = RunProcess("sc.exe", arguments);
    var message = string.IsNullOrEmpty(result.Message)
      ? (result.ExitCode == 0 ? "OK" : "Command failed.")
      : result.Message;
    return new HostServiceOperationResult(result.ExitCode == 0, message);
  }

  private static HostServiceOperationResult RunSystemctl(string verb, string unit, string? extra = null) {
    var arguments = string.IsNullOrWhiteSpace(extra) ? $"{verb} {unit}" : $"{verb} {unit} {extra}";
    return RunProcessAsResult("systemctl", arguments);
  }

  private static HostServiceOperationResult RunProcessAsResult(string fileName, string arguments) {
    var result = RunProcess(fileName, arguments);
    return new HostServiceOperationResult(result.ExitCode == 0, result.Message);
  }

  private static (int ExitCode, string Message) RunProcess(string fileName, string arguments) {
    try {
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
    catch (Exception ex) {
      return (1, $"Failed to execute {fileName}: {ex.Message}");
    }
  }

  [DllImport("libc", EntryPoint = "geteuid", SetLastError = true)]
  private static extern uint GetEuid();
}
