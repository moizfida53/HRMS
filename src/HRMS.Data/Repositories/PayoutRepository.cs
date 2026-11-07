using System.Data;
using System.Globalization;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// db/123: the pay-out of a closed payroll (Payroll.usp_PayrollRun_Payout) -
// Approved, Execution, Completed - for the payroll workspace and the lists.
// ===========================================================================

public interface IPayoutRepository
{
    /// <summary>The pay-out of each payroll (in the company scope); a payroll not approved yet has no PayoutStatus.</summary>
    Task<IReadOnlyList<RunPayout>> ListAsync(IEnumerable<long> runIds, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<RunPayout?> GetAsync(long runId, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<PayoutCounts> CountsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    /// <summary>Saves the status of a payroll (null = every closed payroll in scope) that changed, with the history.</summary>
    Task SyncAsync(long? runId, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    /// <summary>True when the payroll, or a payroll of the payments, is completed (read-only).</summary>
    Task<bool> IsLockedAsync(long? runId, IEnumerable<long>? paymentIds, CancellationToken cancellationToken = default);
}

public sealed class PayoutRepository : IPayoutRepository
{
    private readonly ISqlExecutor _sql;

    public PayoutRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<IReadOnlyList<RunPayout>> ListAsync(IEnumerable<long> runIds, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var ids = Csv(runIds);
        if (ids is null) return Array.Empty<RunPayout>();
        var p = Params("LIST", companyId, companyIds);
        p.Add("@RunIds", ids, DbType.String);
        return await _sql.QueryAsync<RunPayout>(StoredProcedure.PayrollRunPayout, p, cancellationToken).ConfigureAwait(false);
    }

    public async Task<RunPayout?> GetAsync(long runId, int? companyId, string? companyIds, CancellationToken cancellationToken = default) =>
        (await ListAsync([runId], companyId, companyIds, cancellationToken).ConfigureAwait(false)).FirstOrDefault();

    public async Task<PayoutCounts> CountsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default) =>
        await _sql.QuerySingleOrDefaultAsync<PayoutCounts>(StoredProcedure.PayrollRunPayout, Params("COUNTS", companyId, companyIds), cancellationToken)
                  .ConfigureAwait(false) ?? new PayoutCounts();

    public Task SyncAsync(long? runId, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Params("SYNC", companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        return _sql.ExecuteAsync(StoredProcedure.PayrollRunPayout, p, cancellationToken);
    }

    public async Task<bool> IsLockedAsync(long? runId, IEnumerable<long>? paymentIds, CancellationToken cancellationToken = default)
    {
        var p = Params("LOCKED", null, null);
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@PaymentIds", Csv(paymentIds ?? []), DbType.String);
        return await _sql.ExecuteScalarAsync<int>(StoredProcedure.PayrollRunPayout, p, cancellationToken).ConfigureAwait(false) > 0;
    }

    private static DynamicParameters Params(string action, int? companyId, string? companyIds)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", string.IsNullOrWhiteSpace(companyIds) ? null : companyIds.Trim(), DbType.String, size: 2000);
        return p;
    }

    private static string? Csv(IEnumerable<long> ids)
    {
        var list = ids.Where(i => i > 0).Distinct().ToList();
        return list.Count == 0 ? null : string.Join(',', list.Select(i => i.ToString(CultureInfo.InvariantCulture)));
    }
}
