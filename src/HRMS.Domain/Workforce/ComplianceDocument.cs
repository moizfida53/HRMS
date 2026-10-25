namespace HRMS.Domain.Workforce;

/// <summary>
/// The Kuwait Compliance items whose images are tied to an expiry date (db/71):
/// the document types linked to each item live in Kuwait.ComplianceDocumentTypes.
/// </summary>
public static class ComplianceDocumentKey
{
    public const string CivilId = "CIVIL_ID";
    public const string Passport = "PASSPORT";
    public const string Residency = "RESIDENCY";
    public const string WorkPermit = "WORK_PERMIT";

    public static readonly IReadOnlyList<string> All = [CivilId, Passport, Residency, WorkPermit];

    public static bool IsValid(string? key) => key is not null && All.Contains(key);
}

/// <summary>State of one image (Documents.EmployeeDocumentAttachments.ImageState).</summary>
public static class ComplianceImageState
{
    /// <summary>The image in use.</summary>
    public const string Current = "C";
    /// <summary>A new image waiting for its renewal to be confirmed.</summary>
    public const string Renewal = "R";
    /// <summary>A previous image, replaced by a confirmed renewal.</summary>
    public const string Archived = "A";
}

/// <summary>
/// One linked document type of a compliance item with one of its images (the current
/// or the renewal one) - Kuwait.usp_ComplianceDocument_Manage LIST. A type without an
/// image comes once, with no AttachmentId; with both images it comes twice.
/// </summary>
public sealed class ComplianceDocumentRow
{
    public string ComplianceKey { get; set; } = string.Empty;
    public int DocumentTypeId { get; set; }
    public string DocumentTypeName { get; set; } = string.Empty;
    public string? DocumentTypeNameAr { get; set; }

    public long? AttachmentId { get; set; }
    public string? ImageState { get; set; }
    public string? OriginalFileName { get; set; }
    public string? ContentType { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime? UploadedDate { get; set; }

    public DateTime? ConfirmedExpiryDate { get; set; }
    public string? ConfirmedNumber { get; set; }
    public DateTime? ConfirmedDate { get; set; }

    public int ArchivedCount { get; set; }

    public bool IsConfirmed => ConfirmedDate is not null;
}

/// <summary>Every image of one compliance item, archived ones too - HISTORY.</summary>
public sealed class ComplianceImageEntry
{
    public long AttachmentId { get; set; }
    public int DocumentTypeId { get; set; }
    public string DocumentTypeName { get; set; } = string.Empty;
    public string? DocumentTypeNameAr { get; set; }
    public string ImageState { get; set; } = ComplianceImageState.Current;
    public string OriginalFileName { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime UploadedDate { get; set; }
    public string? UploadedByName { get; set; }
    public DateTime? ConfirmedExpiryDate { get; set; }
    public string? ConfirmedNumber { get; set; }
    public DateTime? ConfirmedDate { get; set; }
    public DateTime? ArchivedDate { get; set; }
}
