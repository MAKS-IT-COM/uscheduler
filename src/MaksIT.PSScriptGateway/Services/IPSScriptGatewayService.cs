using MaksIT.PSScriptGateway.Models;
using MaksIT.Results;

namespace MaksIT.PSScriptGateway.Services;

public interface IPSScriptGatewayService
{
  Task<Result<object?>> ExecuteAsync(string scriptName, ScriptExecutionRequest request, CancellationToken cancellationToken);
}
