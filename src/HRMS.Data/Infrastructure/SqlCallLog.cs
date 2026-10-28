using System.Collections.Concurrent;

namespace HRMS.Data.Infrastructure;

/// <summary>
/// The database calls of the current web request and how long each took - filled by the
/// executor, read by the web app's timing middleware (Server-Timing header, log line).
/// Flows with the request's async calls, including ones run in parallel.
/// </summary>
public sealed class SqlCallLog
{
    private static readonly AsyncLocal<SqlCallLog?> CurrentLog = new();

    private readonly ConcurrentQueue<(string Procedure, double Milliseconds)> _calls = new();

    /// <summary>The log of the request in progress; null outside a timed request.</summary>
    public static SqlCallLog? Current
    {
        get => CurrentLog.Value;
        set => CurrentLog.Value = value;
    }

    public void Add(string procedure, double milliseconds) => _calls.Enqueue((procedure, milliseconds));

    public IReadOnlyList<(string Procedure, double Milliseconds)> Calls => _calls.ToArray();
}
