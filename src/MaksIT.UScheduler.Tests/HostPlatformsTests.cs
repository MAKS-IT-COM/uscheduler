using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Tests;

public class HostPlatformsTests {
  [Fact]
  public void IsCompatible_EmptyPlatforms_IsTrueOnAnyHost() =>
    Assert.True(HostPlatforms.IsCompatible([]));

  [Fact]
  public void IsCompatible_NullPlatforms_IsTrueOnAnyHost() =>
    Assert.True(HostPlatforms.IsCompatible(null));

  [Fact]
  public void IsCompatible_CurrentHostOnly_MatchesOperatingSystem() {
    if (OperatingSystem.IsWindows()) {
      Assert.True(HostPlatforms.IsCompatible(["Windows"]));
      Assert.False(HostPlatforms.IsCompatible(["Linux"]));
      return;
    }

    if (OperatingSystem.IsLinux()) {
      Assert.True(HostPlatforms.IsCompatible(["Linux"]));
      Assert.False(HostPlatforms.IsCompatible(["Windows"]));
    }
  }

  [Fact]
  public void IsCompatible_IsCaseInsensitive() {
    var current = OperatingSystem.IsWindows() ? "windows" : "linux";
    if (!OperatingSystem.IsWindows() && !OperatingSystem.IsLinux())
      return;

    Assert.True(HostPlatforms.IsCompatible([current]));
  }

  [Fact]
  public void FormatLabel_Empty_IsWindowsAndLinux() =>
    Assert.Equal("Windows and Linux", HostPlatforms.FormatLabel([]));

  [Fact]
  public void FormatLabel_WindowsOnly() =>
    Assert.Equal("Windows only", HostPlatforms.FormatLabel(["Windows"]));

  [Fact]
  public void FormatLabel_LinuxOnly() =>
    Assert.Equal("Linux only", HostPlatforms.FormatLabel(["Linux"]));

  [Fact]
  public void FormatLabel_BothNamed() =>
    Assert.Equal("Windows and Linux", HostPlatforms.FormatLabel(["Windows", "Linux"]));
}
