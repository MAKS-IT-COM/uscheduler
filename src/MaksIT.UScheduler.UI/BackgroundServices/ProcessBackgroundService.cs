using System.Collections.Concurrent;
using Microsoft.Extensions.Options;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;
using MaksIT.UScheduler.Services;


namespace MaksIT.UScheduler.BackgroundServices;

/// <summary>
/// Keeps each configured program running under the service.
/// A program starts with the service, restarts when it exits, and stops when the service stops.
/// One program does not block the others.
/// </summary>
public sealed class ProcessBackgroundService : BackgroundService {

  private readonly ILogger<ProcessBackgroundService> _logger;
  private readonly IOptionsMonitor<Configuration> _optionsMonitor;
  private readonly IProcessService _processService;
  private readonly ConcurrentDictionary<string, SupervisedRun> _runs = new(PathComparer);
  private readonly ConcurrentDictionary<string, byte> _down = new(PathComparer);
  private readonly ConcurrentDictionary<string, byte> _held = new(PathComparer);
  private readonly SemaphoreSlim _gate = new(1, 1);
  private readonly TimeSpan _checkInterval;
  private CancellationToken _hostStopping;

  private static StringComparer PathComparer =>
    OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

  /// <summary>
  /// Initializes a new instance of the <see cref="ProcessBackgroundService"/> class.
  /// </summary>
  /// <param name="logger">The logger instance for this service.</param>
  /// <param name="optionsMonitor">The configuration options containing process definitions.</param>
  /// <param name="processService">The process service for executing processes.</param>
  public ProcessBackgroundService(
    ILogger<ProcessBackgroundService> logger,
    IOptionsMonitor<Configuration> optionsMonitor,
    IProcessService processService
  ) : this(logger, optionsMonitor, processService, TimeSpan.FromSeconds(10)) {
  }

  /// <summary>
  /// Initializes a new instance with a custom check interval. Tests use this.
  /// </summary>
  public ProcessBackgroundService(
    ILogger<ProcessBackgroundService> logger,
    IOptionsMonitor<Configuration> optionsMonitor,
    IProcessService processService,
    TimeSpan checkInterval
  ) {
    _logger = logger;
    _optionsMonitor = optionsMonitor;
    _processService = processService;
    _checkInterval = checkInterval;
  }

  /// <summary>
  /// Starts configured programs that are not already running, then checks again in 10 seconds
  /// for settings changes. A program that is kept running restarts itself when it exits.
  /// </summary>
  /// <param name="stoppingToken">Cancellation token that signals when the service should stop.</param>
  /// <returns>A task representing the background operation.</returns>
  protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Starting ProcessBackgroundService");
    _hostStopping = stoppingToken;

