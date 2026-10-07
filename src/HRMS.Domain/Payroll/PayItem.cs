namespace HRMS.Domain.Payroll;

/// <summary>How a pay item type is grouped (Payroll.PayComponents.ItemClass).</summary>
public static class ItemClass
{
    public const string Salary = "SALARY";
    public const string Earning = "EARNING";
    public const string Deduction = "DEDUCTION";
    public const string Loan = "LOAN";

    public static readonly IReadOnlyList<string> All = [Salary, Earning, Deduction, Loan];

    public static string Label(string? cls) => cls switch
    {
        Salary => "Salary",
        Earning => "Earning",
        Deduction => "Deduction",
        Loan => "Loan / advance",
        _ => "Statutory"
    };

    public static string Badge(string? cls) => cls switch
    {
        Salary => "info",
        Earning => "success",
        Deduction => "warning",
        Loan => "purple",
        _ => "muted"
    };

    /// <summary>Earnings add to the net; every other class is deducted.</summary>
    public static bool IsPositive(string? cls) => cls is Salary or Earning;

    /// <summary>Salary and loan items are paid only after approval (HR, then Finance).</summary>
    public static bool NeedsApproval(string? cls) => cls is Salary or Loan;
}

public static class AppliesMode
{
    public const string Monthly = "MONTHLY";
    public const string Once = "ONCE";
    public const string Instalment = "INSTALMENT";
}

public static class PayItemStatus
{
    public const string Active = "ACTIVE";
    public const string Pending = "PENDING";
    public const string Ended = "ENDED";
}

/// <summary>One row of Payroll.EmployeePayItems with what payrolls have paid of it.</summary>
public sealed class PayItem
{
    public long EmployeePayItemId { get; init; }
    public int CompanyId { get; init; }
    public string? CompanyName { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public int PayComponentId { get; init; }
    public string? ComponentCode { get; init; }
    public string? ComponentName { get; init; }
    public string? ComponentArabicName { get; init; }
    public string ItemClass { get; init; } = Payroll.ItemClass.Earning;
    public string? SystemCode { get; init; }
    public decimal Amount { get; init; }
    public string AppliesMode { get; init; } = Payroll.AppliesMode.Once;
    public DateTime StartMonth { get; init; }
    public DateTime? EndMonth { get; init; }
    public int? InstalmentCount { get; init; }
    public decimal? TotalAmount { get; init; }
    public string? Comment { get; init; }
    public string Status { get; init; } = PayItemStatus.Active;
    public string EffectiveStatus { get; init; } = PayItemStatus.Active;
    public int ApprovalLevel { get; init; }
    public long? SubmittedBy { get; init; }
    public DateTime? SubmittedDate { get; init; }
    public long? ReplacesItemId { get; init; }
    public decimal? ReplacedAmount { get; init; }
    public string? SourceRef { get; init; }
    public long? CreatedBy { get; init; }
    public DateTime CreatedDate { get; init; }
    public int PaidCount { get; init; }
    public decimal PaidAmount { get; init; }
    public DateTime? LastPaidMonth { get; init; }
    public decimal? Balance { get; init; }

    public bool IsPending => Status == PayItemStatus.Pending;
    public bool IsEnded => EffectiveStatus == PayItemStatus.Ended;
    public bool IsUsed => PaidCount > 0;
    public bool IsPositive => Payroll.ItemClass.IsPositive(ItemClass);
    /// <summary>The amount as it shows on a payroll: deductions and loans negative.</summary>
    public decimal SignedAmount => IsPositive ? Amount : -Amount;
}

/// <summary>Key figures of the Pay Items page.</summary>
public sealed class PayItemSummary
{
    public DateTime SummaryMonth { get; init; }
    public decimal MonthlySalary { get; init; }
    public int SalaryEmployees { get; init; }
    public int SalaryItems { get; init; }
    public decimal Earnings { get; init; }
    public int EarningItems { get; init; }
    public decimal Deductions { get; init; }
    public int DeductionItems { get; init; }
    public decimal LoanOutstanding { get; init; }
    public int LoansRunning { get; init; }
    public int LoansPending { get; init; }
    public int PendingApprovals { get; init; }
}

/// <summary>One employee's salary, loans and payment method (the card above the list and the loan checks).</summary>
public sealed class PayItemEmployeeSummary
{
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public int CompanyId { get; init; }
    public string? DepartmentName { get; init; }
    public string? DesignationName { get; init; }
    public decimal MonthlySalary { get; init; }
    public decimal LoanBalance { get; init; }
    public decimal LoanPending { get; init; }
    public decimal MonthlyDeductions { get; init; }
    public bool HasIban { get; init; }
    public string? BankName { get; init; }
}

public sealed class PayItemType
{
    public int PayComponentId { get; init; }
    public int CompanyId { get; init; }
    public string? ComponentCode { get; init; }
    public string? ComponentName { get; init; }
    public string? ArabicName { get; init; }
    public string ItemClass { get; init; } = Payroll.ItemClass.Earning;
    public string? SystemCode { get; init; }
    public bool IsActive { get; init; }
}

public sealed class PayItemEmployeeOption
{
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? EmployeeArabicName { get; init; }
    public int CompanyId { get; init; }
    public bool IsActive { get; init; }
}

public sealed class PayItemHistoryEntry
{
    public long PayItemHistoryId { get; init; }
    public long EmployeePayItemId { get; init; }
    public string ActionCode { get; init; } = "CREATED";
    public int? ApprovalLevel { get; init; }
    public decimal? OldAmount { get; init; }
    public decimal? NewAmount { get; init; }
    public string? Comment { get; init; }
    public long? ActionBy { get; init; }
    public DateTime ActionDate { get; init; }
    public DateTime StartMonth { get; init; }
    public DateTime? EndMonth { get; init; }
    public string? AppliesMode { get; init; }
    public string? Status { get; init; }
    public string? ActionByName { get; init; }
}

/// <summary>What the pay item form posts.</summary>
public sealed class PayItemInput
{
    public long EmployeePayItemId { get; set; }
    public long EmployeeId { get; set; }
    public int PayComponentId { get; set; }
    public decimal? Amount { get; set; }
    public string? AppliesMode { get; set; }
    public DateTime? StartMonth { get; set; }
    public DateTime? EndMonth { get; set; }
    public int? InstalmentCount { get; set; }
    public decimal? TotalAmount { get; set; }
    public string? Comment { get; set; }
}

/// <summary>One row read from an import file (all text - the procedure validates it).</summary>
public sealed class PayItemImportRow
{
    public int Row { get; set; }
    public string? EmployeeNo { get; set; }
    public string? ItemType { get; set; }
    public string? Amount { get; set; }
    public string? Applies { get; set; }
    public string? FromMonth { get; set; }
    public string? UntilMonth { get; set; }
    public string? Instalments { get; set; }
    public string? Total { get; set; }
    public string? Comment { get; set; }
}

public sealed class PayItemImportError
{
    public int? RowNo { get; init; }
    public string? Message { get; init; }
}

public sealed class PayItemImportResult
{
    public bool Success { get; init; }
    public int Imported { get; init; }
    public string? Message { get; init; }
    public string? ErrorCode { get; init; }
    public IReadOnlyList<PayItemImportError> Errors { get; init; } = Array.Empty<PayItemImportError>();
}
