namespace HRMS.Domain.Payroll;

/// <summary>Separation types of a final settlement (Payroll.FinalSettlements.SettlementType).</summary>
public static class SettlementType
{
    public const string Resignation = "RESIGNATION";
    public const string Termination = "TERMINATION";
    public const string ContractEnd = "CONTRACT_END";
    public const string Retirement = "RETIREMENT";
    public const string Death = "DEATH";
    public const string Disability = "DISABILITY";
    /// <summary>Leave encashment without exit.</summary>
    public const string Encashment = "ENCASHMENT";

    /// <summary>The exit types, in the order the form offers them.</summary>
    public static readonly IReadOnlyList<string> Exit = [Resignation, Termination, ContractEnd, Retirement, Death, Disability];

    public static readonly IReadOnlyList<string> All = [.. Exit, Encashment];

    public static bool IsExit(string? type) => type is not null && type != Encashment && All.Contains(type);

    public static string Label(string? type) => type switch
    {
        Resignation => "Resignation",
        Termination => "Termination",
        ContractEnd => "End of contract",
        Retirement => "Retirement",
        Death => "Death",
        Disability => "Disability",
        Encashment => "Leave encashment",
        _ => "Other"
    };
}

public static class SettlementStatus
{
    public const string Draft = "DRAFT";
    public const string Pending = "PENDING";
    public const string Approved = "APPROVED";
    public const string Paid = "PAID";
    public const string Cancelled = "CANCELLED";
}

public static class SettlementSection
{
    public const string Salary = "SALARY";
    public const string Earning = "EARNING";
    public const string Leave = "LEAVE";
    public const string Indemnity = "INDEMNITY";
    public const string Recovery = "RECOVERY";
}

public static class PaymentMethod
{
    public const string Bank = "BANK";
    public const string Cheque = "CHEQUE";
    public const string Cash = "CASH";
    public const string Payroll = "PAYROLL";

    public static readonly IReadOnlyList<string> All = [Bank, Cheque, Cash, Payroll];

    public static string Label(string? method) => method switch
    {
        Bank => "Bank transfer",
        Cheque => "Cheque",
        Cash => "Cash",
        Payroll => "Through payroll",
        _ => "—"
    };
}

/// <summary>One row of the settlements list.</summary>
public sealed class FinalSettlementRow
{
    public long FinalSettlementId { get; init; }
    public string SettlementNo { get; init; } = string.Empty;
    public int CompanyId { get; init; }
    public string? CompanyName { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public string? DepartmentName { get; init; }
    public string SettlementType { get; init; } = Payroll.SettlementType.Resignation;
    public string Status { get; init; } = SettlementStatus.Draft;
    public int ApprovalLevel { get; init; }
    public DateTime LastWorkingDay { get; init; }
    public int ServiceDays { get; init; }
    public decimal ServiceYears { get; init; }
    public decimal EncashDays { get; init; }
    public DateTime? PayMonth { get; init; }
    public decimal NetPayable { get; init; }
    public DateTime? PaidDate { get; init; }
    public string? PaymentMethod { get; init; }
    public long? SubmittedBy { get; init; }
    public DateTime CreatedDate { get; init; }
    public bool RuleSetVerified { get; init; }

    public bool IsExit => Payroll.SettlementType.IsExit(SettlementType);
}

/// <summary>A settlement with everything its pages and statement show.</summary>
public sealed class FinalSettlement
{
    public long FinalSettlementId { get; init; }
    public int CompanyId { get; init; }
    public long EmployeeId { get; init; }
    public string SettlementNo { get; init; } = string.Empty;
    public string SettlementType { get; init; } = Payroll.SettlementType.Resignation;
    public string Status { get; init; } = SettlementStatus.Draft;
    public int ApprovalLevel { get; init; }

    public DateTime LastWorkingDay { get; init; }
    public DateTime? NoticeDate { get; init; }
    public string? Reason { get; init; }
    public DateTime? SalaryFrom { get; init; }
    public decimal LeaveBalanceDays { get; init; }
    public decimal EncashDays { get; init; }
    public DateTime? PayMonth { get; init; }

