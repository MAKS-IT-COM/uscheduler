using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Tests;

public class HostDataDirectoriesTests {
  [Fact]
  public void CopySeedScriptsIfMissing_skips_existing_script_folder() {
    var root = Path.Combine(Path.GetTempPath(), $"uscheduler-seed-{Guid.NewGuid():N}");
    var source = Path.Combine(root, "seed");
    var dest = Path.Combine(root, "scripts");
    var seedFolder = Path.Combine(source, "File-Sync");
    var existingFolder = Path.Combine(dest, "File-Sync");
    Directory.CreateDirectory(seedFolder);
    Directory.CreateDirectory(existingFolder);
    File.WriteAllText(Path.Combine(seedFolder, "file-sync.ps1"), "seed");
    File.WriteAllText(Path.Combine(seedFolder, "extra.ps1"), "new");
    File.WriteAllText(Path.Combine(existingFolder, "file-sync.ps1"), "customized");

    try {
      var result = HostDataDirectories.CopySeedScriptsIfMissing(source, dest);

      Assert.Equal(0, result.CopiedFiles);
      Assert.Equal(1, result.SkippedItems);
      Assert.Equal("customized", File.ReadAllText(Path.Combine(existingFolder, "file-sync.ps1")));
      Assert.False(File.Exists(Path.Combine(existingFolder, "extra.ps1")));
    }
    finally {
      Directory.Delete(root, true);
    }
  }

  [Fact]
  public void CopySeedScriptsIfMissing_skips_existing_root_file() {
    var root = Path.Combine(Path.GetTempPath(), $"uscheduler-seed-{Guid.NewGuid():N}");
    var source = Path.Combine(root, "seed");
    var dest = Path.Combine(root, "scripts");
    Directory.CreateDirectory(source);
    Directory.CreateDirectory(dest);
    File.WriteAllText(Path.Combine(source, "SchedulerTemplate.psm1"), "seed");
    File.WriteAllText(Path.Combine(dest, "SchedulerTemplate.psm1"), "customized");

    try {
      var result = HostDataDirectories.CopySeedScriptsIfMissing(source, dest);

      Assert.Equal(0, result.CopiedFiles);
      Assert.Equal(1, result.SkippedItems);
      Assert.Equal("customized", File.ReadAllText(Path.Combine(dest, "SchedulerTemplate.psm1")));
    }
    finally {
      Directory.Delete(root, true);
    }
  }

  [Fact]
  public void CopySeedScriptsIfMissing_copies_only_missing_folders() {
    var root = Path.Combine(Path.GetTempPath(), $"uscheduler-seed-{Guid.NewGuid():N}");
    var source = Path.Combine(root, "seed");
    var dest = Path.Combine(root, "scripts");
    Directory.CreateDirectory(Path.Combine(source, "File-Sync"));
    Directory.CreateDirectory(Path.Combine(source, "Native-Sync"));
    Directory.CreateDirectory(Path.Combine(dest, "File-Sync"));
    File.WriteAllText(Path.Combine(source, "File-Sync", "file-sync.ps1"), "seed");
    File.WriteAllText(Path.Combine(source, "Native-Sync", "native-sync.ps1"), "seed");
    File.WriteAllText(Path.Combine(dest, "File-Sync", "file-sync.ps1"), "customized");

    try {
      var result = HostDataDirectories.CopySeedScriptsIfMissing(source, dest);

      Assert.Equal(1, result.CopiedFiles);
      Assert.Equal(1, result.SkippedItems);
      Assert.Equal("customized", File.ReadAllText(Path.Combine(dest, "File-Sync", "file-sync.ps1")));
      Assert.Equal("seed", File.ReadAllText(Path.Combine(dest, "Native-Sync", "native-sync.ps1")));
    }
    finally {
      Directory.Delete(root, true);
    }
  }

  [Fact]
  public void CopySeedScriptsIfMissing_copies_into_empty_destination() {
    var root = Path.Combine(Path.GetTempPath(), $"uscheduler-seed-{Guid.NewGuid():N}");
    var source = Path.Combine(root, "seed");
    var dest = Path.Combine(root, "scripts");
    Directory.CreateDirectory(Path.Combine(source, "File-Sync"));
    Directory.CreateDirectory(dest);
    File.WriteAllText(Path.Combine(source, "File-Sync", "file-sync.ps1"), "seed");
    File.WriteAllText(Path.Combine(source, "SchedulerTemplate.psm1"), "module");

    try {
      var result = HostDataDirectories.CopySeedScriptsIfMissing(source, dest);

      Assert.Equal(2, result.CopiedFiles);
      Assert.Equal(0, result.SkippedItems);
      Assert.Equal("seed", File.ReadAllText(Path.Combine(dest, "File-Sync", "file-sync.ps1")));
      Assert.Equal("module", File.ReadAllText(Path.Combine(dest, "SchedulerTemplate.psm1")));
    }
    finally {
      Directory.Delete(root, true);
    }
  }

  [Fact]
  public void ResolveLayout_standard_uses_machine_wide_paths() {
    var install = Path.Combine(Path.GetTempPath(), $"uscheduler-layout-std-{Guid.NewGuid():N}");
    Directory.CreateDirectory(install);
    try {
      var layout = HostDataDirectories.ResolveLayout(install);
      Assert.False(layout.Portable);
      Assert.Equal(HostPaths.DefaultDataRoot, layout.Root);
      Assert.Equal(HostPaths.DefaultScriptsDirectory, layout.ScriptsDirectory);
      Assert.Equal(HostPaths.DefaultLogDirectory, layout.LogDirectory);
      Assert.Equal(HostPaths.SharedSettingsFile, layout.SharedSettingsFile);
    }
    finally {
      Directory.Delete(install, true);
    }
  }

  [Fact]
  public void ResolveLayout_portable_requested_keeps_everything_under_install_folder() {
    var install = Path.Combine(Path.GetTempPath(), $"uscheduler-layout-port-{Guid.NewGuid():N}");
    Directory.CreateDirectory(install);
    try {
      var layout = HostDataDirectories.ResolveLayout(install, portableRequested: true);
      Assert.True(layout.Portable);
      Assert.Equal(Path.GetFullPath(install), Path.GetFullPath(layout.Root));
      Assert.Equal(Path.GetFullPath(Path.Combine(install, "Scripts")), Path.GetFullPath(layout.ScriptsDirectory));
      Assert.Equal(Path.GetFullPath(Path.Combine(install, "Logs")), Path.GetFullPath(layout.LogDirectory));
      Assert.Equal(
        Path.GetFullPath(Path.Combine(install, "Data", "settings.json")),
        Path.GetFullPath(layout.SharedSettingsFile));
    }
    finally {
      Directory.Delete(install, true);
    }
  }

  [Fact]
  public void ResolveLayout_detects_existing_portable_marker() {
    var install = Path.Combine(Path.GetTempPath(), $"uscheduler-layout-mark-{Guid.NewGuid():N}");
    Directory.CreateDirectory(install);
    File.WriteAllText(Path.Combine(install, HostPaths.PortableMarkerFileName), HostPaths.PortableMarkerContent);
    try {
      var layout = HostDataDirectories.ResolveLayout(install);
      Assert.True(layout.Portable);
      Assert.Equal(Path.GetFullPath(install), Path.GetFullPath(layout.Root));
    }
    finally {
      Directory.Delete(install, true);
    }
  }
}
