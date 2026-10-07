using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Workforce;

/// <summary>
/// One row of the Dependents tab of the Employee Profile screen - a spouse,
/// child or other dependent registered against one employee, typically for
/// health-insurance coverage. Unlike <see cref="EmployeeKuwaitCompliance"/>
/// (a 1:1 record), an employee can have any number of these, so this is a
/// real child list with its own INSERT/UPDATE/DELETE, not a GET/UPSERT pair.
/// </summary>
public sealed class EmployeeDependent
{
    public long DependentId { get; set; }

    public long EmployeeId { get; set; }

    [Required(ErrorMessage = "Full name is required.")]
    [StringLength(150)]
    [Display(Name = "Full Name")]
    public string FullName { get; set; } = string.Empty;

    [Required(ErrorMessage = "Select a relationship.")]
    [StringLength(30)]
    public string Relationship { get; set; } = string.Empty;

    [DataType(DataType.Date)]
    [Display(Name = "Date of Birth")]
    public DateTime? DateOfBirth { get; set; }

    [StringLength(1)]
    [RegularExpression("^[MF]$", ErrorMessage = "Select a gender.")]
    public string? Gender { get; set; }

    [Display(Name = "Health Insurance Coverage")]
    public bool HasHealthInsurance { get; set; }
}
