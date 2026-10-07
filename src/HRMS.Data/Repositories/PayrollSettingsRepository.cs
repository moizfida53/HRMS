using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Payroll Settings - Pay Item Types (Payroll.usp_PayComponent_Manage, db/30)
// ===========================================================================

public interface IPayItemTypeRepository
{
    Task<PagedResult<PayItemTypeSetting>> ListAsync(PayItemTypeFilter filter, CancellationToken cancellationToken = default);
    Task<PayItemTypeSetting?> GetAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveAsync(PayItemTypeSetting item, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> DeleteAsync(int id, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> ToggleAsync(int id, long? userId, CancellationToken cancellationToken = default);

    /// <summary>Adds the standard types (Basic Salary, PIFSS, Loan, ...) a company is missing.</summary>
    Task<SaveResult> SeedAsync(int companyId, long? userId, CancellationToken cancellationToken = default);
}

public sealed class PayItemTypeRepository : IPayItemTypeRepository
{
    private readonly ISqlExecutor _sql;

    public PayItemTypeRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<PagedResult<PayItemTypeSetting>> ListAsync(PayItemTypeFilter filter, CancellationToken cancellationToken = default)
    {
        var p = Envelope("LIST");
        p.Add("@CompanyId", filter.CompanyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(filter.CompanyIds, 2000), DbType.String, size: 2000);
        p.Add("@Search", Trim(filter.Search, 200), DbType.String, size: 200);
        p.Add("@ComponentTypeFilter", filter.ComponentType, DbType.AnsiString, size: 10);
        p.Add("@IsActiveFilter", filter.IsActive, DbType.Boolean);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(filter.PageSize, 1, 200), DbType.Int32);
        p.Add("@SortColumn", "DisplayOrder", DbType.AnsiString, size: 50);

        var rows = await _sql.QueryAsync<PayItemTypeSetting>(StoredProcedure.PayComponentManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<PayItemTypeSetting>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, filter.PageNumber),
            PageSize = Math.Clamp(filter.PageSize, 1, 200)
        };
    }

    public Task<PayItemTypeSetting?> GetAsync(int id, CancellationToken cancellationToken = default)
    {
        var p = Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<PayItemTypeSetting>(StoredProcedure.PayComponentManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveAsync(PayItemTypeSetting item, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope(item.PayComponentId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", item.PayComponentId > 0 ? item.PayComponentId : null, DbType.Int64);
        p.Add("@CompanyId", item.CompanyId, DbType.Int32);
        p.Add("@ComponentCode", Trim(item.ComponentCode, 30)?.ToUpperInvariant(), DbType.String, size: 30);
        p.Add("@ComponentName", Trim(item.ComponentName, 150), DbType.String, size: 150);
        p.Add("@ArabicName", Trim(item.ArabicName, 150), DbType.String, size: 150);
        p.Add("@PayslipLabel", Trim(item.PayslipLabel, 100), DbType.String, size: 100);
        p.Add("@ComponentType", item.ComponentType, DbType.AnsiString, size: 10);
        p.Add("@ValueType", item.ValueType, DbType.AnsiString, size: 10);
        p.Add("@CalculationMethod", item.CalculationMethod, DbType.AnsiString, size: 12);
        p.Add("@CalculationBase", Trim(item.CalculationBase, 15), DbType.AnsiString, size: 15);
        p.Add("@DefaultAmount", item.DefaultAmount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@DefaultPercentage", item.DefaultPercentage, DbType.Decimal, precision: 7, scale: 4);
        p.Add("@Formula", Trim(item.Formula, 1000), DbType.String, size: 1000);
        p.Add("@MinAmount", item.MinAmount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@MaxAmount", item.MaxAmount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@IsTaxable", item.IsTaxable, DbType.Boolean);
        p.Add("@IsPifssApplicable", item.IsPifssApplicable, DbType.Boolean);
        p.Add("@IsIndemnityApplicable", item.IsIndemnityApplicable, DbType.Boolean);
        p.Add("@IsOvertimeApplicable", item.IsOvertimeApplicable, DbType.Boolean);
        p.Add("@IsLeaveSalaryApplicable", item.IsLeaveSalaryApplicable, DbType.Boolean);
        p.Add("@IsRecurring", item.IsRecurring, DbType.Boolean);
        p.Add("@IsProrated", item.IsProrated, DbType.Boolean);
        p.Add("@ShowOnPayslip", item.ShowOnPayslip, DbType.Boolean);
        p.Add("@GLAccountCode", Trim(item.GLAccountCode, 50), DbType.String, size: 50);
        p.Add("@GLAccountName", Trim(item.GLAccountName, 150), DbType.String, size: 150);
        p.Add("@CostCenterId", item.CostCenterId, DbType.Int32);
        p.Add("@DisplayOrder", item.DisplayOrder, DbType.Int16);
        p.Add("@Description", Trim(item.Description, 500), DbType.String, size: 500);
        p.Add("@IsActive", item.IsActive, DbType.Boolean);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayComponentManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, item.PayComponentId);
    }

    public Task<SaveResult> DeleteAsync(int id, long? userId, CancellationToken cancellationToken = default) => Simple("DELETE", id, userId, cancellationToken);

    public Task<SaveResult> ToggleAsync(int id, long? userId, CancellationToken cancellationToken = default) => Simple("TOGGLE", id, userId, cancellationToken);

    public async Task<SaveResult> SeedAsync(int companyId, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Envelope("SEED");
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayComponentManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, companyId);
    }

    private async Task<SaveResult> Simple(string action, int id, long? userId, CancellationToken cancellationToken)
    {
        var p = Envelope(action);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PayComponentManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    /// <summary>usp_PayComponent_Manage takes @Action as VARCHAR(10).</summary>
    private static DynamicParameters Envelope(string action)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        return p;
    }

    internal static string? Trim(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length > maxLength ? value[..maxLength] : value;
    }
}
