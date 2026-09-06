using System.Net;
using System.Reflection;
using MaksIT.Results;


namespace MaksIT.PSScriptGateway.Services;

internal static class ScriptExecutionResultFactory {
  private static readonly Type GenericResultType = typeof(Result<object?>);
  private static readonly Type NonGenericResultType = typeof(Result);
  private static readonly IReadOnlyDictionary<int, string> StatusMethodNames = Enum
    .GetValues<HttpStatusCode>()
    .Distinct()
    .ToDictionary(code => (int)code, code => code.ToString());

  public static Result<object?> FromResponse(int statusCode, object? value, IReadOnlyList<string> messages) {
    var normalizedStatusCode = NormalizeStatusCode(statusCode);
    var resolvedMessages = messages.Count == 0
      ? [GetDefaultMessage(normalizedStatusCode)]
      : messages.ToArray();

    if (TryBuildGenericResult(normalizedStatusCode, value, resolvedMessages, out var genericResult))
      return genericResult;

    if (value is null && TryBuildResult(normalizedStatusCode, resolvedMessages, out var result))
      return result.ToResultOfType<object?>(null);

    return Result<object?>.Ok(value, resolvedMessages);
  }

  private static bool TryBuildGenericResult(int statusCode, object? value, string[] messages, out Result<object?> result) {
    result = null!;

    if (!StatusMethodNames.TryGetValue(statusCode, out var methodName))
      return false;

    var method = GenericResultType
      .GetMethods(BindingFlags.Public | BindingFlags.Static)
      .FirstOrDefault(current =>
        current.Name == methodName &&
        Matches(current.GetParameters(), typeof(object), typeof(string[])));

    if (method is null)
      return false;

    if (method.Invoke(null, [value, messages]) is not Result<object?> invoked)
      return false;

    result = invoked;
    return true;
  }

  private static bool TryBuildResult(int statusCode, string[] messages, out Result result) {
    result = null!;

    if (!StatusMethodNames.TryGetValue(statusCode, out var methodName))
      return false;

    var method = NonGenericResultType
      .GetMethods(BindingFlags.Public | BindingFlags.Static)
      .FirstOrDefault(current =>
        current.Name == methodName &&
        Matches(current.GetParameters(), typeof(string[])));

    if (method is null)
      return false;

    if (method.Invoke(null, [messages]) is not Result invoked)
      return false;

    result = invoked;
    return true;
  }

  private static bool Matches(ParameterInfo[] parameters, params Type[] parameterTypes) {
    if (parameters.Length != parameterTypes.Length)
      return false;

    for (var index = 0; index < parameters.Length; index++) {
      if (parameters[index].ParameterType != parameterTypes[index])
        return false;
    }

    return true;
  }

  private static int NormalizeStatusCode(int statusCode) {
    return statusCode is >= 100 and <= 599
      ? statusCode
      : StatusCodes.Status500InternalServerError;
  }

  private static string GetDefaultMessage(int statusCode) {
    return StatusMethodNames.TryGetValue(statusCode, out var methodName)
      ? methodName
      : "Request completed.";
  }
}
