using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Tests;

public class ScriptRunChannelTests {
  [Fact]
  public void FindConfiguredScript_MatchesConfigPathAndResolvedPath() {
    var dir = Path.Combine(Path.GetTempPath(), $"uscheduler-run-{Guid.NewGuid():N}");
    Directory.CreateDirectory(dir);
    try {
      var config = new Configuration {
        ScriptsDir = dir,
        Powershell = [
          new PowershellScript { Path = Path.Combine("File-Sync", "file-sync.ps1"), IsSigned = false }
        ]
      };

      var relative = Path.Combine("File-Sync", "file-sync.ps1");
      Assert.NotNull(ScriptRunChannel.FindConfiguredScript(config, relative));
      Assert.NotNull(ScriptRunChannel.FindConfiguredScript(config, config.ResolveScriptPath(relative)));
      Assert.Null(ScriptRunChannel.FindConfiguredScript(config, Path.Combine("Other", "nope.ps1")));
    }
    finally {
      Directory.Delete(dir, true);
    }
  }

  [Fact]
  public void Result_round_trips() {
    var json = ScriptRunChannel.SerializeResult(new ScriptRunResult(true, "The service started the script."));
    var back = ScriptRunChannel.DeserializeResult(json);
    Assert.NotNull(back);
    Assert.True(back!.Accepted);
    Assert.Equal("The service started the script.", back.Message);
  }

  [Fact]
  public async Task RequestAsync_WhenServiceIsNotRunning_ReturnsFailure() {
    var result = await ScriptRunChannel.RequestAsync(
      "File-Sync\\file-sync.ps1",
      TestContext.Current.CancellationToken,
      "MaksIT.UScheduler.Run." + Guid.NewGuid().ToString("N"),
      200);

    Assert.False(result.Accepted);
    Assert.Contains("not running", result.Message, StringComparison.OrdinalIgnoreCase);
  }
}
