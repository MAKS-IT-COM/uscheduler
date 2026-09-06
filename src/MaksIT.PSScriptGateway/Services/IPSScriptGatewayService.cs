using MaksIT.Results;
using MaksIT.PSScriptGateway.Models;


namespace MaksIT.PSScriptGateway.Services;

public interface IPSScriptGatewayService {
  Task<Result<object?>> ExecuteAsync(string scriptName, ScriptExecutionRequest request, CancellationToken cancellationToken);
}
