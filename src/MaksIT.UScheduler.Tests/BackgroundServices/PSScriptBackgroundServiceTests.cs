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
/// Unit tests for PSScriptBackgroundService.
/// </summary>
public class PSScriptBackgroundServiceTests {
  private readonly Mock<ILogger<PSScriptBackgroundService>> _loggerMock;
  private readonly Mock<IPSScriptService> _psScriptServiceMock;

  public PSScriptBackgroundServiceTests() {
    _loggerMock = new Mock<ILogger<PSScriptBackgroundService>>();
    _psScriptServiceMock = new Mock<IPSScriptService>();
  }

  private PSScriptBackgroundService CreateService(Configuration config) {
    var optionsMonitorMock = new Mock<IOptionsMonitor<Configuration>>();
    optionsMonitorMock.Setup(m => m.CurrentValue).Returns(config);
    return new PSScriptBackgroundService(_loggerMock.Object, optionsMonitorMock.Object, _psScriptServiceMock.Object);
  }

  [Fact]
  public async Task ExecuteAsync_WithNoScripts_DoesNotCallRunScriptAsync() {
    // Arrange
    var config = new Configuration { LogDir = ".\\Logs", Powershell = [] };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Act
    cts.Cancel();
    await service.StartAsync(cts.Token);

    // Assert
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  [Fact]
  public async Task ExecuteAsync_WithDisabledScript_DoesNotRunDisabledScript() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Powershell = [
        new PowershellScript { Path = @"C:\Scripts\test.ps1", Disabled = true }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Act
    cts.Cancel();
    await service.StartAsync(cts.Token);

    // Assert
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  [Fact]
  public async Task ExecuteAsync_WithEmptyPath_DoesNotRunScript() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Powershell = [ new PowershellScript { Path = "" } ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    // Act
    cts.Cancel();
    await service.StartAsync(cts.Token);

    // Assert
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()),
      Times.Never);
  }

  [Fact]
  public async Task StopAsync_TerminatesAllScripts() {
    // Arrange
    var config = new Configuration { LogDir = ".\\Logs" };
    var service = CreateService(config);

    // Act
    await service.StopAsync(CancellationToken.None);

    // Assert
    _psScriptServiceMock.Verify(x => x.TerminateAllScripts(), Times.Once);
  }

  [Fact]
  public async Task ExecuteAsync_WithEnabledScript_CallsRunScriptAsync() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Powershell = [
        new PowershellScript { Path = @"C:\Scripts\test.ps1", Disabled = false, IsSigned = true }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    _psScriptServiceMock
      .Setup(x => x.RunScriptAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
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

    // Assert
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(@"C:\Scripts\test.ps1", true, It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
  }

  [Fact]
  public async Task ExecuteAsync_WithUnsignedScript_PassesIsSignedFalse() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Powershell = [
        new PowershellScript { Path = @"C:\Scripts\test.ps1", Disabled = false, IsSigned = false }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    _psScriptServiceMock
      .Setup(x => x.RunScriptAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
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

    // Assert - verify IsSigned=false was passed
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(@"C:\Scripts\test.ps1", false, It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
  }

  [Fact]
  public async Task ExecuteAsync_WithMultipleScripts_RunsAllEnabledScripts() {
    // Arrange
    var config = new Configuration {
      LogDir = ".\\Logs",
      Powershell = [
        new PowershellScript { Path = @"C:\Scripts\script1.ps1", Disabled = false },
        new PowershellScript { Path = @"C:\Scripts\script2.ps1", Disabled = true },
        new PowershellScript { Path = @"C:\Scripts\script3.ps1", Disabled = false }
      ]
    };
    var service = CreateService(config);
    using var cts = new CancellationTokenSource();

    _psScriptServiceMock
      .Setup(x => x.RunScriptAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
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

    // Assert - only enabled scripts should run
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(@"C:\Scripts\script1.ps1", It.IsAny<bool>(), It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(@"C:\Scripts\script2.ps1", It.IsAny<bool>(), It.IsAny<CancellationToken>()),
      Times.Never);
    _psScriptServiceMock.Verify(
      x => x.RunScriptAsync(@"C:\Scripts\script3.ps1", It.IsAny<bool>(), It.IsAny<CancellationToken>()),
      Times.AtLeastOnce);
  }
}
