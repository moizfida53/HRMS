using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Workforce;

/// <summary>
/// The Employee master - Personal Info and Employment tabs of the Employee
/// Profile screen. Kuwait Compliance is a separate 1:1 record
/// (<see cref="EmployeeKuwaitCompliance"/>), not more properties on this
/// class, because it comes from a different table with its own procedure.
/// </summary>
public sealed class Employee
{
    public long EmployeeId { get; set; }

    [StringLength(20)]
    [Display(Name = "Employee Code")]
    public string? EmployeeCode { get; set; }

    /// <summary>
    /// Pre-existing NOT NULL identifier column from the base schema (not
    /// created by this project, distinct from <see cref="EmployeeCode"/>).
    /// Entered directly on the form - see db/16_Employee_Manage_EmployeeNo.sql.
    /// </summary>
    [Required(ErrorMessage = "Employee No is required.")]
    [StringLength(20)]
    [Display(Name = "Employee No")]
    public string EmployeeNo { get; set; } = string.Empty;

    // ---------------------------------------------------------------
    // Personal info
    // ---------------------------------------------------------------

    [Required(ErrorMessage = "First name is required.")]
    [StringLength(100)]
    [Display(Name = "First Name")]
    public string FirstName { get; set; } = string.Empty;

    [StringLength(100)]
    [Display(Name = "Middle Name")]
    public string? MiddleName { get; set; }

    [StringLength(100)]
    [Display(Name = "Last Name")]
    public string? LastName { get; set; }

    [StringLength(300)]
    [Display(Name = "Name (Arabic)")]
    public string? ArabicName { get; set; }

    [StringLength(1)]
    [RegularExpression("^[MF]$", ErrorMessage = "Select a gender.")]
    public string? Gender { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Date of Birth")]
    public DateTime? DateOfBirth { get; set; }

    [StringLength(20)]
    [Display(Name = "Marital Status")]
    public string? MaritalStatus { get; set; }

    [Display(Name = "Nationality")]
    public int? NationalityCountryId { get; set; }

    [StringLength(50)]
    public string? Religion { get; set; }

    [StringLength(5)]
    [Display(Name = "Blood Group")]
    public string? BloodGroup { get; set; }

    [StringLength(20)]
    [Display(Name = "Mobile Number")]
    public string? MobileNumber { get; set; }

    [StringLength(10)]
    public string? Extension { get; set; }

    [EmailAddress(ErrorMessage = "Enter a valid email address.")]
    [StringLength(150)]
    [Display(Name = "Personal Email")]
    public string? PersonalEmail { get; set; }

    [EmailAddress(ErrorMessage = "Enter a valid email address.")]
    [StringLength(150)]
    [Display(Name = "Work Email")]
    public string? WorkEmail { get; set; }

    /// <summary>
    /// Legacy free-text address. No longer shown on the Personal Info form -
    /// replaced there by the structured PACI-style fields below - but the
    /// column and this property are kept so nothing already saved is lost.
    /// </summary>
    [StringLength(500)]
    public string? Address { get; set; }

    [StringLength(100)]
    public string? Neighborhood { get; set; }

    [StringLength(20)]
    public string? Block { get; set; }

    [StringLength(150)]
    [Display(Name = "Street Name")]
    public string? StreetName { get; set; }

    [StringLength(30)]
    [Display(Name = "Building / Villa Number")]
    public string? BuildingNumber { get; set; }

    [StringLength(20)]
    [Display(Name = "Floor Number")]
    public string? FloorNumber { get; set; }

    [StringLength(20)]
    [Display(Name = "Flat Number")]
    public string? FlatNumber { get; set; }

    [StringLength(20)]
    [Display(Name = "PACI Number")]
    public string? PaciNumber { get; set; }

    [StringLength(200)]
    public string? Landmark { get; set; }

    [StringLength(300)]
    public string? PhotoPath { get; set; }

    [StringLength(150)]
    [Display(Name = "Emergency Contact Name")]
    public string? EmergencyContactName { get; set; }

    [StringLength(20)]
    [Display(Name = "Emergency Contact Phone")]
    public string? EmergencyContactPhone { get; set; }

    [StringLength(50)]
    [Display(Name = "Relationship")]
    public string? EmergencyContactRelation { get; set; }

    // ---------------------------------------------------------------
    // Father's details
    // ---------------------------------------------------------------

    [StringLength(150)]
    [Display(Name = "Father's Name")]
    public string? FatherName { get; set; }

    [StringLength(100)]
    [Display(Name = "Father's Occupation")]
    public string? FatherOccupation { get; set; }

    [StringLength(20)]
    [Display(Name = "Father's Mobile Number")]
    public string? FatherMobileNumber { get; set; }

    [Display(Name = "Father Deceased")]
    public bool FatherIsDeceased { get; set; }

    [Display(Name = "Currently Residing In")]
    public int? CurrentResidenceCountryId { get; set; }

    // Passport and Civil ID are intentionally NOT duplicated here - the
    // Kuwait Compliance tab already owns Passport Number/Country/Expiry and
    // Civil ID Number/Expiry (see Kuwait.EmployeeCompliance /
    // EmployeeKuwaitCompliance). A first attempt added a second,
    // general-HR-record copy of these fields to Personal Info (following the
    // same two-columns-not-one reasoning already used for BloodGroup/
    // PaciNumber) - the user asked for that to be removed as redundant, so
    // Personal Info no longer collects or shows Passport/Civil ID data at
    // all; edit those exclusively on Kuwait Compliance. The underlying
    // Employee.Employees columns from db/17 and the usp_Employee_Manage
    // parameters from db/18 still exist in the database (never edit an
    // already-shipped script in place) but are unused/dead by design - see
    // architecture_decisions.md for the full history.

    // ---------------------------------------------------------------
    // Employment
    // ---------------------------------------------------------------

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Display(Name = "Branch")]
    public int? BranchId { get; set; }

