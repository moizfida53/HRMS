using HRMS.Domain.Organization;
using HRMS.Web.Localization;

namespace HRMS.Web.Models.Organization;

/// <summary>Text helpers for the organization documents (Setup tab, Workforce > Organizations, Dashboard).</summary>
public static class OrgDocumentFormat
{
    public static string Name(IUiText L, string? english, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : english ?? string.Empty;

    public static string CategoryLabel(IUiText L, string? category) => category switch
    {
        OrgDocumentCategory.License => L["od.cat_license"],
        OrgDocumentCategory.Registration => L["od.cat_registration"],
        OrgDocumentCategory.Authorization => L["od.cat_authorization"],
        OrgDocumentCategory.Contract => L["od.cat_contract"],
        OrgDocumentCategory.Insurance => L["od.cat_insurance"],
        _ => L["od.cat_other"]
    };

    /// <summary>The colour/icon key of a category (CSS modifier).</summary>
    public static string CategoryKey(string? category) => (category ?? OrgDocumentCategory.Other).ToLowerInvariant();

    public static string CategoryIcon(string? category) => category switch
    {
        OrgDocumentCategory.License => "id-card",
        OrgDocumentCategory.Registration => "book",
        OrgDocumentCategory.Authorization => "user-check",
        OrgDocumentCategory.Contract => "file",
        OrgDocumentCategory.Insurance => "shield",
        _ => "folder"
    };

    /// <summary>"3 months before", "1 week before", "On the day".</summary>
    public static string AlertLabel(IUiText L, ExpiryAlert rule) => (rule.Unit, rule.Value) switch
    {
        (_, 0) => L["od.alert_on_day"],
        ('M', 1) => L["od.alert_1_month"],
        ('M', var n) => L["od.alert_n_months", n],
        ('W', 1) => L["od.alert_1_week"],
        ('W', var n) => L["od.alert_n_weeks", n],
        ('D', 1) => L["od.alert_1_day"],
        (_, var n) => L["od.alert_n_days", n]
    };

    /// <summary>Short form for chips: "3 mo", "1 wk", "3 d", "Day".</summary>
    public static string AlertShort(IUiText L, ExpiryAlert rule) => rule.Value == 0
        ? L["od.alert_short_day"]
        : rule.Unit switch { 'M' => L["od.alert_short_m", rule.Value], 'W' => L["od.alert_short_w", rule.Value], _ => L["od.alert_short_d", rule.Value] };

    public static string FileSize(long? bytes) => bytes switch
    {
        null => "",
        >= 1024 * 1024 => $"{bytes.Value / 1024d / 1024d:0.0} MB",
        _ => $"{Math.Max(1, (int)Math.Round(bytes.Value / 1024d))} KB"
    };
}
