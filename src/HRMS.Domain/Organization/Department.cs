using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

public sealed class Department
{
    public int DepartmentId { get; set; }

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Display(Name = "Parent Department")]
    public int? ParentDepartmentId { get; set; }

    [Required(ErrorMessage = "Department code is required.")]
    [StringLength(50)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Department Code")]
    public string DepartmentCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Department name is required.")]
    [StringLength(150)]
    [Display(Name = "Department Name")]
    public string DepartmentName { get; set; } = string.Empty;

    [Display(Name = "Cost Center")]
    public int? CostCenterId { get; set; }

    [Display(Name = "Manager")]
    public long? ManagerEmployeeId { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST-only columns ----
    public string? CompanyName { get; set; }
    public string? ParentDepartmentName { get; set; }
    public string? CostCenterName { get; set; }
    public string? ManagerName { get; set; }
    public int SectionCount { get; set; }
    public int EmployeeCount { get; set; }
}
