using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

/// <summary>
/// A document employees upload on the Documents tab of their profile (Civil ID,
/// passport, contract, ...): which section it is listed under and whether it is
/// mandatory. Group-wide - not per company. Organization > Employee Documents (db/63).
/// </summary>
public sealed class DocumentType
{
    public int DocumentTypeId { get; set; }

    [Required(ErrorMessage = "Document type name is required.")]
    [StringLength(150)]
    [Display(Name = "Document Type")]
    public string DocumentTypeName { get; set; } = string.Empty;

    [StringLength(150)]
    [Display(Name = "Arabic Name")]
    public string? ArabicName { get; set; }

    [Display(Name = "Section")]
    public int? SectionId { get; set; }

    /// <summary>An employee must have a file attached for this type.</summary>
    [Display(Name = "Mandatory")]
    public bool IsMandatory { get; set; }

    [Range(0, 9999)]
    [Display(Name = "Sort Order")]
    public int? SortOrder { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST / GET-only display columns ----
    public string? SectionName { get; set; }
    public string? SectionNameAr { get; set; }
    public int? SectionSeq { get; set; }
    /// <summary>Employee files currently attached to this type.</summary>
    public int UsageCount { get; set; }
}

/// <summary>A band on the Documents tab that document types are listed under (Documents.DocumentSections).</summary>
public sealed class DocumentSection
{
    public int SectionId { get; set; }
    public string NameEng { get; set; } = string.Empty;
    public string? NameArb { get; set; }
    public int Seq { get; set; }
    public bool IsActive { get; set; } = true;
    public int TypeCount { get; set; }
}
