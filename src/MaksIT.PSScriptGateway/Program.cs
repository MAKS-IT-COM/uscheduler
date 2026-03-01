using MaksIT.PSScriptGateway.Configuration;
using MaksIT.PSScriptGateway.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<PSScriptGatewayOptions>(
  builder.Configuration.GetSection(PSScriptGatewayOptions.SectionName));
builder.Services.AddSingleton<IPSScriptGatewayService, PSScriptGatewayService>();
builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();

app.Run();
