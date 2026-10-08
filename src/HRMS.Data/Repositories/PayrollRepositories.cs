using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Payroll calendars (db/29-30) - same envelope as the Organization masters
// ===========================================================================

public interface IPayrollCalendarRepository : IMasterRepository<PayrollCalendar>
{
    Task<IReadOnlyList<PayrollPeriodRow>> PeriodsAsync(int calendarId, int? year, bool openableOnly, CancellationToken cancellationToken = default);

    Task<SaveResult> GeneratePeriodsAsync(int calendarId, int year, long? userId, CancellationToken cancellationToken = default);

    Task<PayrollPeriodEdit?> GetPeriodAsync(int periodId, CancellationToken cancellationToken = default);

    Task<SaveResult> SavePeriodAsync(PayrollPeriodEdit period, long? userId, CancellationToken cancellationToken = default);

    Task<SaveResult> DeletePeriodAsync(int periodId, long? userId, CancellationToken cancellationToken = default);
}

public sealed class PayrollCalendarRepository : MasterRepositoryBase<PayrollCalendar>, IPayrollCalendarRepository
{
    private readonly ISqlExecutor _sql;

    public PayrollCalendarRepository(ISqlExecutor sql) : base(sql) => _sql = sql;

    protected override string ProcedureName => StoredProcedure.PayrollCalendarManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "CalendarCode", "CalendarName", "PayFrequency", "CompanyName", "IsActive" };

    protected override string DefaultSortColumn => "CalendarName";

    protected override long GetKey(PayrollCalendar entity) => entity.PayrollCalendarId;

    protected override void AddEntityParameters(DynamicParameters parameters, PayrollCalendar entity)
    {
        var monthly = entity.PayFrequency == "MONTHLY";
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@CalendarCode", entity.CalendarCode?.Trim(), DbType.String, size: 30);
        parameters.Add("@CalendarName", entity.CalendarName?.Trim(), DbType.String, size: 150);
        parameters.Add("@ArabicName", NullIfEmpty(entity.ArabicName), DbType.String, size: 150);
        parameters.Add("@PayFrequency", entity.PayFrequency, DbType.AnsiString, size: 10);
        parameters.Add("@FirstPeriodStartDate", entity.FirstPeriodStartDate, DbType.Date);
        parameters.Add("@CutOffDay", monthly ? entity.CutOffDay : null, DbType.Byte);
        parameters.Add("@PaymentDay", monthly ? entity.PaymentDay : null, DbType.Byte);
        parameters.Add("@PaymentMonthOffset", monthly && entity.PaymentNextMonth ? 1 : 0, DbType.Byte);
        parameters.Add("@CutOffOffsetDays", monthly ? null : entity.CutOffOffsetDays, DbType.Int16);
        parameters.Add("@PaymentOffsetDays", monthly ? null : entity.PaymentOffsetDays, DbType.Int16);
        parameters.Add("@WorkingDaysBasis", entity.WorkingDaysBasis, DbType.AnsiString, size: 10);
        parameters.Add("@FixedDaysPerMonth", entity.WorkingDaysBasis == "FIXED" ? entity.FixedDaysPerMonth : null, DbType.Byte);
        parameters.Add("@CurrencyId", entity.CurrencyId, DbType.Int32);
        parameters.Add("@Description", NullIfEmpty(entity.Description), DbType.String, size: 500);
        parameters.Add("@IsDefault", entity.IsDefault, DbType.Boolean);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }

    public Task<IReadOnlyList<PayrollPeriodRow>> PeriodsAsync(int calendarId, int? year, bool openableOnly, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("PERIODS");
        p.Add("@PayrollCalendarId", calendarId, DbType.Int32);
        p.Add("@Year", year, DbType.Int32);
        p.Add("@StageFilter", openableOnly ? "OPENABLE" : null, DbType.AnsiString, size: 20);
        return _sql.QueryAsync<PayrollPeriodRow>(StoredProcedure.PayrollRunManage, p, cancellationToken);
    }

    public async Task<SaveResult> GeneratePeriodsAsync(int calendarId, int year, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PeriodEnvelope("GENERATE");
        p.Add("@ParentId", calendarId, DbType.Int32);
        p.Add("@PeriodYear", (short)year, DbType.Int16);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollPeriodManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, calendarId);
    }

    public Task<PayrollPeriodEdit?> GetPeriodAsync(int periodId, CancellationToken cancellationToken = default)
    {
        var p = PeriodEnvelope("GET");
        p.Add("@Id", periodId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<PayrollPeriodEdit>(StoredProcedure.PayrollPeriodManage, p, cancellationToken);
    }

    public async Task<SaveResult> SavePeriodAsync(PayrollPeriodEdit period, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PeriodEnvelope("UPDATE");
        p.Add("@Id", period.PayrollPeriodId, DbType.Int64);
        p.Add("@StartDate", period.StartDate, DbType.Date);
        p.Add("@EndDate", period.EndDate, DbType.Date);
        p.Add("@CutOffDate", period.CutOffDate, DbType.Date);
        p.Add("@PaymentDate", period.PaymentDate, DbType.Date);
        p.Add("@PeriodName", NullIfEmpty(period.PeriodName), DbType.String, size: 100);
        p.Add("@Remarks", NullIfEmpty(period.Remarks), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollPeriodManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, period.PayrollPeriodId);
    }

    public async Task<SaveResult> DeletePeriodAsync(int periodId, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PeriodEnvelope("DELETE");
        p.Add("@Id", periodId, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollPeriodManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, periodId);
    }

    private static DynamicParameters PeriodEnvelope(string action)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        return p;
    }

    private static string? NullIfEmpty(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}

