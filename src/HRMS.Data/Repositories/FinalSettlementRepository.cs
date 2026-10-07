using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Final Settlement (db/39-40) - end-of-service settlements and leave encashment
// ===========================================================================

public interface IFinalSettlementRepository
{
    Task<PagedResult<FinalSettlementRow>> ListAsync(FinalSettlementFilter filter, CancellationToken cancellationToken = default);
    Task<FinalSettlementSummary?> SummaryAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<FinalSettlement?> GetAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<FinalSettlementLine>> LinesAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<FinalSettlementHistoryEntry>> HistoryAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<SettlementEmployeeOption>> EmployeesAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<SettlementDefaults?> DefaultsAsync(long employeeId, DateTime? lastWorkingDay, int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveAsync(FinalSettlementInput input, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> AddLineAsync(long id, string? section, string? description, decimal? amount, int? companyId, string? companyIds, long? userId,
                                  CancellationToken cancellationToken = default);

    /// <summary>RECALC, REMOVE_LINE, TOGGLE_LINE, SUBMIT, APPROVE, RETURN, REJECT, PAY, CANCEL.</summary>
    Task<SaveResult> ActionAsync(string action, long id, int? companyId, string? companyIds, long? userId, SettlementActionArgs? args = null,
                                 CancellationToken cancellationToken = default);
}

/// <summary>The optional values of a workflow action.</summary>
public sealed class SettlementActionArgs
{
    public long? LineId { get; init; }
    public string? Comment { get; init; }
    public bool AckUnverified { get; init; }
    public bool AllowSelfApproval { get; init; }
    public int? ExpectedLevel { get; init; }
    public DateTime? PaidDate { get; init; }
    public string? PaymentMethod { get; init; }
    public string? PaymentRef { get; init; }
}

public sealed class FinalSettlementRepository : IFinalSettlementRepository
{
    private readonly ISqlExecutor _sql;

    public FinalSettlementRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<PagedResult<FinalSettlementRow>> ListAsync(FinalSettlementFilter filter, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("LIST");
        Scope(p, filter.CompanyId, filter.CompanyIds);
        p.Add("@EmployeeId", filter.EmployeeId, DbType.Int64);
        p.Add("@TypeFilter", Trim(filter.Type, 20), DbType.AnsiString, size: 20);
        p.Add("@StatusFilter", Trim(filter.Status, 10), DbType.AnsiString, size: 10);
        p.Add("@Search", Trim(filter.Search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(filter.PageSize, 1, 10000), DbType.Int32);

        var rows = await _sql.QueryAsync<FinalSettlementRow>(StoredProcedure.FinalSettlementManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<FinalSettlementRow>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, filter.PageNumber),
            PageSize = Math.Clamp(filter.PageSize, 1, 10000)
        };
    }

    public Task<FinalSettlementSummary?> SummaryAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("SUMMARY");
        Scope(p, companyId, companyIds);
        return _sql.QuerySingleOrDefaultAsync<FinalSettlementSummary>(StoredProcedure.FinalSettlementManage, p, cancellationToken);
    }

    public Task<FinalSettlement?> GetAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("GET");
        Scope(p, companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<FinalSettlement>(StoredProcedure.FinalSettlementManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<FinalSettlementLine>> LinesAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("LINES");
        Scope(p, companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QueryAsync<FinalSettlementLine>(StoredProcedure.FinalSettlementManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<FinalSettlementHistoryEntry>> HistoryAsync(long id, int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("HISTORY");
        Scope(p, companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QueryAsync<FinalSettlementHistoryEntry>(StoredProcedure.FinalSettlementManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<SettlementEmployeeOption>> EmployeesAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("EMPLOYEES");
        Scope(p, companyId, companyIds);
        return _sql.QueryAsync<SettlementEmployeeOption>(StoredProcedure.FinalSettlementManage, p, cancellationToken);
    }

    public Task<SettlementDefaults?> DefaultsAsync(long employeeId, DateTime? lastWorkingDay, int? companyId, string? companyIds,
                                                   CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("DEFAULTS");
        Scope(p, companyId, companyIds);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@LastWorkingDay", lastWorkingDay, DbType.Date);
        return _sql.QuerySingleOrDefaultAsync<SettlementDefaults>(StoredProcedure.FinalSettlementManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveAsync(FinalSettlementInput input, int? companyId, string? companyIds, long? userId,
                                            CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("SAVE");
        Scope(p, companyId, companyIds);
        p.Add("@Id", input.FinalSettlementId, DbType.Int64);
        p.Add("@EmployeeId", input.EmployeeId, DbType.Int64);
        p.Add("@SettlementType", Trim(input.SettlementType, 20), DbType.AnsiString, size: 20);
        p.Add("@LastWorkingDay", input.LastWorkingDay, DbType.Date);
        p.Add("@NoticeDate", input.NoticeDate, DbType.Date);
        p.Add("@Reason", Trim(input.Reason, 500), DbType.String, size: 500);
        p.Add("@SalaryFrom", input.SalaryFrom, DbType.Date);
        p.Add("@LeaveBalanceDays", input.LeaveBalanceDays, DbType.Decimal, precision: 7, scale: 2);
        p.Add("@EncashDays", input.EncashDays, DbType.Decimal, precision: 7, scale: 2);
        p.Add("@PayMonth", input.PayMonth, DbType.Date);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.FinalSettlementManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, input.FinalSettlementId);
    }

    public async Task<SaveResult> AddLineAsync(long id, string? section, string? description, decimal? amount, int? companyId, string? companyIds,
                                               long? userId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("ADD_LINE");
        Scope(p, companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Section", Trim(section, 10), DbType.AnsiString, size: 10);
        p.Add("@Description", Trim(description, 300), DbType.String, size: 300);
        p.Add("@Amount", amount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.FinalSettlementManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    public async Task<SaveResult> ActionAsync(string action, long id, int? companyId, string? companyIds, long? userId, SettlementActionArgs? args = null,
                                              CancellationToken cancellationToken = default)
    {
        args ??= new SettlementActionArgs();
        var p = PayrollRunRepository.Envelope(action);
        Scope(p, companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@LineId", args.LineId, DbType.Int64);
        p.Add("@Comment", Trim(args.Comment, 500), DbType.String, size: 500);
        p.Add("@AckUnverified", args.AckUnverified, DbType.Boolean);
        p.Add("@AllowSelfApproval", args.AllowSelfApproval, DbType.Boolean);
        p.Add("@ExpectedLevel", args.ExpectedLevel is { } lv ? (byte)lv : null, DbType.Byte);
        p.Add("@PaidDate", args.PaidDate, DbType.Date);
        p.Add("@PaymentMethod", Trim(args.PaymentMethod, 10), DbType.AnsiString, size: 10);
        p.Add("@PaymentRef", Trim(args.PaymentRef, 100), DbType.String, size: 100);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.FinalSettlementManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    private static void Scope(DynamicParameters p, int? companyId, string? companyIds)
    {
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(companyIds, 2000), DbType.String, size: 2000);
    }

    private static string? Trim(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length > maxLength ? value[..maxLength] : value;
    }
}
