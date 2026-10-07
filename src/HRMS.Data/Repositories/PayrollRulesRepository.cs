using System.Data;
using System.Text.Json;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Payroll Settings - the rule screens (db/47-48): usp_DeductionPolicy_Manage,
// usp_ProrationRule_Manage, usp_ApprovalProcess_Manage,
// usp_BankFileFormat_Manage, usp_GLMapping_Manage
// ===========================================================================

/// <summary>The list filter shared by the rule screens.</summary>
public sealed class RuleListFilter
{
    public int? CompanyId { get; init; }
    public string? CompanyIds { get; init; }
    public string? Search { get; init; }
    public bool? IsActive { get; init; }
    /// <summary>Approval: the process code. GL mapping: EARNING / DEDUCTION.</summary>
    public string? Kind { get; init; }
    public int Page { get; init; } = 1;
}

public interface IPayrollRulesRepository
{
    Task<PagedResult<DeductionPolicy>> DeductionPoliciesAsync(RuleListFilter filter, CancellationToken cancellationToken = default);
    /// <summary>The policy with its priorities.</summary>
    Task<DeductionPolicy?> DeductionPolicyAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveDeductionPolicyAsync(DeductionPolicy policy, long? userId, CancellationToken cancellationToken = default);
    /// <summary>The active calendars of a company (plus <paramref name="keepId"/>).</summary>
    Task<IReadOnlyList<LookupItem>> CalendarsAsync(int companyId, int? keepId, CancellationToken cancellationToken = default);

