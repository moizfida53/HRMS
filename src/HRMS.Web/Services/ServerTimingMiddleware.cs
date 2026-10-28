using System.Diagnostics;
using System.Globalization;
using System.Text;
using HRMS.Data.Infrastructure;

namespace HRMS.Web.Services;

/// <summary>
/// Where a request's time goes: adds a Server-Timing header (browser: Developer tools ->
/// Network -> the request -> Timing) with the server's total time, the number and time of
/// its database calls and the slowest procedures, and logs one line per slow page.
/// On in Development, or with "Diagnostics:ServerTiming": true in appsettings.
/// </summary>
public sealed class ServerTimingMiddleware
{
    private const int SlowPageMs = 500;
    private readonly RequestDelegate _next;
    private readonly ILogger<ServerTimingMiddleware> _logger;

    public ServerTimingMiddleware(RequestDelegate next, ILogger<ServerTimingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? "";
        if (path.StartsWith("/css/", StringComparison.OrdinalIgnoreCase) || path.StartsWith("/js/", StringComparison.OrdinalIgnoreCase)
            || path.StartsWith("/lib/", StringComparison.OrdinalIgnoreCase) || path.StartsWith("/img/", StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        var log = new SqlCallLog();
        SqlCallLog.Current = log;
        var clock = Stopwatch.StartNew();

        context.Response.OnStarting(() =>
        {
            context.Response.Headers.Append("Server-Timing", Header(log, clock.Elapsed.TotalMilliseconds));
            return Task.CompletedTask;
        });

        try
        {
            await _next(context);
        }
        finally
        {
            clock.Stop();
            var calls = log.Calls;
            if (clock.ElapsedMilliseconds >= SlowPageMs)
            {
                _logger.LogInformation(
                    "{Method} {Path} took {TotalMs} ms: {Count} database calls, {DbMs} ms ({Slowest}).",
                    context.Request.Method, path, clock.ElapsedMilliseconds, calls.Count,
                    Math.Round(calls.Sum(c => c.Milliseconds)), Slowest(calls, 5));
            }
            SqlCallLog.Current = null;
        }
    }

    private static string Header(SqlCallLog log, double totalMs)
    {
        var calls = log.Calls;
        var inv = CultureInfo.InvariantCulture;
        var sb = new StringBuilder();
        sb.Append(inv, $"server;desc=\"Server total\";dur={totalMs:0.0}");
        sb.Append(inv, $", db;desc=\"{calls.Count} database calls\";dur={calls.Sum(c => c.Milliseconds):0.0}");
        var i = 0;
        foreach (var g in Grouped(calls).Take(6))
        {
            sb.Append(inv, $", sql{++i};desc=\"{g.Procedure} x{g.Count}\";dur={g.Milliseconds:0.0}");
        }
        return sb.ToString();
    }

    private static IEnumerable<(string Procedure, int Count, double Milliseconds)> Grouped(IEnumerable<(string Procedure, double Milliseconds)> calls) =>
        calls.GroupBy(c => c.Procedure)
             .Select(g => (g.Key, g.Count(), g.Sum(c => c.Milliseconds)))
             .OrderByDescending(g => g.Item3);

    private static string Slowest(IEnumerable<(string Procedure, double Milliseconds)> calls, int take) =>
        string.Join(", ", Grouped(calls).Take(take).Select(g => $"{g.Procedure} x{g.Count} {Math.Round(g.Milliseconds)} ms"));
}
