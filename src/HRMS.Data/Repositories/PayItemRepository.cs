using System.Data;
using System.Text.Json;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Pay Items (db/37-38) - salary, earnings, deductions, loans as line items
// ===========================================================================

public sealed class PayItemFilter
{
    /// <summary>The user's own company (company users); null for group users.</summary>
    public int? CompanyId { get; set; }
    /// <summary>The company filter of the top bar (CSV).</summary>
    public string? CompanyIds { get; set; }
    public long? EmployeeId { get; set; }
    public string? ItemClass { get; set; }
    /// <summary>OPEN (active + pending), ACTIVE, PENDING, ENDED or ALL.</summary>
    public string? Status { get; set; }
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 25;
}

public interface IPayItemRepository
{
    Task<PagedResult<PayItem>> ListAsync(PayItemFilter filter, CancellationToken cancellationToken = default);
    Task<PayItem?> GetAsync(long id, int? companyId, CancellationToken cancellationToken = default);
    Task<PayItemSummary?> SummaryAsync(int? companyId, string? companyIds, DateTime month, CancellationToken cancellationToken = default);
    Task<PayItemEmployeeSummary?> EmployeeSummaryAsync(long employeeId, int? companyId, DateTime month, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PayItemType>> TypesAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PayItemEmployeeOption>> EmployeesAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PayItemHistoryEntry>> HistoryAsync(long id, int? companyId, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveAsync(PayItemInput input, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> ActionAsync(string action, long id, int? companyId, string? companyIds, long? userId, string? comment = null,
                                 DateTime? endMonth = null, bool allowSelfApproval = false, int? expectedLevel = null,
                                 CancellationToken cancellationToken = default);
    Task<PayItemImportResult> ImportAsync(IReadOnlyList<PayItemImportRow> rows, int? companyId, string? companyIds, long? userId,
                                          CancellationToken cancellationToken = default);
}

public sealed class PayItemRepository : IPayItemRepository
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private readonly ISqlExecutor _sql;

    public PayItemRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<PagedResult<PayItem>> ListAsync(PayItemFilter filter, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("LIST");
        Scope(p, filter.CompanyId, filter.CompanyIds);
        p.Add("@EmployeeId", filter.EmployeeId, DbType.Int64);
        p.Add("@ItemClass", Trim(filter.ItemClass, 10), DbType.AnsiString, size: 10);
        p.Add("@StatusFilter", Trim(filter.Status, 10), DbType.AnsiString, size: 10);
        p.Add("@Search", Trim(filter.Search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(filter.PageSize, 1, 10000), DbType.Int32);

        var rows = await _sql.QueryAsync<PayItem>(StoredProcedure.PayItemManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<PayItem>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, filter.PageNumber),
            PageSize = Math.Clamp(filter.PageSize, 1, 10000)
        };
    }

    public Task<PayItem?> GetAsync(long id, int? companyId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        p.Add("@CompanyId", companyId, DbType.Int32);
        return _sql.QuerySingleOrDefaultAsync<PayItem>(StoredProcedure.PayItemManage, p, cancellationToken);
    }

    public Task<PayItemSummary?> SummaryAsync(int? companyId, string? companyIds, DateTime month, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("SUMMARY");
        Scope(p, companyId, companyIds);
        p.Add("@Month", month, DbType.Date);
        return _sql.QuerySingleOrDefaultAsync<PayItemSummary>(StoredProcedure.PayItemManage, p, cancellationToken);
    }

    public Task<PayItemEmployeeSummary?> EmployeeSummaryAsync(long employeeId, int? companyId, DateTime month, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("EMP_SUMMARY");
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@Month", month, DbType.Date);
        return _sql.QuerySingleOrDefaultAsync<PayItemEmployeeSummary>(StoredProcedure.PayItemManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<PayItemType>> TypesAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("TYPES");
        Scope(p, companyId, companyIds);
        return _sql.QueryAsync<PayItemType>(StoredProcedure.PayItemManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<PayItemEmployeeOption>> EmployeesAsync(int? companyId, string? companyIds, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("EMPLOYEES");
        Scope(p, companyId, companyIds);
        return _sql.QueryAsync<PayItemEmployeeOption>(StoredProcedure.PayItemManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<PayItemHistoryEntry>> HistoryAsync(long id, int? companyId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("HISTORY");
        p.Add("@Id", id, DbType.Int64);
        p.Add("@CompanyId", companyId, DbType.Int32);
        return _sql.QueryAsync<PayItemHistoryEntry>(StoredProcedure.PayItemManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveAsync(PayItemInput input, int? companyId, string? companyIds, long? userId, CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope("SAVE");
        Scope(p, companyId, companyIds);
        p.Add("@Id", input.EmployeePayItemId, DbType.Int64);
        p.Add("@EmployeeId", input.EmployeeId, DbType.Int64);
        p.Add("@PayComponentId", input.PayComponentId, DbType.Int32);
        p.Add("@Amount", input.Amount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@AppliesMode", Trim(input.AppliesMode, 10), DbType.AnsiString, size: 10);
        p.Add("@StartMonth", input.StartMonth, DbType.Date);
        p.Add("@EndMonth", input.EndMonth, DbType.Date);
        p.Add("@InstalmentCount", input.InstalmentCount is { } n ? (short)Math.Clamp(n, short.MinValue, short.MaxValue) : null, DbType.Int16);
        p.Add("@TotalAmount", input.TotalAmount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@Comment", Trim(input.Comment, 500), DbType.String, size: 500);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayItemManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, input.EmployeePayItemId);
    }

    public async Task<SaveResult> ActionAsync(string action, long id, int? companyId, string? companyIds, long? userId, string? comment = null,
                                              DateTime? endMonth = null, bool allowSelfApproval = false, int? expectedLevel = null,
                                              CancellationToken cancellationToken = default)
    {
        var p = PayrollRunRepository.Envelope(action);
        Scope(p, companyId, companyIds);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Comment", Trim(comment, 500), DbType.String, size: 500);
        p.Add("@EndMonth", endMonth, DbType.Date);
        p.Add("@AllowSelfApproval", allowSelfApproval, DbType.Boolean);
        p.Add("@ExpectedLevel", expectedLevel is { } lv ? (byte)lv : null, DbType.Byte);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayItemManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    public async Task<PayItemImportResult> ImportAsync(IReadOnlyList<PayItemImportRow> rows, int? companyId, string? companyIds, long? userId,
                                                       CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@Json", JsonSerializer.Serialize(rows, Json), DbType.String, size: -1);
        Scope(p, companyId, companyIds);
        p.Add("@UserId", userId, DbType.Int64);
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);

        var errors = await _sql.QueryAsync<PayItemImportError>(StoredProcedure.PayItemImport, p, cancellationToken).ConfigureAwait(false);
        var code = p.Get<string?>("@ResultCode") ?? ResultCode.Success;
        return new PayItemImportResult
        {
            Success = string.Equals(code, ResultCode.Success, StringComparison.Ordinal),
            ErrorCode = code,
            Imported = p.Get<int?>("@TotalCount") ?? 0,
            Message = p.Get<string?>("@ResultMessage"),
            Errors = errors
        };
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
