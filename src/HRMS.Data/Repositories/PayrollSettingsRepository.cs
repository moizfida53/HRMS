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

// ===========================================================================
// Payroll Settings - Payroll Rules (statutory, db/29-30):
// usp_PifssRate_Manage, usp_IndemnityRuleSet_Manage, usp_OvertimeRate_Manage
// ===========================================================================

public interface IStatutoryRepository
{
    Task<PagedResult<PifssRate>> PifssListAsync(string? search, bool? isActive, bool inForceToday, int page, CancellationToken cancellationToken = default);
    Task<PifssRate?> PifssGetAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> PifssSaveAsync(PifssRate rate, long? userId, CancellationToken cancellationToken = default);

    Task<PagedResult<IndemnityRuleSet>> IndemnityListAsync(string? search, bool? isActive, int page, CancellationToken cancellationToken = default);
    /// <summary>The rule set with its slabs and factors.</summary>
    Task<IndemnityRuleSet?> IndemnityGetAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> IndemnitySaveAsync(IndemnityRuleSet ruleSet, long? userId, CancellationToken cancellationToken = default);

    Task<PagedResult<OvertimeRate>> OvertimeListAsync(int? companyId, string? companyIds, string? search, bool? isActive, int page,
                                                      CancellationToken cancellationToken = default);
    Task<OvertimeRate?> OvertimeGetAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> OvertimeSaveAsync(OvertimeRate rate, long? userId, CancellationToken cancellationToken = default);

    /// <summary>DELETE or TOGGLE of a row of "PIFSS", "INDEMNITY" or "OVERTIME".</summary>
    Task<SaveResult> ActionAsync(string table, string action, int id, long? userId, CancellationToken cancellationToken = default);
}

public sealed class StatutoryRepository : IStatutoryRepository
{
    private readonly ISqlExecutor _sql;

    public StatutoryRepository(ISqlExecutor sql) => _sql = sql;

    private static string Proc(string table) => table switch
    {
        "PIFSS" => StoredProcedure.PifssRateManage,
        "INDEMNITY" => StoredProcedure.IndemnityRuleSetManage,
        "OVERTIME" => StoredProcedure.OvertimeRateManage,
        _ => throw new ArgumentOutOfRangeException(nameof(table))
    };

    // ---------------------------------------------------------------- PIFSS
    public async Task<PagedResult<PifssRate>> PifssListAsync(string? search, bool? isActive, bool inForceToday, int page,
                                                             CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("LIST");
        p.Add("@Search", PayItemTypeRepository.Trim(search, 200), DbType.String, size: 200);
        p.Add("@IsActiveFilter", isActive, DbType.Boolean);
        p.Add("@AsOfDate", inForceToday ? DateTime.Today : null, DbType.Date);
        return await SettingsSql.PageAsync<PifssRate>(_sql, StoredProcedure.PifssRateManage, p, page, cancellationToken).ConfigureAwait(false);
    }

    public Task<PifssRate?> PifssGetAsync(int id, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<PifssRate>(StoredProcedure.PifssRateManage, p, cancellationToken);
    }

    public async Task<SaveResult> PifssSaveAsync(PifssRate r, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(r.PifssRateId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", r.PifssRateId > 0 ? r.PifssRateId : null, DbType.Int64);
        p.Add("@ContributionCode", PayItemTypeRepository.Trim(r.ContributionCode, 30)?.ToUpperInvariant(), DbType.String, size: 30);
        p.Add("@ContributionName", PayItemTypeRepository.Trim(r.ContributionName, 150), DbType.String, size: 150);
        p.Add("@ApplicableTo", r.ApplicableTo, DbType.AnsiString, size: 10);
        p.Add("@CalculationBasis", r.CalculationBasis, DbType.AnsiString, size: 10);
        p.Add("@EmployeeRate", r.EmployeeRate, DbType.Decimal, precision: 7, scale: 4);
        p.Add("@EmployerRate", r.EmployerRate, DbType.Decimal, precision: 7, scale: 4);
        p.Add("@GovernmentRate", r.GovernmentRate, DbType.Decimal, precision: 7, scale: 4);
        p.Add("@SalaryFloor", r.SalaryFloor, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@SalaryCeiling", r.SalaryCeiling, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@EffectiveFrom", r.EffectiveFrom, DbType.Date);
        p.Add("@EffectiveTo", r.EffectiveTo, DbType.Date);
        p.Add("@IsVerified", r.IsVerified, DbType.Boolean);
        p.Add("@Notes", PayItemTypeRepository.Trim(r.Notes, 500), DbType.String, size: 500);
        p.Add("@IsActive", r.IsActive, DbType.Boolean);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.PifssRateManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, r.PifssRateId);
    }

