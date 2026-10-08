namespace HRMS.Domain.Payroll;

// ===========================================================================
// Bank Processing and Accounting (db/49-50): salary files, the payment
// register, payroll journals and cost allocations - all for CLOSED payrolls.
// ===========================================================================

/// <summary>A closed payroll as Bank Processing and Accounting list it (with its file / journal state).</summary>
public sealed class FinanceRun
{
    public long PayrollRunId { get; set; }
    public string RunCode { get; set; } = string.Empty;
    public string RunType { get; set; } = "REGULAR";
    public DateTime RunMonth { get; set; }
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string? CalendarName { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public DateTime? PaymentDate { get; set; }
    public DateTime? ClosedDate { get; set; }
    public int EmployeeCount { get; set; }
    public decimal TotalNet { get; set; }

    // bank
    public int FileCount { get; set; }
    public string? LastFileNo { get; set; }
    public DateTime? LastFileDate { get; set; }
    public int PaidCount { get; set; }
    public int FailedCount { get; set; }
    public int InFileCount { get; set; }
    public int RetryCount { get; set; }
    public int CashPendingCount { get; set; }

    // accounting
    public decimal TotalGross { get; set; }
    public decimal TotalDeductions { get; set; }
    public long? JournalId { get; set; }
    public string? JournalNo { get; set; }
    public string? JournalStatus { get; set; }
}

/// <summary>What a bank file would hold, per bank (Method BANK) - or the employees with no IBAN (CASH).</summary>
public sealed class BankReviewRow
{
    public string Method { get; set; } = "BANK";
    public int? BankId { get; set; }
    public string? BankName { get; set; }
    public string? WpsBankCode { get; set; }
    public bool HasOwnFormat { get; set; }
    public int EmployeeCount { get; set; }
    public decimal Amount { get; set; }
}

/// <summary>One employee of a bank file, with every value a bank format can use.</summary>
public sealed class BankFileLine
{
    public long RunEmployeeId { get; set; }
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? CivilId { get; set; }
    public string? Iban { get; set; }
    public int? BankId { get; set; }
    public string? BankName { get; set; }
    public string? WpsBankCode { get; set; }
    public string? SwiftCode { get; set; }
    public decimal NetPay { get; set; }
    public decimal SalaryTotal { get; set; }
    public decimal EarningsTotal { get; set; }
    public decimal DeductionsTotal { get; set; }
}

/// <summary>Payroll.BankFiles - a generated salary file (FULL or RETRY).</summary>
public sealed class BankFile
{
    public long BankFileId { get; set; }
    public string FileNo { get; set; } = string.Empty;
    public string FileKind { get; set; } = "FULL";
    public string FileName { get; set; } = string.Empty;
    public string? Content { get; set; }
    public DateTime ValueDate { get; set; }
    public int LineCount { get; set; }
    public decimal TotalAmount { get; set; }
    /// <summary>GENERATED / SENT / SUPERSEDED.</summary>
    public string Status { get; set; } = "GENERATED";
    public string? Reason { get; set; }
    public int DownloadCount { get; set; }
    public DateTime? SentDate { get; set; }
    public string? SentReference { get; set; }
    public DateTime CreatedDate { get; set; }
    public long PayrollRunId { get; set; }
    public int CompanyId { get; set; }
    public string? RunCode { get; set; }
    public DateTime RunMonth { get; set; }
    public string? CompanyName { get; set; }
    public string? FormatName { get; set; }
    public string? BankName { get; set; }
    public string? AccountTitle { get; set; }
    public string? CreatedByName { get; set; }
    public int PaidCount { get; set; }
    public int FailedCount { get; set; }
}

/// <summary>Payroll.BankPayments - a row of the payment register.</summary>
public sealed class BankPayment
{
    public long BankPaymentId { get; set; }
    public long PayrollRunId { get; set; }
    public long EmployeeId { get; set; }
    public decimal Amount { get; set; }
    /// <summary>BANK / CASH.</summary>
    public string Method { get; set; } = "BANK";
    /// <summary>PENDING / IN_FILE / PAID / FAILED.</summary>
    public string Status { get; set; } = "PENDING";
    public string? Iban { get; set; }
    public string? Reference { get; set; }
    public string? FailureReason { get; set; }
    public DateTime? PaidDate { get; set; }
    public int AttemptCount { get; set; }
    public long? BankFileId { get; set; }
    public string? FileNo { get; set; }
    public string? BankName { get; set; }
    public string? RunCode { get; set; }
    public DateTime RunMonth { get; set; }
    public int CompanyId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? DepartmentName { get; set; }
}

public sealed class PaymentSummary
{
    public int TotalCount { get; set; }
    public decimal TotalAmount { get; set; }
    public int PaidCount { get; set; }
    public decimal PaidAmount { get; set; }
    public int InFileCount { get; set; }
    public decimal InFileAmount { get; set; }
    public int FailedCount { get; set; }
    public decimal FailedAmount { get; set; }
    public int PendingCount { get; set; }
    public decimal PendingAmount { get; set; }
}

/// <summary>Payroll.JournalBatches - the journal of a payroll.</summary>
public sealed class PayrollJournal
{
    public long JournalId { get; set; }
    public int CompanyId { get; set; }
    public long PayrollRunId { get; set; }
    public string JournalNo { get; set; } = string.Empty;
    public DateTime JournalDate { get; set; }
    /// <summary>READY / EXPORTED / POSTED / REVERSED.</summary>
    public string Status { get; set; } = "READY";
    public decimal TotalDebit { get; set; }
    public decimal TotalCredit { get; set; }
    public int LineCount { get; set; }
    public int UnmappedCount { get; set; }
    public int ExportCount { get; set; }
    public DateTime? ExportedDate { get; set; }
    public string? PostedReference { get; set; }
    public DateTime? PostedDate { get; set; }
    public DateTime? ReversedDate { get; set; }
    public string? ReverseReason { get; set; }
    public DateTime CreatedDate { get; set; }
    public string? RunCode { get; set; }
    public DateTime RunMonth { get; set; }
    public string? CompanyName { get; set; }
    public string? ExportedByName { get; set; }
    public string? PostedByName { get; set; }
}

public sealed class JournalLine
{
    public int LineNumber { get; set; }
    public string AccountCode { get; set; } = string.Empty;
    public string? AccountName { get; set; }
    public int? CostCenterId { get; set; }
    public string? CostCenterName { get; set; }
    public decimal Debit { get; set; }
    public decimal Credit { get; set; }
    public bool IsUnmapped { get; set; }
    public string? Description { get; set; }
}

/// <summary>Payroll.AccountingDefaults - the salaries payable account of a company.</summary>
public sealed class AccountingDefaults
{
    public int CompanyId { get; set; }
    public string NetPayAccountCode { get; set; } = "210100";
    public string? NetPayAccountName { get; set; }
    public bool IsSaved { get; set; }
}

/// <summary>Payroll.CostAllocations - an employee's cost split across cost centers from a date.</summary>
public sealed class CostAllocation
{
    public int CostAllocationId { get; set; }
    public int CompanyId { get; set; }
    public long EmployeeId { get; set; }
    public DateTime? EffectiveFrom { get; set; }
    public DateTime? EffectiveTo { get; set; }
    public string? Notes { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? CompanyName { get; set; }
    /// <summary>"Head Office 60% · Operations 40%" (lists).</summary>
    public string? Split { get; set; }
    public bool IsCurrent { get; set; }
    public List<CostAllocationLine> Lines { get; set; } = [];
}

public sealed class CostAllocationLine
{
    public int CostCenterId { get; set; }
    public decimal SharePercent { get; set; }
    public string? CostCenterName { get; set; }
}

/// <summary>The sidebar figures of Bank Processing and Accounting.</summary>
public sealed class FinanceNavCounts
{
    public int BankFilesToMake { get; set; }
    public int PaymentsOpen { get; set; }
    public int JournalsToMake { get; set; }
    public int JournalsToPost { get; set; }
}

/// <summary>The common filter of the finance lists.</summary>
public sealed class FinanceFilter
{
    public int? CompanyId { get; init; }
    public string? CompanyIds { get; init; }
    public int? Year { get; init; }
    public DateTime? RunMonth { get; init; }
    public long? RunId { get; init; }
    public string? Status { get; init; }
    public string? Method { get; init; }
    public int? BankId { get; init; }
    public long? FileId { get; init; }
    public int? CostCenterId { get; init; }
    public string? Search { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 25;
}
