using MaksIT.UScheduler;
using MaksIT.UScheduler.BackgroundServices;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.Shared;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using Xunit;

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
      x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<CancellationToken>()),
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
      x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  [Fact]
  public async Task ExecuteAsync_WithEmptyPath_DoesNotRunProcess() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Processes = [ new ProcessConfiguration { Path = "" } ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Act
    cts.Cancel();
    await service.StartAsync(cts.Token);

    // Assert - processes with empty paths should not be run
    _processServiceMock.Verify(
      x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<CancellationToken>()),
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
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<CancellationToken>()))
      .Returns(Task.CompletedTask);

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
      x => x.RunProcessAsync(@"C:\app.exe", It.IsAny<string[]?>(), It.IsAny<CancellationToken>()),
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
      .Setup(x => x.RunProcessAsync(It.IsAny<string>(), It.IsAny<string[]?>(), It.IsAny<CancellationToken>()))
      .Returns(Task.CompletedTask);

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
      x => x.RunProcessAsync(@"C:\app.exe", expectedArgs, It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
  }
}