    [Display(Name = "Department")]
    public int? DepartmentId { get; set; }

    [Display(Name = "Section")]
    public int? SectionId { get; set; }

    [Display(Name = "Job Position")]
    public int? PositionId { get; set; }

    [Display(Name = "Designation")]
    public int? DesignationId { get; set; }

    [Display(Name = "Grade")]
    public int? GradeId { get; set; }

    [Display(Name = "Cost Center")]
    public int? CostCenterId { get; set; }

    [Display(Name = "Work Location")]
    public int? WorkLocationId { get; set; }

    [Display(Name = "Reporting Manager")]
    public long? ReportingManagerId { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Hire Date")]
    public DateTime? HireDate { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Probation End Date")]
    public DateTime? ProbationEndDate { get; set; }

    [DataType(DataType.Date)]
    [Display(Name = "Termination Date")]
    public DateTime? TerminationDate { get; set; }

    [StringLength(20)]
    [Display(Name = "Employment Type")]
    public string? EmploymentType { get; set; }

    [StringLength(20)]
    [Display(Name = "Employment Status")]
    public string EmploymentStatus { get; set; } = "Active";

    [Range(0, 365, ErrorMessage = "Enter a notice period between 0 and 365 days.")]
    [Display(Name = "Notice Period (Days)")]
    public int? NoticePeriodDays { get; set; }

    // ---------------------------------------------------------------
    // Company contact & assets (db/20)
    // ---------------------------------------------------------------

    [StringLength(20)]
    [Phone]
    [Display(Name = "Company Phone")]
    public string? CompanyPhone { get; set; }

    [StringLength(300)]
    [Display(Name = "Company Assets")]
    public string? CompanyAssets { get; set; }

    // ---------------------------------------------------------------
    // Payroll & bank (db/20) - stored in Employee.EmployeePayroll (1:1),
    // read and written through usp_Employee_Manage with the rest of the
    // Employment tab.
    // ---------------------------------------------------------------

    [Range(typeof(decimal), "0", "999999999.999", ErrorMessage = "Enter a basic salary of 0 or more.")]
    [Display(Name = "Basic Salary (KWD)")]
    public decimal? BasicSalary { get; set; }

    [Range(typeof(decimal), "0", "999999999.999", ErrorMessage = "Enter allowances of 0 or more.")]
    [Display(Name = "Allowances (KWD)")]
    public decimal? Allowances { get; set; }

    [StringLength(100)]
    [Display(Name = "Bank Name")]
    public string? BankName { get; set; }

    [StringLength(34)]
    [RegularExpression(@"^[A-Za-z0-9 ]*$", ErrorMessage = "IBAN / account number can contain letters, digits and spaces only.")]
    [Display(Name = "IBAN / Account No.")]
    public string? Iban { get; set; }

    /// <summary>Basic + allowances, for display only.</summary>
    public decimal? GrossSalary =>
        BasicSalary is null && Allowances is null ? null : (BasicSalary ?? 0) + (Allowances ?? 0);

    /// <summary>Inverse of the row's IsDeleted flag - true means not deleted.</summary>
    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST / GET-only display columns ----
    public string? FullName { get; set; }
    public string? CompanyName { get; set; }
    public string? BranchName { get; set; }
    public string? DepartmentName { get; set; }
    public string? SectionName { get; set; }
    public string? PositionName { get; set; }
    public string? DesignationName { get; set; }
    public string? GradeName { get; set; }
    public string? CostCenterName { get; set; }
    public string? LocationName { get; set; }
    public string? CurrentResidenceCountryName { get; set; }
    public string? ReportingManagerName { get; set; }
    public string? NationalityName { get; set; }
}
