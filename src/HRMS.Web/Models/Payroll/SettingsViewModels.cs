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
}

/// <summary>A select of a settings toolbar: query name, aria label and (value, text) options; the first one is the default.</summary>
public sealed record SettingsFilter(string Name, string Label, IReadOnlyList<(string Value, string Text)> Options);

/// <summary>An on / off switch of a settings form (_Switch partial): posts "true" when on, "false" when off.</summary>
public sealed record SettingsSwitch(string Name, string Label, bool Checked, string? Hint = null, bool Disabled = false);
