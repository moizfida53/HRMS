using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Payslips (db/42-43) - generate, view and email the payslips of a payroll
// ===========================================================================

public interface IPayslipRepository
{
    Task<IReadOnlyList<PayslipRun>> RunsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<PayslipSummary?> SummaryAsync(long runId, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<PagedResult<PayslipRow>> ListAsync(PayslipListFilter filter, CancellationToken cancellationToken = default);
    Task<PayslipNavCounts?> NavCountsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);

    /// <summary>The payslip of one employee in one payroll; <paramref name="selfEmployeeId"/> = My Payslips (own, generated, closed only).</summary>
    Task<Payslip?> GetAsync(long runId, long employeeId, int? companyId, string? companyIds, long? selfEmployeeId = null,
                            CancellationToken cancellationToken = default);

    Task<SaveResult> GenerateAsync(long runId, string template, int? departmentId, IReadOnlyCollection<long>? employeeIds,
                                   int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);

    Task<SaveResult> QueueEmailAsync(long runId, IReadOnlyCollection<long>? employeeIds, bool resend, int? companyId, string? companyIds,
                                     long? userId, CancellationToken cancellationToken = default);

    Task MarkViewedAsync(long runId, long employeeId, CancellationToken cancellationToken = default);

    // ---- the email sender (no user, no company scope) ----

    Task<IReadOnlyList<PayslipEmailJob>> ClaimEmailsAsync(int batchSize, CancellationToken cancellationToken = default);
    Task EmailResultAsync(long payslipId, bool success, string? error, CancellationToken cancellationToken = default);
}

public sealed class PayslipRepository : IPayslipRepository
{
    private readonly ISqlExecutor _sql;

    public PayslipRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<PayslipRun>> RunsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("RUNS");
        Scope(p, companyId, companyIds);
        return _sql.QueryAsync<PayslipRun>(StoredProcedure.PayslipManage, p, cancellationToken);
    }

    public Task<PayslipSummary?> SummaryAsync(long runId, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("SUMMARY");
        Scope(p, companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<PayslipSummary>(StoredProcedure.PayslipManage, p, cancellationToken);
    }

    public Task<PayslipNavCounts?> NavCountsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("NAV_COUNTS");
        Scope(p, companyId, companyIds);
        return _sql.QuerySingleOrDefaultAsync<PayslipNavCounts>(StoredProcedure.PayslipManage, p, cancellationToken);
    }

    public async Task<PagedResult<PayslipRow>> ListAsync(PayslipListFilter filter, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("LIST");
        Scope(p, filter.CompanyId, filter.CompanyIds);
        p.Add("@RunId", filter.RunId, DbType.Int64);
        p.Add("@Year", filter.Year, DbType.Int32);
        p.Add("@RunMonth", filter.RunMonth, DbType.Date);
        p.Add("@EmployeeId", filter.EmployeeId, DbType.Int64);
        p.Add("@SelfEmployeeId", filter.SelfEmployeeId, DbType.Int64);
        p.Add("@DepartmentId", filter.DepartmentId, DbType.Int32);
        p.Add("@StatusFilter", PayslipFilter.Normalize(filter.Status), DbType.AnsiString, size: 20);
        p.Add("@Search", Trim(filter.Search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(filter.PageSize, 1, 10000), DbType.Int32);

        var rows = await _sql.QueryAsync<PayslipRow>(StoredProcedure.PayslipManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<PayslipRow>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, filter.PageNumber),
            PageSize = Math.Clamp(filter.PageSize, 1, 10000)
        };
    }

    public Task<Payslip?> GetAsync(long runId, long employeeId, int? companyId, string? companyIds, long? selfEmployeeId = null,
                                   CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("GET");
        Scope(p, companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@SelfEmployeeId", selfEmployeeId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<Payslip>(StoredProcedure.PayslipManage, p, cancellationToken);
    }

    public async Task<SaveResult> GenerateAsync(long runId, string template, int? departmentId, IReadOnlyCollection<long>? employeeIds,
                                                int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("GENERATE");
        Scope(p, companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@Template", PayslipTemplate.Normalize(template), DbType.AnsiString, size: 10);
        p.Add("@DepartmentId", departmentId, DbType.Int32);
        p.Add("@EmployeeIds", Csv(employeeIds), DbType.String, size: -1);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayslipManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, runId);
    }

    public async Task<SaveResult> QueueEmailAsync(long runId, IReadOnlyCollection<long>? employeeIds, bool resend, int? companyId,
                                                  string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("QUEUE_EMAIL");
        Scope(p, companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@EmployeeIds", Csv(employeeIds), DbType.String, size: -1);
        p.Add("@Resend", resend, DbType.Boolean);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayslipManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, runId);
    }

    public Task MarkViewedAsync(long runId, long employeeId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("VIEWED");
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@SelfEmployeeId", employeeId, DbType.Int64);
        return _sql.ExecuteAsync(StoredProcedure.PayslipManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<PayslipEmailJob>> ClaimEmailsAsync(int batchSize, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("EMAIL_CLAIM");
        p.Add("@PageSize", Math.Clamp(batchSize, 1, 500), DbType.Int32);
        return _sql.QueryAsync<PayslipEmailJob>(StoredProcedure.PayslipManage, p, cancellationToken);
    }

    public Task EmailResultAsync(long payslipId, bool success, string? error, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("EMAIL_RESULT");
        p.Add("@Id", payslipId, DbType.Int64);
        p.Add("@Success", success, DbType.Boolean);
        p.Add("@Error", Trim(error, 400), DbType.String, size: 400);
        return _sql.ExecuteAsync(StoredProcedure.PayslipManage, p, cancellationToken);
    }

    private static void Scope(DynamicParameters p, int? companyId, string? companyIds)
    {
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(companyIds, 2000), DbType.String, size: 2000);
    }

    private static string? Csv(IReadOnlyCollection<long>? ids) =>
        ids is null || ids.Count == 0 ? null : string.Join(',', ids.Where(i => i > 0).Distinct());

    private static string? Trim(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length > maxLength ? value[..maxLength] : value;
    }
}
