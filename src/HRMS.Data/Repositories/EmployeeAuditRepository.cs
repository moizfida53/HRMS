using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>The employee Audit Report: write one transaction, list them with filters (db/60).</summary>
public interface IEmployeeAuditRepository
{
    Task<SaveResult> AddAsync(EmployeeAuditInput input, long? userId, CancellationToken cancellationToken = default);
    Task<PagedResult<EmployeeAuditEntry>> ListAsync(EmployeeAuditFilter filter, CancellationToken cancellationToken = default);
}

public sealed class EmployeeAuditRepository : IEmployeeAuditRepository
{
    private readonly ISqlExecutor _sql;

    public EmployeeAuditRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<SaveResult> AddAsync(EmployeeAuditInput input, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("ADD");
        p.Add("@Id", input.EmployeeId, DbType.Int64);
        p.Add("@TransactionType", input.TransactionType, DbType.AnsiString, size: 400);
        p.Add("@FieldName", Cut(input.FieldName, 100), DbType.String, size: 100);
        p.Add("@OldValue", Cut(input.OldValue, 500), DbType.String, size: 500);
        p.Add("@NewValue", Cut(input.NewValue, 500), DbType.String, size: 500);
        p.Add("@Reference", Cut(input.Reference, 100), DbType.String, size: 100);
        p.Add("@Remarks", Cut(input.Remarks, 1000), DbType.String, size: 1000);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.EmployeeAuditManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, 0);
    }

    public async Task<PagedResult<EmployeeAuditEntry>> ListAsync(EmployeeAuditFilter filter, CancellationToken cancellationToken = default)
    {
        var pageSize = Math.Clamp(filter.PageSize, 1, 20000);
        var p = PayrollRunRepository.Envelope("LIST");
        p.Add("@CompanyId", filter.CompanyId, DbType.Int32);
        p.Add("@CompanyIds", Cut(filter.CompanyIds, 2000), DbType.String, size: 2000);
        p.Add("@EmployeeId", filter.EmployeeId, DbType.Int64);
        p.Add("@TransactionType", filter.Types.Count == 0 ? null : string.Join(',', filter.Types), DbType.AnsiString, size: 400);
        p.Add("@DateFrom", filter.DateFromUtc, DbType.DateTime2);
        p.Add("@DateTo", filter.DateToUtc, DbType.DateTime2);
        p.Add("@Search", Cut(filter.Search, 200), DbType.String, size: 200);
        p.Add("@SortColumn", Cut(filter.Sort, 30), DbType.AnsiString, size: 30);
        p.Add("@SortDirection", Cut(filter.Direction, 4), DbType.AnsiString, size: 4);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", pageSize, DbType.Int32);

        var rows = await _sql.QueryAsync<EmployeeAuditEntry>(StoredProcedure.EmployeeAuditManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<EmployeeAuditEntry>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, filter.PageNumber),
            PageSize = pageSize
        };
    }

    private static string? Cut(string? value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length <= max ? value : value[..max];
    }
}

/// <summary>Each employee's payroll calendar (db/60): read, assign / change (logged), counts per calendar.</summary>
public interface IEmployeePayrollCalendarRepository
{
    Task<EmployeePayrollCalendar?> GetAsync(long employeeId, CancellationToken cancellationToken = default);
    Task<SaveResult> SetAsync(long employeeId, int calendarId, string? remarks, long? userId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<CalendarEmployeeCount>> CountsAsync(int companyId, CancellationToken cancellationToken = default);
}

public sealed class EmployeePayrollCalendarRepository : IEmployeePayrollCalendarRepository
{
    private readonly ISqlExecutor _sql;

    public EmployeePayrollCalendarRepository(ISqlExecutor sql) => _sql = sql;

    public Task<EmployeePayrollCalendar?> GetAsync(long employeeId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("GET");
        p.Add("@Id", employeeId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<EmployeePayrollCalendar>(StoredProcedure.EmployeePayrollCalendarManage, p, cancellationToken);
    }

    public async Task<SaveResult> SetAsync(long employeeId, int calendarId, string? remarks, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("SET");
        p.Add("@Id", employeeId, DbType.Int64);
        p.Add("@PayrollCalendarId", calendarId, DbType.Int32);
        p.Add("@Remarks", string.IsNullOrWhiteSpace(remarks) ? null : remarks.Trim()[..Math.Min(remarks.Trim().Length, 1000)], DbType.String, size: 1000);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.EmployeePayrollCalendarManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, employeeId);
    }

    public Task<IReadOnlyList<CalendarEmployeeCount>> CountsAsync(int companyId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("COUNTS");
        p.Add("@CompanyId", companyId, DbType.Int32);
        return _sql.QueryAsync<CalendarEmployeeCount>(StoredProcedure.EmployeePayrollCalendarManage, p, cancellationToken);
    }
}

/// <summary>An employee's own annual leave (Employment Terms, db/82): blank = the Annual Leave type's days.</summary>
public sealed class EmployeeLeaveTerms
{
    public long EmployeeId { get; init; }
    public decimal? AnnualLeaveDays { get; init; }
    /// <summary>Days per year of the company's Annual Leave type (Leave > Settings) - used when the employee has none.</summary>
    public decimal? DefaultAnnualLeaveDays { get; init; }
}

public interface IEmployeeLeaveTermsRepository
{
    Task<EmployeeLeaveTerms?> GetAsync(long employeeId, CancellationToken cancellationToken = default);
    Task<SaveResult> SetAsync(long employeeId, decimal? annualLeaveDays, long? userId, CancellationToken cancellationToken = default);
}

public sealed class EmployeeLeaveTermsRepository : IEmployeeLeaveTermsRepository
{
    private readonly ISqlExecutor _sql;

    public EmployeeLeaveTermsRepository(ISqlExecutor sql) => _sql = sql;

    public Task<EmployeeLeaveTerms?> GetAsync(long employeeId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("GET");
        p.Add("@Id", employeeId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<EmployeeLeaveTerms>(StoredProcedure.EmployeeLeaveTermsManage, p, cancellationToken);
    }

    public async Task<SaveResult> SetAsync(long employeeId, decimal? annualLeaveDays, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("SET");
        p.Add("@Id", employeeId, DbType.Int64);
        p.Add("@AnnualLeaveDays", annualLeaveDays, DbType.Decimal, precision: 6, scale: 2);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.EmployeeLeaveTermsManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, employeeId);
    }
}
