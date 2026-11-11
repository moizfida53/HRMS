using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Domain.Attendance;
using HRMS.Domain.Common;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Employee Self Service (/ess, db/146). Every call is for the employee linked
// to the signed-in user (@UserId) - the procedure resolves the employee itself,
// so no employee id is ever taken from the browser.
// ===========================================================================

/// <summary>A punch from the phone: what it reported, and the rules it is checked against.</summary>
public sealed record EssPunchRequest(
    long UserId,
    string PunchType,
    DateTime LocalNow,
    decimal? Latitude,
    decimal? Longitude,
    decimal? AccuracyM,
    int DefaultRadiusM,
    int MaxAccuracyM,
    string? IpAddress,
    string? UserAgent);

public interface ISelfServiceRepository
{
    Task<EssToday?> TodayAsync(long userId, DateTime localNow, CancellationToken ct = default);
    Task<IReadOnlyList<EssLocation>> LocationsAsync(long userId, int defaultRadiusM, CancellationToken ct = default);
    Task<(SaveResult Result, EssPunchRow? Row)> PunchAsync(EssPunchRequest request, CancellationToken ct = default);
    Task<IReadOnlyList<EssDay>> MonthAsync(long userId, DateTime month, DateTime localNow, CancellationToken ct = default);
    Task<EssProfile?> ProfileAsync(long userId, CancellationToken ct = default);
}

public sealed class SelfServiceRepository : ISelfServiceRepository
{
    private const string Proc = "Attendance.usp_EssSelfService";

    private readonly ISqlExecutor _sql;

    public SelfServiceRepository(ISqlExecutor sql) => _sql = sql;

    private static DynamicParameters P(string action, long userId, DateTime? localNow = null)
    {
        var p = PayrollRunRepository.Envelope(action);
        p.Add("@UserId", userId, DbType.Int64);
        if (localNow is { } now) p.Add("@LocalNow", now, DbType.DateTime2);
        return p;
    }

    public async Task<EssToday?> TodayAsync(long userId, DateTime localNow, CancellationToken ct = default) =>
        (await _sql.QueryAsync<EssToday>(Proc, P("TODAY", userId, localNow), ct).ConfigureAwait(false)).FirstOrDefault();

    public async Task<IReadOnlyList<EssLocation>> LocationsAsync(long userId, int defaultRadiusM, CancellationToken ct = default)
    {
        var p = P("LOCATIONS", userId);
        p.Add("@DefaultRadiusM", defaultRadiusM, DbType.Int32);
        return await _sql.QueryAsync<EssLocation>(Proc, p, ct).ConfigureAwait(false);
    }

    public async Task<(SaveResult Result, EssPunchRow? Row)> PunchAsync(EssPunchRequest r, CancellationToken ct = default)
    {
        var p = P("PUNCH", r.UserId, r.LocalNow);
        p.Add("@PunchType", r.PunchType == "OUT" ? "OUT" : "IN", DbType.AnsiString, size: 3);
        p.Add("@Latitude", r.Latitude, DbType.Decimal, precision: 10, scale: 7);
        p.Add("@Longitude", r.Longitude, DbType.Decimal, precision: 10, scale: 7);
        p.Add("@AccuracyM", r.AccuracyM, DbType.Decimal, precision: 9, scale: 2);
        p.Add("@DefaultRadiusM", r.DefaultRadiusM, DbType.Int32);
        p.Add("@MaxAccuracyM", r.MaxAccuracyM, DbType.Int32);
        p.Add("@IpAddress", Cut(r.IpAddress, 64), DbType.String, size: 64);
        p.Add("@UserAgent", Cut(r.UserAgent, 400), DbType.String, size: 400);

        var rows = await _sql.QueryAsync<EssPunchRow>(Proc, p, ct).ConfigureAwait(false);
        return (PayrollRunRepository.ReadResult(p, 0), rows.FirstOrDefault());
    }

    public async Task<IReadOnlyList<EssDay>> MonthAsync(long userId, DateTime month, DateTime localNow, CancellationToken ct = default)
    {
        var p = P("MONTH", userId, localNow);
        p.Add("@Month", new DateTime(month.Year, month.Month, 1), DbType.Date);
        return await _sql.QueryAsync<EssDay>(Proc, p, ct).ConfigureAwait(false);
    }

    public async Task<EssProfile?> ProfileAsync(long userId, CancellationToken ct = default) =>
        (await _sql.QueryAsync<EssProfile>(Proc, P("PROFILE", userId), ct).ConfigureAwait(false)).FirstOrDefault();

    private static string? Cut(string? value, int max) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Length <= max ? value : value[..max];
}
