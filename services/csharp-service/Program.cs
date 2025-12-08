using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME") ?? "csharp-service";

app.MapGet("/", (HttpContext context) =>
{
    return Results.Json(new
    {
        service = serviceName,
        message = "Hello from C# service! This is a public endpoint.",
        timestamp = DateTime.UtcNow,
        user = GetUser(context)
    });
});

app.MapGet("/health", () => Results.Json(new { status = "healthy" }));

app.MapGet("/api/data", (HttpContext context) =>
{
    return Results.Json(new
    {
        service = serviceName,
        message = "API data endpoint - requires user or admin role",
        timestamp = DateTime.UtcNow,
        user = GetUser(context)
    });
});

app.MapGet("/admin/users", (HttpContext context) =>
{
    return Results.Json(new
    {
        service = serviceName,
        message = "Admin endpoint - requires admin role",
        timestamp = DateTime.UtcNow,
        user = GetUser(context)
    });
});

string GetUser(HttpContext context)
{
    var auth = context.Request.Headers["Authorization"].ToString();
    return string.IsNullOrEmpty(auth) ? "anonymous" : "authenticated-user";
}

app.Run();
