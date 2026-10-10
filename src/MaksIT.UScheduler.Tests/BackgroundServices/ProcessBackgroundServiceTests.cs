using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.BackgroundServices;


namespace MaksIT.UScheduler.Tests.BackgroundServices;

/// <summary>
/// Unit tests for ProcessBackgroundService.
/// </summary>
public class ProcessBackgroundServiceTests {
  private readonly Mock<ILogger<ProcessBackgroundService>> _loggerMock;
  private readonly Mock<IProcessService> _processServiceMock;

  public ProcessBackgroundServiceTests() {
    _loggerMock = new Mock<ILogger<ProcessBackgroundService>>();
    _processServiceMock = new Mock<IProcessService>();
  }

  private ProcessBackgroundService CreateService(Configuration config) {
    var optionsMonitorMock = new Mock<IOptionsMonitor<Configuration>>();
    optionsMonitorMock.Setup(m => m.CurrentValue).Returns(config);
    return new ProcessBackgroundService(_loggerMock.Object, optionsMonitorMock.Object, _processServiceMock.Object);
  }

  [Fact]
  public async Task ExecuteAsync_WithNoProcesses_DoesNotCallRunProcessAsync() {
    // Arrange
    var config = new Configuration { LogDir = ".\\Logs", Processes = [] };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Act - cancel immediately to stop the service
    cts.Cancel();

    // Start the service - it should complete without errors
    await service.StartAsync(cts.Token);

    // Assert
    _processServiceMock.Verify(
      x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  [Fact]
  public async Task ExecuteAsync_WithDisabledProcess_DoesNotRunDisabledProcess() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [
        new ProcessConfiguration { Path = @"C:\app.exe", Disabled = true }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Act
    cts.Cancel();
    await service.StartAsync(cts.Token);

    // Assert - disabled processes should not be run
    _processServiceMock.Verify(
      x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  [Fact]
  public async Task ExecuteAsync_WithEmptyPath_DoesNotRunProcess() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [new ProcessConfiguration { Path = "" }]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Act
    cts.Cancel();
    await service.StartAsync(cts.Token);

    // Assert - processes with empty paths should not be run
    _processServiceMock.Verify(
      x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  [Fact]
  public async Task StopAsync_TerminatesAllProcesses() {
    // Arrange
    var config = new Configuration { LogDir = ".\\Logs" };
    var service = CreateService(config);

    // Act
    await service.StopAsync(CancellationToken.None);

    // Assert
    _processServiceMock.Verify(x => x.TerminateAllProcesses(), Times.Once);
  }

  [Fact]
  public async Task ExecuteAsync_WithEnabledProcess_CallsRunProcessAsync() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [
        new ProcessConfiguration { Path = @"C:\app.exe", Disabled = false }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Setup mock to complete immediately
    _processServiceMock
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()))
      .ReturnsAsync(new ProcessRunResult(true, 0, false));

    // Act - start the service then cancel after a short delay
    var executeTask = service.StartAsync(cts.Token);

    // Give it a moment to start processing, then cancel
    await Task.Delay(100);
    cts.Cancel();

    // Wait for the service to stop gracefully
    try {
      await service.StopAsync(CancellationToken.None);
    }
    catch (OperationCanceledException) {
      // Expected when cancelling
    }

    // Assert - the enabled process should have been run at least once
    _processServiceMock.Verify(
      x => x.RunProcessAsync(
        @"C:\app.exe",
        It.IsAny<string[]?>(),
        It.Is<ProcessSupervision>(s => s.KeepRunning && s.Throttle == TimeSpan.FromMilliseconds(1500)),
        It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
  }

  [Fact]
  public async Task ExecuteAsync_WithProcessArgs_PassesArgsToService() {
    // Arrange
    var expectedArgs = new[] { "--verbose", "--log" };
    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [
        new ProcessConfiguration {
          Path = @"C:\app.exe",
          Disabled = false,
          Args = expectedArgs
        }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    _processServiceMock
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()))
      .ReturnsAsync(new ProcessRunResult(true, 0, false));

    // Act
    var executeTask = service.StartAsync(cts.Token);
    await Task.Delay(100);
    cts.Cancel();

    try {
      await service.StopAsync(CancellationToken.None);
    }
    catch (OperationCanceledException) {
      // Expected
    }

    // Assert - verify args were passed correctly
    _processServiceMock.Verify(
      x => x.RunProcessAsync(
        @"C:\app.exe",
        expectedArgs,
        It.Is<ProcessSupervision>(s => s.KeepRunning),
        It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
  }

  [Fact]
  public async Task ExecuteAsync_PassesRestartOnFailure() {
    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [
        new ProcessConfiguration {
          Path = @"C:\app.exe",
          RestartOnFailure = true,
          RestartDelayMs = 500,
          ThrottleMs = 2500
        }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    _processServiceMock
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()))
      .ReturnsAsync(new ProcessRunResult(true, 0, false));

    await service.StartAsync(cts.Token);
    await Task.Delay(100);
    cts.Cancel();

    try {
      await service.StopAsync(CancellationToken.None);
    }
    catch (OperationCanceledException) {
    }

    _processServiceMock.Verify(
      x => x.RunProcessAsync(
        @"C:\app.exe",
        It.IsAny<string[]?>(),
        It.Is<ProcessSupervision>(s =>
          s.KeepRunning
          && s.RestartDelay == TimeSpan.FromMilliseconds(500)
          && s.Throttle == TimeSpan.FromMilliseconds(2500)),
        It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
  }

  [Fact]
  public async Task ExecuteAsync_StartsEachProcessWithoutWaitingForTheOthers() {
    var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    var release = new TaskCompletionSource<ProcessRunResult>(TaskCreationOptions.RunContinuationsAsynchronously);
    var calls = 0;

    _processServiceMock
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()))
      .Returns(() => {
        if (Interlocked.Increment(ref calls) >= 2)
          started.TrySetResult();

        return release.Task;
      });

    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [
        new ProcessConfiguration { Path = @"C:\a.exe" },
        new ProcessConfiguration { Path = @"C:\b.exe" }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    await service.StartAsync(cts.Token);
    var finished = await Task.WhenAny(started.Task, Task.Delay(2000));
    cts.Cancel();
    release.TrySetResult(new ProcessRunResult(true, 0, false));

    try {
      await service.StopAsync(CancellationToken.None);
    }
    catch (OperationCanceledException) {
    }

    Assert.Same(started.Task, finished);
  }

  [Fact]
  public async Task StopAsync_ReturnsWhileAProcessIsStillRunning() {
    var hung = new TaskCompletionSource<ProcessRunResult>(TaskCreationOptions.RunContinuationsAsynchronously);

    _processServiceMock
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()))
      .Returns(hung.Task);

    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [new ProcessConfiguration { Path = @"C:\app.exe" }]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    await service.StartAsync(cts.Token);
    await Task.Delay(100);

    var stop = service.StopAsync(CancellationToken.None);
    var finished = await Task.WhenAny(stop, Task.Delay(2000));
    hung.TrySetResult(new ProcessRunResult(true, 0, false));

    Assert.Same(stop, finished);
    await stop;
  }

  [Fact]
  public async Task StopProgram_stays_down_until_start() {
    var calls = 0;
    _processServiceMock
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()))
      .Returns((string _, string[]? _, ProcessSupervision _, CancellationToken token) => {
        Interlocked.Increment(ref calls);
        var done = new TaskCompletionSource<ProcessRunResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        token.Register(() => done.TrySetResult(new ProcessRunResult(true, null, false)));
        return done.Task;
      });

    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [new ProcessConfiguration { Path = @"C:\app.exe", Name = "Demo" }]
    };
    var service = new ProcessBackgroundService(
      _loggerMock.Object,
      Options(config),
      _processServiceMock.Object,
      TimeSpan.FromMilliseconds(30));
    using var cts = new CancellationTokenSource();

    await service.StartAsync(cts.Token);
    Assert.True(await WaitFor(() => Volatile.Read(ref calls) >= 1), "the program did not start");

    var stopped = await service.StopProgramAsync(@"C:\app.exe", CancellationToken.None);
    Assert.True(stopped.Accepted);
    await Task.Delay(180, TestContext.Current.CancellationToken);
    var afterStop = Volatile.Read(ref calls);

    var started = await service.StartProgramAsync(@"C:\app.exe", CancellationToken.None);
    Assert.True(started.Accepted);
    Assert.Equal(afterStop, calls - 1);

    cts.Cancel();
    try {
      await service.StopAsync(CancellationToken.None);
    }
    catch (OperationCanceledException) {
    }
  }

  [Fact]
  public async Task RestartProgram_starts_a_new_run() {
    var tokens = new List<CancellationToken>();
    _processServiceMock
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()))
      .Returns((string _, string[]? _, ProcessSupervision _, CancellationToken token) => {
        lock (tokens)
          tokens.Add(token);

        var done = new TaskCompletionSource<ProcessRunResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        token.Register(() => done.TrySetResult(new ProcessRunResult(true, null, false)));
        return done.Task;
      });

    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [new ProcessConfiguration { Path = @"C:\app.exe" }]
    };
    var service = CreateService(config);

    var started = await service.StartProgramAsync(@"C:\app.exe", CancellationToken.None);
    var restarted = await service.RestartProgramAsync(@"C:\app.exe", CancellationToken.None);

    Assert.True(started.Accepted);
    Assert.True(restarted.Accepted);
    Assert.Equal(2, tokens.Count);
    Assert.True(tokens[0].IsCancellationRequested);
    Assert.False(tokens[1].IsCancellationRequested);
  }

  [Fact]
  public async Task StartProgram_rejects_a_disabled_program() {
    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [new ProcessConfiguration { Path = @"C:\app.exe", Disabled = true }]
    };
    var service = CreateService(config);

    var result = await service.StartProgramAsync(@"C:\app.exe", CancellationToken.None);

    Assert.False(result.Accepted);
    _processServiceMock.Verify(
      x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<ProcessSupervision>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  private static IOptionsMonitor<Configuration> Options(Configuration config) {
    var options = new Mock<IOptionsMonitor<Configuration>>();
    options.Setup(monitor => monitor.CurrentValue).Returns(config);
    return options.Object;
  }

  private static async Task<bool> WaitFor(Func<bool> ready) {
    var start = Environment.TickCount64;
    while (!ready()) {
      if (Environment.TickCount64 - start > 2000)
        return false;

      await Task.Delay(15);
    }

    return true;
  }
}
