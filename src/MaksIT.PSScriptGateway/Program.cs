using System.Text.Json;
using System.Text.Json.Serialization;
using MaksIT.Results.Mvc;
using MaksIT.Core.Logging;
using MaksIT.Core.Webapi.Middlewares;
using MaksIT.PSScriptGateway.Services;
using MaksIT.PSScriptGateway.Configuration;


var builder = WebApplication.CreateBuilder(args);

var configuration = builder.Configuration;

builder.Logging.AddConsoleLogger();

var appsettingsPath = Path.Combine(Path.DirectorySeparatorChar.ToString(), "configMap", "appsettings.json");
if (File.Exists(appsettingsPath))
  configuration.AddJsonFile(appsettingsPath, optional: false, reloadOnChange: true);

var secretsPaths = new[] {
  Path.Combine(Path.DirectorySeparatorChar.ToString(), "secrets", "appsecrets.json"),
  Path.Combine(builder.Environment.ContentRootPath ?? "", "secrets", "appsecrets.json"),
  Path.Combine(builder.Environment.ContentRootPath ?? "", "appsecrets.json")
};

foreach (var secretsPath in secretsPaths) {
  if (!string.IsNullOrEmpty(secretsPath) && File.Exists(secretsPath)) {
    configuration.AddJsonFile(secretsPath, optional: false, reloadOnChange: true);
    break;
  }
}

static void ConfigureJsonSerializerOptions(JsonSerializerOptions options) {
  options.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
  options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
}

builder.Services.Configure<PSScriptGatewayOptions>(
  configuration.GetSection(PSScriptGatewayOptions.SectionName));
builder.Services.AddSingleton<IPSScriptGatewayService, PSScriptGatewayService>();
builder.Services.AddControllers()
  .AddJsonOptions(options => ConfigureJsonSerializerOptions(options.JsonSerializerOptions));
builder.Services.AddOptions<JsonOptions>().Configure(o =>
  ConfigureJsonSerializerOptions(o.JsonSerializerOptions));

var app = builder.Build();

app.UseMiddleware<ErrorHandlingMiddleware>();
app.MapControllers();

app.Run();
