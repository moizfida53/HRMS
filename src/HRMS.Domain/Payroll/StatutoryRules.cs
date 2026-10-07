using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Payroll;

// ===========================================================================
// Payroll Rules - Kuwait statutory settings (db/29-30). Every row is
// effective-dated (a change = end-date the row and add a new one, so history
// is kept) and carries IsVerified: seeded values must be confirmed by finance.
// ===========================================================================

/// <summary>Payroll.PifssContributionRates - social security (PIFSS) contribution rates.</summary>
public sealed class PifssRate
{
    public int PifssRateId { get; set; }

    [Required(ErrorMessage = "Enter a code.")]
    [StringLength(30)]
    public string ContributionCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter the name.")]
    [StringLength(150)]
    public string ContributionName { get; set; } = string.Empty;

    /// <summary>KUWAITI / GCC / EXPAT / ALL.</summary>
    public string ApplicableTo { get; set; } = "KUWAITI";

    /// <summary>CAPPED (salary up to the ceiling) / BAND (the slice between floor and ceiling).</summary>
    public string CalculationBasis { get; set; } = "CAPPED";

    [Range(0, 100, ErrorMessage = "Enter a rate between 0 and 100.")]
    public decimal EmployeeRate { get; set; }

    [Range(0, 100, ErrorMessage = "Enter a rate between 0 and 100.")]
    public decimal EmployerRate { get; set; }

    [Range(0, 100, ErrorMessage = "Enter a rate between 0 and 100.")]
    public decimal? GovernmentRate { get; set; }

    [Range(0, 999999999, ErrorMessage = "Enter an amount of 0 or more.")]
    public decimal? SalaryFloor { get; set; }

    [Range(0, 999999999, ErrorMessage = "Enter an amount of 0 or more.")]
    public decimal? SalaryCeiling { get; set; }

    [Required(ErrorMessage = "Enter the date it applies from.")]
    public DateTime? EffectiveFrom { get; set; }

    public DateTime? EffectiveTo { get; set; }
    public bool IsVerified { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;
    public bool IsCurrent { get; set; }
}

/// <summary>Payroll.IndemnityRuleSets - end-of-service indemnity rules (header, slabs, factors).</summary>
public sealed class IndemnityRuleSet
{
    public int IndemnityRuleSetId { get; set; }

    [Required(ErrorMessage = "Enter a code.")]
    [StringLength(30)]
    public string RuleSetCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter the name.")]
    [StringLength(150)]
    public string RuleSetName { get; set; } = string.Empty;

    [Range(0.01, 31, ErrorMessage = "Enter the days of a month's wage (1 to 31).")]
    public decimal DailyWageDivisor { get; set; } = 26;

    [Range(0.01, 999, ErrorMessage = "Enter the cap in months (more than 0).")]
    public decimal? MaxIndemnityMonths { get; set; }

    [Range(0, 999, ErrorMessage = "Enter the months of service (0 or more).")]
    public decimal? MinServiceMonths { get; set; }

    [Required(ErrorMessage = "Enter the date it applies from.")]
    public DateTime? EffectiveFrom { get; set; }

    public DateTime? EffectiveTo { get; set; }
    public bool IsVerified { get; set; }

    [StringLength(1000)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;
    public int SlabCount { get; set; }
    public int FactorCount { get; set; }

    public List<IndemnitySlab> Slabs { get; set; } = [];
    public List<IndemnityFactor> Factors { get; set; } = [];

    public bool IsCurrent =>
        EffectiveFrom is { } f && f.Date <= DateTime.Today && (EffectiveTo is null || EffectiveTo.Value.Date >= DateTime.Today);
}

/// <summary>Entitlement per year of service, by band (n DAYS or n MONTHS of wage per year).</summary>
public sealed class IndemnitySlab
{
    [Range(0, 99, ErrorMessage = "Enter the years (0 to 99).")]
    public decimal FromYears { get; set; }

    [Range(0, 99, ErrorMessage = "Enter the years (0 to 99).")]
    public decimal? ToYears { get; set; }

    /// <summary>DAYS / MONTHS.</summary>
    public string EntitlementUnit { get; set; } = "DAYS";

    [Range(0, 9999, ErrorMessage = "Enter 0 or more.")]
    public decimal EntitlementValue { get; set; }
}

/// <summary>% of the computed indemnity paid, by separation type and length of service.</summary>
public sealed class IndemnityFactor
{
    /// <summary>RESIGNATION / TERMINATION / CONTRACT_END / RETIREMENT / DEATH / DISABILITY / OTHER.</summary>
    public string SeparationType { get; set; } = "RESIGNATION";

    [Range(0, 99, ErrorMessage = "Enter the years (0 to 99).")]
    public decimal FromYears { get; set; }

    [Range(0, 99, ErrorMessage = "Enter the years (0 to 99).")]
    public decimal? ToYears { get; set; }

    [Range(0, 100, ErrorMessage = "Enter a percentage between 0 and 100.")]
    public decimal EntitlementPercent { get; set; } = 100;
}

/// <summary>Payroll.OvertimeRates - overtime multipliers (statutory default, or a company's own policy).</summary>
public sealed class OvertimeRate
{
    public int OvertimeRateId { get; set; }

    /// <summary>Null = the statutory default for every company.</summary>
    public int? CompanyId { get; set; }

    /// <summary>NORMAL_DAY / REST_DAY / PUBLIC_HOLIDAY / NIGHT / OTHER.</summary>
    public string OvertimeCode { get; set; } = "NORMAL_DAY";

    [Required(ErrorMessage = "Enter the name.")]
    [StringLength(150)]
    public string OvertimeName { get; set; } = string.Empty;

    [Range(0.001, 10, ErrorMessage = "Enter a multiplier above 0 and up to 10.")]
    public decimal Multiplier { get; set; } = 1.25m;

    [Range(0.01, 31, ErrorMessage = "Enter the days (1 to 31).")]
    public decimal HourlyRateDivisorDays { get; set; } = 26;

    [Range(0.01, 24, ErrorMessage = "Enter the hours (1 to 24).")]
    public decimal HoursPerDay { get; set; } = 8;

    [Range(0, 24, ErrorMessage = "Enter the hours (0 to 24).")]
    public decimal? MaxHoursPerDay { get; set; }

    [Range(0, 9999, ErrorMessage = "Enter the hours (0 or more).")]
    public int? MaxHoursPerYear { get; set; }

    [Required(ErrorMessage = "Enter the date it applies from.")]
    public DateTime? EffectiveFrom { get; set; }

    public DateTime? EffectiveTo { get; set; }
    public bool IsVerified { get; set; }

    [StringLength(500)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;
    public string? CompanyName { get; set; }
    public bool IsCompanyOverride { get; set; }

    public bool IsCurrent =>
        EffectiveFrom is { } f && f.Date <= DateTime.Today && (EffectiveTo is null || EffectiveTo.Value.Date >= DateTime.Today);
}

/// <summary>Codes and lists of the statutory screens.</summary>
public static class StatutoryCodes
{
    public static readonly IReadOnlyList<string> ApplicableTo = ["KUWAITI", "GCC", "EXPAT", "ALL"];
    public static readonly IReadOnlyList<string> Bases = ["CAPPED", "BAND"];
    public static readonly IReadOnlyList<string> SeparationTypes = ["RESIGNATION", "TERMINATION", "CONTRACT_END", "RETIREMENT", "DEATH", "DISABILITY", "OTHER"];
    public static readonly IReadOnlyList<string> OvertimeCodes = ["NORMAL_DAY", "REST_DAY", "PUBLIC_HOLIDAY", "NIGHT", "OTHER"];
}
