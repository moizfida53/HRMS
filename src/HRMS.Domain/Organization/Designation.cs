using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

/// <summary>
/// The job title as it appears on the Civil ID, work permit and contract
/// (for example "Accountant", "Heavy Driver"). Distinct from a Job Position,
/// which is a seat in the org chart.
/// </summary>
public sealed class Designation
{
    public int DesignationId { get; set; }

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Required(ErrorMessage = "Designation code is required.")]
    [StringLength(50)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Designation Code")]
    public string DesignationCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Designation name is required.")]
    [StringLength(150)]
    [Display(Name = "Designation Name")]
    public string DesignationName { get; set; } = string.Empty;

    [StringLength(150)]
    [Display(Name = "Arabic Name")]
    public string? ArabicName { get; set; }

    [Display(Name = "Grade")]
    public int? GradeId { get; set; }

    [StringLength(500)]
    public string? Description { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST-only columns ----
    public string? CompanyName { get; set; }
    public string? GradeName { get; set; }
    public int EmployeeCount { get; set; }
}
