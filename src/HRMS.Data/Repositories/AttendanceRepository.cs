using System.Data;
using System.Globalization;
using System.Text.Json;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Domain.Attendance;
using HRMS.Domain.Common;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Time & Attendance (db/126): patterns, employees, imports, days, the month.
// ===========================================================================

public sealed record AttScope(int? CompanyId, string? CompanyIds);

public sealed class AttRecordFilter
{
    public int? CompanyId { get; init; }
    public DateTime Month { get; init; }
    public long? EmployeeId { get; init; }
    /// <summary>A status, or ISSUES / DEDUCTED / LATE / SHORT / OVERTIME.</summary>
    public string? Status { get; init; }
    public string? Search { get; init; }
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 50;
}

/// <summary>The months of a company a change touched (they are worked out again).</summary>
public sealed record AttMonth(int CompanyId, DateTime RunMonth);

public interface IAttendanceRepository
{
    // patterns
    Task<IReadOnlyList<AttendancePattern>> PatternsAsync(AttScope scope, string? search = null, bool? active = null, CancellationToken ct = default);
    Task<AttendancePattern?> PatternAsync(int id, CancellationToken ct = default);
    Task<SaveResult> SavePatternAsync(AttendancePattern pattern, long? userId, CancellationToken ct = default);
    Task<SaveResult> TogglePatternAsync(int id, long? userId, CancellationToken ct = default);
    Task<SaveResult> DeletePatternAsync(int id, long? userId, CancellationToken ct = default);

    // employees
    Task<PagedResult<AttendanceEmployee>> EmployeesAsync(AttScope scope, int? company, int? pattern, string? search, int page, int size, CancellationToken ct = default);
    Task<IReadOnlyList<AttendanceEmployee>> MatchListAsync(AttScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<AttendanceAssignment>> AssignmentsAsync(AttScope scope, long? employeeId = null, CancellationToken ct = default);
    Task<SaveResult> SetEmployeesAsync(AttScope scope, IEnumerable<object> rows, long? userId, CancellationToken ct = default);
    Task<SaveResult> UnassignAsync(AttScope scope, long assignmentId, long? userId, CancellationToken ct = default);

    // imports
    Task<(SaveResult Result, IReadOnlyList<AttMonth> Months)> ImportAsync(AttScope scope, string fileName, string format, string? mapping, int rowCount,
                                                                          int skipped, IEnumerable<object> days, long? userId, CancellationToken ct = default);
    Task<PagedResult<AttendanceImport>> ImportsAsync(AttScope scope, int page, CancellationToken ct = default);
    Task<(SaveResult Result, IReadOnlyList<AttMonth> Months)> DeleteImportAsync(AttScope scope, long id, long? userId, CancellationToken ct = default);

    // the calculation
    Task<IReadOnlyList<AttDayInput>> MonthDaysAsync(AttScope scope, int company, DateTime month, long? employeeId, CancellationToken ct = default);
    Task<IReadOnlyList<AttEmployeeInput>> MonthEmployeesAsync(AttScope scope, int company, DateTime month, long? employeeId, CancellationToken ct = default);
    Task<IReadOnlyList<AttLeaveInput>> MonthLeaveAsync(int company, DateTime month, CancellationToken ct = default);
    Task<IReadOnlyList<AttHolidayInput>> MonthHolidaysAsync(int company, DateTime month, CancellationToken ct = default);
    Task SaveMonthAsync(AttScope scope, int company, DateTime month, long? employeeId, IEnumerable<AttDayResult> days, long? userId, CancellationToken ct = default);

    // days
    Task<PagedResult<AttendanceRecord>> RecordsAsync(AttScope scope, AttRecordFilter filter, CancellationToken ct = default);
    Task<AttendanceRecord?> RecordAsync(AttScope scope, long id, CancellationToken ct = default);
    Task<AttendanceKpis> KpisAsync(AttScope scope, int? company, DateTime month, long? employeeId, CancellationToken ct = default);
    Task<IReadOnlyList<DateTime>> MonthsAsync(AttScope scope, int? company, CancellationToken ct = default);
    Task<(SaveResult Result, AttMonth? Month)> EditRecordAsync(AttScope scope, long id, DateTime? clockIn, DateTime? clockOut, bool excused, string? note,
                                                             long? userId, CancellationToken ct = default);
    Task<(SaveResult Result, AttMonth? Month)> AddRecordAsync(AttScope scope, long employeeId, DateTime date, DateTime? clockIn, DateTime? clockOut,
                                                            bool excused, string? note, long? userId, CancellationToken ct = default);

    // the month
    Task<IReadOnlyList<AttendanceSummaryRow>> SummaryAsync(AttScope scope, int company, DateTime month, CancellationToken ct = default);
    Task<SaveResult> PostAsync(AttScope scope, int company, DateTime month, IEnumerable<object> rows, long? userId, CancellationToken ct = default);
    Task<SaveResult> UnpostAsync(AttScope scope, int company, DateTime month, long? userId, CancellationToken ct = default);
}

public sealed class AttendanceRepository : IAttendanceRepository
{
    private const string PatternProc = "Attendance.usp_AttPattern_Manage";
    private const string EmployeeProc = "Attendance.usp_AttEmployee_Manage";
    private const string ImportProc = "Attendance.usp_AttImport_Manage";
    private const string RecordProc = "Attendance.usp_AttRecord_Manage";
    private const string SummaryProc = "Attendance.usp_AttSummary_Manage";
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private readonly ISqlExecutor _sql;