    Task<PagedResult<ProrationRule>> ProrationRulesAsync(RuleListFilter filter, CancellationToken cancellationToken = default);
    Task<ProrationRule?> ProrationRuleAsync(int payrollCalendarId, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveProrationRuleAsync(ProrationRule rule, long? userId, CancellationToken cancellationToken = default);

    Task<PagedResult<ApprovalProcess>> ApprovalProcessesAsync(RuleListFilter filter, CancellationToken cancellationToken = default);
    Task<ApprovalProcess?> ApprovalProcessAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveApprovalProcessAsync(ApprovalProcess process, long? userId, CancellationToken cancellationToken = default);
    /// <summary>The active roles of a company plus the global ones.</summary>
    Task<IReadOnlyList<LookupItem>> RolesAsync(int? companyId, CancellationToken cancellationToken = default);
    /// <summary>The active users of a company plus those of no company.</summary>
    Task<IReadOnlyList<LookupItem>> UsersAsync(int? companyId, CancellationToken cancellationToken = default);

    Task<PagedResult<BankFileFormat>> BankFileFormatsAsync(RuleListFilter filter, CancellationToken cancellationToken = default);
    /// <summary>The format with its fields.</summary>
    Task<BankFileFormat?> BankFileFormatAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveBankFileFormatAsync(BankFileFormat format, long? userId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<LookupItem>> FormatBanksAsync(int? keepId, CancellationToken cancellationToken = default);

    Task<PagedResult<GLMapping>> GLMappingsAsync(RuleListFilter filter, CancellationToken cancellationToken = default);
    Task<GLMapping?> GLMappingAsync(int id, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveGLMappingAsync(GLMapping mapping, long? userId, CancellationToken cancellationToken = default);
    /// <summary>The pay item types of a company (plus <paramref name="keepId"/>).</summary>
    Task<IReadOnlyList<LookupItem>> ComponentsAsync(int companyId, int? keepId, CancellationToken cancellationToken = default);

    /// <summary>DELETE or TOGGLE of a "DEDUCTION", "APPROVAL", "FORMAT" or "GL" row.</summary>
    Task<SaveResult> ActionAsync(string table, string action, int id, long? userId, CancellationToken cancellationToken = default);
}

public sealed class PayrollRulesRepository : IPayrollRulesRepository
{
    private readonly ISqlExecutor _sql;

    public PayrollRulesRepository(ISqlExecutor sql) => _sql = sql;

    private static string? T(string? value, int max) => PayItemTypeRepository.Trim(value, max);

    private static string Proc(string table) => table switch
    {
        "DEDUCTION" => StoredProcedure.DeductionPolicyManage,
        "APPROVAL" => StoredProcedure.ApprovalProcessManage,
        "FORMAT" => StoredProcedure.BankFileFormatManage,
        "GL" => StoredProcedure.GLMappingManage,
        _ => throw new ArgumentOutOfRangeException(nameof(table))
    };

    private static DynamicParameters ListParams(RuleListFilter f)
    {
        var p = SettingsSql.Envelope("LIST");
        p.Add("@CompanyId", f.CompanyId, DbType.Int32);
        p.Add("@CompanyIds", T(f.CompanyIds, 2000), DbType.String, size: 2000);
        p.Add("@Search", T(f.Search, 200), DbType.String, size: 200);
        p.Add("@IsActiveFilter", f.IsActive, DbType.Boolean);
        return p;
    }

    private Task<T?> GetAsync<T>(string proc, int id, CancellationToken ct)
    {
        var p = SettingsSql.Envelope("GET");
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<T>(proc, p, ct);
    }

    private async Task<SaveResult> RunAsync(string proc, DynamicParameters p, long? userId, int id, CancellationToken ct)
    {
        p.Add("@UserId", userId, DbType.Int64);
        await _sql.ExecuteAsync(proc, p, ct).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, id);
    }

    private Task<IReadOnlyList<LookupItem>> LookupAsync(string proc, string action, Action<DynamicParameters> fill, CancellationToken ct)
    {
        var p = SettingsSql.Envelope(action);
        fill(p);
        return _sql.QueryAsync<LookupItem>(proc, p, ct);
    }

    // ------------------------------------------------------- deduction rules
    public Task<PagedResult<DeductionPolicy>> DeductionPoliciesAsync(RuleListFilter filter, CancellationToken cancellationToken = default) =>
        SettingsSql.PageAsync<DeductionPolicy>(_sql, StoredProcedure.DeductionPolicyManage, ListParams(filter), filter.Page, cancellationToken);

    public async Task<DeductionPolicy?> DeductionPolicyAsync(int id, CancellationToken cancellationToken = default)
    {
        var policy = await GetAsync<DeductionPolicy>(StoredProcedure.DeductionPolicyManage, id, cancellationToken).ConfigureAwait(false);
        if (policy is null) return null;
        var p = SettingsSql.Envelope("LINES");
        p.Add("@Id", id, DbType.Int64);
        policy.Priorities = (await _sql.QueryAsync<DeductionPriority>(StoredProcedure.DeductionPolicyManage, p, cancellationToken).ConfigureAwait(false)).ToList();
        return policy;
    }

    public Task<SaveResult> SaveDeductionPolicyAsync(DeductionPolicy d, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(d.DeductionPolicyId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", d.DeductionPolicyId > 0 ? d.DeductionPolicyId : null, DbType.Int64);
        p.Add("@CompanyId", d.CompanyId, DbType.Int32);
        p.Add("@PayrollCalendarId", d.PayrollCalendarId, DbType.Int32);
        p.Add("@MaxDeductionPercent", d.MaxDeductionPercent, DbType.Decimal, precision: 5, scale: 2);
        p.Add("@WhenExceeded", d.WhenExceeded, DbType.AnsiString, size: 10);
        p.Add("@Notes", T(d.Notes, 500), DbType.String, size: 500);
        p.Add("@IsActive", d.IsActive, DbType.Boolean);
        // array order = recovery order (the procedure numbers them)
        p.Add("@PrioritiesJson", JsonSerializer.Serialize(d.Priorities.Select(x => new { x.DeductionGroup, x.Behaviour })), DbType.String, size: -1);
        return RunAsync(StoredProcedure.DeductionPolicyManage, p, userId, d.DeductionPolicyId, cancellationToken);
    }

    public Task<IReadOnlyList<LookupItem>> CalendarsAsync(int companyId, int? keepId, CancellationToken cancellationToken = default) =>
        LookupAsync(StoredProcedure.DeductionPolicyManage, "CALENDARS", p =>
        {
            p.Add("@CompanyId", companyId, DbType.Int32);
            p.Add("@PayrollCalendarId", keepId, DbType.Int32);
        }, cancellationToken);

    // ------------------------------------------------------------ proration
    public Task<PagedResult<ProrationRule>> ProrationRulesAsync(RuleListFilter filter, CancellationToken cancellationToken = default) =>
        SettingsSql.PageAsync<ProrationRule>(_sql, StoredProcedure.ProrationRuleManage, ListParams(filter), filter.Page, cancellationToken);

    public Task<ProrationRule?> ProrationRuleAsync(int payrollCalendarId, CancellationToken cancellationToken = default) =>
        GetAsync<ProrationRule>(StoredProcedure.ProrationRuleManage, payrollCalendarId, cancellationToken);

    public Task<SaveResult> SaveProrationRuleAsync(ProrationRule r, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope("UPDATE");
        p.Add("@Id", r.PayrollCalendarId, DbType.Int64);
        p.Add("@WorkingDaysBasis", r.WorkingDaysBasis, DbType.AnsiString, size: 10);
        p.Add("@FixedDaysPerMonth", r.FixedDaysPerMonth, DbType.Byte);
        p.Add("@ProrateJoiners", r.ProrateJoiners, DbType.Boolean);
        p.Add("@ProrateLeavers", r.ProrateLeavers, DbType.Boolean);
        p.Add("@ProrateRevisions", r.ProrateRevisions, DbType.Boolean);
        p.Add("@ProrateUnpaidLeave", r.ProrateUnpaidLeave, DbType.Boolean);
        p.Add("@ExcludeRestDays", r.ExcludeRestDays, DbType.Boolean);
        p.Add("@Notes", T(r.Notes, 500), DbType.String, size: 500);
        return RunAsync(StoredProcedure.ProrationRuleManage, p, userId, r.PayrollCalendarId, cancellationToken);
    }

    // ------------------------------------------------------- approval routes
    public Task<PagedResult<ApprovalProcess>> ApprovalProcessesAsync(RuleListFilter filter, CancellationToken cancellationToken = default)
    {
        var p = ListParams(filter);
        p.Add("@ProcessCode", string.IsNullOrEmpty(filter.Kind) ? null : filter.Kind, DbType.AnsiString, size: 20);
        return SettingsSql.PageAsync<ApprovalProcess>(_sql, StoredProcedure.ApprovalProcessManage, p, filter.Page, cancellationToken);
    }

    public Task<ApprovalProcess?> ApprovalProcessAsync(int id, CancellationToken cancellationToken = default) =>
        GetAsync<ApprovalProcess>(StoredProcedure.ApprovalProcessManage, id, cancellationToken);

    public Task<SaveResult> SaveApprovalProcessAsync(ApprovalProcess a, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(a.ApprovalProcessId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", a.ApprovalProcessId > 0 ? a.ApprovalProcessId : null, DbType.Int64);
        p.Add("@ProcessCode", a.ProcessCode, DbType.AnsiString, size: 20);
        p.Add("@CompanyId", a.CompanyId, DbType.Int32);
        p.Add("@Level1RoleId", a.Level1RoleId, DbType.Int32);
        p.Add("@Level1DelegateUserId", a.Level1DelegateUserId, DbType.Int64);
        p.Add("@Level2RoleId", a.Level2RoleId, DbType.Int32);
        p.Add("@Level2DelegateUserId", a.Level2DelegateUserId, DbType.Int64);
        p.Add("@Level2AboveAmount", a.Level2AboveAmount, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@AllowSelfApproval", a.AllowSelfApproval, DbType.Boolean);
        p.Add("@Notes", T(a.Notes, 500), DbType.String, size: 500);
        p.Add("@IsActive", a.IsActive, DbType.Boolean);
        return RunAsync(StoredProcedure.ApprovalProcessManage, p, userId, a.ApprovalProcessId, cancellationToken);
    }

    public Task<IReadOnlyList<LookupItem>> RolesAsync(int? companyId, CancellationToken cancellationToken = default) =>
        LookupAsync(StoredProcedure.ApprovalProcessManage, "ROLES", p => p.Add("@CompanyId", companyId, DbType.Int32), cancellationToken);

    public Task<IReadOnlyList<LookupItem>> UsersAsync(int? companyId, CancellationToken cancellationToken = default) =>
        LookupAsync(StoredProcedure.ApprovalProcessManage, "USERS", p => p.Add("@CompanyId", companyId, DbType.Int32), cancellationToken);

    // ----------------------------------------------------- bank file formats
    public Task<PagedResult<BankFileFormat>> BankFileFormatsAsync(RuleListFilter filter, CancellationToken cancellationToken = default) =>
        SettingsSql.PageAsync<BankFileFormat>(_sql, StoredProcedure.BankFileFormatManage, ListParams(filter), filter.Page, cancellationToken);

    public async Task<BankFileFormat?> BankFileFormatAsync(int id, CancellationToken cancellationToken = default)
    {
        var format = await GetAsync<BankFileFormat>(StoredProcedure.BankFileFormatManage, id, cancellationToken).ConfigureAwait(false);
        if (format is null) return null;
        var p = SettingsSql.Envelope("LINES");
        p.Add("@Id", id, DbType.Int64);
        format.Fields = (await _sql.QueryAsync<BankFileField>(StoredProcedure.BankFileFormatManage, p, cancellationToken).ConfigureAwait(false)).ToList();
        return format;
    }

    public Task<SaveResult> SaveBankFileFormatAsync(BankFileFormat f, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(f.BankFileFormatId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", f.BankFileFormatId > 0 ? f.BankFileFormatId : null, DbType.Int64);
        p.Add("@FormatCode", T(f.FormatCode, 30)?.ToUpperInvariant(), DbType.String, size: 30);
        p.Add("@FormatName", T(f.FormatName, 150), DbType.String, size: 150);
        p.Add("@BankId", f.BankId, DbType.Int32);
        p.Add("@FileType", f.FileType, DbType.AnsiString, size: 10);
        // "\t" typed in the form means a tab; the delimiter is kept as typed otherwise (a space is a valid delimiter)
        p.Add("@Delimiter", f.Delimiter is null or "" ? null : f.Delimiter.Replace("\\t", "\t"), DbType.String, size: 3);
        p.Add("@HasHeader", f.HasHeader, DbType.Boolean);
        p.Add("@HasTrailer", f.HasTrailer, DbType.Boolean);
        p.Add("@FileNamePattern", T(f.FileNamePattern, 100), DbType.String, size: 100);
        p.Add("@IsDefault", f.IsDefault, DbType.Boolean);
        p.Add("@Notes", T(f.Notes, 500), DbType.String, size: 500);
        p.Add("@IsActive", f.IsActive, DbType.Boolean);
        p.Add("@FieldsJson", JsonSerializer.Serialize(f.Fields.Select(x => new
        {
            FieldName = T(x.FieldName, 50), x.SourceCode, ConstantValue = x.SourceCode == "CONSTANT" ? x.ConstantValue : null,
            x.Width, PadChar = string.IsNullOrEmpty(x.PadChar) ? null : x.PadChar[..1], x.AlignRight
        })), DbType.String, size: -1);
        return RunAsync(StoredProcedure.BankFileFormatManage, p, userId, f.BankFileFormatId, cancellationToken);
    }

    public Task<IReadOnlyList<LookupItem>> FormatBanksAsync(int? keepId, CancellationToken cancellationToken = default) =>
        LookupAsync(StoredProcedure.BankFileFormatManage, "BANKS", p => p.Add("@BankId", keepId, DbType.Int32), cancellationToken);

    // ------------------------------------------------------------ GL mapping
    public Task<PagedResult<GLMapping>> GLMappingsAsync(RuleListFilter filter, CancellationToken cancellationToken = default)
    {
        var p = ListParams(filter);
        p.Add("@ComponentType", filter.Kind is "EARNING" or "DEDUCTION" ? filter.Kind : null, DbType.AnsiString, size: 10);
        return SettingsSql.PageAsync<GLMapping>(_sql, StoredProcedure.GLMappingManage, p, filter.Page, cancellationToken);
    }

    public Task<GLMapping?> GLMappingAsync(int id, CancellationToken cancellationToken = default) =>
        GetAsync<GLMapping>(StoredProcedure.GLMappingManage, id, cancellationToken);

    public Task<SaveResult> SaveGLMappingAsync(GLMapping g, long? userId, CancellationToken cancellationToken = default)
    {
        var p = SettingsSql.Envelope(g.GLMappingId > 0 ? "UPDATE" : "INSERT");
        p.Add("@Id", g.GLMappingId > 0 ? g.GLMappingId : null, DbType.Int64);
        p.Add("@PayComponentId", g.PayComponentId, DbType.Int32);
        p.Add("@CostCenterId", g.CostCenterId, DbType.Int32);
        p.Add("@DebitAccountCode", T(g.DebitAccountCode, 50), DbType.String, size: 50);
        p.Add("@DebitAccountName", T(g.DebitAccountName, 150), DbType.String, size: 150);
        p.Add("@CreditAccountCode", T(g.CreditAccountCode, 50), DbType.String, size: 50);
        p.Add("@CreditAccountName", T(g.CreditAccountName, 150), DbType.String, size: 150);
        p.Add("@Notes", T(g.Notes, 500), DbType.String, size: 500);
        p.Add("@IsActive", g.IsActive, DbType.Boolean);
        return RunAsync(StoredProcedure.GLMappingManage, p, userId, g.GLMappingId, cancellationToken);
    }

    public Task<IReadOnlyList<LookupItem>> ComponentsAsync(int companyId, int? keepId, CancellationToken cancellationToken = default) =>
        LookupAsync(StoredProcedure.GLMappingManage, "COMPONENTS", p =>
        {
            p.Add("@CompanyId", companyId, DbType.Int32);
            p.Add("@PayComponentId", keepId, DbType.Int32);
        }, cancellationToken);

    // --------------------------------------------------------------- shared
    public Task<SaveResult> ActionAsync(string table, string action, int id, long? userId, CancellationToken cancellationToken = default)
    {
        if (action is not ("DELETE" or "TOGGLE")) throw new ArgumentOutOfRangeException(nameof(action));
        var p = SettingsSql.Envelope(action);
        p.Add("@Id", id, DbType.Int64);
        return RunAsync(Proc(table), p, userId, id, cancellationToken);
    }
}
