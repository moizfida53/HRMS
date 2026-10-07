using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

public sealed class Section
{
    public int SectionId { get; set; }

    [Required(ErrorMessage = "Department is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a department.")]
    [Display(Name = "Department")]
    public int DepartmentId { get; set; }

    [Required(ErrorMessage = "Section code is required.")]
    [StringLength(50)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Section Code")]
    public string SectionCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Section name is required.")]
    [StringLength(150)]
    [Display(Name = "Section Name")]
    public string SectionName { get; set; } = string.Empty;

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    /// <summary>Not stored on Sections - carried for the cascading company filter on the form.</summary>
    [Display(Name = "Company")]
    public int? CompanyId { get; set; }

    // ---- LIST-only columns ----
    public string? DepartmentName { get; set; }
    public string? CompanyName { get; set; }
    public int EmployeeCount { get; set; }
}
