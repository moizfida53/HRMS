using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

public sealed class CostCenter
{
    public int CostCenterId { get; set; }

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Display(Name = "Parent Cost Center")]
    public int? ParentCostCenterId { get; set; }

    [Required(ErrorMessage = "Cost center code is required.")]
    [StringLength(50)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Cost Center Code")]
    public string CostCenterCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Cost center name is required.")]
    [StringLength(150)]
    [Display(Name = "Cost Center Name")]
    public string CostCenterName { get; set; } = string.Empty;

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST-only columns ----
    public string? CompanyName { get; set; }
    public string? ParentCostCenterName { get; set; }
    public int DepartmentCount { get; set; }
}
