using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Payroll;

// ===========================================================================
// Payroll Settings - the rule screens (db/47-48): deduction rules, proration,
// approval workflow, bank file formats and GL mapping. Configuration only:
// the payroll engine keeps its current behaviour until it reads these.
// ===========================================================================

/// <summary>Payroll.DeductionPolicies - the deduction limit and recovery order.</summary>
public sealed class DeductionPolicy
{
    public int DeductionPolicyId { get; set; }

    /// <summary>Null = the default for every company.</summary>
    public int? CompanyId { get; set; }

    /// <summary>Null = every calendar of the company.</summary>
    public int? PayrollCalendarId { get; set; }

    [Range(0.01, 100, ErrorMessage = "Enter a percentage above 0 and up to 100.")]
    public decimal MaxDeductionPercent { get; set; } = 50;

    /// <summary>DEFER (defer in reverse priority order) / WARN (warn only).</summary>
    public string WhenExceeded { get; set; } = "DEFER";

    [StringLength(500)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;

    public string? CompanyName { get; set; }
    public string? CalendarName { get; set; }
    public bool IsDefault { get; set; }

    /// <summary>The groups in recovery order, comma separated (lists).</summary>
    public string? PriorityOrder { get; set; }

    /// <summary>Top = recovered first.</summary>
    public List<DeductionPriority> Priorities { get; set; } = [];
}

public sealed class DeductionPriority
{
    /// <summary>STATUTORY / ABSENCE / STANDING / ADVANCE / LOAN / ONE_TIME.</summary>
    public string DeductionGroup { get; set; } = "STANDING";

    /// <summary>ALWAYS (never deferred) / TAKEN / DEFER.</summary>
    public string Behaviour { get; set; } = "TAKEN";
}

/// <summary>A payroll calendar with its proration rule (Payroll.ProrationRules; defaults until first saved).</summary>
public sealed class ProrationRule
{
    public int PayrollCalendarId { get; set; }
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string? CalendarCode { get; set; }
    public string? CalendarName { get; set; }
    public string? PayFrequency { get; set; }

    /// <summary>CALENDAR / FIXED / WORKING (kept on the calendar).</summary>
    public string WorkingDaysBasis { get; set; } = "FIXED";

    [Range(1, 31, ErrorMessage = "Enter the days per month (1 to 31).")]
    public byte? FixedDaysPerMonth { get; set; } = 26;

    public bool IsActive { get; set; } = true;
    public bool HasRule { get; set; }

    public bool ProrateJoiners { get; set; } = true;
    public bool ProrateLeavers { get; set; } = true;
    public bool ProrateRevisions { get; set; } = true;
    public bool ProrateUnpaidLeave { get; set; } = true;
    public bool ExcludeRestDays { get; set; } = true;

    [StringLength(500)]
    public string? Notes { get; set; }
}

/// <summary>Payroll.ApprovalProcesses - who approves a process (level 1, optional level 2).</summary>
public sealed class ApprovalProcess
{
    public int ApprovalProcessId { get; set; }

    /// <summary>PAYROLL_RUN / SALARY_REVISION / LOAN / SALARY_ADVANCE / PAYROLL_ADJUSTMENT / FINAL_SETTLEMENT.</summary>
    public string ProcessCode { get; set; } = "PAYROLL_RUN";

    /// <summary>Null = the default for every company.</summary>
    public int? CompanyId { get; set; }

    public int? Level1RoleId { get; set; }
    public long? Level1DelegateUserId { get; set; }
    public int? Level2RoleId { get; set; }
    public long? Level2DelegateUserId { get; set; }

    /// <summary>Null = level 2 always; else only above this amount (KWD).</summary>
    [Range(0, 999999999, ErrorMessage = "Enter an amount of 0 or more.")]
    public decimal? Level2AboveAmount { get; set; }

    public bool AllowSelfApproval { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;

    public string? CompanyName { get; set; }
    public string? Level1RoleName { get; set; }
    public string? Level1DelegateName { get; set; }
    public string? Level2RoleName { get; set; }
    public string? Level2DelegateName { get; set; }
    public bool IsDefault { get; set; }
}

/// <summary>Payroll.BankFileFormats - the salary (WPS) file layout of a bank.</summary>
public sealed class BankFileFormat
{
    public int BankFileFormatId { get; set; }

