using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>
/// Alerts on the employee date fields (db/65): the reminders set on each field, which
/// apply to every employee, and the employee dates that have reached one of them.
/// </summary>
public interface IDateAlertRepository
{
    Task<IReadOnlyList<DateAlertRule>> ListRulesAsync(CancellationToken cancellationToken = default);

    /// <summary>Replaces the field's reminders with <paramref name="rules"/> (none = the field has no alerts).</summary>
    Task<SaveResult> SaveRulesAsync(string fieldKey, IReadOnlyList<DateAlertRule> rules, long? userId, CancellationToken cancellationToken = default);

    /// <param name="companyIds">Top-bar company filter, comma-separated; null = all companies.</param>
    Task<IReadOnlyList<DateAlertDue>> DueAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
}

public sealed class DateAlertRepository : IDateAlertRepository
{
    private readonly ISqlExecutor _sql;

    public DateAlertRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<DateAlertRule>> ListRulesAsync(CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@Action", "LIST", DbType.AnsiString, size: 10);
        return _sql.QueryAsync<DateAlertRule>(StoredProcedure.DateAlertManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveRulesAsync(string fieldKey, IReadOnlyList<DateAlertRule> rules, long? userId, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@Action", "SAVE", DbType.AnsiString, size: 10);
        p.Add("@FieldKey", fieldKey, DbType.AnsiString, size: 50);
        // "M2,W1,D0": unit + value, comma separated
        p.Add("@Rules", string.Join(",", rules.Select(r => r.UnitCode + r.Value.ToString(System.Globalization.CultureInfo.InvariantCulture))), DbType.AnsiString, size: 400);
        p.Add("@UserId", userId, DbType.Int64);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        await _sql.ExecuteAsync(StoredProcedure.DateAlertManage, p, cancellationToken).ConfigureAwait(false);

        var code = p.Get<string?>("@ResultCode") ?? ResultCode.Success;
        var message = p.Get<string?>("@ResultMessage") ?? string.Empty;
        return code == ResultCode.Success
            ? SaveResult.Ok(p.Get<long?>("@NewId") ?? 0, message)
            : SaveResult.Fail(string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code);
    }

    public Task<IReadOnlyList<DateAlertDue>> DueAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@Action", "DUE", DbType.AnsiString, size: 10);
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", companyIds, DbType.String, size: 2000);
        return _sql.QueryAsync<DateAlertDue>(StoredProcedure.DateAlertManage, p, cancellationToken);
    }
}