    public AttendanceRepository(ISqlExecutor sql) => _sql = sql;

    private static DynamicParameters P(string action, AttScope? scope)
    {
        var p = PayrollRunRepository.Envelope(action);
        if (scope is not null)
        {
            p.Add("@CompanyId", scope.CompanyId, DbType.Int32);
            p.Add("@CompanyIds", string.IsNullOrWhiteSpace(scope.CompanyIds) ? null : scope.CompanyIds, DbType.String, size: 2000);
        }
        return p;
    }

    private static string? T(string? v, int max) => string.IsNullOrWhiteSpace(v) ? null : v.Trim().Length <= max ? v.Trim() : v.Trim()[..max];

    private static DateTime MonthOf(DateTime d) => new(d.Year, d.Month, 1);

    // ------------------------------------------------------------ patterns

    public async Task<IReadOnlyList<AttendancePattern>> PatternsAsync(AttScope scope, string? search = null, bool? active = null, CancellationToken ct = default)
    {
        var p = P("LIST", scope);
        p.Add("@Search", T(search, 200), DbType.String, size: 200);
        p.Add("@IsActiveFilter", active, DbType.Boolean);
        var list = await _sql.QueryAsync<AttendancePattern>(PatternProc, p, ct).ConfigureAwait(false);
        var slabs = await _sql.QueryAsync<AttendanceSlab>(PatternProc, P("SLABS", scope), ct).ConfigureAwait(false);
        foreach (var pt in list) pt.Slabs = slabs.Where(s => s.PatternId == pt.PatternId).ToList();
        return list;
    }

    public async Task<AttendancePattern?> PatternAsync(int id, CancellationToken ct = default)
    {
        var p = P("GET", null);
        p.Add("@Id", id, DbType.Int32);
        var pattern = await _sql.QuerySingleOrDefaultAsync<AttendancePattern>(PatternProc, p, ct).ConfigureAwait(false);
        if (pattern is null) return null;
        var s = P("SLABS", null);
        s.Add("@Id", id, DbType.Int32);
        pattern.Slabs = (await _sql.QueryAsync<AttendanceSlab>(PatternProc, s, ct).ConfigureAwait(false)).ToList();
        return pattern;
    }