// ===========================================================================
// Payroll runs (db/34-35)
// ===========================================================================

public sealed class RunListFilter
{
    public int? CompanyId { get; set; }
    public string? CompanyIds { get; set; }
    public DateTime? RunMonth { get; set; }
    public string? Stage { get; set; }
    public string? Type { get; set; }
    public int? Year { get; set; }
    public string? Search { get; set; }
    /// <summary>Closed payrolls with payslips still to generate (any stage filter is ignored).</summary>
    public bool PayslipPending { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 25;
}

public sealed class RunEmployeeFilter
{
    public long? EmployeeId { get; set; }
    public string? Filter { get; set; }
    public string? Search { get; set; }
    public string? Sort { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 25;
}

public interface IPayrollRunRepository
{
    Task<PagedResult<PayrollRun>> ListAsync(RunListFilter filter, CancellationToken cancellationToken = default);
    Task<PayrollRun?> GetAsync(long runId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<RunMonthOption>> MonthsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<NextRunCode?> NextCodeAsync(int periodId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PayrollDraft>> DraftsAsync(int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PayrollRunHistoryEntry>> HistoryAsync(long runId, CancellationToken cancellationToken = default);

    Task<SaveResult> SaveDraftAsync(PayrollDraftInput input, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> RunActionAsync(string action, long runId, long? userId, string? stage = null, string? comment = null,
                                    bool allowSelfApproval = false, CancellationToken cancellationToken = default);

    Task<PagedResult<PayrollRunEmployee>> EmployeesAsync(long runId, RunEmployeeFilter filter, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ExcludedEmployee>> ExcludedAsync(long runId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PayrollRunLine>> LinesAsync(long runId, long? employeeId, CancellationToken cancellationToken = default);
    Task<PayrollRunSummary> SummaryAsync(long runId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PayComponentOption>> ComponentsAsync(long runId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<RunCompareRow>> CompareAsync(long runA, long runB, CancellationToken cancellationToken = default);

    Task<SaveResult> AddLineAsync(long runId, IReadOnlyCollection<long> employeeIds, int componentId, decimal amount, string? comment,
                                  long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> RemoveLineAsync(long runId, long lineId, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> ExcludeAsync(long runId, long employeeId, bool exclude, string? reason, long? userId, CancellationToken cancellationToken = default);

    Task<PagedResult<PayrollRunIssue>> IssuesAsync(long runId, string? severity, string? status, string? search, int page, int pageSize,
                                                   CancellationToken cancellationToken = default);
    Task<SaveResult> AcknowledgeAsync(long runId, long issueId, string? reason, long? userId, CancellationToken cancellationToken = default);
}

public sealed class PayrollRunRepository : IPayrollRunRepository
{
    private readonly ISqlExecutor _sql;

    public PayrollRunRepository(ISqlExecutor sql) => _sql = sql;

    // ---------------------------------------------------------------- runs

    public async Task<PagedResult<PayrollRun>> ListAsync(RunListFilter filter, CancellationToken cancellationToken = default)
    {
        var p = Envelope("LIST");
        p.Add("@CompanyId", filter.CompanyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(filter.CompanyIds, 2000), DbType.String, size: 2000);
        p.Add("@RunMonth", filter.RunMonth, DbType.Date);
        p.Add("@StageFilter", Trim(filter.Stage, 20), DbType.AnsiString, size: 20);
        p.Add("@TypeFilter", Trim(filter.Type, 10), DbType.AnsiString, size: 10);
        p.Add("@Year", filter.Year, DbType.Int32);
        p.Add("@Search", Trim(filter.Search, 200), DbType.String, size: 200);
        p.Add("@PayslipPending", filter.PayslipPending, DbType.Boolean);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(filter.PageSize, 1, 500), DbType.Int32);

        var rows = await _sql.QueryAsync<PayrollRun>(StoredProcedure.PayrollRunManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<PayrollRun>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, filter.PageNumber),
            PageSize = Math.Clamp(filter.PageSize, 1, 500)
        };
    }

    public Task<PayrollRun?> GetAsync(long runId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("GET");
        p.Add("@Id", runId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<PayrollRun>(StoredProcedure.PayrollRunManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<RunMonthOption>> MonthsAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = Envelope("MONTHS");
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(companyIds, 2000), DbType.String, size: 2000);
        return _sql.QueryAsync<RunMonthOption>(StoredProcedure.PayrollRunManage, p, cancellationToken);
    }

    public Task<NextRunCode?> NextCodeAsync(int periodId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("NEXT_CODE");
        p.Add("@PayrollPeriodId", periodId, DbType.Int32);
        return _sql.QuerySingleOrDefaultAsync<NextRunCode>(StoredProcedure.PayrollRunManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<PayrollDraft>> DraftsAsync(int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("DRAFTS");
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(companyIds, 2000), DbType.String, size: 2000);
        p.Add("@UserId", userId, DbType.Int64);
        return _sql.QueryAsync<PayrollDraft>(StoredProcedure.PayrollRunManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<PayrollRunHistoryEntry>> HistoryAsync(long runId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("HISTORY");
        p.Add("@Id", runId, DbType.Int64);
        return _sql.QueryAsync<PayrollRunHistoryEntry>(StoredProcedure.PayrollRunManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveDraftAsync(PayrollDraftInput input, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("DRAFT_SAVE");
        p.Add("@Id", input.PayrollRunId is > 0 ? input.PayrollRunId : null, DbType.Int64);
        p.Add("@CompanyId", input.CompanyId > 0 ? input.CompanyId : null, DbType.Int32);
        p.Add("@PayrollCalendarId", input.PayrollCalendarId, DbType.Int32);
        p.Add("@PayrollPeriodId", input.PayrollPeriodId, DbType.Int32);
        p.Add("@RunType", input.RunType, DbType.AnsiString, size: 10);
        p.Add("@Description", Trim(input.Description, 500), DbType.String, size: 500);
        p.Add("@ScopeDepartmentId", input.ScopeDepartmentId is > 0 ? input.ScopeDepartmentId : null, DbType.Int32);
        p.Add("@ScopeWorkLocationId", input.ScopeWorkLocationId is > 0 ? input.ScopeWorkLocationId : null, DbType.Int32);
        p.Add("@ScopeEmploymentType", Trim(input.ScopeEmploymentType, 20), DbType.String, size: 20);
        p.Add("@ScopeNationality", Trim(input.ScopeNationality, 12), DbType.AnsiString, size: 12);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollRunManage, p, cancellationToken).ConfigureAwait(false);
        return ReadResult(p, input.PayrollRunId ?? 0);
    }

    public async Task<SaveResult> RunActionAsync(string action, long runId, long? userId, string? stage = null, string? comment = null,
                                                 bool allowSelfApproval = false, CancellationToken cancellationToken = default)
    {
        var p = Envelope(action);
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@Stage", Trim(stage, 20), DbType.AnsiString, size: 20);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        p.Add("@AllowSelfApproval", allowSelfApproval, DbType.Boolean);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollRunManage, p, cancellationToken).ConfigureAwait(false);
        return ReadResult(p, runId);
    }

    // ------------------------------------------------------- employees / lines

    public async Task<PagedResult<PayrollRunEmployee>> EmployeesAsync(long runId, RunEmployeeFilter filter, CancellationToken cancellationToken = default)
    {
        var p = Envelope("LIST");
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@EmployeeId", filter.EmployeeId, DbType.Int64);
        p.Add("@Filter", Trim(filter.Filter, 20), DbType.AnsiString, size: 20);
        p.Add("@Search", Trim(filter.Search, 200), DbType.String, size: 200);
        p.Add("@SortColumn", Trim(filter.Sort, 30), DbType.AnsiString, size: 30);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(filter.PageSize, 1, 5000), DbType.Int32);

        var rows = await _sql.QueryAsync<PayrollRunEmployee>(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<PayrollRunEmployee>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, filter.PageNumber),
            PageSize = Math.Clamp(filter.PageSize, 1, 5000)
        };
    }

    public Task<IReadOnlyList<ExcludedEmployee>> ExcludedAsync(long runId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("EXCLUDED");
        p.Add("@Id", runId, DbType.Int64);
        return _sql.QueryAsync<ExcludedEmployee>(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<PayrollRunLine>> LinesAsync(long runId, long? employeeId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("LINES");
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        return _sql.QueryAsync<PayrollRunLine>(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken);
    }

    public async Task<PayrollRunSummary> SummaryAsync(long runId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("SUMMARY");
        p.Add("@Id", runId, DbType.Int64);
        return await _sql.QuerySingleOrDefaultAsync<PayrollRunSummary>(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken)
                         .ConfigureAwait(false) ?? new PayrollRunSummary();
    }

    public Task<IReadOnlyList<PayComponentOption>> ComponentsAsync(long runId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("COMPONENTS");
        p.Add("@Id", runId, DbType.Int64);
        return _sql.QueryAsync<PayComponentOption>(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<RunCompareRow>> CompareAsync(long runA, long runB, CancellationToken cancellationToken = default)
    {
        var p = Envelope("COMPARE");
        p.Add("@Id", runA, DbType.Int64);
        p.Add("@OtherId", runB, DbType.Int64);
        return _sql.QueryAsync<RunCompareRow>(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken);
    }

    public async Task<SaveResult> AddLineAsync(long runId, IReadOnlyCollection<long> employeeIds, int componentId, decimal amount, string? comment,
                                               long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("ADD_LINE");
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@EmployeeIds", string.Join(',', employeeIds.Distinct().Take(5000)), DbType.String, size: -1);
        p.Add("@PayComponentId", componentId, DbType.Int32);
        p.Add("@Amount", amount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken).ConfigureAwait(false);
        return ReadResult(p, runId);
    }

    public async Task<SaveResult> RemoveLineAsync(long runId, long lineId, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("REMOVE_LINE");
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@LineId", lineId, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken).ConfigureAwait(false);
        return ReadResult(p, runId);
    }

    public async Task<SaveResult> ExcludeAsync(long runId, long employeeId, bool exclude, string? reason, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope(exclude ? "EXCLUDE" : "INCLUDE");
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@Comment", Trim(reason, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollRunEmployeeManage, p, cancellationToken).ConfigureAwait(false);
        return ReadResult(p, runId);
    }

    // ------------------------------------------------------------- issues

    public async Task<PagedResult<PayrollRunIssue>> IssuesAsync(long runId, string? severity, string? status, string? search, int page, int pageSize,
                                                                CancellationToken cancellationToken = default)
    {
        var p = Envelope("LIST");
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@Severity", Trim(severity, 10), DbType.AnsiString, size: 10);
        p.Add("@StatusFilter", Trim(status, 10), DbType.AnsiString, size: 10);
        p.Add("@Search", Trim(search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, page), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(pageSize, 1, 1000), DbType.Int32);
        var rows = await _sql.QueryAsync<PayrollRunIssue>(StoredProcedure.PayrollRunIssueManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<PayrollRunIssue>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, page),
            PageSize = Math.Clamp(pageSize, 1, 1000)
        };
    }

    public async Task<SaveResult> AcknowledgeAsync(long runId, long issueId, string? reason, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("ACK");
        p.Add("@Id", runId, DbType.Int64);
        p.Add("@IssueId", issueId, DbType.Int64);
        p.Add("@Comment", Trim(reason, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayrollRunIssueManage, p, cancellationToken).ConfigureAwait(false);
        return ReadResult(p, issueId);
    }

    // ------------------------------------------------------------- helpers

    internal static DynamicParameters Envelope(string action)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 20);
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        return p;
    }

    internal static SaveResult ReadResult(DynamicParameters parameters, long fallbackId)
    {
        var code = parameters.Get<string?>("@ResultCode") ?? ResultCode.Success;
        var message = parameters.Get<string?>("@ResultMessage") ?? string.Empty;
        var newId = parameters.Get<long?>("@NewId") ?? fallbackId;

        return string.Equals(code, ResultCode.Success, StringComparison.Ordinal)
            ? SaveResult.Ok(newId, string.IsNullOrWhiteSpace(message) ? "Saved successfully." : message)
            : SaveResult.Fail(string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code);
    }

    private static string? Trim(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        value = value.Trim();
        return value.Length <= maxLength ? value : value[..maxLength];
    }
}
