using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Payroll Components > Collection (db/115, Payroll.usp_Collection_Manage)
// ===========================================================================

public interface ICollectionRepository
{
    /// <summary>The company's payroll months (regular payrolls), newest first.</summary>
    Task<IReadOnlyList<CollectionMonth>> MonthsAsync(int companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<CollectionSummary> SummaryAsync(int companyId, string? companyIds, DateTime month, CancellationToken cancellationToken = default);
    /// <summary>The Payroll Dashboard: the month's collections of the user's company, else of the companies in scope.</summary>
    Task<CollectionSummary> DashboardAsync(int? companyId, string? companyIds, DateTime month, CancellationToken cancellationToken = default);
    /// <summary>Not collected first. <paramref name="status"/>: PENDING, COLLECTED or null for both.</summary>
    Task<IReadOnlyList<CollectionItem>> ListAsync(int companyId, string? companyIds, DateTime month, string? status, string? search,
                                                  CancellationToken cancellationToken = default);
    Task<IReadOnlyList<CollectionHistoryEntry>> HistoryAsync(long id, string? companyIds, CancellationToken cancellationToken = default);
    /// <summary>Marks pending collections as received.</summary>
    Task<SaveResult> CollectAsync(IReadOnlyCollection<long> ids, DateTime? collectedDate, string? reference, string? comment,
                                  string? companyIds, long? userId, CancellationToken cancellationToken = default);
    /// <summary>db/119: records the Work Permit Collections of a payroll once it is approved (closed).</summary>
    Task FromPayrollAsync(long runId, long? userId, CancellationToken cancellationToken = default);
    /// <summary>db/120: Work Permit Payable and Total Collection Amount of one payroll (any stage).</summary>
    Task<CollectionPreview?> RunPreviewAsync(long runId, CancellationToken cancellationToken = default);
    /// <summary>Sets a received collection back to pending (with the reason).</summary>
    Task<SaveResult> ReopenAsync(long id, string? comment, string? companyIds, long? userId, CancellationToken cancellationToken = default);
}

public sealed class CollectionRepository : ICollectionRepository
{
    private readonly ISqlExecutor _sql;

    public CollectionRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<CollectionMonth>> MonthsAsync(int companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Envelope("MONTHS", companyId, companyIds);
        return _sql.QueryAsync<CollectionMonth>(StoredProcedure.CollectionManage, p, cancellationToken);
    }

    public async Task<CollectionSummary> SummaryAsync(int companyId, string? companyIds, DateTime month, CancellationToken cancellationToken = default)
    {
        var p = Envelope("SUMMARY", companyId, companyIds);
        p.Add("@Month", month, DbType.Date);
        return await _sql.QuerySingleOrDefaultAsync<CollectionSummary>(StoredProcedure.CollectionManage, p, cancellationToken).ConfigureAwait(false)
               ?? new CollectionSummary();
    }

    public async Task<CollectionSummary> DashboardAsync(int? companyId, string? companyIds, DateTime month, CancellationToken cancellationToken = default)
    {
        var p = Envelope("DASHBOARD", companyId, companyIds);
        p.Add("@Month", month, DbType.Date);
        return await _sql.QuerySingleOrDefaultAsync<CollectionSummary>(StoredProcedure.CollectionManage, p, cancellationToken).ConfigureAwait(false)
               ?? new CollectionSummary();
    }

    public Task<IReadOnlyList<CollectionItem>> ListAsync(int companyId, string? companyIds, DateTime month, string? status, string? search,
                                                         CancellationToken cancellationToken = default)
    {
        var p = Envelope("LIST", companyId, companyIds);
        p.Add("@Month", month, DbType.Date);
        p.Add("@Status", status is CollectionStatus.Pending or CollectionStatus.Collected ? status : null, DbType.AnsiString, size: 10);
        p.Add("@Search", Trim(search, 200), DbType.String, size: 200);
        return _sql.QueryAsync<CollectionItem>(StoredProcedure.CollectionManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<CollectionHistoryEntry>> HistoryAsync(long id, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Envelope("HISTORY", null, companyIds);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QueryAsync<CollectionHistoryEntry>(StoredProcedure.CollectionManage, p, cancellationToken);
    }

    public async Task<SaveResult> CollectAsync(IReadOnlyCollection<long> ids, DateTime? collectedDate, string? reference, string? comment,
                                               string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("COLLECT", null, companyIds);
        p.Add("@Ids", string.Join(",", ids), DbType.String, size: -1);
        p.Add("@CollectedDate", collectedDate?.Date, DbType.Date);
        p.Add("@Reference", Trim(reference, 100), DbType.String, size: 100);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.CollectionManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, ids.FirstOrDefault());
    }

    public async Task<SaveResult> ReopenAsync(long id, string? comment, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("REOPEN", null, companyIds);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.CollectionManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    public Task FromPayrollAsync(long runId, long? userId, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        return _sql.ExecuteAsync(StoredProcedure.CollectionFromPayroll, p, cancellationToken);
    }

    public Task<CollectionPreview?> RunPreviewAsync(long runId, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@RunId", runId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<CollectionPreview>(StoredProcedure.CollectionRunPreview, p, cancellationToken);
    }

    private static DynamicParameters Envelope(string action, int? companyId, string? companyIds)
    {
        var p = PayrollRunRepository.Envelope(action);
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(companyIds, 2000), DbType.String, size: 2000);
        return p;
    }

    private static string? Trim(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var v = value.Trim();
        return v.Length <= maxLength ? v : v[..maxLength];
    }
}
