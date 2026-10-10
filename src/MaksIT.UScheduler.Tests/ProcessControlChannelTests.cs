using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.UI.ViewModels;


namespace MaksIT.UScheduler.Tests;

public class ProcessControlChannelTests {
  [Fact]
  public void Find_matches_the_configured_path() {
    var config = new Configuration {
      Processes = [
        new ProcessConfiguration { Path = @"C:\Tools\MyApp.exe", Name = "My app" }
      ]
    };

    Assert.NotNull(ProcessControlChannel.Find(config, @"C:\Tools\MyApp.exe"));
    Assert.Null(ProcessControlChannel.Find(config, @"C:\Tools\Other.exe"));
  }

  [Fact]
  public void Result_round_trips() {
    var json = ProcessControlChannel.SerializeResult(new ProcessControlResult(true, "The service started the program."));
    var back = ProcessControlChannel.DeserializeResult(json);

    Assert.NotNull(back);
    Assert.True(back!.Accepted);
    Assert.Equal("The service started the program.", back.Message);
  }

  [Fact]
  public async Task RequestAsync_when_the_service_is_not_running_returns_failure() {
    var result = await ProcessControlChannel.RequestAsync(
      @"C:\Tools\MyApp.exe",
      ProcessControlChannel.Start,
      TestContext.Current.CancellationToken,
      "MaksIT.UScheduler.Process." + Guid.NewGuid().ToString("N"),
      200);

    Assert.False(result.Accepted);
    Assert.Contains("not running", result.Message, StringComparison.OrdinalIgnoreCase);
  }

  [Fact]
  public void Name_is_the_list_label_and_round_trips() {
    var row = SupervisedProcessRow.From(new ProcessConfiguration {
      Path = @"C:\Tools\MyApp.exe",
      Name = "My app"
    });

    Assert.Equal("My app", row.ListTitle);
    Assert.Equal("My app", row.ToConfiguration().Name);

    row.Name = "  ";
    Assert.Equal("MyApp.exe", row.ListTitle);
    Assert.Null(row.ToConfiguration().Name);
  }
}