    public DateTime? HireDate { get; init; }
    public int ServiceDays { get; init; }
    public decimal ServiceYears { get; init; }
    public bool IsKuwaiti { get; init; }
    public decimal MonthlySalary { get; init; }
    public decimal IndemnityBase { get; init; }
    public decimal LeaveBase { get; init; }
    public decimal DailyDivisor { get; init; }
    public bool SalaryFromProfile { get; init; }
    public int? IndemnityRuleSetId { get; init; }
    public bool RuleSetVerified { get; init; }
    public decimal IndemnityGross { get; init; }
    public decimal? IndemnityCap { get; init; }
    public decimal IndemnityPercent { get; init; }
    public bool BelowMinService { get; init; }

    public decimal PendingSalaryAmount { get; init; }
    public decimal OtherEarningsAmount { get; init; }
    public decimal LeaveAmount { get; init; }
    public decimal IndemnityAmount { get; init; }
    public decimal RecoveryAmount { get; init; }
    public decimal NetPayable { get; init; }
    public DateTime? CalculatedDate { get; init; }

    public bool AckUnverified { get; init; }
    public long? SubmittedBy { get; init; }
    public DateTime? SubmittedDate { get; init; }
    public long? ApprovedBy { get; init; }
    public DateTime? ApprovedDate { get; init; }
    public DateTime? PaidDate { get; init; }
    public string? PaymentMethod { get; init; }
    public string? PaymentRef { get; init; }
    public long? PayItemId { get; init; }
    public DateTime? PayItemMonth { get; init; }
    public DateTime? CancelledDate { get; init; }
    public string? CancelReason { get; init; }
    public long? CreatedBy { get; init; }
    public DateTime CreatedDate { get; init; }

    // ---- joined ----
    public string? CompanyName { get; init; }
    public string? CompanyArabicName { get; init; }
    public string? CompanyCode { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public string? EmploymentStatus { get; init; }
    public int? NoticePeriodDays { get; init; }
    public string? DepartmentName { get; init; }
    public string? DepartmentArabicName { get; init; }
    public string? DesignationName { get; init; }
    public string? DesignationArabicName { get; init; }
    public string? NationalityName { get; init; }
    public string? RuleSetCode { get; init; }
    public string? RuleSetName { get; init; }
    public DateTime? PaidThrough { get; init; }
    public string? PaidByRun { get; init; }
    public string? SubmittedByName { get; init; }
    public string? ApprovedByName { get; init; }
    public string? PaidByName { get; init; }
    public string? CreatedByName { get; init; }

    public bool IsExit => Payroll.SettlementType.IsExit(SettlementType);
    public bool IsDraft => Status == SettlementStatus.Draft;
    public bool IsPending => Status == SettlementStatus.Pending;
    public bool IsApproved => Status == SettlementStatus.Approved;
    public bool IsPaid => Status == SettlementStatus.Paid;
    public bool IsCancelled => Status == SettlementStatus.Cancelled;

    /// <summary>Gross indemnity before the entitlement %: capped when the cap is reached.</summary>
    public decimal IndemnityCapped => IndemnityCap is { } cap && IndemnityGross > cap ? cap : IndemnityGross;
    public bool CapReached => IndemnityCap is { } cap && IndemnityGross > cap;

    /// <summary>Everything paid before recoveries.</summary>
    public decimal GrossPayable => PendingSalaryAmount + OtherEarningsAmount + LeaveAmount + IndemnityAmount;
}

/// <summary>One line of a settlement (Amount signed: recoveries negative).</summary>
public sealed class FinalSettlementLine
{
    public long SettlementLineId { get; init; }
    public long FinalSettlementId { get; init; }
    public string Section { get; init; } = SettlementSection.Salary;
    public string LineCode { get; init; } = "SALARY";
    public bool IsManual { get; init; }
    public bool IsInfo { get; init; }
    public bool IsIncluded { get; init; } = true;
    public string? Description { get; init; }
    public string? ArabicDescription { get; init; }
    public int? PayComponentId { get; init; }
    public long? EmployeePayItemId { get; init; }
    public string? SourceRef { get; init; }
    public DateTime? PeriodFrom { get; init; }
    public DateTime? PeriodTo { get; init; }
    public decimal? Quantity { get; init; }
    public decimal? Rate { get; init; }
    public decimal? Basis { get; init; }
    public decimal? FromYears { get; init; }
    public decimal? ToYears { get; init; }
    public string? Unit { get; init; }
    public decimal Amount { get; init; }
    public int DisplayOrder { get; init; }

