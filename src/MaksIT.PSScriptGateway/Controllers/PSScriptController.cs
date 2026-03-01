using MaksIT.PSScriptGateway.Models;
using MaksIT.PSScriptGateway.Services;
using Microsoft.AspNetCore.Mvc;

namespace MaksIT.PSScriptGateway.Controllers;

[ApiController]
[Route("api/scripts")]
public sealed class PSScriptController : ControllerBase
{
  private readonly IPSScriptGatewayService _scriptGatewayService;

  public PSScriptController(IPSScriptGatewayService scriptGatewayService)
  {
    _scriptGatewayService = scriptGatewayService;
  }

  [AcceptVerbs("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS")]
  [Route("{**scriptName}")]
  public async Task<IActionResult> Execute(string scriptName, CancellationToken cancellationToken)
  {
    var request = await BuildRequestAsync(scriptName, cancellationToken);
    var response = await _scriptGatewayService.ExecuteAsync(scriptName, request, cancellationToken);
    return ResultMapper.ToActionResult(response.StatusCode, response.Value, response.Messages);
  }

  private async Task<ScriptExecutionRequest> BuildRequestAsync(string scriptName, CancellationToken cancellationToken)
  {
    var body = await ReadBodyAsync(cancellationToken);

    return new ScriptExecutionRequest(
      Request.Method,
      Request.Path.Value ?? string.Empty,
      scriptName,
      Request.ContentType,
      body,
      Request.Query.ToDictionary(
        pair => pair.Key,
        pair => pair.Value.Select(static value => value ?? string.Empty).ToArray(),
        StringComparer.OrdinalIgnoreCase),
      Request.Headers.ToDictionary(
        pair => pair.Key,
        pair => pair.Value.Select(static value => value ?? string.Empty).ToArray(),
        StringComparer.OrdinalIgnoreCase),
      RouteData.Values.ToDictionary(
        pair => pair.Key,
        pair => pair.Value,
        StringComparer.OrdinalIgnoreCase));
  }

  private async Task<string?> ReadBodyAsync(CancellationToken cancellationToken)
  {
    if (Request.ContentLength is null or 0)
      return null;

    Request.EnableBuffering();
    Request.Body.Position = 0;

    using var reader = new StreamReader(Request.Body, leaveOpen: true);
    var body = await reader.ReadToEndAsync(cancellationToken);
    Request.Body.Position = 0;

    return string.IsNullOrWhiteSpace(body) ? null : body;
  }
}
