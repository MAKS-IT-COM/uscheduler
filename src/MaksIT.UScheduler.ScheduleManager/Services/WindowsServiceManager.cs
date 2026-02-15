using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace MaksIT.UScheduler.ScheduleManager.Services;

/// <summary>
/// Service status enumeration.
/// </summary>
public enum ServiceStatus
{
    NotInstalled,
    Stopped,
    StartPending,
    StopPending,
    Running,
    ContinuePending,
    PausePending,
    Paused,
    Unknown
}

/// <summary>
/// Result of a service operation.
/// </summary>
public record ServiceOperationResult(bool Success, string Message);

/// <summary>
/// Manages Windows service operations for MaksIT.UScheduler by calling the executable with CLI args.
/// </summary>
public class WindowsServiceManager
{
    private const string DefaultServiceName = "MaksIT.UScheduler";
    
    public string ServiceName { get; }

    public WindowsServiceManager(string? serviceName = null)
    {
        ServiceName = serviceName ?? DefaultServiceName;
    }

    /// <summary>
    /// Gets the current status of the service by running --status command.
    /// </summary>
    public ServiceStatus GetStatus(string? executablePath = null)
    {
        // Try using sc.exe query directly for status
        var result = RunScCommand($"query \"{ServiceName}\"");
        
        if (!result.Success)
        {
            // Service might not exist
            if (result.Message.Contains("1060") || result.Message.Contains("does not exist"))
                return ServiceStatus.NotInstalled;
            
            return ServiceStatus.Unknown;
        }

        // Parse state from sc.exe output. Use numeric state code (locale-independent);
        // sc query shows e.g. "STATE              : 4  RUNNING" (text may be localized).
        var match = Regex.Match(result.Message, @"STATE\s*:\s*(\d+)", RegexOptions.IgnoreCase);
        if (match.Success && int.TryParse(match.Groups[1].Value, out var state))
        {
            return state switch
            {
                1 => ServiceStatus.Stopped,
                2 => ServiceStatus.StartPending,
                3 => ServiceStatus.StopPending,
                4 => ServiceStatus.Running,
                5 => ServiceStatus.ContinuePending,
                6 => ServiceStatus.PausePending,
                7 => ServiceStatus.Paused,
                _ => ServiceStatus.Unknown
            };
        }

        // Fallback: text match (English)
        var output = result.Message.ToUpperInvariant();
        if (output.Contains("RUNNING")) return ServiceStatus.Running;
        if (output.Contains("STOPPED")) return ServiceStatus.Stopped;
        if (output.Contains("START_PENDING")) return ServiceStatus.StartPending;
        if (output.Contains("STOP_PENDING")) return ServiceStatus.StopPending;
        if (output.Contains("PAUSED")) return ServiceStatus.Paused;
        if (output.Contains("PAUSE_PENDING")) return ServiceStatus.PausePending;
        if (output.Contains("CONTINUE_PENDING")) return ServiceStatus.ContinuePending;

        return ServiceStatus.Unknown;
    }

    /// <summary>
    /// Starts the service using the executable's --start command.
    /// </summary>
    public ServiceOperationResult Start(string? executablePath = null)
    {
        if (!string.IsNullOrEmpty(executablePath) && File.Exists(executablePath))
        {
            return RunExecutable(executablePath, "--start");
        }
        
        // Fallback to sc.exe
        return RunScCommand($"start \"{ServiceName}\"");
    }

    /// <summary>
    /// Stops the service using the executable's --stop command.
    /// </summary>
    public ServiceOperationResult Stop(string? executablePath = null)
    {
        if (!string.IsNullOrEmpty(executablePath) && File.Exists(executablePath))
        {
            return RunExecutable(executablePath, "--stop");
        }
        
        // Fallback to sc.exe
        return RunScCommand($"stop \"{ServiceName}\"");
    }

    /// <summary>
    /// Registers (installs) the service using the executable's --install command.
    /// </summary>
    public ServiceOperationResult Register(string executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath))
            return new ServiceOperationResult(false, "Executable path is required.");

        if (!File.Exists(executablePath))
            return new ServiceOperationResult(false, $"Executable not found: {executablePath}");

        var status = GetStatus();
        if (status != ServiceStatus.NotInstalled)
            return new ServiceOperationResult(false, "Service is already installed.");

        return RunExecutable(executablePath, "--install");
    }

    /// <summary>
    /// Unregisters (removes) the service using the executable's --uninstall command.
    /// </summary>
    public ServiceOperationResult Unregister(string? executablePath = null)
    {
        var status = GetStatus();
        
        if (status == ServiceStatus.NotInstalled)
            return new ServiceOperationResult(false, "Service is not installed.");

        if (!string.IsNullOrEmpty(executablePath) && File.Exists(executablePath))
        {
            return RunExecutable(executablePath, "--uninstall");
        }

        // Fallback: stop first, then delete via sc.exe
        if (status == ServiceStatus.Running)
        {
            RunScCommand($"stop \"{ServiceName}\"");
        }

        return RunScCommand($"delete \"{ServiceName}\"");
    }

    /// <summary>
    /// Runs the UScheduler executable with the specified arguments.
    /// </summary>
    private static ServiceOperationResult RunExecutable(string executablePath, string arguments)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = executablePath,
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(executablePath) ?? ""
            };

            using var process = Process.Start(startInfo);
            if (process == null)
                return new ServiceOperationResult(false, "Failed to start process.");

            var output = process.StandardOutput.ReadToEnd();
            var error = process.StandardError.ReadToEnd();
            process.WaitForExit(30000); // 30 second timeout

            var message = string.IsNullOrEmpty(error) ? output.Trim() : $"{output}\n{error}".Trim();

            if (process.ExitCode == 0)
                return new ServiceOperationResult(true, message);
            
            return new ServiceOperationResult(false, message);
        }
        catch (Exception ex)
        {
            return new ServiceOperationResult(false, $"Failed to execute: {ex.Message}");
        }
    }

    /// <summary>
    /// Runs an sc.exe command and returns the result.
    /// </summary>
    private static ServiceOperationResult RunScCommand(string arguments)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "sc.exe",
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            using var process = Process.Start(startInfo);
            if (process == null)
                return new ServiceOperationResult(false, "Failed to start sc.exe process.");

            var output = process.StandardOutput.ReadToEnd();
            var error = process.StandardError.ReadToEnd();
            process.WaitForExit();

            // sc.exe often writes to stderr; combine both so status parsing sees the STATE line
            var message = $"{output}{error}".Trim();
            if (string.IsNullOrEmpty(message))
                message = process.ExitCode == 0 ? "OK" : "Command failed.";

            if (process.ExitCode == 0)
                return new ServiceOperationResult(true, message);
            
            return new ServiceOperationResult(false, message);
        }
        catch (Exception ex)
        {
            return new ServiceOperationResult(false, $"Failed to execute sc.exe: {ex.Message}");
        }
    }
}
