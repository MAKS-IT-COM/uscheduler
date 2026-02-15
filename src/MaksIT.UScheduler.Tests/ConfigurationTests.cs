using MaksIT.UScheduler.Shared;
using Xunit;

namespace MaksIT.UScheduler.Tests;

/// <summary>
/// Unit tests for configuration classes.
/// </summary>
public class ConfigurationTests {
  private const string TestLogDir = ".\\Logs";

  [Fact]
  public void Configuration_DefaultValues_AreCorrect() {
    // Arrange & Act
    var config = new Configuration { LogDir = TestLogDir };

    // Assert
    Assert.Equal("MaksIT.UScheduler", config.ServiceName);
    Assert.Equal(TestLogDir, config.LogDir);
    Assert.NotNull(config.Powershell);
    Assert.Empty(config.Powershell);
    Assert.NotNull(config.Processes);
    Assert.Empty(config.Processes);
  }

  [Fact]
  public void Configuration_CanSetServiceName() {
    // Arrange
    var config = new Configuration { LogDir = TestLogDir };

    // Act
    config.ServiceName = "CustomServiceName";

    // Assert
    Assert.Equal("CustomServiceName", config.ServiceName);
  }

  [Fact]
  public void Configuration_CanSetLogDir() {
    // Arrange
    var config = new Configuration { LogDir = TestLogDir };

    // Act
    config.LogDir = @"C:\Logs";

    // Assert
    Assert.Equal(@"C:\Logs", config.LogDir);
  }

  [Fact]
  public void Configuration_CanAddPowerShellScripts() {
    // Arrange
    var config = new Configuration { LogDir = TestLogDir };
    var script = new PowershellScript { Path = @"C:\Scripts\test.ps1" };

    // Act
    config.Powershell.Add(script);

    // Assert
    Assert.Single(config.Powershell);
    Assert.Equal(@"C:\Scripts\test.ps1", config.Powershell[0].Path);
  }

  [Fact]
  public void Configuration_CanAddProcesses() {
    // Arrange
    var config = new Configuration { LogDir = TestLogDir };
    var process = new ProcessConfiguration { 
      Path = @"C:\App\app.exe",
      Args = ["--verbose", "--output", "log.txt"]
    };

    // Act
    config.Processes.Add(process);

    // Assert
    Assert.Single(config.Processes);
    Assert.Equal(@"C:\App\app.exe", config.Processes[0].Path);
    Assert.Equal(3, config.Processes[0].Args!.Length);
  }

  [Fact]
  public void PowershellScript_DefaultValues_AreCorrect() {
    // Arrange & Act
    var script = new PowershellScript { Path = @"C:\test.ps1" };

    // Assert
    Assert.Equal(@"C:\test.ps1", script.Path);
    Assert.True(script.IsSigned);  // Default should be true
    Assert.False(script.Disabled); // Default should be false
  }

  [Fact]
  public void PowershellScript_CanSetIsSigned() {
    // Arrange
    var script = new PowershellScript { Path = @"C:\test.ps1" };

    // Act
    script.IsSigned = false;

    // Assert
    Assert.False(script.IsSigned);
  }

  [Fact]
  public void PowershellScript_CanSetDisabled() {
    // Arrange
    var script = new PowershellScript { Path = @"C:\test.ps1" };

    // Act
    script.Disabled = true;

    // Assert
    Assert.True(script.Disabled);
  }

  [Fact]
  public void ProcessConfiguration_DefaultValues_AreCorrect() {
    // Arrange & Act
    var process = new ProcessConfiguration { Path = @"C:\app.exe" };

    // Assert
    Assert.Equal(@"C:\app.exe", process.Path);
    Assert.Null(process.Args);
    Assert.False(process.RestartOnFailure); // Default should be false
    Assert.False(process.Disabled);         // Default should be false
  }

  [Fact]
  public void ProcessConfiguration_CanSetArgs() {
    // Arrange
    var process = new ProcessConfiguration { Path = @"C:\app.exe" };

    // Act
    process.Args = ["arg1", "arg2"];

    // Assert
    Assert.NotNull(process.Args);
    Assert.Equal(2, process.Args.Length);
    Assert.Equal("arg1", process.Args[0]);
    Assert.Equal("arg2", process.Args[1]);
  }

  [Fact]
  public void ProcessConfiguration_CanSetRestartOnFailure() {
    // Arrange
    var process = new ProcessConfiguration { Path = @"C:\app.exe" };

    // Act
    process.RestartOnFailure = true;

    // Assert
    Assert.True(process.RestartOnFailure);
  }
}
