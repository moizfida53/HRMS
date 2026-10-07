namespace HRMS.Domain.Workforce;

/// <summary>
/// One row of the Documents tab of the Employee Profile screen: an active
/// document type (grouped under its Document Section) plus the employee's
/// current uploaded file for it, if any. Returned by
/// Documents.usp_EmployeeDocument_Manage LIST - every active type is listed,
/// whether or not a file has been uploaded, so the tab can show what is
/// still missing.
/// </summary>
public sealed class EmployeeDocumentRow
{
    // ---- section (null = document type not filed under any section) ----
    public int? SectionId { get; set; }
    public string? SectionNameEng { get; set; }
    public string? SectionNameArb { get; set; }
    public int? SectionSeq { get; set; }

    // ---- document type ----
    public int DocumentTypeId { get; set; }
    public string DocumentTypeName { get; set; } = string.Empty;
    public string? DocumentTypeNameAr { get; set; }
    public bool AttachmentMandatory { get; set; }

    // ---- current file (all null when nothing uploaded yet) ----
    public long? AttachmentId { get; set; }
    public string? OriginalFileName { get; set; }
    public string? ContentType { get; set; }
    public long? FileSizeBytes { get; set; }
    public DateTime? UploadedDate { get; set; }

    public bool HasFile => AttachmentId is > 0;

    public bool IsMissingRequired => AttachmentMandatory && !HasFile;
}

/// <summary>One uploaded file - Documents.usp_EmployeeDocument_Manage GET.</summary>
public sealed class EmployeeDocumentFile
{
    public long AttachmentId { get; set; }
    public long EmployeeId { get; set; }
    public int DocumentTypeId { get; set; }
    public string OriginalFileName { get; set; } = string.Empty;

    /// <summary>Path relative to the document storage root - never a full path.</summary>
    public string StoredFileName { get; set; } = string.Empty;

    public string ContentType { get; set; } = "application/octet-stream";
    public long FileSizeBytes { get; set; }
    public DateTime UploadedDate { get; set; }
}
