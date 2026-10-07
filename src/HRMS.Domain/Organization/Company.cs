using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

public sealed class Company
{
    public int CompanyId { get; set; }

    [Required(ErrorMessage = "Company code is required.")]
    [StringLength(30, ErrorMessage = "Company code cannot exceed 30 characters.")]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Company Code")]
    public string CompanyCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Company name is required.")]
    [StringLength(200)]
    [Display(Name = "Company Name")]
    public string CompanyName { get; set; } = string.Empty;

    [StringLength(250)]
    [Display(Name = "Legal Name")]
    public string? LegalName { get; set; }

    [StringLength(100)]
    [Display(Name = "CR Number")]
    public string? CommercialRegistrationNo { get; set; }

    [StringLength(100)]
    [Display(Name = "Tax Number")]
    public string? TaxNo { get; set; }

    [Display(Name = "Country")]
    public int? CountryId { get; set; }

    [Display(Name = "Default Currency")]
    public int? DefaultCurrencyId { get; set; }

    [StringLength(500)]
    public string? Address { get; set; }

    [StringLength(50)]
    public string? Telephone { get; set; }

    [EmailAddress(ErrorMessage = "Enter a valid email address.")]
    [StringLength(150)]
    public string? Email { get; set; }

    [StringLength(200)]
    public string? Website { get; set; }

    [StringLength(500)]
    [Display(Name = "Logo")]
    public string? LogoPath { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- read-only columns returned by the LIST action ----
    public string? CountryName { get; set; }
    public string? CurrencyCode { get; set; }
    public int BranchCount { get; set; }
    public int EmployeeCount { get; set; }
}
