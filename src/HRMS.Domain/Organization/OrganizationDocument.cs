using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

/// <summary>What a type of company document is about - groups and colours it on screen (db/73).</summary>
public static class OrgDocumentCategory
{
    public const string License = "LICENSE";
    public const string Registration = "REGISTRATION";
    public const string Authorization = "AUTHORIZATION";
    public const string Contract = "CONTRACT";
    public const string Insurance = "INSURANCE";
    public const string Other = "OTHER";

    public static readonly IReadOnlyList<string> All = [License, Registration, Authorization, Contract, Insurance, Other];
}

/// <summary>
/// One alert on an expiry date: <c>M3</c> = 3 months before, <c>W1</c> = 1 week before,
/// <c>D0</c> = on the day. A type keeps its alerts as <c>"M3,M1,W1"</c>.
/// </summary>
public readonly record struct ExpiryAlert(char Unit, int Value)
{
    /// <summary>The choices offered on the type form, longest first.</summary>
    public static readonly IReadOnlyList<ExpiryAlert> Presets =
        [new('M', 6), new('M', 3), new('M', 2), new('M', 1), new('W', 2), new('W', 1), new('D', 3), new('D', 0)];

    public string Code => $"{Unit}{Value}";

    public static IReadOnlyList<ExpiryAlert> Parse(string? rules) =>
        (rules ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(r => r.Length >= 2 && "MWD".Contains(r[0]) && int.TryParse(r[1..], out var n) && n is >= 0 and <= 99)
            .Select(r => new ExpiryAlert(r[0], int.Parse(r[1..], System.Globalization.CultureInfo.InvariantCulture)))
            .Distinct()
            .OrderByDescending(r => r.DaysBefore)
            .ToList();

    /// <summary>Roughly how far before the date it fires - only to order the alerts.</summary>
    public int DaysBefore => Unit switch { 'M' => Value * 30, 'W' => Value * 7, _ => Value };

    /// <summary>The day it fires for a date.</summary>
    public DateTime FiresOn(DateTime date) => Unit switch
    {
        'M' => date.AddMonths(-Value),
        'W' => date.AddDays(-7 * Value),
        _ => date.AddDays(-Value)
    };
}

/// <summary>Setup > Organization > Organization Documents: a type of company document.</summary>
public sealed class OrgDocumentType
{
    public int OrgDocumentTypeId { get; set; }

    [Required(ErrorMessage = "Document type name is required.")]
    [StringLength(150)]
    [Display(Name = "Document Type")]
    public string TypeName { get; set; } = string.Empty;

    [StringLength(150)]
    [Display(Name = "Arabic Name")]
    public string? ArabicName { get; set; }

    public string Category { get; set; } = OrgDocumentCategory.Other;

    /// <summary>Every active company must keep one.</summary>
    public bool IsMandatory { get; set; }
    public bool HasNumber { get; set; } = true;
    public bool HasIssueDate { get; set; } = true;
    public bool HasExpiryDate { get; set; } = true;

    /// <summary>Alerts before the expiry date, e.g. "M3,M1,W1" (see <see cref="ExpiryAlert"/>).</summary>
    [StringLength(60)]
    public string? AlertRules { get; set; }

    /// <summary>The form's ticked alerts ("M3", "W1", ...) - joined into <see cref="AlertRules"/> on save.</summary>
    public string[]? AlertChoices { get; set; }

    [Range(0, 9999)]
    public int? SortOrder { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>Who issues it (Documents.IssuingAuthorities, db/75) - chosen here, not on each document.</summary>
    public int? IssuingAuthorityId { get; set; }

    /// <summary>Companies that keep a current document of this type (LIST / GET).</summary>
    public int UsageCount { get; set; }

    // ---- LIST / GET-only display columns ----
    public string? AuthorityName { get; set; }
    public string? AuthorityNameAr { get; set; }
    public string? AuthorityShortName { get; set; }
}

/// <summary>A body that issues company documents - the Kuwait government authorities (db/75).</summary>
public sealed class IssuingAuthority
{
    public int IssuingAuthorityId { get; set; }
    public string AuthorityName { get; set; } = string.Empty;
    public string? ArabicName { get; set; }
    public string? ShortName { get; set; }
    public bool IsGovernment { get; set; } = true;
    public bool IsActive { get; set; } = true;
}

/// <summary>Workforce > Organizations: an active company and the health of its documents.</summary>
public sealed class OrgCompanySummary
{
    public int CompanyId { get; set; }
    public string? CompanyCode { get; set; }
    public string CompanyName { get; set; } = string.Empty;
    public string? LegalName { get; set; }
    public string? CommercialRegistrationNo { get; set; }
    public int TypeCount { get; set; }
    public int RecordedCount { get; set; }
    public int MissingCount { get; set; }
    public int ExpiredCount { get; set; }
    /// <summary>Documents whose expiry date reached one of their alerts (not yet expired).</summary>
    public int DueCount { get; set; }
    public DateTime? NextExpiry { get; set; }
}

/// <summary>One company: an active document type with its current document (all null when none) - LIST.</summary>
public sealed class OrgDocumentRow
{
    public int OrgDocumentTypeId { get; set; }
    public string TypeName { get; set; } = string.Empty;
    public string? ArabicName { get; set; }
    public string Category { get; set; } = OrgDocumentCategory.Other;
    public bool IsMandatory { get; set; }
    public bool HasNumber { get; set; }
    public bool HasIssueDate { get; set; }
    public bool HasExpiryDate { get; set; }
    public string? AlertRules { get; set; }
    /// <summary>The type's issuing authority (db/75).</summary>
    public string? AuthorityName { get; set; }
    public string? AuthorityNameAr { get; set; }
    public string? AuthorityShortName { get; set; }

    public long? OrgDocumentId { get; set; }
    public string? DocumentNumber { get; set; }
    public string? IssuingAuthority { get; set; }
    public DateTime? IssueDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public string? Notes { get; set; }
    public string? OriginalFileName { get; set; }
    public string? ContentType { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime? UpdatedDate { get; set; }
    public int ArchivedCount { get; set; }
    /// <summary>The alert that fired most recently (e.g. "M1"); null = none yet.</summary>
    public string? FiredRule { get; set; }

    public bool HasDocument => OrgDocumentId is > 0;
    public bool HasFile => !string.IsNullOrEmpty(OriginalFileName);
    public int? DaysLeft => ExpiryDate is { } d ? (int)(d.Date - DateTime.Today).TotalDays : null;
    public bool IsExpired => HasExpiryDate && DaysLeft is < 0;
    public bool IsDue => HasExpiryDate && !IsExpired && FiredRule is not null;
}

/// <summary>One document (any state) - GET; also its file for viewing.</summary>
public sealed class OrgDocument
{
    public long OrgDocumentId { get; set; }
    public int CompanyId { get; set; }
    public int OrgDocumentTypeId { get; set; }
    public string State { get; set; } = "C";
    public string? DocumentNumber { get; set; }
    public string? IssuingAuthority { get; set; }
    public DateTime? IssueDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public string? Notes { get; set; }
    public string? OriginalFileName { get; set; }
    public string? StoredFileName { get; set; }
    public string? ContentType { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime CreatedDate { get; set; }
    public DateTime? ArchivedDate { get; set; }
    public string? TypeName { get; set; }
    public string? ArabicName { get; set; }
}

/// <summary>A document's versions: the current one and the ones its renewals archived - HISTORY.</summary>
public sealed class OrgDocumentVersion
{
    public long OrgDocumentId { get; set; }
    public string State { get; set; } = "C";
    public string? DocumentNumber { get; set; }
    public string? IssuingAuthority { get; set; }
    public DateTime? IssueDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public string? Notes { get; set; }
    public string? OriginalFileName { get; set; }
    public string? ContentType { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime CreatedDate { get; set; }
    public DateTime? ArchivedDate { get; set; }
    public string? CreatedByName { get; set; }
}

/// <summary>A company document whose expiry date reached an alert - DUE (Dashboard).</summary>
public sealed class OrgDocumentDue
{
    public int CompanyId { get; set; }
    public string CompanyName { get; set; } = string.Empty;
    public int OrgDocumentTypeId { get; set; }
    public string TypeName { get; set; } = string.Empty;
    public string? ArabicName { get; set; }
    public string Category { get; set; } = OrgDocumentCategory.Other;
    public long OrgDocumentId { get; set; }
    public string? DocumentNumber { get; set; }
    public DateTime ExpiryDate { get; set; }
    public int DaysLeft { get; set; }
    public string? FiredRule { get; set; }
}

/// <summary>The document form: add, change or renew.</summary>
public sealed class OrgDocumentInput
{
    public long OrgDocumentId { get; set; }
    public int CompanyId { get; set; }
    public int OrgDocumentTypeId { get; set; }
    public bool Renew { get; set; }
    [StringLength(100)] public string? DocumentNumber { get; set; }
    [StringLength(150)] public string? IssuingAuthority { get; set; }
    public DateTime? IssueDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    [StringLength(500)] public string? Notes { get; set; }
    public bool RemoveFile { get; set; }
}

/// <summary>A scan saved with a document.</summary>
public sealed record OrgDocumentFile(string StoredFileName, string OriginalFileName, string ContentType, long SizeBytes);