    [Required(ErrorMessage = "Enter a code.")]
    [StringLength(30)]
    public string FormatCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter the name.")]
    [StringLength(150)]
    public string FormatName { get; set; } = string.Empty;

    /// <summary>Null = a general format (the default is used for banks without their own).</summary>
    public int? BankId { get; set; }

    /// <summary>CSV / TXT / FIXED.</summary>
    public string FileType { get; set; } = "CSV";

    [StringLength(3)]
    public string? Delimiter { get; set; } = ",";

    public bool HasHeader { get; set; } = true;
    public bool HasTrailer { get; set; }

    [StringLength(100)]
    public string? FileNamePattern { get; set; }

    public bool IsDefault { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;

    public string? BankName { get; set; }
    public int FieldCount { get; set; }

    public List<BankFileField> Fields { get; set; } = [];
}

public sealed class BankFileField
{
    [StringLength(50)]
    public string FieldName { get; set; } = string.Empty;

    public string SourceCode { get; set; } = "EMPLOYEE_CODE";

    [StringLength(100)]
    public string? ConstantValue { get; set; }

    [Range(1, 500, ErrorMessage = "Enter a width from 1 to 500.")]
    public short? Width { get; set; }

    [StringLength(1)]
    public string? PadChar { get; set; }

    public bool AlignRight { get; set; }
}

/// <summary>Payroll.GLMappings - the debit / credit GL accounts of a pay item type.</summary>
public sealed class GLMapping
{
    public int GLMappingId { get; set; }

    [Range(1, int.MaxValue, ErrorMessage = "Select the pay item type.")]
    public int PayComponentId { get; set; }

    /// <summary>Null = any cost center.</summary>
    public int? CostCenterId { get; set; }

    [Required(ErrorMessage = "Enter the debit account.")]
    [StringLength(50)]
    public string DebitAccountCode { get; set; } = string.Empty;

    [StringLength(150)]
    public string? DebitAccountName { get; set; }

    [Required(ErrorMessage = "Enter the credit account.")]
    [StringLength(50)]
    public string CreditAccountCode { get; set; } = string.Empty;

    [StringLength(150)]
    public string? CreditAccountName { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;

    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string? ComponentCode { get; set; }
    public string? ComponentName { get; set; }
    public string? ComponentType { get; set; }
    public string? CostCenterName { get; set; }
}

/// <summary>Codes of the rule screens.</summary>
public static class PayrollRuleCodes
{
    public static readonly IReadOnlyList<string> DeductionGroups = ["STATUTORY", "ABSENCE", "STANDING", "ADVANCE", "LOAN", "ONE_TIME"];
    public static readonly IReadOnlyList<string> Behaviours = ["ALWAYS", "TAKEN", "DEFER"];
    public static readonly IReadOnlyList<string> DayBases = ["FIXED", "CALENDAR", "WORKING"];
    public static readonly IReadOnlyList<string> Processes = ["PAYROLL_RUN", "SALARY_REVISION", "LOAN", "SALARY_ADVANCE", "PAYROLL_ADJUSTMENT", "FINAL_SETTLEMENT"];
    public static readonly IReadOnlyList<string> FileTypes = ["CSV", "TXT", "FIXED"];

    public static readonly IReadOnlyList<string> FieldSources =
    [
        "EMPLOYER_CODE", "PAM_FILE_NO", "EMPLOYEE_CODE", "CIVIL_ID", "EMPLOYEE_NAME", "BANK_WPS_CODE", "BANK_SWIFT", "IBAN", "ACCOUNT_NO",
        "NET_AMOUNT", "BASIC_AMOUNT", "ALLOWANCES", "DEDUCTIONS", "PERIOD_YYYYMM", "PAY_DATE", "DEBIT_IBAN", "CONSTANT"
    ];

    /// <summary>The default recovery order of a new deduction rule.</summary>
    public static List<DeductionPriority> DefaultPriorities() =>
    [
        new() { DeductionGroup = "STATUTORY", Behaviour = "ALWAYS" },
        new() { DeductionGroup = "ABSENCE", Behaviour = "ALWAYS" },
        new() { DeductionGroup = "STANDING", Behaviour = "TAKEN" },
        new() { DeductionGroup = "ADVANCE", Behaviour = "DEFER" },
        new() { DeductionGroup = "LOAN", Behaviour = "DEFER" },
        new() { DeductionGroup = "ONE_TIME", Behaviour = "DEFER" }
    ];
}
