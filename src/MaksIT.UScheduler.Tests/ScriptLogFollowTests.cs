using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.UI.Services;


namespace MaksIT.UScheduler.Tests;

public class ScriptLogFollowTests {
  [Fact]
  public void Today_UsesScriptFileNameAndUtcDate() {
    var path = ScriptLogFollow.Today(
      Path.Combine("C:", "Logs"),
      Path.Combine("C:", "Scripts", "File-Sync", "file-sync.ps1"));
    var expected = Path.Combine(
      "C:",
      "Logs",
      "file-sync",
      "log_" + DateTime.UtcNow.ToString("yyyy-MM-dd") + ".txt");

    Assert.Equal(expected, path);
  }

  [Fact]
  public void ReadNewText_ReturnsOnlyBytesAfterPosition() {
    var dir = Path.Combine(Path.GetTempPath(), "uscheduler-log-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(dir);
    try {
      var path = Path.Combine(dir, "log.txt");
      File.WriteAllText(path, "one\n");
      long position = 0;
      var first = ScriptLogFollow.ReadNewText(path, ref position);
      Assert.Equal("one\n", first);

      File.AppendAllText(path, "two\n");
      var second = ScriptLogFollow.ReadNewText(path, ref position);
      Assert.Equal("two\n", second);
      Assert.Equal("", ScriptLogFollow.ReadNewText(path, ref position));
    }
    finally {
      Directory.Delete(dir, true);
    }
  }

  [Fact]
  public void ReadNewText_WhenFileIsMissing_LeavesPosition() {
    long position = 4;
    var missing = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "missing.txt");
    var text = ScriptLogFollow.ReadNewText(missing, ref position);

    Assert.Equal("", text);
    Assert.Equal(4, position);
  }

  [Fact]
  public void ReadNewText_WhenFileShrinks_ReadsFromTheStart() {
    var dir = Path.Combine(Path.GetTempPath(), "uscheduler-log-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(dir);
    try {
      var path = Path.Combine(dir, "log.txt");
      File.WriteAllText(path, "short");
      long position = 100;
      var text = ScriptLogFollow.ReadNewText(path, ref position);

      Assert.Equal("short", text);
      Assert.Equal(5, position);
    }
    finally {
      Directory.Delete(dir, true);
    }
  }

  [Fact]
  public void FormatPowerShell_StripsFileLoggerDecorations() {
    var pending = "";
    var level = "";
    var raw = "2026-10-23T15:04:00.1234567Z [Information] [PS Output] [Info] Manual execution started\r\n"
      + "2026-10-23T15:04:01.0000000Z [Error] [PS Error] boom\n";
    var shown = ScriptLogFollow.FormatPowerShell(raw, ref pending, ref level, out var finished);

    Assert.False(finished);
    Assert.Equal("", pending);
    Assert.Equal("[Info] Manual execution started", shown[0].Text);
    Assert.Equal("Info", shown[0].Level);
    Assert.Equal("boom", shown[1].Text);
    Assert.Equal("Error", shown[1].Level);
  }

  [Fact]
  public void FormatPowerShell_AssignsWriteLogColorsAndKeepsErrorDetail() {
    var pending = "";
    var level = "";
    var raw = "2026-10-23T15:04:00.0000000Z [Information] [PS Output] [Success] Copied\n"
      + "2026-10-23T15:04:01.0000000Z [Warning] [PS Output] [Warning] Careful\n"
      + "2026-10-23T15:04:02.0000000Z [Error] [PS Error] boom\n"
      + "    + CategoryInfo : fail\n";
    var shown = ScriptLogFollow.FormatPowerShell(raw, ref pending, ref level, out _);

    Assert.Equal(["Success", "Warning", "Error", "Error"], shown.Select(line => line.Level));
    Assert.Equal("[Success] Copied", shown[0].Text);
    Assert.Equal("[Warning] Careful", shown[1].Text);
    Assert.Equal("    + CategoryInfo : fail", shown[3].Text);
  }

  [Fact]
  public void FormatPowerShell_HidesFinishedMarkerAndKeepsEarlierLines() {
    var pending = "";
    var level = "";
    var raw = "2026-10-23T15:04:00.1234567Z [Information] [PS Output] [Info] Done\n"
      + "2026-10-23T15:04:01.0000000Z [Information] " + ScriptRunMarkers.FinishedMessage + "\n";
    var shown = ScriptLogFollow.FormatPowerShell(raw, ref pending, ref level, out var finished);

    Assert.True(finished);
    Assert.Single(shown);
    Assert.Equal("[Info] Done", shown[0].Text);
  }

  [Fact]
  public void FormatPowerShell_KeepsPartialLineUntilNewline() {
    var pending = "";
    var level = "";
    var first = ScriptLogFollow.FormatPowerShell(
      "2026-10-23T15:04:00.1234567Z [Information] [PS Output] [Info] Hel",
      ref pending,
      ref level,
      out var finished);
    Assert.Empty(first);
    Assert.False(finished);
    Assert.NotEqual("", pending);

    var second = ScriptLogFollow.FormatPowerShell("lo\n", ref pending, ref level, out finished);
    Assert.False(finished);
    Assert.Equal("", pending);
    Assert.Equal("[Info] Hello", second[0].Text);
    Assert.Equal("Info", second[0].Level);
  }

  [Fact]
  public void FormatPowerShell_ReadsLevelWhenTimestampIsNotIso() {
    var pending = "";
    var level = "";
    var raw = "2026-10-23 15:04:01 [Information] [PS Output] [Warning] Careful\n";
    var shown = ScriptLogFollow.FormatPowerShell(raw, ref pending, ref level, out _);

    Assert.Equal("[Warning] Careful", shown[0].Text);
    Assert.Equal("Warning", shown[0].Level);
  }
}
