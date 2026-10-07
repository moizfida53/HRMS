using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

/// <summary>Maps to Core.Positions - a seat in the org structure.</summary>
public sealed class JobPosition
{
    public int PositionId { get; set; }

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Required(ErrorMessage = "Position code is required.")]
    [StringLength(50)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Position Code")]
    public string PositionCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Position name is required.")]
    [StringLength(150)]
    [Display(Name = "Position Name")]
    public string PositionName { get; set; } = string.Empty;

    [Display(Name = "Job Description")]
    public string? JobDescription { get; set; }

    [Display(Name = "Grade")]
    public int? GradeId { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST-only columns ----
    public string? CompanyName { get; set; }
    public string? GradeName { get; set; }
    public int EmployeeCount { get; set; }
}
