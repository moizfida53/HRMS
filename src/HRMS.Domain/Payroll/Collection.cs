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
    /// <summary>db/121: the net pay the collection was worked out from (null for older ones).</summary>
    public decimal? NetPayable { get; init; }
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

/// <summary>
/// db/121: what one employee of a payroll is transferred (Payroll.ufn_RunFunding): step 1 the work
/// permit salary, step 2 the net pay above it; step 1 paying more than the net pay is collected back.
/// </summary>
public sealed class PayrollFundingRow
{
    public long RunEmployeeId { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? DepartmentName { get; init; }
    /// <summary>BANK / CASH (no IBAN).</summary>
    public string Method { get; init; } = "BANK";
    public string? BankName { get; init; }
    public decimal NetPay { get; init; }
    public decimal? Wps { get; init; }
    public decimal WorkPermitTransfer { get; init; }
    public decimal BalanceTransfer { get; init; }
    public decimal ToCollect { get; init; }
    public decimal CashPayment { get; init; }
    /// <summary>EQUAL / COLLECT / BALANCE / CASH / NO_WPS.</summary>
    public string FundingCase { get; init; } = "EQUAL";
    /// <summary>db/122: the figures saved when the payroll was approved (not worked out now).</summary>
    public bool IsSnapshot { get; init; }
    public DateTime? SnapshotDate { get; init; }
    public string? SnapshotByName { get; init; }
}

/// <summary>db/121: the funding summary of a payroll - the totals and the cases, from its rows.</summary>
public sealed class PayrollFunding
{
    public static readonly IReadOnlyList<string> Cases = ["EQUAL", "COLLECT", "BALANCE", "PROBATION", "CASH", "NO_WPS"];

    public IReadOnlyList<PayrollFundingRow> Rows { get; init; } = Array.Empty<PayrollFundingRow>();

    /// <summary>db/122: a closed payroll shows its funding as approved.</summary>
    public bool IsSnapshot => Rows.Count > 0 && Rows[0].IsSnapshot;
    public DateTime? SnapshotDate => Rows.Count > 0 ? Rows[0].SnapshotDate : null;
    public string? SnapshotByName => Rows.Count > 0 ? Rows[0].SnapshotByName : null;

    public decimal NetPayable => Rows.Sum(r => r.NetPay);
    public decimal NetPayableByBank => Rows.Where(r => r.Method == "BANK").Sum(r => r.NetPay);
    public decimal WorkPermitTransfer => Rows.Sum(r => r.WorkPermitTransfer);
    public decimal BalanceTransfer => Rows.Sum(r => r.BalanceTransfer);
    public decimal ToCollect => Rows.Sum(r => r.ToCollect);
    public decimal Cash => Rows.Sum(r => r.CashPayment);
    public int Count(string fundingCase) => Rows.Count(r => r.FundingCase == fundingCase);
    public IEnumerable<PayrollFundingRow> Of(string fundingCase) => Rows.Where(r => r.FundingCase == fundingCase);
    /// <summary>Work permit transfer + balance transfer - to collect = net payable by bank.</summary>
    public bool IsBalanced => WorkPermitTransfer + BalanceTransfer - ToCollect == NetPayableByBank;
}

/// <summary>db/120: the work permit figures of one payroll (Create Payroll summary).</summary>
public sealed class CollectionPreview
{
    /// <summary>The Work Permit Salary of the employees in the payroll.</summary>
    public decimal WorkPermitPayable { get; init; }
    public int WorkPermitCount { get; init; }
    /// <summary>Work Permit Salary less Gross Monthly, where above zero - recorded when the payroll is approved.</summary>
    public decimal CollectionAmount { get; init; }
    public int CollectionCount { get; init; }
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