    /// <summary>Pay item and loan lines can be waived (left out) by the user.</summary>
    public bool IsWaivable => !IsManual && LineCode is "PAY_ITEM" or "LOAN";
}

public sealed class FinalSettlementHistoryEntry
{
    public long SettlementHistoryId { get; init; }
    public long FinalSettlementId { get; init; }
    public string ActionCode { get; init; } = "CREATED";
    public int? ApprovalLevel { get; init; }
    public decimal? NetPayable { get; init; }
    public string? Comment { get; init; }
    public long? ActionBy { get; init; }
    public DateTime ActionDate { get; init; }
    public string? ActionByName { get; init; }
}

/// <summary>Key figures of the settlements page.</summary>
public sealed class FinalSettlementSummary
{
    public int DraftCount { get; init; }
    public int PendingCount { get; init; }
    public int PendingHrCount { get; init; }
    public int PendingFinanceCount { get; init; }
    public int ApprovedCount { get; init; }
    public decimal ApprovedAmount { get; init; }
    public int PaidCount { get; init; }
    public decimal PaidAmount { get; init; }
    public decimal OpenIndemnity { get; init; }
}

/// <summary>An employee in the picker of the settlement form.</summary>
public sealed class SettlementEmployeeOption
{
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public int CompanyId { get; init; }
    public string? EmploymentStatus { get; init; }
    public DateTime? HireDate { get; init; }
    public string? OpenSettlementNo { get; init; }
    public long? OpenSettlementId { get; init; }

    public bool HasLeft => EmploymentStatus is "Terminated" or "Resigned";
}

/// <summary>What step 1 of the form shows once an employee and last day are chosen.</summary>
public sealed class SettlementDefaults
{
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public DateTime? HireDate { get; init; }
    public string? EmploymentStatus { get; init; }
    public int? NoticePeriodDays { get; init; }
    public string? DepartmentName { get; init; }
    public string? DesignationName { get; init; }
    public int ServiceDays { get; init; }
    public decimal MonthlySalary { get; init; }
    public decimal IndemnityBase { get; init; }
    public decimal LeaveBase { get; init; }
    public DateTime? PaidThrough { get; init; }
    public string? PaidByRun { get; init; }
    public DateTime? DefaultSalaryFrom { get; init; }
    public string? RuleSetCode { get; init; }
    public bool RuleSetVerified { get; init; }
    public string? OpenSettlementNo { get; init; }
    public long? OpenSettlementId { get; init; }
}

/// <summary>What the settlement form posts.</summary>
public sealed class FinalSettlementInput
{
    public long FinalSettlementId { get; set; }
    public long? EmployeeId { get; set; }
    public string? SettlementType { get; set; }
    public DateTime? LastWorkingDay { get; set; }
    public DateTime? NoticeDate { get; set; }
    public string? Reason { get; set; }
    public DateTime? SalaryFrom { get; set; }
    public decimal? LeaveBalanceDays { get; set; }
    public decimal? EncashDays { get; set; }
    public DateTime? PayMonth { get; set; }
}

public sealed class FinalSettlementFilter
{
    public int? CompanyId { get; set; }
    public string? CompanyIds { get; set; }
    public long? EmployeeId { get; set; }
    /// <summary>EXIT, ENCASHMENT or one type.</summary>
    public string? Type { get; set; }
    /// <summary>OPEN, DRAFT, PENDING, APPROVED, PAID, CANCELLED or ALL.</summary>
    public string? Status { get; set; }
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 25;
}
