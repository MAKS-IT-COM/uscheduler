using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.Tests;

public class ConfigurationFileServiceTests {
  [Fact]
  public void Default_path_is_shared_programdata() {
    var service = new ConfigurationFileService();
    Assert.Equal(UserSettingsPath.GetShared(ConfigurationFileService.ProductFolder), service.FilePath);
  }

  [Fact]
  public void Save_to_new_file_writes_only_configuration() {
    var path = Path.Combine(Path.GetTempPath(), $"uscheduler-{Guid.NewGuid():N}.json");
    try {
      var service = new ConfigurationFileService(path);
      service.Save(new Configuration {
        LogDir = @"C:\MaksIT\Logs",
        ScriptsDir = @"C:\MaksIT\Scripts"
      });

      var json = File.ReadAllText(path);
      Assert.Contains("\"Configuration\"", json, StringComparison.Ordinal);
      Assert.DoesNotContain("\"Logging\"", json, StringComparison.Ordinal);
      Assert.Contains("C:\\\\MaksIT\\\\Logs", json, StringComparison.Ordinal);

      var reloaded = new ConfigurationFileService(path);
      Assert.Equal(@"C:\MaksIT\Logs", reloaded.Current.LogDir);
      Assert.Equal(@"C:\MaksIT\Scripts", reloaded.Current.ScriptsDir);
    }
    finally {
      if (File.Exists(path))
        File.Delete(path);
    }
  }

  [Fact]
  public void Copies_seed_configuration_without_logging() {
    var dir = Path.Combine(Path.GetTempPath(), $"uscheduler-{Guid.NewGuid():N}");
    Directory.CreateDirectory(dir);
    var seed = Path.Combine(dir, "appsettings.json");
    var user = Path.Combine(dir, "settings.json");
    File.WriteAllText(seed, """
      {
        "Logging": { "LogLevel": { "Default": "Information" } },
        "Configuration": {
          "LogDir": "C:\\MaksIT\\Logs",
          "ScriptsDir": "C:\\MaksIT\\Scripts",
          "Powershell": [ { "Path": "File-Sync\\file-sync.ps1", "Disabled": true } ]
        }
      }
      """);

    try {
      var service = new ConfigurationFileService(user, seed);
      Assert.True(File.Exists(user));
      Assert.Equal(@"C:\MaksIT\Logs", service.Current.LogDir);
      Assert.Single(service.Current.Powershell);

      var json = File.ReadAllText(user);
      Assert.Contains("\"Configuration\"", json, StringComparison.Ordinal);
      Assert.DoesNotContain("\"Logging\"", json, StringComparison.Ordinal);
    }
    finally {
      Directory.Delete(dir, true);
    }
  }

  [Fact]
  public void Logging_only_seed_does_not_create_user_file() {
    var dir = Path.Combine(Path.GetTempPath(), $"uscheduler-{Guid.NewGuid():N}");
    Directory.CreateDirectory(dir);
    var seed = Path.Combine(dir, "appsettings.json");
    var user = Path.Combine(dir, "settings.json");
    File.WriteAllText(seed, """
      {
        "Logging": { "LogLevel": { "Default": "Information" } }
      }
      """);

    try {
      var service = new ConfigurationFileService(user, seed);
      Assert.False(File.Exists(user));
      Assert.Equal(HostPaths.DefaultLogDirectory, service.Current.LogDir);
    }
    finally {
      Directory.Delete(dir, true);
    }
  }

  [Fact]
  public void Save_round_trips_powershell_entries() {
    var path = Path.Combine(Path.GetTempPath(), $"uscheduler-{Guid.NewGuid():N}.json");
    try {
      var service = new ConfigurationFileService(path);
      service.Save(new Configuration {
        Powershell = [
          new PowershellScript {
            Path = @"File-Sync\file-sync.ps1",
            Name = "File Sync",
            Disabled = true,
            IsSigned = false
          }
        ]
      });

      var reloaded = new ConfigurationFileService(path);
      Assert.Single(reloaded.Current.Powershell);
      Assert.Equal(@"File-Sync\file-sync.ps1", reloaded.Current.Powershell[0].Path);
      Assert.True(reloaded.Current.Powershell[0].Disabled);
      Assert.False(reloaded.Current.Powershell[0].IsSigned);
    }
    finally {
      if (File.Exists(path))
        File.Delete(path);
    }
  }
}

public class HostPathsTests {
  [Fact]
  public void Windows_defaults_use_maksit_data_root() {
    if (!OperatingSystem.IsWindows())
      return;

    Assert.Equal(@"C:\MaksIT\Scripts", HostPaths.DefaultScriptsDirectory);
    Assert.Equal(@"C:\MaksIT\Logs", HostPaths.DefaultLogDirectory);
    Assert.Equal(@"C:\MaksIT", HostPaths.DefaultDataRoot);
    Assert.EndsWith(
      Path.Combine("MaksIT", "UScheduler"),
      HostPaths.DefaultInstallDirectory,
      StringComparison.OrdinalIgnoreCase);
    Assert.Equal(
      Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "MaksIT", "UScheduler"),
      HostPaths.DefaultInstallDirectory);
  }

  [Fact]
  public void DetectServiceBinPath_finds_worker_next_to_ui() {
    var root = Path.Combine(Path.GetTempPath(), $"uscheduler-detect-{Guid.NewGuid():N}");
    Directory.CreateDirectory(root);
    var exeName = HostServiceManager.GetExecutableFileName();
    File.WriteAllBytes(Path.Combine(root, exeName), [0]);
    try {
      Assert.Equal(Path.GetFullPath(root), HostPaths.FindWorkerDirectory(root));
    }
    finally {
      Directory.Delete(root, true);
    }
  }

  [Fact]
  public void Shared_settings_are_under_programdata() {
    if (!OperatingSystem.IsWindows())
      return;

    var path = UserSettingsPath.GetShared("UScheduler");
    Assert.Contains("MaksIT", path, StringComparison.OrdinalIgnoreCase);
    Assert.Contains("UScheduler", path, StringComparison.OrdinalIgnoreCase);
    Assert.EndsWith("settings.json", path, StringComparison.OrdinalIgnoreCase);
    Assert.Equal(
      Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "MaksIT", "UScheduler", "settings.json"),
      path);
  }

  [Fact]
  public void Per_user_settings_are_under_appdata() {
    var path = UserSettingsPath.Get("UScheduler");
    Assert.Equal(
      Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MaksIT", "UScheduler", "settings.json"),
      path);
  }

  [Fact]
  public void ResolveScriptPath_uses_scripts_dir() {
    var dir = Path.Combine(Path.GetTempPath(), $"uscheduler-scripts-{Guid.NewGuid():N}");
    Directory.CreateDirectory(dir);
    try {
      var config = new Configuration { ScriptsDir = dir };
      var resolved = config.ResolveScriptPath(Path.Combine("File-Sync", "file-sync.ps1"));
      Assert.Equal(Path.GetFullPath(Path.Combine(dir, "File-Sync", "file-sync.ps1")), resolved);
    }
    finally {
      Directory.Delete(dir, true);
    }
  }
}