    public async Task<SaveResult> SavePatternAsync(AttendancePattern x, long? userId, CancellationToken ct = default)
    {
        var p = P("SAVE", null);
        p.Add("@Id", x.PatternId > 0 ? x.PatternId : null, DbType.Int32);
        p.Add("@PatternCompanyId", x.CompanyId > 0 ? x.CompanyId : null, DbType.Int32);
        p.Add("@PatternCode", T(x.PatternCode, 30)?.ToUpperInvariant(), DbType.String, size: 30);
        p.Add("@PatternName", T(x.PatternName, 150), DbType.String, size: 150);
        p.Add("@ArabicName", T(x.ArabicName, 150), DbType.String, size: 150);
        p.Add("@PatternType", x.PatternType == AttCodes.Flexible ? AttCodes.Flexible : AttCodes.Fixed, DbType.AnsiString, size: 10);
        p.Add("@ShiftStart", x.ShiftStart, DbType.Time);
        p.Add("@ShiftEnd", x.ShiftEnd, DbType.Time);
        p.Add("@RequiredMinutes", (short)Math.Clamp(x.RequiredMinutes, 1, 1440), DbType.Int16);
        p.Add("@BreakMinutes", (short)Math.Clamp(x.BreakMinutes, 0, 600), DbType.Int16);
        p.Add("@GraceMinutes", (short)Math.Clamp(x.GraceMinutes, 0, 600), DbType.Int16);
        p.Add("@WeeklyOffDays", T(x.WeeklyOffDays, 30), DbType.AnsiString, size: 30);
        p.Add("@LateEnabled", x.LateEnabled, DbType.Boolean);
        p.Add("@ShortEnabled", x.ShortEnabled, DbType.Boolean);
        p.Add("@CombineRule", x.CombineRule == "BOTH" ? "BOTH" : "HIGHER", DbType.AnsiString, size: 10);
        p.Add("@FreeLatesPerMonth", (byte)Math.Clamp(x.FreeLatesPerMonth, 0, 31), DbType.Byte);
        p.Add("@AbsentEnabled", x.AbsentEnabled, DbType.Boolean);
        p.Add("@AbsentDayValue", x.AbsentDayValue, DbType.Decimal, precision: 5, scale: 2);
        p.Add("@MissingPunch", x.MissingPunch is "IGNORE" or "HALF_DAY" or "ABSENT" ? x.MissingPunch : "FLAG", DbType.AnsiString, size: 10);
        p.Add("@OvertimeEnabled", x.OvertimeEnabled, DbType.Boolean);
        p.Add("@OvertimeAfterMinutes", (short)Math.Clamp(x.OvertimeAfterMinutes, 0, 1440), DbType.Int16);
        p.Add("@OvertimeRate", x.OvertimeRate, DbType.Decimal, precision: 5, scale: 2);
        p.Add("@SalaryBasis", x.SalaryBasis == "GROSS" ? "GROSS" : "BASIC", DbType.AnsiString, size: 10);
        p.Add("@DayDivisor", (byte)Math.Clamp(x.DayDivisor, 1, 31), DbType.Byte);
        p.Add("@MaxDeductionType", x.MaxDeductionType is "AMOUNT" or "PERCENT" ? x.MaxDeductionType : "NONE", DbType.AnsiString, size: 10);
        p.Add("@MaxDeductionValue", x.MaxDeductionType is "AMOUNT" or "PERCENT" ? x.MaxDeductionValue : null, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@Description", T(x.Description, 500), DbType.String, size: 500);
        p.Add("@IsActive", x.IsActive, DbType.Boolean);
        p.Add("@SlabsJson", JsonSerializer.Serialize(x.Slabs.Select(s => new { s.RuleKind, s.FromMinutes, s.ToMinutes, s.DeductionType, s.Value }), Json),
              DbType.String, size: -1);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(PatternProc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, x.PatternId);
    }

    public Task<SaveResult> TogglePatternAsync(int id, long? userId, CancellationToken ct = default) => PatternAction("TOGGLE", id, userId, ct);
    public Task<SaveResult> DeletePatternAsync(int id, long? userId, CancellationToken ct = default) => PatternAction("DELETE", id, userId, ct);

    private async Task<SaveResult> PatternAction(string action, int id, long? userId, CancellationToken ct)
    {
        var p = P(action, null);
        p.Add("@Id", id, DbType.Int32);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(PatternProc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    // ------------------------------------------------------------ employees

    public async Task<PagedResult<AttendanceEmployee>> EmployeesAsync(AttScope scope, int? company, int? pattern, string? search, int page, int size,
                                                                     CancellationToken ct = default)
    {
        var p = P("LIST", scope);
        p.Add("@FilterCompany", company, DbType.Int32);
        p.Add("@PatternFilter", pattern, DbType.Int32);
        p.Add("@Search", T(search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, page), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(size, 1, 500), DbType.Int32);
        var rows = await _sql.QueryAsync<AttendanceEmployee>(EmployeeProc, p, ct).ConfigureAwait(false);
        return new PagedResult<AttendanceEmployee>
        {
            Items = rows, TotalCount = rows.Count == 0 ? 0 : rows[0].Total, PageNumber = Math.Max(1, page), PageSize = Math.Clamp(size, 1, 500)
        };
    }

    public Task<IReadOnlyList<AttendanceEmployee>> MatchListAsync(AttScope scope, CancellationToken ct = default) =>
        _sql.QueryAsync<AttendanceEmployee>(EmployeeProc, P("MATCH", scope), ct);

    public Task<IReadOnlyList<AttendanceAssignment>> AssignmentsAsync(AttScope scope, long? employeeId = null, CancellationToken ct = default)
    {
        var p = P("ASSIGNS", scope);
        p.Add("@Id", employeeId, DbType.Int64);
        return _sql.QueryAsync<AttendanceAssignment>(EmployeeProc, p, ct);
    }

    public async Task<SaveResult> SetEmployeesAsync(AttScope scope, IEnumerable<object> rows, long? userId, CancellationToken ct = default)
    {
        var p = P("SET", scope);
        p.Add("@Json", JsonSerializer.Serialize(rows, Json), DbType.String, size: -1);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(EmployeeProc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, 0);
    }

    public async Task<SaveResult> UnassignAsync(AttScope scope, long assignmentId, long? userId, CancellationToken ct = default)
    {
        var p = P("UNASSIGN", scope);
        p.Add("@Id", assignmentId, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(EmployeeProc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, assignmentId);
    }

    // ------------------------------------------------------------ imports

    public async Task<(SaveResult Result, IReadOnlyList<AttMonth> Months)> ImportAsync(AttScope scope, string fileName, string format, string? mapping,
        int rowCount, int skipped, IEnumerable<object> days, long? userId, CancellationToken ct = default)
    {
        var p = P("SAVE", scope);
        p.Add("@FileName", T(fileName, 260), DbType.String, size: 260);
        p.Add("@FileFormat", format == "PUNCH" ? "PUNCH" : "PAIRED", DbType.AnsiString, size: 10);
        p.Add("@MappingText", T(mapping, 1000), DbType.String, size: 1000);
        p.Add("@FileRowCount", rowCount, DbType.Int32);
        p.Add("@SkippedCount", skipped, DbType.Int32);
        p.Add("@Json", JsonSerializer.Serialize(days, Json), DbType.String, size: -1);
        p.Add("@UserId", userId, DbType.Int64);
        var months = await _sql.QueryAsync<AttMonth>(ImportProc, p, ct).ConfigureAwait(false);
        return (PayrollRunRepository.ReadResult(p, 0), months);
    }

    public async Task<PagedResult<AttendanceImport>> ImportsAsync(AttScope scope, int page, CancellationToken ct = default)
    {
        var p = P("LIST", scope);
        p.Add("@PageNumber", Math.Max(1, page), DbType.Int32);
        p.Add("@PageSize", 15, DbType.Int32);
        var rows = await _sql.QueryAsync<AttendanceImport>(ImportProc, p, ct).ConfigureAwait(false);
        return new PagedResult<AttendanceImport> { Items = rows, TotalCount = rows.Count == 0 ? 0 : rows[0].Total, PageNumber = Math.Max(1, page), PageSize = 15 };
    }

    public async Task<(SaveResult Result, IReadOnlyList<AttMonth> Months)> DeleteImportAsync(AttScope scope, long id, long? userId, CancellationToken ct = default)
    {
        var p = P("DELETE", scope);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        var months = await _sql.QueryAsync<AttMonth>(ImportProc, p, ct).ConfigureAwait(false);
        return (PayrollRunRepository.ReadResult(p, id), months);
    }

    // ------------------------------------------------------------ the calculation

    private DynamicParameters Ctx(string action, AttScope? scope, int company, DateTime month, long? employeeId)
    {
        var p = P(action, scope);
        p.Add("@FilterCompany", company, DbType.Int32);
        p.Add("@Month", MonthOf(month), DbType.Date);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        return p;
    }

    public Task<IReadOnlyList<AttDayInput>> MonthDaysAsync(AttScope scope, int company, DateTime month, long? employeeId, CancellationToken ct = default) =>
        _sql.QueryAsync<AttDayInput>(RecordProc, Ctx("CTX_RECORDS", scope, company, month, employeeId), ct);

    public Task<IReadOnlyList<AttEmployeeInput>> MonthEmployeesAsync(AttScope scope, int company, DateTime month, long? employeeId, CancellationToken ct = default) =>
        _sql.QueryAsync<AttEmployeeInput>(RecordProc, Ctx("CTX_EMP", scope, company, month, employeeId), ct);

    public Task<IReadOnlyList<AttLeaveInput>> MonthLeaveAsync(int company, DateTime month, CancellationToken ct = default) =>
        _sql.QueryAsync<AttLeaveInput>(RecordProc, Ctx("CTX_LEAVE", null, company, month, null), ct);

    public Task<IReadOnlyList<AttHolidayInput>> MonthHolidaysAsync(int company, DateTime month, CancellationToken ct = default) =>
        _sql.QueryAsync<AttHolidayInput>(RecordProc, Ctx("CTX_HOLIDAY", null, company, month, null), ct);

    public Task SaveMonthAsync(AttScope scope, int company, DateTime month, long? employeeId, IEnumerable<AttDayResult> days, long? userId,
                               CancellationToken ct = default)
    {
        var p = Ctx("SAVE_CALC", scope, company, month, employeeId);
        p.Add("@Json", JsonSerializer.Serialize(days.Select(d => new
        {
            d.RecordId, d.EmployeeId, WorkDate = d.WorkDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), d.PatternId, d.Status,
            d.WorkedMinutes, d.LateMinutes, d.ShortMinutes, d.OvertimeMinutes, d.DeductionAmount, d.OvertimeAmount,
            DeductionNote = d.DeductionNote is { Length: > 300 } n ? n[..300] : d.DeductionNote
        }), Json), DbType.String, size: -1);
        p.Add("@UserId", userId, DbType.Int64);
        return _sql.ExecuteAsync(RecordProc, p, ct);
    }

    // ------------------------------------------------------------ days

    public async Task<PagedResult<AttendanceRecord>> RecordsAsync(AttScope scope, AttRecordFilter f, CancellationToken ct = default)
    {
        var p = P("LIST", scope);
        p.Add("@FilterCompany", f.CompanyId, DbType.Int32);
        p.Add("@Month", MonthOf(f.Month), DbType.Date);
        p.Add("@EmployeeId", f.EmployeeId, DbType.Int64);
        p.Add("@StatusFilter", T(f.Status, 12), DbType.AnsiString, size: 12);
        p.Add("@Search", T(f.Search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, f.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(f.PageSize, 1, 500), DbType.Int32);
        var rows = await _sql.QueryAsync<AttendanceRecord>(RecordProc, p, ct).ConfigureAwait(false);
        return new PagedResult<AttendanceRecord>
        {
            Items = rows, TotalCount = rows.Count == 0 ? 0 : rows[0].Total, PageNumber = Math.Max(1, f.PageNumber), PageSize = Math.Clamp(f.PageSize, 1, 500)
        };
    }

    public async Task<AttendanceRecord?> RecordAsync(AttScope scope, long id, CancellationToken ct = default)
    {
        var p = P("GET", scope);
        p.Add("@Id", id, DbType.Int64);
        return (await _sql.QueryAsync<AttendanceRecord>(RecordProc, p, ct).ConfigureAwait(false)).FirstOrDefault();
    }

    public async Task<AttendanceKpis> KpisAsync(AttScope scope, int? company, DateTime month, long? employeeId, CancellationToken ct = default)
    {
        var p = P("KPIS", scope);
        p.Add("@FilterCompany", company, DbType.Int32);
        p.Add("@Month", MonthOf(month), DbType.Date);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        return await _sql.QuerySingleOrDefaultAsync<AttendanceKpis>(RecordProc, p, ct).ConfigureAwait(false) ?? new AttendanceKpis();
    }

    public async Task<IReadOnlyList<DateTime>> MonthsAsync(AttScope scope, int? company, CancellationToken ct = default)
    {
        var p = P("MONTHS", scope);
        p.Add("@FilterCompany", company, DbType.Int32);
        return await _sql.QueryAsync<DateTime>(RecordProc, p, ct).ConfigureAwait(false);
    }

    public async Task<(SaveResult Result, AttMonth? Month)> EditRecordAsync(AttScope scope, long id, DateTime? clockIn, DateTime? clockOut, bool excused,
                                                                          string? note, long? userId, CancellationToken ct = default)
    {
        var p = P("EDIT", scope);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@ClockIn", clockIn, DbType.DateTime2);
        p.Add("@ClockOut", clockOut, DbType.DateTime2);
        p.Add("@IsExcused", excused, DbType.Boolean);
        p.Add("@Note", T(note, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        var month = (await _sql.QueryAsync<AttMonth>(RecordProc, p, ct).ConfigureAwait(false)).FirstOrDefault();
        return (PayrollRunRepository.ReadResult(p, id), month);
    }

    public async Task<(SaveResult Result, AttMonth? Month)> AddRecordAsync(AttScope scope, long employeeId, DateTime date, DateTime? clockIn, DateTime? clockOut,
                                                                         bool excused, string? note, long? userId, CancellationToken ct = default)
    {
        var p = P("ADD", scope);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@Month", date.Date, DbType.Date);
        p.Add("@ClockIn", clockIn, DbType.DateTime2);
        p.Add("@ClockOut", clockOut, DbType.DateTime2);
        p.Add("@IsExcused", excused, DbType.Boolean);
        p.Add("@Note", T(note, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        var month = (await _sql.QueryAsync<AttMonth>(RecordProc, p, ct).ConfigureAwait(false)).FirstOrDefault();
        return (PayrollRunRepository.ReadResult(p, 0), month);
    }

    // ------------------------------------------------------------ the month

    private static DynamicParameters Sum(string action, AttScope scope, int company, DateTime month)
    {
        var p = P(action, scope);
        p.Add("@FilterCompany", company, DbType.Int32);
        p.Add("@Month", MonthOf(month), DbType.Date);
        return p;
    }

    public Task<IReadOnlyList<AttendanceSummaryRow>> SummaryAsync(AttScope scope, int company, DateTime month, CancellationToken ct = default) =>
        _sql.QueryAsync<AttendanceSummaryRow>(SummaryProc, Sum("LIST", scope, company, month), ct);

    public async Task<SaveResult> PostAsync(AttScope scope, int company, DateTime month, IEnumerable<object> rows, long? userId, CancellationToken ct = default)
    {
        var p = Sum("POST", scope, company, month);
        p.Add("@Json", JsonSerializer.Serialize(rows, Json), DbType.String, size: -1);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(SummaryProc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, 0);
    }

    public async Task<SaveResult> UnpostAsync(AttScope scope, int company, DateTime month, long? userId, CancellationToken ct = default)
    {
        var p = Sum("UNPOST", scope, company, month);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(SummaryProc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, 0);
    }
}
