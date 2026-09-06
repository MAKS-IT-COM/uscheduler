namespace MaksIT.PSScriptGateway.Configuration;

public sealed class PSScriptGatewayOptions {
  public const string SectionName = "PSScriptGateway";

  public string ScriptsRoot { get; set; } = @"..\..\..\..\Scripts";
}
