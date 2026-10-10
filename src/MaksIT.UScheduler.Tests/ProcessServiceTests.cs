using Microsoft.Extensions.Logging;
using MaksIT.UScheduler.Services;


namespace MaksIT.UScheduler.Tests;

public class ProcessServiceTests {
  private static OwnedService CreateService() {
    var factory = LoggerFactory.Create(_ => { });
    return new OwnedService(new ProcessService(factory.CreateLogger<ProcessService>(), factory), factory);
  }

  [Fact]
  public async Task Two_different_programs_run_at_the_same_time() {
    using var owned = CreateService();
    var service = owned.Service;
    var (first, firstArgs, second, secondArgs) = LongRunningPair();
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20));

    var left = service.RunProcessAsync(first, firstArgs, Once, cts.Token);
    var right = service.RunProcessAsync(second, secondArgs, Once, cts.Token);

    var sawBoth = false;
    for (var i = 0; i < 20 && !sawBoth; i++) {
      sawBoth = service.GetRunningProcesses().Count >= 2;
      if (!sawBoth)
        await Task.Delay(50);
    }

    await cts.CancelAsync();
    await Task.WhenAll(left, right);

    Assert.True(sawBoth);
  }

  [Fact]
  public async Task Second_start_of_the_same_program_is_left_alone() {
    using var owned = CreateService();
    var service = owned.Service;
    var (path, args) = OneLongRunning();
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20));

    var first = service.RunProcessAsync(path, args, Once, cts.Token);
    await Task.Delay(200);
    var second = await service.RunProcessAsync(path, args, Once, cts.Token);

    await cts.CancelAsync();
    await first;

    Assert.False(second.Started);
    Assert.Empty(service.GetRunningProcesses());
  }

  [Fact]
  public async Task NonZero_exit_stays_down_unless_restart_is_set() {
    using var owned = CreateService();
    var service = owned.Service;
    var (path, args) = Exit(2);

    var result = await service.RunProcessAsync(path, args, Once, CancellationToken.None);

    Assert.True(result.Started);
    Assert.Equal(2, result.ExitCode);
    Assert.True(result.StayDown);
    Assert.Empty(service.GetRunningProcesses());
  }

  [Fact]
  public async Task Exit_leaves_the_program_stopped_when_it_is_not_kept_running() {
    using var owned = CreateService();
    var service = owned.Service;
    var (path, args) = Exit(0);

    var result = await service.RunProcessAsync(path, args, Once, CancellationToken.None);

    Assert.Equal(0, result.ExitCode);
    Assert.True(result.StayDown);
  }

  [Fact]
  public async Task Keep_running_starts_the_program_again_after_it_exits() {
    using var owned = CreateService();
    var service = owned.Service;
    var log = Path.Combine(Path.GetTempPath(), "uscheduler-process-" + Guid.NewGuid().ToString("N") + ".txt");
    try {
      var (path, args) = AppendLine(log);
      var supervision = new ProcessSupervision(true, TimeSpan.Zero, TimeSpan.FromMilliseconds(150), null);
      using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));

      var run = service.RunProcessAsync(path, args, supervision, cts.Token);
      var lines = 0;
      for (var i = 0; i < 40 && lines < 2; i++) {
        await Task.Delay(100);
        lines = CountLines(log);
      }

      await cts.CancelAsync();
      await run;

      Assert.True(lines >= 2);
    }
    finally {
      if (File.Exists(log))
        File.Delete(log);
    }
  }

  [Fact]
  public async Task A_fast_exit_waits_out_the_throttle_before_the_next_start() {
    using var owned = CreateService();
    var service = owned.Service;
    var log = Path.Combine(Path.GetTempPath(), "uscheduler-process-" + Guid.NewGuid().ToString("N") + ".txt");
    try {
      var (path, args) = AppendLine(log);
      var supervision = new ProcessSupervision(true, TimeSpan.Zero, TimeSpan.FromMilliseconds(2000), null);
      using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
      var run = service.RunProcessAsync(path, args, supervision, cts.Token);

      var sawOne = false;
      for (var i = 0; i < 30 && !sawOne; i++) {
        await Task.Delay(100);
        sawOne = CountLines(log) >= 1;
      }

      await Task.Delay(400);
      var lines = CountLines(log);
      await cts.CancelAsync();
      await run;

      Assert.True(sawOne);
      Assert.Equal(1, lines);
    }
    finally {
      if (File.Exists(log))
        File.Delete(log);
    }
  }

  [Fact]
  public async Task Output_larger_than_the_pipe_does_not_stall_the_process() {
    using var owned = CreateService();
    var service = owned.Service;
    var (path, args) = LargeOutput();
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));

    var result = await service.RunProcessAsync(path, args, Once, cts.Token);

    Assert.False(cts.IsCancellationRequested);
    Assert.Equal(0, result.ExitCode);
  }

  private sealed class OwnedService(ProcessService service, ILoggerFactory factory) : IDisposable {
    public ProcessService Service => service;

    public void Dispose() {
      service.TerminateAllProcesses();
      factory.Dispose();
    }
  }

  private static readonly ProcessSupervision Once = new(false, TimeSpan.Zero, TimeSpan.Zero, null);

  private static int CountLines(string path) {
    if (!File.Exists(path))
      return 0;

    try {
      return File.ReadAllLines(path).Length;
    }
    catch (IOException) {
      return 0;
    }
  }

  private static (string Path, string[] Args) AppendLine(string log) {
    if (OperatingSystem.IsWindows()) {
      var powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
      return (powershell, ["-NoProfile", "-Command", "Add-Content -LiteralPath '" + log + "' -Value x"]);
    }

    return ("/bin/sh", ["-c", "echo x >> '" + log.Replace("'", "'\\''") + "'"]);
  }

  private static (string Path, string[] Args) OneLongRunning() {
    if (OperatingSystem.IsWindows())
      return (SystemFile("ping.exe"), ["127.0.0.1", "-n", "4"]);

    return ("/bin/sleep", ["2"]);
  }

  private static (string First, string[] FirstArgs, string Second, string[] SecondArgs) LongRunningPair() {
    if (OperatingSystem.IsWindows()) {
      return (
        SystemFile("ping.exe"), ["127.0.0.1", "-n", "4"],
        SystemFile("cmd.exe"), ["/c", "ping", "127.0.0.1", "-n", "4"]);
    }

    return ("/bin/sleep", ["2"], "/bin/sh", ["-c", "sleep 2"]);
  }

  private static (string Path, string[] Args) Exit(int code) {
    if (OperatingSystem.IsWindows())
      return (SystemFile("cmd.exe"), ["/c", "exit", code.ToString()]);

    return ("/bin/sh", ["-c", $"exit {code}"]);
  }

  private static (string Path, string[] Args) LargeOutput() {
    if (OperatingSystem.IsWindows()) {
      return (SystemFile("cmd.exe"), ["/c", "for /L %i in (1,1,4000) do @echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]);
    }

    return ("/bin/sh", ["-c", "i=0; while [ $i -lt 4000 ]; do echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx; i=$((i+1)); done"]);
  }

  private static string SystemFile(string name) =>
    Path.Combine(Environment.SystemDirectory, name);
}
