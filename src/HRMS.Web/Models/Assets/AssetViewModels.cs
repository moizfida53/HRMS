using HRMS.Domain.Assets;
using HRMS.Domain.Common;
using HRMS.Web.Localization;

namespace HRMS.Web.Models.Assets;

/// <summary>What the signed-in user may do on Workforce > Assets (Security > Create Roles).</summary>
public sealed record AssetRights(bool CanView, bool CanEdit, bool CanDelete);

/// <summary>Names, icons and states of assets on screen.</summary>
public static class AssetFormat
{
    public static string Name(IUiText L, string? english, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : english ?? string.Empty;

    /// <summary>The CSS modifier of a type's colour (car, bike, phone ...).</summary>
    public static string Key(string? icon) => (AssetIcon.All.Contains(icon ?? "") ? icon! : AssetIcon.Other).ToLowerInvariant();

    public static string Icon(string? icon) => icon switch
    {
        AssetIcon.Car => "car",
        AssetIcon.Bike => "bike",
        AssetIcon.Phone => "smartphone",
        AssetIcon.Laptop => "laptop",
        AssetIcon.Tablet => "tablet",
        AssetIcon.Key => "key",
        AssetIcon.Tool => "tool",
        _ => "box"
    };

    public static string IconLabel(IUiText L, string icon) => icon switch
    {
        AssetIcon.Car => L["as.icon_car"],
        AssetIcon.Bike => L["as.icon_bike"],
        AssetIcon.Phone => L["as.icon_phone"],
        AssetIcon.Laptop => L["as.icon_laptop"],
        AssetIcon.Tablet => L["as.icon_tablet"],
        AssetIcon.Key => L["as.icon_key"],
        AssetIcon.Tool => L["as.icon_tool"],
        _ => L["as.icon_other"]
    };

    /// <summary>The status of an asset: retired, expired, expiring, in use or available.</summary>
    public static (string Css, string Text) State(IUiText L, AssetRow a) =>
        !a.IsActive ? ("muted", L["as.st_retired"])
        : a.ExpiryState == "EXPIRED" ? ("danger", L["as.st_expired"])
        : a.ExpiryState == "EXPIRING" ? ("warning", L["as.st_expiring"])
        : a.AssignedEmployeeId is not null ? ("success", L["as.st_assigned"])
        : ("info", L["as.st_available"]);

    public static string Due(IUiText L, int? days) => days switch
    {
        null => string.Empty,
        -1 => L["dash.alert_overdue_yesterday"],
        < 0 => L["dash.alert_overdue_days", -days.Value],
        0 => L["dash.alert_today"],
        1 => L["dash.alert_tomorrow"],
        _ => L["dash.alert_in_days", days.Value]
    };
}

public sealed class AssetsPageModel
{
    public required AssetRights Rights { get; init; }
    public IReadOnlyList<AssetSummaryRow> Summary { get; init; } = Array.Empty<AssetSummaryRow>();
    public int? TypeId { get; init; }
    public string? Status { get; init; }
}

public sealed class AssetGridModel
{
    public required AssetRights Rights { get; init; }
    public IReadOnlyList<AssetRow> Rows { get; init; } = Array.Empty<AssetRow>();
    public int Total { get; init; }
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 25;
    public int TotalPages => Math.Max(1, (int)Math.Ceiling(Total / (double)PageSize));
    public bool Filtered { get; init; }
}

public sealed class AssetFormModel
{
    public AssetRow? Asset { get; init; }
    public IReadOnlyList<AssetType> Types { get; init; } = Array.Empty<AssetType>();
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    /// <summary>The employees of the companies on the form (LookupItem.ParentId = company).</summary>
    public IReadOnlyList<LookupItem> Employees { get; init; } = Array.Empty<LookupItem>();
    public int? CompanyId { get; init; }
    public int? TypeId { get; init; }
}

public sealed class AssetHistoryModel
{
    public required AssetRow Asset { get; init; }
    public IReadOnlyList<AssetAssignment> Entries { get; init; } = Array.Empty<AssetAssignment>();
}