    // ------------------------------------------------------------ INDEMNITY
    public async Task<PagedResult<IndemnityRuleSet>> IndemnityListAsync(string? search, bool? isActive, int page, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("LIST");
        p.Add("@Search", PayItemTypeRepository.Trim(search, 200), DbType.String, size: 200);
        p.Add("@IsActiveFilter", isActive, DbType.Boolean);
        return await SettingsSql.PageAsync<IndemnityRuleSet>(_sql, StoredProcedure.IndemnityRuleSetManage, p, page, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IndemnityRuleSet?> IndemnityGetAsync(int id, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        var set = await _sql.QuerySingleOrDefaultAsync<IndemnityRuleSet>(StoredProcedure.IndemnityRuleSetManage, p, cancellationToken).ConfigureAwait(false);
        if (set is null) return null;

        var s = SettingsSql.Envelope("SLABS");
        s.Add("@Id", id, DbType.Int64);
        set.Slabs = (await _sql.QueryAsync<IndemnitySlab>(StoredProcedure.IndemnityRuleSetManage, s, cancellationToken).ConfigureAwait(false)).ToList();
        var f = SettingsSql.Envelope("FACTORS");
        f.Add("@Id", id, DbType.Int64);
        set.Factors = (await _sql.QueryAsync<IndemnityFactor>(StoredProcedure.IndemnityRuleSetManage, f, cancellationToken).ConfigureAwait(false)).ToList();
        return set;
    }

    public async Task<SaveResult> IndemnitySaveAsync(IndemnityRuleSet r, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(r.IndemnityRuleSetId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", r.IndemnityRuleSetId > 0 ? r.IndemnityRuleSetId : null, DbType.Int64);
        p.Add("@RuleSetCode", PayItemTypeRepository.Trim(r.RuleSetCode, 30)?.ToUpperInvariant(), DbType.String, size: 30);
        p.Add("@RuleSetName", PayItemTypeRepository.Trim(r.RuleSetName, 150), DbType.String, size: 150);
        p.Add("@DailyWageDivisor", r.DailyWageDivisor, DbType.Decimal, precision: 5, scale: 2);
        p.Add("@MaxIndemnityMonths", r.MaxIndemnityMonths, DbType.Decimal, precision: 6, scale: 2);
        p.Add("@MinServiceMonths", r.MinServiceMonths, DbType.Decimal, precision: 6, scale: 2);
        p.Add("@EffectiveFrom", r.EffectiveFrom, DbType.Date);
        p.Add("@EffectiveTo", r.EffectiveTo, DbType.Date);
        p.Add("@IsVerified", r.IsVerified, DbType.Boolean);
        p.Add("@Notes", PayItemTypeRepository.Trim(r.Notes, 1000), DbType.String, size: 1000);
        p.Add("@IsActive", r.IsActive, DbType.Boolean);
        // the procedure replaces the slabs and factors with these (PascalCase JSON, as it reads them)
        p.Add("@SlabsJson", System.Text.Json.JsonSerializer.Serialize(r.Slabs.Select((x, i) => new
        {
            x.FromYears, x.ToYears, x.EntitlementUnit, x.EntitlementValue, DisplayOrder = i + 1
        })), DbType.String, size: -1);
        p.Add("@FactorsJson", System.Text.Json.JsonSerializer.Serialize(r.Factors.Select(x => new
        {
            x.SeparationType, x.FromYears, x.ToYears, x.EntitlementPercent
        })), DbType.String, size: -1);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.IndemnityRuleSetManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, r.IndemnityRuleSetId);
    }

    // ------------------------------------------------------------- OVERTIME
    public async Task<PagedResult<OvertimeRate>> OvertimeListAsync(int? companyId, string? companyIds, string? search, bool? isActive, int page,
                                                                   CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("LIST");
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", PayItemTypeRepository.Trim(companyIds, 2000), DbType.String, size: 2000);
        p.Add("@Search", PayItemTypeRepository.Trim(search, 200), DbType.String, size: 200);
        p.Add("@IsActiveFilter", isActive, DbType.Boolean);
        return await SettingsSql.PageAsync<OvertimeRate>(_sql, StoredProcedure.OvertimeRateManage, p, page, cancellationToken).ConfigureAwait(false);
    }

    public Task<OvertimeRate?> OvertimeGetAsync(int id, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<OvertimeRate>(StoredProcedure.OvertimeRateManage, p, cancellationToken);
    }

    public async Task<SaveResult> OvertimeSaveAsync(OvertimeRate r, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(r.OvertimeRateId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", r.OvertimeRateId > 0 ? r.OvertimeRateId : null, DbType.Int64);
        p.Add("@CompanyId", r.CompanyId, DbType.Int32);
        p.Add("@OvertimeCode", r.OvertimeCode, DbType.AnsiString, size: 20);
        p.Add("@OvertimeName", PayItemTypeRepository.Trim(r.OvertimeName, 150), DbType.String, size: 150);
        p.Add("@Multiplier", r.Multiplier, DbType.Decimal, precision: 5, scale: 3);
        p.Add("@HourlyRateDivisorDays", r.HourlyRateDivisorDays, DbType.Decimal, precision: 5, scale: 2);
        p.Add("@HoursPerDay", r.HoursPerDay, DbType.Decimal, precision: 4, scale: 2);
        p.Add("@MaxHoursPerDay", r.MaxHoursPerDay, DbType.Decimal, precision: 4, scale: 2);
        p.Add("@MaxHoursPerYear", r.MaxHoursPerYear, DbType.Int32);
        p.Add("@EffectiveFrom", r.EffectiveFrom, DbType.Date);
        p.Add("@EffectiveTo", r.EffectiveTo, DbType.Date);
        p.Add("@IsVerified", r.IsVerified, DbType.Boolean);
        p.Add("@Notes", PayItemTypeRepository.Trim(r.Notes, 500), DbType.String, size: 500);
        p.Add("@IsActive", r.IsActive, DbType.Boolean);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.OvertimeRateManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, r.OvertimeRateId);
    }

    public async Task<SaveResult> ActionAsync(string table, string action, int id, long? userId, CancellationToken cancellationToken = default)
    {
        if (action is not ("DELETE" or "TOGGLE")) throw new ArgumentOutOfRangeException(nameof(action));
        var p = SettingsSql.Envelope(action);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(Proc(table), p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }
}

/// <summary>The envelope and paging shared by the db/30 master procedures (@Action VARCHAR(10), page size up to 200).</summary>
internal static class SettingsSql
{
    public const int PageSize = 50;

    public static DynamicParameters Envelope(string action)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        return p;
    }

    public static async Task<PagedResult<T>> PageAsync<T>(ISqlExecutor sql, string procedure, DynamicParameters p, int page,
                                                          CancellationToken cancellationToken)
    {
        page = Math.Max(1, page);
        p.Add("@PageNumber", page, DbType.Int32);
        p.Add("@PageSize", PageSize, DbType.Int32);
        var rows = await sql.QueryAsync<T>(procedure, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<T> { Items = rows, TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count, PageNumber = page, PageSize = PageSize };
    }
}

// ===========================================================================
// Payroll Settings - Banks & Accounts (db/29-30):
// usp_Bank_Manage, usp_CompanyBankAccount_Manage
// ===========================================================================

public interface IBankRepository
{
    Task<PagedResult<Bank>> BanksAsync(string? search, bool? isActive, int page, CancellationToken cancellationToken = default);
    Task<Bank?> BankAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveBankAsync(Bank bank, long? userId, CancellationToken cancellationToken = default);

    Task<PagedResult<CompanyBankAccount>> AccountsAsync(int? companyId, string? companyIds, string? search, bool? isActive, int page,
                                                        CancellationToken cancellationToken = default);
    Task<CompanyBankAccount?> AccountAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveAccountAsync(CompanyBankAccount account, long? userId, CancellationToken cancellationToken = default);

    /// <summary>DELETE or TOGGLE of a "BANK" or "ACCOUNT".</summary>
    Task<SaveResult> ActionAsync(string table, string action, int id, long? userId, CancellationToken cancellationToken = default);
}

public sealed class BankRepository : IBankRepository
{
    private readonly ISqlExecutor _sql;

    public BankRepository(ISqlExecutor sql) => _sql = sql;

    private static string T(string? v, int max) => PayItemTypeRepository.Trim(v, max)!;

    public async Task<PagedResult<Bank>> BanksAsync(string? search, bool? isActive, int page, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("LIST");
        p.Add("@Search", PayItemTypeRepository.Trim(search, 200), DbType.String, size: 200);
        p.Add("@IsActiveFilter", isActive, DbType.Boolean);
        return await SettingsSql.PageAsync<Bank>(_sql, StoredProcedure.BankManage, p, page, cancellationToken).ConfigureAwait(false);
    }

    public Task<Bank?> BankAsync(int id, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<Bank>(StoredProcedure.BankManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveBankAsync(Bank b, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(b.BankId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", b.BankId > 0 ? b.BankId : null, DbType.Int64);
        p.Add("@BankCode", T(b.BankCode, 20)?.ToUpperInvariant(), DbType.String, size: 20);
        p.Add("@BankName", T(b.BankName, 150), DbType.String, size: 150);
        p.Add("@ArabicName", PayItemTypeRepository.Trim(b.ArabicName, 150), DbType.String, size: 150);
        p.Add("@ShortName", PayItemTypeRepository.Trim(b.ShortName, 30), DbType.String, size: 30);
        p.Add("@SwiftCode", PayItemTypeRepository.Trim(b.SwiftCode, 11)?.ToUpperInvariant(), DbType.String, size: 11);
        p.Add("@IbanBankCode", PayItemTypeRepository.Trim(b.IbanBankCode, 10)?.ToUpperInvariant(), DbType.String, size: 10);
        p.Add("@WpsBankCode", PayItemTypeRepository.Trim(b.WpsBankCode, 20), DbType.String, size: 20);
        p.Add("@CountryId", b.CountryId, DbType.Int32);
        p.Add("@IsActive", b.IsActive, DbType.Boolean);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.BankManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, b.BankId);
    }

    public async Task<PagedResult<CompanyBankAccount>> AccountsAsync(int? companyId, string? companyIds, string? search, bool? isActive, int page,
                                                                     CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("LIST");
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@CompanyIds", PayItemTypeRepository.Trim(companyIds, 2000), DbType.String, size: 2000);
        p.Add("@Search", PayItemTypeRepository.Trim(search, 200), DbType.String, size: 200);
        p.Add("@IsActiveFilter", isActive, DbType.Boolean);
        return await SettingsSql.PageAsync<CompanyBankAccount>(_sql, StoredProcedure.CompanyBankAccountManage, p, page, cancellationToken).ConfigureAwait(false);
    }

    public Task<CompanyBankAccount?> AccountAsync(int id, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<CompanyBankAccount>(StoredProcedure.CompanyBankAccountManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveAccountAsync(CompanyBankAccount a, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(a.CompanyBankAccountId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", a.CompanyBankAccountId > 0 ? a.CompanyBankAccountId : null, DbType.Int64);
        p.Add("@CompanyId", a.CompanyId, DbType.Int32);
        p.Add("@BankId", a.BankId, DbType.Int32);
        p.Add("@AccountCode", T(a.AccountCode, 30)?.ToUpperInvariant(), DbType.String, size: 30);
        p.Add("@AccountTitle", T(a.AccountTitle, 150), DbType.String, size: 150);
        p.Add("@AccountNumber", PayItemTypeRepository.Trim(a.AccountNumber, 34), DbType.String, size: 34);
        p.Add("@Iban", PayItemTypeRepository.Trim(a.Iban, 50)?.ToUpperInvariant(), DbType.String, size: 50);
        p.Add("@CurrencyId", a.CurrencyId, DbType.Int32);
        p.Add("@BranchName", PayItemTypeRepository.Trim(a.BranchName, 150), DbType.String, size: 150);
        p.Add("@WpsEmployerCode", PayItemTypeRepository.Trim(a.WpsEmployerCode, 50), DbType.String, size: 50);
        p.Add("@PamFileNo", PayItemTypeRepository.Trim(a.PamFileNo, 50), DbType.String, size: 50);
        p.Add("@IsDefault", a.IsDefault, DbType.Boolean);
        p.Add("@IsActive", a.IsActive, DbType.Boolean);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.CompanyBankAccountManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, a.CompanyBankAccountId);
    }

    public async Task<SaveResult> ActionAsync(string table, string action, int id, long? userId, CancellationToken cancellationToken = default)
    {
        if (action is not ("DELETE" or "TOGGLE")) throw new ArgumentOutOfRangeException(nameof(action));
        var p = SettingsSql.Envelope(action);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(table == "BANK" ? StoredProcedure.BankManage : StoredProcedure.CompanyBankAccountManage, p, cancellationToken)
                  .ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }
}
