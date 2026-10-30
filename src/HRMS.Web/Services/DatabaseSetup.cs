using System.Net;
using HRMS.Data.Infrastructure;
using Microsoft.Extensions.Options;

namespace HRMS.Web.Services;

/// <summary>
/// While no connection string is configured, every request (static files aside) gets a
/// page saying where to set it (appsettings.json), instead of a startup failure or a
/// server error. As soon as appsettings.json is saved (it is re-read on change) the site works.
/// </summary>
public sealed class DatabaseSetupMiddleware
{
    private readonly RequestDelegate _next;
    private readonly IOptionsMonitor<SqlServerOptions> _options;
    private readonly IWebHostEnvironment _environment;

    public DatabaseSetupMiddleware(RequestDelegate next, IOptionsMonitor<SqlServerOptions> options, IWebHostEnvironment environment)
    {
        _next = next;
        _options = options;
        _environment = environment;
    }

    public Task InvokeAsync(HttpContext context)
    {
        if (_options.CurrentValue.IsConfigured || IsAsset(context.Request.Path))
        {
            return _next(context);
        }
        return WritePageAsync(context);
    }

    private static bool IsAsset(PathString path) =>
        path.StartsWithSegments("/css") || path.StartsWithSegments("/js") || path.StartsWithSegments("/lib")
        || path.StartsWithSegments("/img") || path.StartsWithSegments("/favicon.ico");

    private Task WritePageAsync(HttpContext context)
    {
        // the folder only to someone on the server itself (a remote visitor learns nothing about the machine)
        var local = context.Connection.RemoteIpAddress is { } ip && (IPAddress.IsLoopback(ip) || ip.Equals(context.Connection.LocalIpAddress));
        var folder = local ? WebUtility.HtmlEncode(_environment.ContentRootPath) : "the application folder on the server";

        context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        context.Response.ContentType = "text/html; charset=utf-8";
        context.Response.Headers.CacheControl = "no-store";
        context.Response.Headers.RetryAfter = "30";
        return context.Response.WriteAsync($$"""
            <!doctype html>
            <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <title>HRMS - database connection not set up</title>
            <style>
              :root { color-scheme: light; }
              body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 16px; box-sizing: border-box;
                     background: #f4f6f6; color: #212322; font: 15px/1.55 "Segoe UI", system-ui, sans-serif; }
              .card { max-width: 680px; width: 100%; background: #fff; border: 1px solid #e4e7ec; border-radius: 16px;
                      box-shadow: 0 12px 32px rgba(33,35,34,.12); padding: 28px 30px; }
              .mark { display: inline-grid; place-items: center; width: 44px; height: 44px; border-radius: 12px;
                      background: #0d827a; color: #fff; font-weight: 700; }
              h1 { font-size: 21px; margin: 14px 0 4px; }
              p { margin: 6px 0; color: #475467; }
              ol { padding-inline-start: 20px; } li { margin: 8px 0; }
              code, pre { font-family: Consolas, ui-monospace, monospace; font-size: 13px; }
              code { background: #f2f4f7; padding: 1px 6px; border-radius: 5px; color: #0a6b63; }
              pre { background: #212322; color: #e6f3f2; padding: 14px 16px; border-radius: 10px; overflow-x: auto; }
              .note { margin-top: 16px; padding: 10px 14px; border-radius: 10px; background: #fffaeb; color: #b54708; font-size: 13px; }
            </style></head>
            <body><main class="card">
              <span class="mark">HR</span>
              <h1>The database connection is not set up yet</h1>
              <p>HRMS is installed but does not know which SQL Server database to use.</p>
              <ol>
                <li>On the server, open <code>appsettings.json</code> in the folder <code>{{folder}}</code> (Notepad is fine).</li>
                <li>Fill in <code>SqlServerConnectionString</code>:
            <pre>"ConnectionStrings": {
              "SqlServerConnectionString": "Server=SQLSERVER;Database=HRMS_Kuwait;User Id=hrms_app;Password=YourPassword;"
            }</pre></li>
                <li>Save the file and refresh this page - no restart is needed.</li>
              </ol>
              <p class="note">Set it in Visual Studio before publishing and every publish carries it - otherwise a new publish
                 replaces appsettings.json and it is set again here.</p>
            </main></body></html>
            """);
    }
}
