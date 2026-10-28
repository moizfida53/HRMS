using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Leave;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Leave (db/68-69): setup, requests and balances
// ===========================================================================

/// <summary>Who is asking: their companies, user and rights - passed to every Leave procedure.</summary>
public sealed class LeaveScope
{
    /// <summary>The user's own company (company users); null for group users.</summary>
    public int? CompanyId { get; init; }
    /// <summary>The company filter of the top bar (CSV).</summary>
    public string? CompanyIds { get; init; }
    public long? UserId { get; init; }
    /// <summary>Acts as HR (LEAVE_MANAGE): for any employee in scope, no notice rule.</summary>
    public bool IsHr { get; init; }
    public bool CanApproveL1 { get; init; }
    public bool CanApproveL2 { get; init; }
    public bool AllowSelf { get; init; }
}

public sealed class LeaveRequestFilter
{
    /// <summary>PENDING, APPROVED, REJECTED, CANCELLED, MINE, ONLEAVE, UPCOMING or ALL.</summary>
    public string? Status { get; init; }
    public int? LeaveTypeId { get; init; }
    public long? EmployeeId { get; init; }
    public DateTime? FromDate { get; init; }
    public DateTime? ToDate { get; init; }
    public string? Search { get; init; }
    /// <summary>My Leave: only this employee's own requests.</summary>
    public long? SelfEmployeeId { get; init; }
    /// <summary>My Leave: requests of the user's team (they are the reporting manager).</summary>
    public bool TeamOnly { get; init; }
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 25;
}

public sealed class LeaveBalanceFilter
{
    public DateTime? AsOf { get; init; }
    public long? EmployeeId { get; init; }
    public int? LeaveTypeId { get; init; }
    public string? Category { get; init; }
    public string? Search { get; init; }
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 25;
}

/// <summary>The file attached to a request (already stored on disk).</summary>
public sealed record LeaveDocument(string Path, string Name, string ContentType, long Size);

