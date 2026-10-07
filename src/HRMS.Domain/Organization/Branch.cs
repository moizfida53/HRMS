using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

public sealed class Branch
{
    public int BranchId { get; set; }

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Required(ErrorMessage = "Branch code is required.")]
    [StringLength(30)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Branch Code")]
    public string BranchCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Branch name is required.")]
    [StringLength(150)]
    [Display(Name = "Branch Name")]
    public string BranchName { get; set; } = string.Empty;

    [StringLength(500)]
    public string? Address { get; set; }

    [StringLength(100)]
    public string? Area { get; set; }

    [StringLength(100)]
    public string? Governorate { get; set; }

    [StringLength(50)]
    public string? Telephone { get; set; }

    [EmailAddress(ErrorMessage = "Enter a valid email address.")]
    [StringLength(150)]
    public string? Email { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST-only columns ----
    public string? CompanyName { get; set; }
    public int EmployeeCount { get; set; }
}
