namespace MaksIT.UScheduler;

public class PowershellScript {
  public required string Path { get; set; }
  public bool IsSigned { get; set; } = false;
}

public class ProcessConfiguration {
  public required string Path { get; set; }
  public string[]? Args { get; set; }
  public bool RestartOnFailure { get; set; } = false;
}

public class Configuration {
  public string ServiceName { get; set; } = "MaksIT.UScheduler";
  public string? LogDir { get; set; }
  public List<PowershellScript> Powershell { get; set; } = [];
  public List<ProcessConfiguration> Processes { get; set; } = [];

}