public interface ILeaveRepository
{
    // setup
    Task<IReadOnlyList<LeaveTypeSetting>> TypesAsync(LeaveScope scope, int? forCompanyId = null, CancellationToken ct = default);
    Task<SaveResult> SaveTypeAsync(LeaveTypeInput input, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> TypeActionAsync(string action, int id, LeaveScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<LeaveHoliday>> HolidaysAsync(int year, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> SaveHolidayAsync(LeaveHolidayInput input, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> DeleteHolidayAsync(int id, LeaveScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<LeaveCompanySetting>> SettingsAsync(LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> SaveSettingsAsync(int companyId, string weekendDays, bool managerApproval, LeaveScope scope, CancellationToken ct = default);

    // requests
    Task<PagedResult<LeaveRequest>> ListAsync(LeaveRequestFilter filter, LeaveScope scope, CancellationToken ct = default);
    Task<LeaveRequest?> GetAsync(long id, CancellationToken ct = default);
    Task<IReadOnlyList<LeaveHistoryEntry>> HistoryAsync(long id, CancellationToken ct = default);
    Task<LeaveSummary> SummaryAsync(LeaveScope scope, DateTime? month = null, CancellationToken ct = default);
    Task<IReadOnlyList<LeaveEmployeeOption>> EmployeesAsync(LeaveScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<LeaveTypeOption>> TypesForAsync(long employeeId, DateTime? onDate, CancellationToken ct = default);
    Task<(LeavePreview? Preview, SaveResult? Error)> PreviewAsync(LeaveRequestInput input, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> SaveAsync(LeaveRequestInput input, LeaveDocument? document, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> DecideAsync(string action, long id, string? comment, int? expectedLevel, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> CancelAsync(long id, string? comment, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> ReturnAsync(long id, DateTime? returnDate, string? comment, LeaveScope scope, CancellationToken ct = default);
    // db/86: the leave salary settlement (HR)
    Task<LeaveSettlement?> SettlementAsync(long id, LeaveScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<LeavePayItem>> PayItemsAsync(long id, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> SettleAsync(LeaveSettlementInput input, LeaveScope scope, CancellationToken ct = default);

    // balances
    Task<PagedResult<LeaveBalance>> BalancesAsync(LeaveBalanceFilter filter, LeaveScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<LeaveBalance>> EmployeeBalancesAsync(long employeeId, DateTime? asOf, LeaveScope? scope, CancellationToken ct = default);
    Task<IReadOnlyList<LeaveLedgerLine>> LedgerAsync(long employeeId, int leaveTypeId, LeaveScope? scope, CancellationToken ct = default);
    /// <summary>db/98: each employee's annual leave balance; minDays = only those over it.</summary>
    Task<IReadOnlyList<AnnualLeaveBalance>> AnnualBalancesAsync(decimal? minDays, LeaveScope scope, CancellationToken ct = default);
    /// <summary>db/98: forces days off an annual balance over 60 days (30 always remain), with remarks.</summary>
    Task<SaveResult> EliminateAsync(long employeeId, int leaveTypeId, decimal? days, string? remarks, LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> AdjustAsync(long employeeId, int leaveTypeId, string entryType, DateTime? entryDate, decimal? days, string? comment,
                                 LeaveScope scope, CancellationToken ct = default);
    Task<SaveResult> DeleteEntryAsync(long entryId, LeaveScope scope, CancellationToken ct = default);
}

public sealed class LeaveRepository : ILeaveRepository
{
    private readonly ISqlExecutor _sql;

    public LeaveRepository(ISqlExecutor sql) => _sql = sql;

    // -------------------------------------------------------------- setup

    public Task<IReadOnlyList<LeaveTypeSetting>> TypesAsync(LeaveScope scope, int? forCompanyId = null, CancellationToken ct = default)
    {
        var p = Envelope("TYPES", scope);
        p.Add("@ForCompanyId", forCompanyId, DbType.Int32);
        return _sql.QueryAsync<LeaveTypeSetting>(StoredProcedure.LeaveSetupManage, p, ct);
    }

    public async Task<SaveResult> SaveTypeAsync(LeaveTypeInput i, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("TYPE_SAVE", scope);
        p.Add("@Id", i.LeaveTypeId, DbType.Int32);
        p.Add("@ForCompanyId", i.CompanyId, DbType.Int32);
        p.Add("@TypeCode", Trim(i.TypeCode, 20), DbType.AnsiString, size: 20);
        p.Add("@TypeName", Trim(i.TypeName, 100), DbType.String, size: 100);
        p.Add("@ArabicName", Trim(i.ArabicName, 100), DbType.String, size: 100);
        p.Add("@Category", Trim(i.Category, 12), DbType.AnsiString, size: 12);
        p.Add("@BalanceMode", Trim(i.BalanceMode, 10), DbType.AnsiString, size: 10);
        p.Add("@DaysPerYear", i.DaysPerYear, DbType.Decimal, precision: 6, scale: 2);
        p.Add("@AccrualMethod", Trim(i.AccrualMethod, 10), DbType.AnsiString, size: 10);
        p.Add("@PayType", Trim(i.PayType, 10), DbType.AnsiString, size: 10);
        p.Add("@EligibleAfterMonths", i.EligibleAfterMonths, DbType.Int16);
        p.Add("@Gender", Trim(i.Gender, 1), DbType.AnsiStringFixedLength, size: 1);
        p.Add("@CountMode", Trim(i.CountMode, 10), DbType.AnsiString, size: 10);
        p.Add("@ExcludeHolidays", i.ExcludeHolidays, DbType.Boolean);
        p.Add("@AllowHalfDay", i.AllowHalfDay, DbType.Boolean);
        p.Add("@AllowNegative", i.AllowNegative, DbType.Boolean);
        p.Add("@RequiresDocument", i.RequiresDocument, DbType.Boolean);
        p.Add("@MinNoticeDays", i.MinNoticeDays, DbType.Int16);
        p.Add("@MaxDaysPerRequest", i.MaxDaysPerRequest, DbType.Int16);
        p.Add("@Color", Trim(i.Color, 7), DbType.AnsiString, size: 7);
        p.Add("@SortOrder", i.SortOrder, DbType.Int16);
        p.Add("@IsActive", i.IsActive, DbType.Boolean);
        p.Add("@Tiers", Trim(i.Tiers, 400), DbType.AnsiString, size: 400);
        await _sql.ExecuteAsync(StoredProcedure.LeaveSetupManage, p, ct).ConfigureAwait(false);
        return Read(p, i.LeaveTypeId);
    }

    public async Task<SaveResult> TypeActionAsync(string action, int id, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope(action, scope);
        p.Add("@Id", id, DbType.Int32);
        await _sql.ExecuteAsync(StoredProcedure.LeaveSetupManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    public Task<IReadOnlyList<LeaveHoliday>> HolidaysAsync(int year, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("HOLIDAYS", scope);
        p.Add("@Year", year, DbType.Int32);
        return _sql.QueryAsync<LeaveHoliday>(StoredProcedure.LeaveSetupManage, p, ct);
    }

    public async Task<SaveResult> SaveHolidayAsync(LeaveHolidayInput i, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("HOLIDAY_SAVE", scope);
        p.Add("@Id", i.HolidayId, DbType.Int32);
        p.Add("@ForCompanyId", i.CompanyId, DbType.Int32);
        p.Add("@AllCompanies", i.AllCompanies, DbType.Boolean);
        p.Add("@HolidayName", Trim(i.HolidayName, 100), DbType.String, size: 100);
        p.Add("@ArabicName", Trim(i.ArabicName, 100), DbType.String, size: 100);
        p.Add("@FromDate", i.FromDate, DbType.Date);
        p.Add("@ToDate", i.ToDate, DbType.Date);
        await _sql.ExecuteAsync(StoredProcedure.LeaveSetupManage, p, ct).ConfigureAwait(false);
        return Read(p, i.HolidayId);
    }

    public async Task<SaveResult> DeleteHolidayAsync(int id, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("HOLIDAY_DELETE", scope);
        p.Add("@Id", id, DbType.Int32);
        await _sql.ExecuteAsync(StoredProcedure.LeaveSetupManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    public Task<IReadOnlyList<LeaveCompanySetting>> SettingsAsync(LeaveScope scope, CancellationToken ct = default) =>
        _sql.QueryAsync<LeaveCompanySetting>(StoredProcedure.LeaveSetupManage, Envelope("SETTINGS", scope), ct);

    public async Task<SaveResult> SaveSettingsAsync(int companyId, string weekendDays, bool managerApproval, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("SETTINGS_SAVE", scope);
        p.Add("@ForCompanyId", companyId, DbType.Int32);
        p.Add("@WeekendDays", Trim(weekendDays, 20) ?? string.Empty, DbType.AnsiString, size: 20);
        p.Add("@ManagerApproval", managerApproval, DbType.Boolean);
        await _sql.ExecuteAsync(StoredProcedure.LeaveSetupManage, p, ct).ConfigureAwait(false);
        return Read(p, companyId);
    }

    // ----------------------------------------------------------- requests

    public async Task<PagedResult<LeaveRequest>> ListAsync(LeaveRequestFilter f, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestEnvelope("LIST", scope);
        p.Add("@StatusFilter", Trim(f.Status, 12), DbType.AnsiString, size: 12);
        p.Add("@LeaveTypeId", f.LeaveTypeId, DbType.Int32);
        p.Add("@EmployeeId", f.EmployeeId, DbType.Int64);
        p.Add("@FromDate", f.FromDate, DbType.Date);
        p.Add("@ToDate", f.ToDate, DbType.Date);
        p.Add("@Search", Trim(f.Search, 200), DbType.String, size: 200);
        p.Add("@SelfOnly", f.SelfEmployeeId is not null, DbType.Boolean);
        p.Add("@SelfEmployeeId", f.SelfEmployeeId, DbType.Int64);
        p.Add("@TeamOnly", f.TeamOnly, DbType.Boolean);
        p.Add("@PageNumber", Math.Max(1, f.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(f.PageSize, 1, 1000), DbType.Int32);
        var rows = await _sql.QueryAsync<LeaveRequest>(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false);
        return new PagedResult<LeaveRequest>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, f.PageNumber),
            PageSize = Math.Clamp(f.PageSize, 1, 1000)
        };
    }

    public Task<LeaveRequest?> GetAsync(long id, CancellationToken ct = default)
    {
        var p = RequestEnvelope("GET", null);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<LeaveRequest>(StoredProcedure.LeaveRequestManage, p, ct);
    }

    public Task<IReadOnlyList<LeaveHistoryEntry>> HistoryAsync(long id, CancellationToken ct = default)
    {
        var p = RequestEnvelope("HISTORY", null);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QueryAsync<LeaveHistoryEntry>(StoredProcedure.LeaveRequestManage, p, ct);
    }

    public async Task<LeaveSummary> SummaryAsync(LeaveScope scope, DateTime? month = null, CancellationToken ct = default)
    {
        var p = RequestEnvelope("SUMMARY", scope);
        p.Add("@FromDate", month, DbType.Date);
        return await _sql.QuerySingleOrDefaultAsync<LeaveSummary>(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false) ?? new LeaveSummary();
    }

    public Task<IReadOnlyList<LeaveEmployeeOption>> EmployeesAsync(LeaveScope scope, CancellationToken ct = default) =>
        _sql.QueryAsync<LeaveEmployeeOption>(StoredProcedure.LeaveRequestManage, RequestEnvelope("EMPLOYEES", scope), ct);

    public Task<IReadOnlyList<LeaveTypeOption>> TypesForAsync(long employeeId, DateTime? onDate, CancellationToken ct = default)
    {
        var p = RequestEnvelope("TYPES", null);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@StartDate", onDate, DbType.Date);
        return _sql.QueryAsync<LeaveTypeOption>(StoredProcedure.LeaveRequestManage, p, ct);
    }

    public async Task<(LeavePreview? Preview, SaveResult? Error)> PreviewAsync(LeaveRequestInput input, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestParams("PREVIEW", input, scope);
        var preview = await _sql.QuerySingleOrDefaultAsync<LeavePreview>(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false);
        var result = Read(p, input.LeaveRequestId);
        return result.Success ? (preview, null) : (null, result);
    }

    public async Task<SaveResult> SaveAsync(LeaveRequestInput input, LeaveDocument? document, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestParams("SAVE", input, scope);
        p.Add("@ApproveNow", input.ApproveNow, DbType.Boolean);
        p.Add("@AcceptUnpaid", input.AcceptUnpaid, DbType.Boolean);
        p.Add("@DocumentPath", document?.Path, DbType.String, size: 400);
        p.Add("@DocumentName", Trim(document?.Name, 260), DbType.String, size: 260);
        p.Add("@DocumentType", Trim(document?.ContentType, 100), DbType.String, size: 100);
        p.Add("@DocumentSize", document?.Size, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false);
        return Read(p, input.LeaveRequestId);
    }

    public async Task<SaveResult> DecideAsync(string action, long id, string? comment, int? expectedLevel, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestEnvelope(action, scope);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        p.Add("@ExpectedLevel", expectedLevel is { } lv ? (byte)lv : null, DbType.Byte);
        await _sql.ExecuteAsync(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    public async Task<SaveResult> CancelAsync(long id, string? comment, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestEnvelope("CANCEL", scope);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        await _sql.ExecuteAsync(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    public async Task<SaveResult> ReturnAsync(long id, DateTime? returnDate, string? comment, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestEnvelope("RETURN", scope);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@ReturnDate", returnDate, DbType.Date);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        await _sql.ExecuteAsync(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    public Task<LeaveSettlement?> SettlementAsync(long id, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestEnvelope("SETTLEMENT", scope);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<LeaveSettlement>(StoredProcedure.LeaveRequestManage, p, ct);
    }

    public Task<IReadOnlyList<LeavePayItem>> PayItemsAsync(long id, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestEnvelope("PAY_ITEMS", scope);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QueryAsync<LeavePayItem>(StoredProcedure.LeaveRequestManage, p, ct);
    }

    public async Task<SaveResult> SettleAsync(LeaveSettlementInput input, LeaveScope scope, CancellationToken ct = default)
    {
        var p = RequestEnvelope("SETTLE", scope);
        p.Add("@Id", input.Id, DbType.Int64);
        p.Add("@SettlementMode", Trim(input.Mode, 10), DbType.AnsiString, size: 10);
        p.Add("@SettlementAmount", input.Amount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@SettlementDate", input.PaidOn, DbType.Date);
        p.Add("@Comment", Trim(input.Remarks, 500), DbType.String, size: 500);
        await _sql.ExecuteAsync(StoredProcedure.LeaveRequestManage, p, ct).ConfigureAwait(false);
        return Read(p, input.Id);
    }

    // ----------------------------------------------------------- balances

    public async Task<PagedResult<LeaveBalance>> BalancesAsync(LeaveBalanceFilter f, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("LIST", scope);
        p.Add("@AsOf", f.AsOf, DbType.Date);
        p.Add("@EmployeeId", f.EmployeeId, DbType.Int64);
        p.Add("@LeaveTypeId", f.LeaveTypeId, DbType.Int32);
        p.Add("@Category", Trim(f.Category, 12), DbType.AnsiString, size: 12);
        p.Add("@Search", Trim(f.Search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, f.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(f.PageSize, 1, 5000), DbType.Int32);
        var rows = await _sql.QueryAsync<LeaveBalance>(StoredProcedure.LeaveBalanceManage, p, ct).ConfigureAwait(false);
        return new PagedResult<LeaveBalance>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, f.PageNumber),
            PageSize = Math.Clamp(f.PageSize, 1, 5000)
        };
    }

    /// <param name="scope">null = the employee is the signed-in user's own (My Leave) - no company check.</param>
    public Task<IReadOnlyList<LeaveBalance>> EmployeeBalancesAsync(long employeeId, DateTime? asOf, LeaveScope? scope, CancellationToken ct = default)
    {
        var p = Envelope("EMPLOYEE", scope);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@AsOf", asOf, DbType.Date);
        p.Add("@SelfOnly", scope is null, DbType.Boolean);
        return _sql.QueryAsync<LeaveBalance>(StoredProcedure.LeaveBalanceManage, p, ct);
    }

    public Task<IReadOnlyList<LeaveLedgerLine>> LedgerAsync(long employeeId, int leaveTypeId, LeaveScope? scope, CancellationToken ct = default)
    {
        var p = Envelope("LEDGER", scope);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@LeaveTypeId", leaveTypeId, DbType.Int32);
        p.Add("@SelfOnly", scope is null, DbType.Boolean);
        return _sql.QueryAsync<LeaveLedgerLine>(StoredProcedure.LeaveBalanceManage, p, ct);
    }

    public Task<IReadOnlyList<AnnualLeaveBalance>> AnnualBalancesAsync(decimal? minDays, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("ANNUAL", scope);
        p.Add("@MinDays", minDays, DbType.Decimal, precision: 7, scale: 2);
        return _sql.QueryAsync<AnnualLeaveBalance>(StoredProcedure.LeaveBalanceManage, p, ct);
    }

    public async Task<SaveResult> EliminateAsync(long employeeId, int leaveTypeId, decimal? days, string? remarks, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("ELIMINATE", scope);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@LeaveTypeId", leaveTypeId, DbType.Int32);
        p.Add("@Days", days, DbType.Decimal, precision: 7, scale: 2);
        p.Add("@Comment", Trim(remarks, 500), DbType.String, size: 500);
        await _sql.ExecuteAsync(StoredProcedure.LeaveBalanceManage, p, ct).ConfigureAwait(false);
        return Read(p, 0);
    }

    public async Task<SaveResult> AdjustAsync(long employeeId, int leaveTypeId, string entryType, DateTime? entryDate, decimal? days, string? comment,
                                              LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("ADJUST", scope);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@LeaveTypeId", leaveTypeId, DbType.Int32);
        p.Add("@EntryType", Trim(entryType, 10), DbType.AnsiString, size: 10);
        p.Add("@EntryDate", entryDate, DbType.Date);
        p.Add("@Days", days, DbType.Decimal, precision: 7, scale: 2);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        await _sql.ExecuteAsync(StoredProcedure.LeaveBalanceManage, p, ct).ConfigureAwait(false);
        return Read(p, 0);
    }

    public async Task<SaveResult> DeleteEntryAsync(long entryId, LeaveScope scope, CancellationToken ct = default)
    {
        var p = Envelope("DELETE_ENTRY", scope);
        p.Add("@Id", entryId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.LeaveBalanceManage, p, ct).ConfigureAwait(false);
        return Read(p, entryId);
    }

    // ------------------------------------------------------------ helpers

    private static DynamicParameters RequestParams(string action, LeaveRequestInput i, LeaveScope scope)
    {
        var p = RequestEnvelope(action, scope);
        p.Add("@Id", i.LeaveRequestId, DbType.Int64);
        p.Add("@EmployeeId", i.EmployeeId, DbType.Int64);
        p.Add("@LeaveTypeId", i.LeaveTypeId, DbType.Int32);
        p.Add("@StartDate", i.StartDate, DbType.Date);
        p.Add("@EndDate", i.EndDate, DbType.Date);
        p.Add("@HalfDay", i.HalfDay, DbType.Boolean);
        p.Add("@Reason", Trim(i.Reason, 500), DbType.String, size: 500);
        p.Add("@ResumeDate", i.ResumeDate, DbType.Date);
        return p;
    }

    /// <summary>The requests procedure also takes the user's rights.</summary>
    private static DynamicParameters RequestEnvelope(string action, LeaveScope? scope)
    {
        var p = Envelope(action, scope);
        if (scope is not null)
        {
            p.Add("@IsHr", scope.IsHr, DbType.Boolean);
            p.Add("@CanApproveL1", scope.CanApproveL1, DbType.Boolean);
            p.Add("@CanApproveL2", scope.CanApproveL2, DbType.Boolean);
            p.Add("@AllowSelf", scope.AllowSelf, DbType.Boolean);
        }
        return p;
    }

    private static DynamicParameters Envelope(string action, LeaveScope? scope)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 20);
        if (scope is not null)
        {
            p.Add("@CompanyId", scope.CompanyId, DbType.Int32);
            p.Add("@CompanyIds", Trim(scope.CompanyIds, 2000), DbType.String, size: 2000);
            p.Add("@UserId", scope.UserId, DbType.Int64);
        }
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        return p;
    }

    private static SaveResult Read(DynamicParameters p, long fallbackId)
    {
        var code = p.Get<string?>("@ResultCode") ?? ResultCode.Success;
        var message = p.Get<string?>("@ResultMessage") ?? string.Empty;
        var id = p.Get<long?>("@NewId") is { } n && n > 0 ? n : fallbackId;
        return string.Equals(code, ResultCode.Success, StringComparison.Ordinal)
            ? SaveResult.Ok(id, string.IsNullOrWhiteSpace(message) ? "Saved successfully." : message)
            : SaveResult.Fail(string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code);
    }

    private static string? Trim(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length > maxLength ? value[..maxLength] : value;
    }
}
