namespace HRMS.Domain.Payroll;

// ===========================================================================
// Collection (db/115) - Work Permit Collection: when an employee's gross monthly
// salary (Basic + Allowances) is below the work permit salary, the payroll pays
// the difference and the company collects it back from the employee.
// ===========================================================================

/// <summary>The kinds of pay item type (Payroll.PayComponents.ComponentType).</summary>
public static class ComponentTypes
{
    public const string Earning = "EARNING";
    public const string Deduction = "DEDUCTION";
    /// <summary>db/115: paid with the salary and collected back from the employee.</summary>
    public const string Collection = "COLLECTION";

    public static bool IsValid(string? type) => type is Earning or Deduction or Collection;
}

/// <summary>PENDING (still to receive) or COLLECTED.</summary>
public static class CollectionStatus
{
    public const string Pending = "PENDING";
    public const string Collected = "COLLECTED";
}

/// <summary>One receivable: what was paid on top in a payroll and is collected back.</summary>
public sealed class CollectionItem
{
    public long CollectionId { get; init; }
    public int CompanyId { get; init; }
    public long PayrollRunId { get; init; }
    public string? RunCode { get; init; }
    public string? RunStage { get; init; }
    public DateTime RunMonth { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public string? DepartmentName { get; init; }
    public decimal GrossMonthly { get; init; }
    public decimal WorkPermitSalary { get; init; }
    public decimal Amount { get; init; }
    public string Status { get; init; } = CollectionStatus.Pending;
    public DateTime? CollectedDate { get; init; }
    public string? Reference { get; init; }
    public string? Comment { get; init; }
    public DateTime? CollectedOn { get; init; }
    public string? CollectedByName { get; init; }

    public bool IsCollected => Status == CollectionStatus.Collected;
    /// <summary>A draft payroll can still change: its collections are not marked yet.</summary>
    public bool IsDraft => RunStage == "DRAFT";
}

/// <summary>The key figures of a company's payroll month.</summary>
public sealed class CollectionSummary
{
    public decimal TotalAmount { get; init; }
    public int TotalCount { get; init; }
    public decimal PendingAmount { get; init; }
    public int PendingCount { get; init; }
    public decimal CollectedAmount { get; init; }
    public int CollectedCount { get; init; }
}

/// <summary>A payroll month of the company (regular payrolls) and what is still due in it.</summary>
public sealed class CollectionMonth
{
    public DateTime RunMonth { get; init; }
    public decimal PendingAmount { get; init; }
    public int CollectionCount { get; init; }
}

/// <summary>One line of a collection's audit (Payroll.CollectionHistory).</summary>
public sealed class CollectionHistoryEntry
{
    public long CollectionHistoryId { get; init; }
    /// <summary>CREATED / UPDATED / COLLECTED / REOPENED / REMOVED.</summary>
    public string ActionCode { get; init; } = string.Empty;
    public decimal? OldAmount { get; init; }
    public decimal? NewAmount { get; init; }
    public DateTime? CollectedDate { get; init; }
    public string? Reference { get; init; }
    public string? Comment { get; init; }
    public DateTime ActionDate { get; init; }
    public string? ActionByName { get; init; }
}
