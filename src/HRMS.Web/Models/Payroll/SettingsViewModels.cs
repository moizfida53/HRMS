using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Web.Models.Payroll;

/// <summary>What the signed-in user may do on the Payroll Settings screens.</summary>
public sealed class SettingsRights
{
    public bool CanCreate { get; init; }
    public bool CanEdit { get; init; }
    public bool CanDelete { get; init; }
}

/// <summary>A Payroll Settings page (the lists load themselves).</summary>
public sealed class SettingsPageModel
{
    public required SettingsRights Rights { get; init; }
    /// <summary>The company "Add standard types" works on (null when several companies are selected).</summary>
    public int? SeedCompanyId { get; init; }
    /// <summary>Statutory rows still marked "not verified" (Payroll Rules banner).</summary>
    public int UnverifiedCount { get; init; }
}

/// <summary>One page of a settings list.</summary>
public sealed class SettingsGridModel<T>
{
    public required PagedResult<T> Page { get; init; }
    public required SettingsRights Rights { get; init; }
    public bool ManyCompanies { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class ItemTypeFormModel
{
    public required PayItemTypeSetting Item { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyList<LookupItem> CostCenters { get; init; } = Array.Empty<LookupItem>();
    public bool IsNew => Item.PayComponentId <= 0;
}

/// <summary>Label keys and badges of the Payroll Settings screens.</summary>
public static class SettingsFormat
{
    public static string ClassKey(string itemClass) => itemClass switch
    {
        "SALARY" => "st.class_salary",
        "EARNING" => "st.class_earning",
        "LOAN" => "st.class_loan",
        "STATUTORY" => "st.class_statutory",
        _ => "st.class_deduction"
    };

    public static string ClassBadge(string itemClass) => itemClass switch
    {
        "SALARY" => "info",
        "EARNING" => "success",
        "LOAN" => "purple",
        "STATUTORY" => "warning",
        _ => "danger"
    };

    public static string MethodKey(string? method) => method switch
    {
        "PERCENTAGE" => "st.method_percentage",
        "DAYS" => "st.method_days",
        "HOURS" => "st.method_hours",
        "FORMULA" => "st.method_formula",
        "SYSTEM" => "st.method_system",
        _ => "st.method_amount"
    };

    public static string BaseKey(string? calculationBase) => calculationBase switch
    {
        "FIXED_GROSS" => "st.base_fixed_gross",
        "OVERTIME_BASE" => "st.base_overtime",
        "INDEMNITY_BASE" => "st.base_indemnity",
        _ => "st.base_basic"
    };

    public static readonly IReadOnlyList<string> Methods = ["AMOUNT", "PERCENTAGE", "DAYS", "HOURS", "FORMULA"];
    public static readonly IReadOnlyList<string> Bases = ["BASIC", "FIXED_GROSS", "OVERTIME_BASE", "INDEMNITY_BASE"];
}

/// <summary>The filter row of a settings list (_Toolbar partial).</summary>
public sealed class SettingsToolbarModel
{
    public string? Title { get; init; }
    public string? SearchPlaceholder { get; init; }
    public IReadOnlyList<SettingsFilter> Filters { get; init; } = Array.Empty<SettingsFilter>();
    /// <summary>An "Add" button in the toolbar for this master (its id) - for pages with several lists.</summary>
    public string? AddMaster { get; init; }
    public string? AddLabel { get; init; }
}

/// <summary>A select of a settings toolbar: query name, aria label and (value, text) options; the first one is the default.</summary>
public sealed record SettingsFilter(string Name, string Label, IReadOnlyList<(string Value, string Text)> Options);

/// <summary>An on / off switch of a settings form (_Switch partial): posts "true" when on, "false" when off.</summary>
public sealed record SettingsSwitch(string Name, string Label, bool Checked, string? Hint = null, bool Disabled = false);

public sealed class OvertimeFormModel
{
    public required OvertimeRate Rate { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    /// <summary>The user may save the statutory default (no company).</summary>
    public bool CanSetDefault { get; init; }
}

/// <summary>Label keys of the statutory screens.</summary>
public static class StatutoryFormat
{
    public static string ApplicableKey(string? v) => v switch
    {
        "GCC" => "st.applies_gcc", "EXPAT" => "st.applies_expat", "ALL" => "st.applies_all", _ => "st.applies_kuwaiti"
    };

    public static string BasisKey(string? v) => v == "BAND" ? "st.basis_band" : "st.basis_capped";

    public static string SeparationKey(string? v) => v switch
    {
        "RESIGNATION" => "fs.type_resignation", "TERMINATION" => "fs.type_termination", "CONTRACT_END" => "fs.type_contract_end",
        "RETIREMENT" => "fs.type_retirement", "DEATH" => "fs.type_death", "DISABILITY" => "fs.type_disability", _ => "st.separation_other"
    };

    public static string OvertimeKey(string? v) => v switch
    {
        "REST_DAY" => "st.ot_rest_day", "PUBLIC_HOLIDAY" => "st.ot_public_holiday", "NIGHT" => "st.ot_night", "OTHER" => "st.ot_other", _ => "st.ot_normal_day"
    };

    public static string Pct(decimal v) => v.ToString("0.####", System.Globalization.CultureInfo.InvariantCulture) + "%";
    public static string Num(decimal? v) => v?.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture) ?? "—";
}
