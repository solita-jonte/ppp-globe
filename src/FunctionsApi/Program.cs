using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.EntityFrameworkCore;


var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Read connection string from env / config
var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__PppDb");

// Register EF Core DbContext
builder.Services.AddDbContext<PppContext>(options =>
    options.UseSqlServer(connectionString));

builder.Build().Run();
