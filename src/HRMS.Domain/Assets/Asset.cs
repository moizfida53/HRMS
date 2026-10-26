using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Assets;

/// <summary>The icon (and colour) of an asset type on screen (db/84).</summary>
public static class AssetIcon
{
    public const string Car = "CAR";
    public const string Bike = "BIKE";
    public const string Phone = "PHONE";
    public const string Laptop = "LAPTOP";
    public const string Tablet = "TABLET";
    public const string Key = "KEY";
    public const string Tool = "TOOL";
    public const string Other = "OTHER";

    public static readonly IReadOnlyList<string> All = [Car, Bike, Phone, Laptop, Tablet, Key, Tool, Other];
}

/// <summary>Setup > Organization > Asset Types: a kind of company asset (cars, motor bikes, phones ...).</summary>
public sealed class AssetType
{
    public int AssetTypeId { get; set; }

    [Required(ErrorMessage = "Asset type name is required.")]
    [StringLength(100)]
    [Display(Name = "Asset Type")]
    public string TypeName { get; set; } = string.Empty;

    [StringLength(100)]
    [Display(Name = "Arabic Name")]
    public string? ArabicName { get; set; }

    public string Icon { get; set; } = AssetIcon.Other;

    /// <summary>Its assets have an expiry date (registration, warranty ...) with alerts.</summary>
    public bool HasExpiryDate { get; set; } = true;

    /// <summary>What the expiry date is, e.g. "Registration (Daftar) expiry".</summary>
    [StringLength(80)]
    public string? ExpiryLabel { get; set; }

    [StringLength(80)]
    public string? ExpiryLabelAr { get; set; }

    /// <summary>Alerts before the expiry date, e.g. "M1,W2,D0" (see Organization.ExpiryAlert).</summary>
    [StringLength(60)]
    public string? AlertRules { get; set; }

    /// <summary>The form's ticked alerts ("M1", "W2", ...) - joined into <see cref="AlertRules"/> on save.</summary>
    public string[]? AlertChoices { get; set; }

    [Range(0, 9999)]
    public int? SortOrder { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>How many assets are of this type (read only).</summary>
    public int UsageCount { get; set; }
}

/// <summary>Workforce > Assets: one row of the list.</summary>
public sealed class AssetRow
{
    public long AssetId { get; init; }
    public int CompanyId { get; init; }
    public string? CompanyName { get; init; }
    public int AssetTypeId { get; init; }
    public string TypeName { get; init; } = string.Empty;
    public string? TypeArabicName { get; init; }
    public string Icon { get; init; } = AssetIcon.Other;
    public bool HasExpiryDate { get; init; }
    public string? ExpiryLabel { get; init; }
    public string? ExpiryLabelAr { get; init; }
    public string AssetCode { get; init; } = string.Empty;
    public string? Brand { get; init; }
    public string? Model { get; init; }
    public string? Color { get; init; }
    public string? SerialNumber { get; init; }
    public DateTime? PurchaseDate { get; init; }
    public decimal? PurchaseCost { get; init; }
    public DateTime? ExpiryDate { get; init; }
    public long? AssignedEmployeeId { get; init; }
    public DateTime? AssignedDate { get; init; }
    public string? Notes { get; init; }
    public bool IsActive { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    /// <summary>NONE (no date), OK, EXPIRING (an alert of its type has fired), EXPIRED.</summary>
    public string ExpiryState { get; init; } = "NONE";
    public int? DaysLeft { get; init; }

    public string Title => string.Join(" ", new[] { Brand, Model }.Where(x => !string.IsNullOrWhiteSpace(x)));
}

/// <summary>An asset being added or changed (Workforce > Assets form).</summary>
public sealed class AssetInput
{
    public long AssetId { get; set; }
    public int CompanyId { get; set; }

    [Range(1, int.MaxValue, ErrorMessage = "Choose the asset type.")]
    public int AssetTypeId { get; set; }

    [StringLength(30)] public string? AssetCode { get; set; }
    [StringLength(100)] public string? Brand { get; set; }
    [StringLength(100)] public string? Model { get; set; }
    [StringLength(50)] public string? Color { get; set; }
    [StringLength(100)] public string? SerialNumber { get; set; }
    public DateTime? PurchaseDate { get; set; }
    [Range(0, 999999999)] public decimal? PurchaseCost { get; set; }
    public DateTime? ExpiryDate { get; set; }
    /// <summary>Who uses it (null = nobody: available).</summary>
    public long? EmployeeId { get; set; }
    public DateTime? AssignedDate { get; set; }
    [StringLength(500)] public string? Notes { get; set; }
    public bool IsActive { get; set; } = true;
    [StringLength(300)] public string? Remarks { get; set; }
}

/// <summary>Counts for the Assets page: one row per active type, with the status totals.</summary>
public sealed class AssetSummaryRow
{
    public int AssetTypeId { get; init; }
    public string TypeName { get; init; } = string.Empty;
    public string? TypeArabicName { get; init; }
    public string Icon { get; init; } = AssetIcon.Other;
    public int TypeCount { get; init; }
    public int TotalCount { get; init; }
    public int AssignedCount { get; init; }
    public int AvailableCount { get; init; }
    public int ExpiringCount { get; init; }
    public int ExpiredCount { get; init; }
    public int RetiredCount { get; init; }
}

/// <summary>One holder of an asset, from / to.</summary>
public sealed class AssetAssignment
{
    public long AssignmentId { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public DateTime FromDate { get; init; }
    public DateTime? ToDate { get; init; }
    public string? Remarks { get; init; }
}

/// <summary>An asset whose expiry date reached an alert of its type (Dashboard).</summary>
public sealed class AssetDue
{
    public long AssetId { get; init; }
    public int CompanyId { get; init; }
    public string? CompanyName { get; init; }
    public string AssetCode { get; init; } = string.Empty;
    public string? Brand { get; init; }
    public string? Model { get; init; }
    public string? SerialNumber { get; init; }
    public DateTime ExpiryDate { get; init; }
    public string TypeName { get; init; } = string.Empty;
    public string? TypeArabicName { get; init; }
    public string Icon { get; init; } = AssetIcon.Other;
    public string? ExpiryLabel { get; init; }
    public string? ExpiryLabelAr { get; init; }
    public string? EmployeeName { get; init; }
    public int DaysLeft { get; init; }
}
