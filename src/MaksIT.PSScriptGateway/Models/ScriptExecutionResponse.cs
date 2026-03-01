namespace MaksIT.PSScriptGateway.Models;

public sealed record ScriptExecutionResponse(
  int StatusCode,
  object? Value,
  IReadOnlyList<string> Messages
);
