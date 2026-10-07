using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Workforce;

/// <summary>
/// Kuwait Compliance tab of the Employee Profile screen - Civil ID,
/// passport, residency (iqama), work permit and PACI address. A 1:1
/// record keyed by EmployeeId; it may not exist yet for a newly created
/// employee, which is a normal state, not an error.
/// </summary>
public sealed class EmployeeKuwaitCompliance
{
    public long EmployeeId { get; set; }

    // ---------------------------------------------------------------
    // Civil ID
    // ---------------------------------------------------------------

    [StringLength(20)]
    [RegularExpression(@"^\d{0,12}$", ErrorMessage = "Civil ID is numeric, up to 12 digits.")]
    [Display(Name = "Civil ID Number")]
    public string? CivilIdNumber { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Civil ID Expiry")]
    public DateTime? CivilIdExpiryDate { get; set; }

    // ---------------------------------------------------------------
    // Passport
    // ---------------------------------------------------------------

    [StringLength(30)]
    [Display(Name = "Passport Number")]
    public string? PassportNumber { get; set; }

    [Display(Name = "Passport Issuing Country")]
    public int? PassportCountryId { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Passport Expiry")]
    public DateTime? PassportExpiryDate { get; set; }

    // ---------------------------------------------------------------
    // Residency (iqama)
    // ---------------------------------------------------------------

    [StringLength(30)]
    [Display(Name = "Residency Number")]
    public string? ResidencyNumber { get; set; }

    [StringLength(50)]
    [Display(Name = "Residency Type")]
    public string? ResidencyType { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Residency Expiry")]
    public DateTime? ResidencyExpiryDate { get; set; }

    [StringLength(200)]
    [Display(Name = "Sponsor Name")]
    public string? SponsorName { get; set; }

    [StringLength(50)]
    [Display(Name = "Sponsor File Number")]
    public string? SponsorFileNumber { get; set; }

    /// <summary>Company Sponsor / Family Sponsor / Self Sponsor ... (db/20)</summary>
    [StringLength(50)]
    [Display(Name = "Sponsor Status")]
    public string? SponsorStatus { get; set; }

    /// <summary>Valid / Under Process / Expired / Cancelled (db/20)</summary>
    [StringLength(30)]
    [Display(Name = "Residency Status")]
    public string? ResidencyStatus { get; set; }

    // ---------------------------------------------------------------
    // Ministry of Labour / work permit
    // ---------------------------------------------------------------

    [StringLength(50)]
    [Display(Name = "MOL File Number")]
    public string? MolFileNumber { get; set; }

    [StringLength(50)]
    [Display(Name = "Work Permit Number")]
    public string? WorkPermitNumber { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Work Permit Expiry")]
    public DateTime? WorkPermitExpiryDate { get; set; }

    // ---------------------------------------------------------------
    // PACI civil address
    // ---------------------------------------------------------------

    [StringLength(20)]
    [Display(Name = "PACI Number")]
    public string? PaciNumber { get; set; }

    [StringLength(300)]
    [Display(Name = "PACI Address")]
    public string? PaciAddress { get; set; }

    // ---------------------------------------------------------------
    // Driving and medical
    // ---------------------------------------------------------------

    [StringLength(30)]
    [Display(Name = "Driving License Number")]
    public string? DrivingLicenseNumber { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Driving License Expiry")]
    public DateTime? DrivingLicenseExpiryDate { get; set; }

    [StringLength(5)]
    [Display(Name = "Blood Type")]
    public string? BloodType { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Health Certificate Expiry")]
    public DateTime? HealthCertificateExpiry { get; set; }

    // ---- GET-only display columns ----
    public string? PassportCountryName { get; set; }
}
