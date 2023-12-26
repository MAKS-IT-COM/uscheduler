using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace UScheduler {

  public class PowershellScript {
    public string? Path { get; set; } 
    public bool? IsSigned { get; set; }

    public string GetPathOrDefault => Path ?? string.Empty;
    public bool GetIsSignedOrDefault => IsSigned ?? false;
  }

  public class ProcessConfiguration {
    public string? Path { get; set; }
    public string[]? Args { get; set; }
    public bool? RestartOnFailure { get; set; }

    public string GetPathOrDefault => Path ?? string.Empty;
    public string[] GetArgsOrDefault => Args ?? [];
    public bool GetRestartOnFailureOrDefault => RestartOnFailure ?? false;
  }

  public class Configuration {

    public string? ServiceName { get; set; }
    public string? Description { get; set; }
    public string? DisplayName { get; set; }

    public List<PowershellScript>? Powershell { get; set; }

    public List<ProcessConfiguration>? Processes { get; set; }

    public string ServiceNameOrDefault => ServiceName ?? string.Empty;
    public string DescriptionOrDefault => Description ?? string.Empty;

    public string DisplayNameOrDefault => DisplayName ?? string.Empty;

    public List<PowershellScript> PowershellOrDefault => Powershell ?? new List<PowershellScript>();

    public List<ProcessConfiguration> ProcessesOrDefault => Processes ?? new List<ProcessConfiguration>();
  }
}
