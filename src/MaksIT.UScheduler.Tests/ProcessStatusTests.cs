using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Tests;

public class ProcessStatusTests {
  [Fact]
  public void Status_file_round_trip_replaces_the_same_path() {
    var directory = Path.Combine(Path.GetTempPath(), "uscheduler-status-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(directory);
    try {
      var options = new Mock<IOptionsMonitor<Configuration>>();
      options.Setup(monitor => monitor.CurrentValue).Returns(new Configuration { LogDir = directory });
      var store = new ProcessStatusFileStore(options.Object);

      store.Upsert(new ProcessStatusEntry { Path = Path.Combine(directory, "app.exe"), State = ProcessStates.Running, ProcessId = 4 });
      store.Upsert(new ProcessStatusEntry { Path = Path.Combine(directory, "app.exe"), State = ProcessStates.Stopped, LastExitCode = 3 });

      var snapshot = ProcessStatusFileStore.Load(directory);

      var entry = Assert.Single(snapshot.Processes);
      Assert.Equal(ProcessStates.Stopped, entry.State);
      Assert.Equal(3, entry.LastExitCode);
      Assert.Null(entry.ProcessId);
    }
    finally {
      Directory.Delete(directory, recursive: true);
    }
  }

  [Theory]
  [InlineData(true, "Disabled", "Gray")]
  public void Disabled_program_stays_disabled(bool serviceRunning, string text, string color) {
    var (actualText, actualColor) = ProcessRuntimeStatus.Describe(
      serviceRunning,
      disabled: true,
      new ProcessStatusEntry { Path = "app.exe", State = ProcessStates.Running, ProcessId = 1 },
      _ => true);

    Assert.Equal(text, actualText);
    Assert.Equal(color, actualColor);
  }

  [Fact]
  public void Stopped_service_hides_a_stale_running_state() {
    var (text, color) = ProcessRuntimeStatus.Describe(
      serviceRunning: false,
      disabled: false,
      new ProcessStatusEntry { Path = "app.exe", State = ProcessStates.Running, ProcessId = 9 },
      _ => true);

    Assert.Equal("Service stopped", text);
    Assert.Equal("Gray", color);
  }

  [Fact]
  public void Live_process_shows_running() {
    var (text, color) = ProcessRuntimeStatus.Describe(
      serviceRunning: true,
      disabled: false,
      new ProcessStatusEntry { Path = "app.exe", State = ProcessStates.Running, ProcessId = 9 },
      _ => true);

    Assert.Equal("Running", text);
    Assert.Equal("Green", color);
  }

  [Fact]
  public void Service_running_state_is_shown_without_opening_the_process() {
    var (text, color) = ProcessRuntimeStatus.Describe(
      serviceRunning: true,
      disabled: false,
      new ProcessStatusEntry { Path = "app.exe", State = ProcessStates.Running, ProcessId = 4 });

    Assert.Equal("Running", text);
    Assert.Equal("Green", color);
  }

  [Fact]
  public void Dead_pid_shows_stopped() {
    var (text, color) = ProcessRuntimeStatus.Describe(
      serviceRunning: true,
      disabled: false,
      new ProcessStatusEntry { Path = "app.exe", State = ProcessStates.Running, ProcessId = 9 },
      _ => false);

    Assert.Equal("Stopped", text);
    Assert.Equal("Gray", color);
  }

  [Fact]
  public void Restarting_shows_restarting() {
    var (text, color) = ProcessRuntimeStatus.Describe(
      serviceRunning: true,
      disabled: false,
      new ProcessStatusEntry { Path = "app.exe", State = ProcessStates.Restarting },
      _ => false);

    Assert.Equal("Restarting", text);
    Assert.Equal("Orange", color);
  }

  [Fact]
  public void Missing_status_while_the_service_is_up_is_waiting() {
    var (text, color) = ProcessRuntimeStatus.Describe(serviceRunning: true, disabled: false, entry: null, _ => false);

    Assert.Equal("Waiting", text);
    Assert.Equal("Orange", color);
  }

  [Fact]
  public async Task A_finished_program_is_published_as_stopped() {
    var status = new MemoryStatus();
    using var factory = LoggerFactory.Create(_ => { });
    var service = new ProcessService(factory.CreateLogger<ProcessService>(), factory, status);
    var (path, args) = OperatingSystem.IsWindows()
      ? (Path.Combine(Environment.SystemDirectory, "cmd.exe"), new[] { "/c", "exit", "2" })
      : ("/bin/sh", new[] { "-c", "exit 2" });

    await service.RunProcessAsync(
      path,
      args,
      new ProcessSupervision(false, TimeSpan.Zero, TimeSpan.Zero, null),
      CancellationToken.None);

    var entry = Assert.Single(status.Entries);
    Assert.Equal(ProcessStates.Stopped, entry.State);
    Assert.Equal(2, entry.LastExitCode);
    Assert.Null(entry.ProcessId);
  }

  private sealed class MemoryStatus : IProcessStatusStore {
    public List<ProcessStatusEntry> Entries { get; } = [];

    public void Upsert(ProcessStatusEntry entry) {
      Entries.RemoveAll(item => string.Equals(item.Path, entry.Path, StringComparison.OrdinalIgnoreCase));
      Entries.Add(JsonSerializer.Deserialize<ProcessStatusEntry>(JsonSerializer.Serialize(entry))!);
    }
  }
}
