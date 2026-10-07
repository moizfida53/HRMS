using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Organization;

/// <summary>
/// A physical work site - office floor, warehouse, site camp, clinic.
/// Used for attendance-device placement and cost reporting.
/// </summary>
public sealed class Location
{
    public int LocationId { get; set; }

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Display(Name = "Branch")]
    public int? BranchId { get; set; }

    [Required(ErrorMessage = "Location code is required.")]
    [StringLength(50)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Location Code")]
    public string LocationCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Location name is required.")]
    [StringLength(150)]
    [Display(Name = "Location Name")]
    public string LocationName { get; set; } = string.Empty;

    [StringLength(50)]
    [Display(Name = "Location Type")]
    public string? LocationType { get; set; }

    [StringLength(100)]
    public string? Governorate { get; set; }

    [StringLength(100)]
    public string? Area { get; set; }

    [StringLength(30)]
    public string? Block { get; set; }

    [StringLength(150)]
    public string? Street { get; set; }

    [StringLength(50)]
    public string? Building { get; set; }

    [Range(-90, 90, ErrorMessage = "Latitude must be between -90 and 90.")]
    public decimal? Latitude { get; set; }

    [Range(-180, 180, ErrorMessage = "Longitude must be between -180 and 180.")]
    public decimal? Longitude { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST-only columns ----
    public string? CompanyName { get; set; }
    public string? BranchName { get; set; }
}
