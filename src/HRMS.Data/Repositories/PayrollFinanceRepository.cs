using System.Data;
using System.Text.Json;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Bank Processing, Accounting and Payroll Reports (db/49-51):
// usp_BankFile_Manage, usp_BankPayment_Manage, usp_Journal_Manage,
// usp_CostAllocation_Manage, usp_PayrollFinance_NavCounts, usp_PayrollReport
// ===========================================================================

public interface IPayrollFinanceRepository
{
    // ------------------------------------------------------------- bank
    /// <summary>Closed payrolls (year / month) with their bank file state.</summary>
    Task<IReadOnlyList<FinanceRun>> BankRunsAsync(int? companyId, string? companyIds, int? year, DateTime? month, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<BankReviewRow>> BankReviewAsync(long runId, string kind, int? bankId, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<BankFileLine>> BankLinesAsync(long runId, string kind, int? bankId, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<SaveResult> CreateBankFileAsync(BankFileRequest request, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<PagedResult<BankFile>> BankFilesAsync(FinanceFilter filter, CancellationToken cancellationToken = default);
    /// <summary>One file with its text (counts the download when <paramref name="download"/>).</summary>
    Task<BankFile?> BankFileAsync(long id, int? companyId, string? companyIds, bool download, CancellationToken cancellationToken = default);
    Task<SaveResult> MarkFileSentAsync(long id, string? reference, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);

    Task<PagedResult<BankPayment>> PaymentsAsync(FinanceFilter filter, CancellationToken cancellationToken = default);
    Task<PaymentSummary> PaymentSummaryAsync(FinanceFilter filter, CancellationToken cancellationToken = default);
    /// <summary>PAID (reference, paid date) or FAILED (reason).</summary>
    Task<SaveResult> SetPaymentStatusAsync(IEnumerable<long> ids, string status, string? reference, string? reason, DateTime? paidDate,
                                           int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    /// <summary>Failed payments wait again - BANK (next re-issue file) or CASH.</summary>
    Task<SaveResult> ReissuePaymentsAsync(IEnumerable<long> ids, string method, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> MarkFilePaidAsync(long fileId, DateTime? paidDate, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);

    // ------------------------------------------------------- accounting
    Task<IReadOnlyList<FinanceRun>> JournalRunsAsync(int? companyId, string? companyIds, int? year, DateTime? month, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<JournalLine>> JournalPreviewAsync(long runId, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<SaveResult> CreateJournalAsync(long runId, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<PagedResult<PayrollJournal>> JournalsAsync(FinanceFilter filter, CancellationToken cancellationToken = default);
    Task<PayrollJournal?> JournalAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<JournalLine>> JournalLinesAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    /// <summary>EXPORTED (counted), POSTED (reference) or REVERSE (reason).</summary>
    Task<SaveResult> JournalActionAsync(long id, string action, string? text, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<AccountingDefaults?> DefaultsAsync(int forCompanyId, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveDefaultsAsync(int forCompanyId, string? code, string? name, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);

    Task<PagedResult<CostAllocation>> AllocationsAsync(FinanceFilter filter, CancellationToken cancellationToken = default);
    /// <summary>The split with its lines.</summary>
    Task<CostAllocation?> AllocationAsync(int id, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveAllocationAsync(CostAllocation allocation, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> DeleteAllocationAsync(int id, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);

    Task<FinanceNavCounts?> NavCountsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);

    // ---------------------------------------------------------- reports
    /// <summary>The rows of a report - each row is column name -> value.</summary>
    Task<IReadOnlyList<IDictionary<string, object?>>> ReportAsync(string report, int? year, DateTime? month, int? departmentId,
                                                                  int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    /// <summary>The months that have closed payrolls (newest first).</summary>
    Task<IReadOnlyList<DateTime>> ReportPeriodsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
}

/// <summary>What the bank file CREATE stores (the text is built by the application).</summary>
public sealed class BankFileRequest
{
    public long RunId { get; init; }
    public string Kind { get; init; } = "FULL";
    public int? BankId { get; init; }
    public int BankFileFormatId { get; init; }
    public int CompanyBankAccountId { get; init; }
    public DateTime ValueDate { get; init; }
    public string FileName { get; init; } = string.Empty;
    public string Content { get; init; } = string.Empty;
    public IReadOnlyList<long> RunEmployeeIds { get; init; } = Array.Empty<long>();
    public string? Reason { get; init; }
}

public sealed class PayrollFinanceRepository : IPayrollFinanceRepository
{
    private readonly ISqlExecutor _sql;

    public PayrollFinanceRepository(ISqlExecutor sql) => _sql = sql;

    private static string? T(string? value, int max) => PayItemTypeRepository.Trim(value, max);

    private static DynamicParameters Env(string action, int? companyId, string? companyIds)
    {
        var p = PayrollRunRepository.Envelope(action);
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", T(companyIds, 2000), DbType.String, size: 2000);
        return p;
    }

    private static DynamicParameters ListEnv(string action, FinanceFilter f)
    {
        var p = Env(action, f.CompanyId, f.CompanyIds);
        p.Add("@Year", f.Year, DbType.Int32);
        p.Add("@RunMonth", f.RunMonth, DbType.Date);
        p.Add("@Search", T(f.Search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, f.Page), DbType.Int32);
        p.Add("@PageSize", f.PageSize, DbType.Int32);
        return p;
    }

    private async Task<PagedResult<TItem>> PageAsync<TItem>(string proc, DynamicParameters p, FinanceFilter f, CancellationToken ct)
    {
        var rows = await _sql.QueryAsync<TItem>(proc, p, ct).ConfigureAwait(false);
        return new PagedResult<TItem>
        {
            Items = rows, TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count, PageNumber = Math.Max(1, f.Page), PageSize = f.PageSize
        };
    }

    private async Task<SaveResult> RunAsync(string proc, DynamicParameters p, long? userId, long id, CancellationToken ct)
    {
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(proc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    private static string Csv(IEnumerable<long> ids) => string.Join(',', ids.Where(i => i > 0).Distinct());

    // ================================================================ bank
    public Task<IReadOnlyList<FinanceRun>> BankRunsAsync(int? companyId, string? companyIds, int? year, DateTime? month, CancellationToken cancellationToken = default)
    {
        var p = Env("RUNS", companyId, companyIds);
        p.Add("@Year", year, DbType.Int32);
        p.Add("@RunMonth", month, DbType.Date);
        return _sql.QueryAsync<FinanceRun>(StoredProcedure.BankFileManage, p, cancellationToken);
    }

    private static DynamicParameters RunEnv(string action, long runId, string kind, int? bankId, int? companyId, string? companyIds)
    {
        var p = Env(action, companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        p.Add("@Kind", kind, DbType.AnsiString, size: 10);
        p.Add("@BankId", bankId, DbType.Int32);
        return p;
    }

    public Task<IReadOnlyList<BankReviewRow>> BankReviewAsync(long runId, string kind, int? bankId, int? companyId, string? companyIds,
                                                             CancellationToken cancellationToken = default) =>
        _sql.QueryAsync<BankReviewRow>(StoredProcedure.BankFileManage, RunEnv("REVIEW", runId, kind, bankId, companyId, companyIds), cancellationToken);

    public Task<IReadOnlyList<BankFileLine>> BankLinesAsync(long runId, string kind, int? bankId, int? companyId, string? companyIds,
                                                           CancellationToken cancellationToken = default) =>
        _sql.QueryAsync<BankFileLine>(StoredProcedure.BankFileManage, RunEnv("LINES", runId, kind, bankId, companyId, companyIds), cancellationToken);

    public Task<SaveResult> CreateBankFileAsync(BankFileRequest r, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = RunEnv("CREATE", r.RunId, r.Kind, r.BankId, companyId, companyIds);
        p.Add("@BankFileFormatId", r.BankFileFormatId, DbType.Int32);
        p.Add("@CompanyBankAccountId", r.CompanyBankAccountId, DbType.Int32);
        p.Add("@ValueDate", r.ValueDate, DbType.Date);
        p.Add("@FileName", T(r.FileName, 150), DbType.String, size: 150);
        p.Add("@Content", r.Content, DbType.String, size: -1);
        p.Add("@RunEmployeeIds", Csv(r.RunEmployeeIds), DbType.String, size: -1);
        p.Add("@Reason", T(r.Reason, 500), DbType.String, size: 500);
        return RunAsync(StoredProcedure.BankFileManage, p, userId, 0, cancellationToken);
    }

    public Task<PagedResult<BankFile>> BankFilesAsync(FinanceFilter f, CancellationToken cancellationToken = default)
    {
        var p = ListEnv("LIST", f);
        p.Add("@RunId", f.RunId, DbType.Int64);
        p.Add("@Status", string.IsNullOrEmpty(f.Status) ? null : f.Status, DbType.AnsiString, size: 12);
        return PageAsync<BankFile>(StoredProcedure.BankFileManage, p, f, cancellationToken);
    }

    public async Task<BankFile?> BankFileAsync(long id, int? companyId, string? companyIds, bool download, CancellationToken cancellationToken = default)
    {
        var p = Env("GET", companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        var file = await _sql.QuerySingleOrDefaultAsync<BankFile>(StoredProcedure.BankFileManage, p, cancellationToken).ConfigureAwait(false);
        if (file is not null && download)
        {
            var d = Env("DOWNLOADED", companyId, companyIds);
            d.Add("@Id", id, DbType.Int64);
            await _sql.ExecuteAsync(StoredProcedure.BankFileManage, d, cancellationToken).ConfigureAwait(false);
        }
        return file;
    }

    public Task<SaveResult> MarkFileSentAsync(long id, string? reference, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("MARK_SENT", companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Reference", T(reference, 100), DbType.String, size: 100);
        return RunAsync(StoredProcedure.BankFileManage, p, userId, id, cancellationToken);
    }

    private static DynamicParameters PaymentEnv(string action, FinanceFilter f)
    {
        var p = ListEnv(action, f);
        p.Add("@RunId", f.RunId, DbType.Int64);
        p.Add("@Status", string.IsNullOrEmpty(f.Status) ? null : f.Status, DbType.AnsiString, size: 8);
        p.Add("@Method", string.IsNullOrEmpty(f.Method) ? null : f.Method, DbType.AnsiString, size: 6);
        p.Add("@BankId", f.BankId, DbType.Int32);
        p.Add("@FileId", f.FileId, DbType.Int64);
        return p;
    }

    public Task<PagedResult<BankPayment>> PaymentsAsync(FinanceFilter f, CancellationToken cancellationToken = default) =>
        PageAsync<BankPayment>(StoredProcedure.BankPaymentManage, PaymentEnv("LIST", f), f, cancellationToken);

    public async Task<PaymentSummary> PaymentSummaryAsync(FinanceFilter f, CancellationToken cancellationToken = default) =>
        await _sql.QuerySingleOrDefaultAsync<PaymentSummary>(StoredProcedure.BankPaymentManage, PaymentEnv("SUMMARY", f), cancellationToken).ConfigureAwait(false)
        ?? new PaymentSummary();

    public Task<SaveResult> SetPaymentStatusAsync(IEnumerable<long> ids, string status, string? reference, string? reason, DateTime? paidDate,
                                                  int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("SET_STATUS", companyId, companyIds);
        p.Add("@Ids", Csv(ids), DbType.String, size: -1);
        p.Add("@Status", status, DbType.AnsiString, size: 8);
        p.Add("@Reference", T(reference, 100), DbType.String, size: 100);
        p.Add("@Reason", T(reason, 300), DbType.String, size: 300);
        p.Add("@PaidDate", paidDate, DbType.Date);
        return RunAsync(StoredProcedure.BankPaymentManage, p, userId, 0, cancellationToken);
    }

    public Task<SaveResult> ReissuePaymentsAsync(IEnumerable<long> ids, string method, int? companyId, string? companyIds, long? userId,
                                                 CancellationToken cancellationToken = default)
    {
        var p = Env("REISSUE", companyId, companyIds);
        p.Add("@Ids", Csv(ids), DbType.String, size: -1);
        p.Add("@Method", method, DbType.AnsiString, size: 6);
        return RunAsync(StoredProcedure.BankPaymentManage, p, userId, 0, cancellationToken);
    }

    public Task<SaveResult> MarkFilePaidAsync(long fileId, DateTime? paidDate, int? companyId, string? companyIds, long? userId,
                                              CancellationToken cancellationToken = default)
    {
        var p = Env("FILE_PAID", companyId, companyIds);
        p.Add("@FileId", fileId, DbType.Int64);
        p.Add("@PaidDate", paidDate, DbType.Date);
        return RunAsync(StoredProcedure.BankPaymentManage, p, userId, fileId, cancellationToken);
    }

    // ========================================================== accounting
    public Task<IReadOnlyList<FinanceRun>> JournalRunsAsync(int? companyId, string? companyIds, int? year, DateTime? month, CancellationToken cancellationToken = default)
    {
        var p = Env("RUNS", companyId, companyIds);
        p.Add("@Year", year, DbType.Int32);
        p.Add("@RunMonth", month, DbType.Date);
        return _sql.QueryAsync<FinanceRun>(StoredProcedure.JournalManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<JournalLine>> JournalPreviewAsync(long runId, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Env("PREVIEW", companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        return _sql.QueryAsync<JournalLine>(StoredProcedure.JournalManage, p, cancellationToken);
    }

    public Task<SaveResult> CreateJournalAsync(long runId, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("CREATE", companyId, companyIds);
        p.Add("@RunId", runId, DbType.Int64);
        return RunAsync(StoredProcedure.JournalManage, p, userId, 0, cancellationToken);
    }

    public Task<PagedResult<PayrollJournal>> JournalsAsync(FinanceFilter f, CancellationToken cancellationToken = default)
    {
        var p = ListEnv("LIST", f);
        p.Add("@Status", string.IsNullOrEmpty(f.Status) ? null : f.Status, DbType.AnsiString, size: 10);
        return PageAsync<PayrollJournal>(StoredProcedure.JournalManage, p, f, cancellationToken);
    }

    public Task<PayrollJournal?> JournalAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Env("GET", companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<PayrollJournal>(StoredProcedure.JournalManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<JournalLine>> JournalLinesAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Env("LINES", companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QueryAsync<JournalLine>(StoredProcedure.JournalManage, p, cancellationToken);
    }

    public Task<SaveResult> JournalActionAsync(long id, string action, string? text, int? companyId, string? companyIds, long? userId,
                                               CancellationToken cancellationToken = default)
    {
        if (action is not ("EXPORTED" or "POSTED" or "REVERSE")) throw new ArgumentOutOfRangeException(nameof(action));
        var p = Env(action, companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Reference", action == "POSTED" ? T(text, 100) : null, DbType.String, size: 100);
        p.Add("@Reason", action == "REVERSE" ? T(text, 500) : null, DbType.String, size: 500);
        return RunAsync(StoredProcedure.JournalManage, p, userId, id, cancellationToken);
    }

    public Task<AccountingDefaults?> DefaultsAsync(int forCompanyId, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Env("DEFAULTS", companyId, companyIds);
        p.Add("@ForCompanyId", forCompanyId, DbType.Int32);
        return _sql.QuerySingleOrDefaultAsync<AccountingDefaults>(StoredProcedure.JournalManage, p, cancellationToken);
    }

    public Task<SaveResult> SaveDefaultsAsync(int forCompanyId, string? code, string? name, int? companyId, string? companyIds, long? userId,
                                              CancellationToken cancellationToken = default)
    {
        var p = Env("SET_DEFAULTS", companyId, companyIds);
        p.Add("@ForCompanyId", forCompanyId, DbType.Int32);
        p.Add("@AccountCode", T(code, 50), DbType.String, size: 50);
        p.Add("@AccountName", T(name, 150), DbType.String, size: 150);
        return RunAsync(StoredProcedure.JournalManage, p, userId, forCompanyId, cancellationToken);
    }

    public Task<PagedResult<CostAllocation>> AllocationsAsync(FinanceFilter f, CancellationToken cancellationToken = default)
    {
        var p = ListEnv("LIST", f);
        p.Add("@CostCenterId", f.CostCenterId, DbType.Int32);
        return PageAsync<CostAllocation>(StoredProcedure.CostAllocationManage, p, f, cancellationToken);
    }

    public async Task<CostAllocation?> AllocationAsync(int id, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Env("GET", companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        var a = await _sql.QuerySingleOrDefaultAsync<CostAllocation>(StoredProcedure.CostAllocationManage, p, cancellationToken).ConfigureAwait(false);
        if (a is null) return null;
        var l = Env("LINES", companyId, companyIds);
        l.Add("@Id", id, DbType.Int64);
        a.Lines = (await _sql.QueryAsync<CostAllocationLine>(StoredProcedure.CostAllocationManage, l, cancellationToken).ConfigureAwait(false)).ToList();
        return a;
    }

    public Task<SaveResult> SaveAllocationAsync(CostAllocation a, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("SAVE", companyId, companyIds);
        p.Add("@Id", a.CostAllocationId > 0 ? a.CostAllocationId : null, DbType.Int64);
        p.Add("@EmployeeId", a.EmployeeId, DbType.Int64);
        p.Add("@EffectiveFrom", a.EffectiveFrom, DbType.Date);
        p.Add("@EffectiveTo", a.EffectiveTo, DbType.Date);
        p.Add("@Notes", T(a.Notes, 500), DbType.String, size: 500);
        p.Add("@LinesJson", JsonSerializer.Serialize(a.Lines.Where(x => x.CostCenterId > 0).Select(x => new { x.CostCenterId, x.SharePercent })),
              DbType.String, size: -1);
        return RunAsync(StoredProcedure.CostAllocationManage, p, userId, a.CostAllocationId, cancellationToken);
    }

    public Task<SaveResult> DeleteAllocationAsync(int id, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("DELETE", companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        return RunAsync(StoredProcedure.CostAllocationManage, p, userId, id, cancellationToken);
    }

    public Task<FinanceNavCounts?> NavCountsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", T(companyIds, 2000), DbType.String, size: 2000);
        return _sql.QuerySingleOrDefaultAsync<FinanceNavCounts>(StoredProcedure.PayrollFinanceNavCounts, p, cancellationToken);
    }

    // ============================================================= reports
    public async Task<IReadOnlyList<IDictionary<string, object?>>> ReportAsync(string report, int? year, DateTime? month, int? departmentId,
                                                                              int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@Report", report, DbType.AnsiString, size: 20);
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", T(companyIds, 2000), DbType.String, size: 2000);
        p.Add("@Year", year, DbType.Int32);
        p.Add("@RunMonth", month, DbType.Date);
        p.Add("@DepartmentId", departmentId, DbType.Int32);
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        var rows = await _sql.QueryAsync<dynamic>(StoredProcedure.PayrollReport, p, cancellationToken).ConfigureAwait(false);
        return rows.Select(r => (IDictionary<string, object?>)(IDictionary<string, object>)r).ToList();
    }

    public async Task<IReadOnlyList<DateTime>> ReportPeriodsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", T(companyIds, 2000), DbType.String, size: 2000);
        return await _sql.QueryAsync<DateTime>(StoredProcedure.PayrollReportPeriods, p, cancellationToken).ConfigureAwait(false);
    }
}
