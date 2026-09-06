using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Tests;

public class HostServiceRegistrationTests {
  [Fact]
  public void FormatWindowsCreateArguments_RequiresSpaceAfterEquals() {
    var arguments = HostServiceRegistration.FormatWindowsCreateArguments(
      "MaksIT.UScheduler",
      Path.Combine(Path.GetTempPath(), "MaksIT.UScheduler.exe"));

    Assert.Contains("binPath= ", arguments, StringComparison.Ordinal);
    Assert.Contains("start= auto", arguments, StringComparison.Ordinal);
    Assert.DoesNotContain("start=auto", arguments, StringComparison.Ordinal);
    Assert.Contains("create \"MaksIT.UScheduler\"", arguments, StringComparison.Ordinal);
  }

  [Fact]
  public void FormatSystemdUnit_UsesNotifyLifetimeAndQuotedPaths() {
    var unit = HostServiceRegistration.FormatSystemdUnit(
      "MaksIT.UScheduler",
      Path.Combine(Path.GetTempPath(), "MaksIT.UScheduler"),
      "Schedules PowerShell scripts.");

    Assert.Contains("Type=notify", unit, StringComparison.Ordinal);
    Assert.Contains("ExecStart=\"", unit, StringComparison.Ordinal);
    Assert.Contains("WorkingDirectory=\"", unit, StringComparison.Ordinal);
    Assert.Contains("WantedBy=multi-user.target", unit, StringComparison.Ordinal);
    Assert.Contains("SyslogIdentifier=MaksIT.UScheduler", unit, StringComparison.Ordinal);
    Assert.Contains("KillSignal=SIGTERM", unit, StringComparison.Ordinal);
  }

  [Fact]
  public void IsValidServiceName_AcceptsDefaultAndRejectsUnsafe() {
    Assert.True(HostServiceRegistration.IsValidServiceName("MaksIT.UScheduler"));
    Assert.False(HostServiceRegistration.IsValidServiceName("MaksIT Scheduler"));
    Assert.False(HostServiceRegistration.IsValidServiceName("../evil"));
    Assert.False(HostServiceRegistration.IsValidServiceName(""));
  }

  [Fact]
  public void GetSystemdUnitPath_IsUnderSystemdSystem() =>
    Assert.Equal(
      "/etc/systemd/system/MaksIT.UScheduler.service",
      HostServiceRegistration.GetSystemdUnitPath("MaksIT.UScheduler"));

  [Fact]
  public void GetExecutableFileName_MatchesHost() {
    var name = HostServiceManager.GetExecutableFileName();
    if (OperatingSystem.IsWindows())
      Assert.Equal("MaksIT.UScheduler.exe", name);
    else
      Assert.Equal("MaksIT.UScheduler", name);
  }
}