    try {
      while (!stoppingToken.IsCancellationRequested) {
        var processes = _optionsMonitor.CurrentValue.Processes
          .Where(process => !process.Disabled && !string.IsNullOrEmpty(process.Path) && HostPlatforms.IsCompatible(process.Platforms))
          .ToList();

        var desired = new HashSet<string>(PathComparer);
        foreach (var process in processes) {
          var key = PathHelper.ResolvePath(process.Path);
          desired.Add(key);
          await SuperviseAsync(key, process, stoppingToken);
        }

        foreach (var key in _runs.Keys.ToArray()) {
          if (desired.Contains(key))
            continue;

          _down.TryRemove(key, out _);
          if (!_runs.TryRemove(key, out var run))
            continue;

          run.Cts.Cancel();
          run.Cts.Dispose();
        }

        await Task.Delay(_checkInterval, stoppingToken);
      }
    }
    catch (OperationCanceledException) {
      _logger.LogInformation("Stopping ProcessBackgroundService due to cancellation request");
    }
    catch (Exception ex) {
      _logger.LogError(ex, "{Message}", ex.Message);

      // Terminates this process and returns an exit code to the operating system.
      // This is required to avoid the 'BackgroundServiceExceptionBehavior', which
      // performs one of two scenarios:
      // 1. When set to "Ignore": will do nothing at all, errors cause zombie services.
      // 2. When set to "StopHost": will cleanly stop the host, and log errors.
      //
      // In order for the Windows Service Management system to leverage configured
      // recovery options, we need to terminate the process with a non-zero exit code.
      Environment.Exit(1);
    }
  }

  /// <summary>
  /// Stops the background service and terminates all running processes.
  /// </summary>
  /// <param name="stoppingToken">Cancellation token for the stop operation.</param>
  /// <returns>A task representing the stop operation.</returns>
  public override Task StopAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Stopping ProcessBackgroundService");

    foreach (var run in _runs.Values.ToArray())
      run.Cts.Cancel();

    _processService.TerminateAllProcesses();
    _logger.LogInformation("All processes terminated");

    return base.StopAsync(stoppingToken);
  }

  /// <summary>
  /// Starts one saved program now. A program stopped from the window starts again.
  /// </summary>
  public async Task<ProcessControlResult> StartProgramAsync(string requestedPath, CancellationToken cancellationToken) {
    var process = FindEnabled(requestedPath, out var failure);
    if (process is null)
      return failure!;

    var key = PathHelper.ResolvePath(process.Path);
    await _gate.WaitAsync(cancellationToken);
    try {
      _held.TryRemove(key, out _);
      _down.TryRemove(key, out _);
      if (IsRunning(key))
        return new ProcessControlResult(false, "That program is already running.");

      DropCompleted(key);
      BeginRun(key, process);
    }
    finally {
      _gate.Release();
    }

    _logger.LogInformation("Manual start requested for {Path}", key);
    return new ProcessControlResult(true, "The service started the program.");
  }

  /// <summary>
  /// Stops one saved program and leaves it stopped until <see cref="StartProgramAsync"/> or a service restart.
  /// </summary>
  public async Task<ProcessControlResult> StopProgramAsync(string requestedPath, CancellationToken cancellationToken) {
    var process = ProcessControlChannel.Find(_optionsMonitor.CurrentValue, requestedPath);
    if (process is null)
      return new ProcessControlResult(false, "That program is not in the service configuration.");

    var key = PathHelper.ResolvePath(process.Path);
    var running = Detach(key, hold: true);
    if (running is not null)
      await AwaitRun(running.Value.Task, cancellationToken);

    running?.Cts.Dispose();
    _logger.LogInformation("Manual stop requested for {Path}", key);
    return new ProcessControlResult(true, "The service stopped the program. It stays stopped until you start it.");
  }

  /// <summary>
  /// Stops one saved program if it is running, then starts it again.
  /// </summary>
  public async Task<ProcessControlResult> RestartProgramAsync(string requestedPath, CancellationToken cancellationToken) {
    var process = FindEnabled(requestedPath, out var failure);
    if (process is null)
      return failure!;

    var key = PathHelper.ResolvePath(process.Path);
    var running = Detach(key, hold: true);
    if (running is not null)
      await AwaitRun(running.Value.Task, cancellationToken);

    running?.Cts.Dispose();

    await _gate.WaitAsync(cancellationToken);
    try {
      _held.TryRemove(key, out _);
      _down.TryRemove(key, out _);
      if (IsRunning(key))
        return new ProcessControlResult(false, "That program is already running.");

      BeginRun(key, process);
    }
    finally {
      _gate.Release();
    }

    _logger.LogInformation("Manual restart requested for {Path}", key);
    return new ProcessControlResult(true, "The service restarted the program.");
  }

  private async Task SuperviseAsync(string key, ProcessConfiguration process, CancellationToken stoppingToken) {
    Task<ProcessRunResult>? retiring = null;
    CancellationTokenSource? retiringCts = null;
    var supervision = ProcessSupervision.For(process);

    await _gate.WaitAsync(stoppingToken);
    try {
      if (_held.ContainsKey(key))
        return;

      if (supervision.KeepRunning)
        _down.TryRemove(key, out _);
      else if (_down.ContainsKey(key))
        return;

      if (_runs.TryGetValue(key, out var existing)) {
        if (!existing.Task.IsCompleted && SameArgs(existing.Args, process.Args) && existing.Supervision == supervision)
          return;

        existing.Cts.Cancel();
        _runs.TryRemove(key, out _);
        retiring = existing.Task;
        retiringCts = existing.Cts;
      }
      else {
        BeginRun(key, process);
        return;
      }
    }
    finally {
      _gate.Release();
    }

    if (retiring is null)
      return;

    ProcessRunResult result;
    try {
      result = await retiring.WaitAsync(stoppingToken);
    }
    catch (OperationCanceledException) {
      result = new ProcessRunResult(true, null, false);
    }
    catch (Exception ex) {
      _logger.LogError(ex, "{Message}", ex.Message);
      result = new ProcessRunResult(true, null, !supervision.KeepRunning);
    }

    retiringCts?.Dispose();

    await _gate.WaitAsync(stoppingToken);
    try {
      if (_held.ContainsKey(key) || _runs.ContainsKey(key))
        return;

      if (result.StayDown && !supervision.KeepRunning) {
        _down.TryAdd(key, 0);
        return;
      }

      if (_down.ContainsKey(key))
        return;

      BeginRun(key, process);
    }
    finally {
      _gate.Release();
    }
  }

  private (Task<ProcessRunResult> Task, CancellationTokenSource Cts)? Detach(string key, bool hold) {
    _gate.Wait();
    try {
      if (hold)
        _held[key] = 0;

      if (!_runs.TryRemove(key, out var run))
        return null;

      run.Cts.Cancel();
      return (run.Task, run.Cts);
    }
    finally {
      _gate.Release();
    }
  }

  private ProcessConfiguration? FindEnabled(string requestedPath, out ProcessControlResult? failure) {
    failure = null;
    var process = ProcessControlChannel.Find(_optionsMonitor.CurrentValue, requestedPath);
    if (process is null) {
      failure = new ProcessControlResult(false, "That program is not in the service configuration.");
      return null;
    }

    if (process.Disabled) {
      failure = new ProcessControlResult(false, "That program is disabled.");
      return null;
    }

    if (!HostPlatforms.IsCompatible(process.Platforms)) {
      failure = new ProcessControlResult(false, "That program cannot run on this operating system.");
      return null;
    }

    return process;
  }

  private void BeginRun(string key, ProcessConfiguration process) {
    var supervision = ProcessSupervision.For(process);
    var cts = CancellationTokenSource.CreateLinkedTokenSource(_hostStopping);
    var task = _processService.RunProcessAsync(process.Path, process.Args, supervision, cts.Token);
    _runs[key] = new SupervisedRun(cts, task, process.Args, supervision);
    var argsString = process.Args != null ? string.Join(", ", process.Args) : "";
    _logger.LogInformation($"Launching process {process.Path} with arguments {argsString}");
  }

  private bool IsRunning(string key) =>
    _runs.TryGetValue(key, out var run) && !run.Task.IsCompleted;

  private void DropCompleted(string key) {
    if (!_runs.TryGetValue(key, out var run) || !run.Task.IsCompleted)
      return;

    _runs.TryRemove(key, out _);
    run.Cts.Dispose();
  }

  private static async Task AwaitRun(Task<ProcessRunResult> running, CancellationToken cancellationToken) {
    try {
      await running.WaitAsync(cancellationToken);
    }
    catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) {
    }
    catch (Exception) {
    }
  }

  private static bool SameArgs(string[]? left, string[]? right) {
    if (left is null || left.Length == 0)
      return right is null || right.Length == 0;

    if (right is null || left.Length != right.Length)
      return false;

    return left.SequenceEqual(right, StringComparer.Ordinal);
  }

  private sealed class SupervisedRun(
    CancellationTokenSource cts,
    Task<ProcessRunResult> task,
    string[]? args,
    ProcessSupervision supervision) {
    public CancellationTokenSource Cts { get; } = cts;

    public Task<ProcessRunResult> Task { get; } = task;

    public string[]? Args { get; } = args;

    public ProcessSupervision Supervision { get; } = supervision;
  }
}
