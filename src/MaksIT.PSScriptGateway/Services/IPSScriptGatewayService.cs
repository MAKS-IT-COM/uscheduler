using MaksIT.PSScriptGateway.Models;

namespace MaksIT.PSScriptGateway.Services;

public interface IPSScriptGatewayService
{
  Task<ScriptExecutionResponse> ExecuteAsync(string scriptName, ScriptExecutionRequest request, CancellationToken cancellationToken);
}
