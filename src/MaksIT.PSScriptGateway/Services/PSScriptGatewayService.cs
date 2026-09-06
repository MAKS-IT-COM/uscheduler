using System.Collections;
using System.Management.Automation;
using System.Collections.ObjectModel;
using Microsoft.Extensions.Options;
using MaksIT.Results;
using MaksIT.PSScriptGateway.Models;
using MaksIT.UScheduler.Shared.Helpers;
using MaksIT.PSScriptGateway.Configuration;


namespace MaksIT.PSScriptGateway.Services;

public sealed class PSScriptGatewayService : IPSScriptGatewayService {
  private readonly ILogger<PSScriptGatewayService> _logger;
  private readonly string _scriptsRoot;

  public PSScriptGatewayService(
    ILogger<PSScriptGatewayService> logger,
    IOptions<PSScriptGatewayOptions> options) {
    _logger = logger;
    _scriptsRoot = ResolveScriptsRoot(options.Value.ScriptsRoot);
  }

  public async Task<Result<object?>> ExecuteAsync(
    string scriptName,
    ScriptExecutionRequest request,
    CancellationToken cancellationToken) {
    var scriptPath = ResolveScriptPath(scriptName);
    if (scriptPath is null)
      return Result<object?>.NotFound(null, "Script not found.");

    using var powerShell = PowerShell.Create();
    using var registration = cancellationToken.Register(() => {
      try {
        powerShell.Stop();
      }
      catch (ObjectDisposedException) {
      }
      catch (InvalidOperationException) {
      }
    });

    powerShell.AddCommand(scriptPath)
      .AddParameter("Request", request)
      .AddParameter("HttpMethod", request.HttpMethod)
      .AddParameter("RequestPath", request.RequestPath)
      .AddParameter("ScriptPath", request.ScriptPath)
      .AddParameter("ContentType", request.ContentType)
      .AddParameter("Body", request.Body)
      .AddParameter("Query", request.Query)
      .AddParameter("Headers", request.Headers)
      .AddParameter("RouteValues", request.RouteValues);

    Collection<PSObject> output;

    try {
      output = await Task.Run(() => powerShell.Invoke(), cancellationToken);
    }
    catch (OperationCanceledException) {
      return ScriptExecutionResultFactory.FromResponse(
        StatusCodes.Status499ClientClosedRequest,
        null,
        ["The request was canceled."]);
    }
    catch (RuntimeException exception) {
      _logger.LogError(exception, "PowerShell runtime error while executing {ScriptPath}", scriptPath);
      return Result<object?>.InternalServerError(null, exception.Message);
    }
    catch (Exception exception) {
      _logger.LogError(exception, "Unhandled error while executing {ScriptPath}", scriptPath);
      return Result<object?>.InternalServerError(null, "Unhandled script execution error.");
    }

    if (TryParseScriptResponse(output, out var response))
      return response;

    if (powerShell.HadErrors) {
      var errors = powerShell.Streams.Error
        .Select(error => error.ToString())
        .Where(message => !string.IsNullOrWhiteSpace(message))
        .ToArray();

      return errors.Length == 0
        ? Result<object?>.InternalServerError(null, "Script execution failed.")
        : Result<object?>.InternalServerError(null, errors);
    }

    return Result<object?>.NoContent(null, "No content.");
  }

  private string ResolveScriptsRoot(string scriptsRoot) {
    var resolvedRoot = PathHelper.ResolvePath(scriptsRoot);
    return Path.GetFullPath(resolvedRoot);
  }

  private string? ResolveScriptPath(string scriptName) {
    var relativePath = scriptName
      .Replace('/', Path.DirectorySeparatorChar)
      .TrimStart(Path.DirectorySeparatorChar);

    if (string.IsNullOrWhiteSpace(relativePath))
      return null;

    if (!relativePath.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
      relativePath += ".ps1";

    var combinedPath = Path.GetFullPath(Path.Combine(_scriptsRoot, relativePath));
    if (!combinedPath.StartsWith(_scriptsRoot, StringComparison.OrdinalIgnoreCase))
      return null;

    return File.Exists(combinedPath) ? combinedPath : null;
  }

  private static bool TryParseScriptResponse(Collection<PSObject> output, out Result<object?> response) {
    response = null!;

    if (output.Count == 0)
      return false;

    if (TryParseExplicitResponse(output[0], out response))
      return true;

    var values = output.Select(UnwrapValue).ToArray();
    var payload = values.Length == 1 ? values[0] : values;
    response = Result<object?>.Ok(payload, ["OK"]);
    return true;
  }

  private static bool TryParseExplicitResponse(PSObject psObject, out Result<object?> response) {
    response = null!;

    if (!TryReadIntProperty(psObject, "StatusCode", out var statusCode))
      return false;

    var messages = ReadMessages(psObject);
    var value = ReadProperty(psObject, "Value")
      ?? ReadProperty(psObject, "Body")
      ?? ReadProperty(psObject, "Data")
      ?? ReadProperty(psObject, "Result");

    response = ScriptExecutionResultFactory.FromResponse(statusCode, value, messages);
    return true;
  }

  private static object? ReadProperty(PSObject psObject, string propertyName) {
    var property = psObject.Properties[propertyName];
    return property is null ? null : UnwrapValue(property.Value);
  }

  private static IReadOnlyList<string> ReadMessages(PSObject psObject) {
    var property = psObject.Properties["Messages"];
    if (property?.Value is null)
      return [];

    if (property.Value is string message)
      return [message];

    if (property.Value is IEnumerable enumerable) {
      return enumerable
        .Cast<object?>()
        .Select(item => item?.ToString())
        .Where(item => !string.IsNullOrWhiteSpace(item))
        .Cast<string>()
        .ToArray();
    }

    return [property.Value.ToString() ?? "Script response."];
  }

  private static bool TryReadIntProperty(PSObject psObject, string propertyName, out int value) {
    value = default;
    var property = psObject.Properties[propertyName];
    if (property?.Value is null)
      return false;

    return int.TryParse(property.Value.ToString(), out value);
  }

  private static object? UnwrapValue(object? value) {
    if (value is PSObject psObject)
      return psObject.BaseObject;

    return value;
  }
}
