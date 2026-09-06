namespace MaksIT.PSScriptGateway.Models;

public sealed record ScriptExecutionRequest(
  string HttpMethod,
  string RequestPath,
  string ScriptPath,
  string? ContentType,
  string? Body,
  IReadOnlyDictionary<string, string[]> Query,
  IReadOnlyDictionary<string, string[]> Headers,
  IReadOnlyDictionary<string, object?> RouteValues
);
