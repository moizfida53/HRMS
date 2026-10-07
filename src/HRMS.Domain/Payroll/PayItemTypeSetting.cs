using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Payroll;

/// <summary>
/// A pay item type (Payroll.PayComponents, db/29-30): an earning or deduction
/// offered when adding a pay item, with the flags the payroll engine reads
/// (PIFSS, end-of-service, overtime, leave salary, prorated, recurring).
/// Standard types carry a SystemCode the engine recognises - they can be
/// renamed and re-flagged but not deleted (Basic Salary not even deactivated).
/// </summary>
public sealed class PayItemTypeSetting
{
    public int PayComponentId { get; set; }

    [Required(ErrorMessage = "Select the company.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select the company.")]
    public int CompanyId { get; set; }

    [Required(ErrorMessage = "Enter a code.")]
    [StringLength(30, ErrorMessage = "The code can be at most 30 characters.")]
    [RegularExpression(@"^[A-Za-z0-9_\-]+$", ErrorMessage = "Use letters, digits, - and _ only.")]
    public string ComponentCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter the name.")]
    [StringLength(150)]
    public string ComponentName { get; set; } = string.Empty;

    [StringLength(150)]
    public string? ArabicName { get; set; }

    [StringLength(100)]
    public string? PayslipLabel { get; set; }

    /// <summary>EARNING / DEDUCTION.</summary>
    public string ComponentType { get; set; } = "EARNING";

    /// <summary>FIXED / VARIABLE.</summary>
    public string ValueType { get; set; } = "FIXED";

    /// <summary>AMOUNT / PERCENTAGE / DAYS / HOURS / FORMULA / SYSTEM.</summary>
    public string CalculationMethod { get; set; } = "AMOUNT";

    /// <summary>BASIC / FIXED_GROSS / OVERTIME_BASE / INDEMNITY_BASE.</summary>
    public string? CalculationBase { get; set; }

    [Range(0, 999999999, ErrorMessage = "Enter an amount of 0 or more.")]
    public decimal? DefaultAmount { get; set; }

    [Range(0, 1000, ErrorMessage = "Enter a percentage between 0 and 1000.")]
    public decimal? DefaultPercentage { get; set; }

    [StringLength(1000)]
    public string? Formula { get; set; }

    [Range(0, 999999999, ErrorMessage = "Enter an amount of 0 or more.")]
    public decimal? MinAmount { get; set; }

    [Range(0, 999999999, ErrorMessage = "Enter an amount of 0 or more.")]
    public decimal? MaxAmount { get; set; }

    public bool IsTaxable { get; set; }
    public bool IsPifssApplicable { get; set; }
    public bool IsIndemnityApplicable { get; set; }
    public bool IsOvertimeApplicable { get; set; }
    public bool IsLeaveSalaryApplicable { get; set; }
    public bool IsRecurring { get; set; } = true;
    public bool IsProrated { get; set; } = true;
    public bool ShowOnPayslip { get; set; } = true;

    [StringLength(50)]
    public string? GLAccountCode { get; set; }

    [StringLength(150)]
    public string? GLAccountName { get; set; }

    public int? CostCenterId { get; set; }

    [Range(0, 32000, ErrorMessage = "Enter a display order between 0 and 32000.")]
    public short DisplayOrder { get; set; } = 100;

    [StringLength(500)]
    public string? Description { get; set; }

    public bool IsActive { get; set; } = true;

    // ---- read only ----
    public string? SystemCode { get; set; }
    public bool IsSystem { get; set; }
    public string? CompanyName { get; set; }
    public string? CostCenterName { get; set; }
    public int StructureCount { get; set; }

    /// <summary>SALARY / EARNING / DEDUCTION / LOAN / STATUTORY - how it is grouped (same rule as the ItemClass column of db/34).</summary>
    public string ItemClass => SystemCode switch
    {
        "PIFSS_EE" => "STATUTORY",
        "LOAN" or "SALARY_ADVANCE" => "LOAN",
        _ when ComponentType == "EARNING" && IsRecurring && ValueType == "FIXED" => "SALARY",
        _ when ComponentType == "EARNING" => "EARNING",
        _ => "DEDUCTION"
    };

    public bool IsStandard => SystemCode is not null;
    public bool IsBasic => SystemCode == "BASIC";
}

/// <summary>Filter of the pay item types list.</summary>
public sealed class PayItemTypeFilter
{
    public int? CompanyId { get; init; }
    public string? CompanyIds { get; init; }
    public string? Search { get; init; }
    /// <summary>EARNING / DEDUCTION, or null for both.</summary>
    public string? ComponentType { get; init; }
    public bool? IsActive { get; init; }
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 50;
}
