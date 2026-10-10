using MaksIT.UScheduler.UI.Services;


namespace MaksIT.UScheduler.Tests;

public class UISettingsLayoutTests {
  [Fact]
  public void Window_layout_round_trips() {
    var path = Path.Combine(Path.GetTempPath(), $"uscheduler-ui-{Guid.NewGuid():N}.json");
    var service = new UISettingsService(path);

    service.Save(new UISettings {
      WhatsNewSeenVersion = "1.2.0",
      WindowWidth = 1280,
      WindowHeight = 720,
      WindowX = 40,
      WindowY = 24,
      WindowState = "Maximized"
    });

    var loaded = service.Load();

    Assert.Equal("1.2.0", loaded.WhatsNewSeenVersion);
    Assert.Equal(1280, loaded.WindowWidth);
    Assert.Equal(720, loaded.WindowHeight);
    Assert.Equal(40, loaded.WindowX);
    Assert.Equal(24, loaded.WindowY);
    Assert.Equal("Maximized", loaded.WindowState);

    File.Delete(path);
  }

  [Fact]
  public void Missing_layout_uses_the_designed_window() {
    var path = Path.Combine(Path.GetTempPath(), $"uscheduler-ui-{Guid.NewGuid():N}.json");
    File.WriteAllText(path, """
      {
        "USchedulerSettings": {
          "WhatsNewSeenVersion": "1.0.0"
        }
      }
      """);

    var loaded = new UISettingsService(path).Load();

    Assert.Equal(UISettings.DefaultWindowWidth, loaded.WindowWidth);
    Assert.Equal(UISettings.DefaultWindowHeight, loaded.WindowHeight);
    Assert.Null(loaded.WindowX);
    Assert.Null(loaded.WindowY);
    Assert.Equal("Normal", loaded.WindowState);

    File.Delete(path);
  }
}
