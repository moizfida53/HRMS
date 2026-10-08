namespace HRMS.Domain.Payroll;

/// <summary>
/// The stages of a payroll run (Payroll.PayrollRuns.Stage, db/34).
/// DRAFT exists only while the Create Payroll wizard is open; it is never listed.
/// </summary>
public static class RunStage
{
    public const string Draft = "DRAFT";
    public const string Registered = "REGISTERED";
    public const string Validation = "VALIDATION";
    public const string AwaitingApproval = "AWAITING_APPROVAL";
    public const string Closed = "CLOSED";
    public const string Cancelled = "CANCELLED";

    /// <summary>Position in the Register → Validation → Approval → Closed sequence (cancelled = -1).</summary>
    public static int Index(string? stage) => stage switch
    {
        Registered => 0,
        Validation => 1,
        AwaitingApproval => 2,
        Closed => 3,
        _ => -1
    };

    /// <summary>English label (translated in the views through Core.UiLabels).</summary>
    public static string Label(string? stage) => stage switch
    {
        Draft => "Draft",
        Registered => "Registered",
        Validation => "Validation",
        AwaitingApproval => "Awaiting Approval",
        Closed => "Closed",
        Cancelled => "Cancelled",
        _ => stage ?? string.Empty
    };

    public static string Badge(string? stage) => stage switch
    {
        Registered => "info",
        Validation => "warning",
        AwaitingApproval => "purple",
        Closed => "success",
        _ => "muted"
    };
}

public static class RunType
{
    public const string Regular = "REGULAR";
    public const string OffCycle = "OFFCYCLE";

    public static string Label(string? type) => type == OffCycle ? "Off-cycle" : "Regular";
}

/// <summary>One payroll run (header) - LIST / GET of Payroll.usp_PayrollRun_Manage.</summary>
public sealed class PayrollRun
{
    public long PayrollRunId { get; init; }
    public int CompanyId { get; init; }
    public string CompanyCode { get; init; } = string.Empty;
    public string CompanyName { get; init; } = string.Empty;
    public int PayrollCalendarId { get; init; }
    public string CalendarCode { get; init; } = string.Empty;
    public string CalendarName { get; init; } = string.Empty;
    public string? CalendarArabicName { get; init; }
    public string PayFrequency { get; init; } = "MONTHLY";
    public int PayrollPeriodId { get; init; }
    public string? PeriodName { get; init; }
    public int? PeriodNumber { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public DateTime? PaymentDate { get; init; }
    public string? PeriodStatus { get; init; }
    public DateTime RunMonth { get; init; }
    public int? RunSeq { get; init; }
    public string? RunCode { get; init; }
    public string RunType { get; init; } = Payroll.RunType.Regular;
    public string? Description { get; init; }
    public string Stage { get; init; } = RunStage.Draft;
    public int ApprovalLevel { get; init; }
    public int? ScopeDepartmentId { get; init; }
    public int? ScopeWorkLocationId { get; init; }
    public string? ScopeEmploymentType { get; init; }
    public string? ScopeNationality { get; init; }
    public int EmployeeCount { get; init; }
    public int ExcludedCount { get; init; }
    /// <summary>LIST: payslips still to generate (closed payrolls; none yet or outdated).</summary>
    public int PayslipsToGenerate { get; init; }
    public decimal TotalSalary { get; init; }
    public decimal TotalEarnings { get; init; }
    public decimal TotalDeductions { get; init; }
    public decimal TotalNet { get; init; }
    public decimal TotalGross { get; init; }
    public int ErrorCount { get; init; }
    public int WarningCount { get; init; }
    public int AcknowledgedCount { get; init; }
    public DateTime? CalculatedDate { get; init; }
    public DateTime? ValidatedDate { get; init; }
    public long? SubmittedBy { get; init; }
    public DateTime? SubmittedDate { get; init; }
    public DateTime? ClosedDate { get; init; }
    public DateTime? CancelledDate { get; init; }
    public string? CancelReason { get; init; }
    public long? CreatedBy { get; init; }
    public DateTime CreatedDate { get; init; }
    public string? CreatedByName { get; init; }
    public string? SubmittedByName { get; init; }
    public string? ClosedByName { get; init; }
    public string? CancelledByName { get; init; }
    public DateTime? LastActionDate { get; init; }
    public long? Level1ApprovedBy { get; init; }

    public bool IsCancelled => Stage == RunStage.Cancelled;
    public bool IsClosed => Stage == RunStage.Closed;
    public bool IsEditable => Stage is RunStage.Draft or RunStage.Registered;
    /// <summary>Employees can be excluded / included again until the payroll is submitted (db/35).</summary>
    public bool CanExclude => Stage is RunStage.Draft or RunStage.Registered or RunStage.Validation;
    public int StageIndex => RunStage.Index(Stage);
}

/// <summary>NEXT_CODE: the name the next payroll of a company and month will get.</summary>
public sealed class NextRunCode
{
    public int NextSeq { get; init; }
    public string RunCode { get; init; } = string.Empty;
    public DateTime RunMonth { get; init; }
    public int IssuedCount { get; init; }
    public int CancelledCount { get; init; }
    public string? RegularRunCode { get; init; }
}

/// <summary>A pay period of a calendar, with how many payrolls it has.</summary>
public sealed class PayrollPeriodRow
{
    public int PayrollPeriodId { get; init; }
    public int PayrollCalendarId { get; init; }
    public int PeriodYear { get; init; }
    public int PayrollMonth { get; init; }
    public int? PeriodNumber { get; init; }
    public string? PeriodCode { get; init; }
    public string? PeriodName { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public DateTime? CutOffDate { get; init; }
    public DateTime? PaymentDate { get; init; }
    public string Status { get; init; } = "OPEN";
    public string? Remarks { get; init; }
    public string PayFrequency { get; init; } = "MONTHLY";
    public DateTime RunMonth { get; init; }
    public int RunCount { get; init; }
    public int CancelledCount { get; init; }
}

public sealed class RunMonthOption
{
    public DateTime RunMonth { get; init; }
    public int RunCount { get; init; }
}

/// <summary>An unfinished Create Payroll wizard of the current user.</summary>
public sealed class PayrollDraft
{
    public long PayrollRunId { get; init; }
    public int CompanyId { get; init; }
    public int PayrollCalendarId { get; init; }
    public string CalendarName { get; init; } = string.Empty;
    public int PayrollPeriodId { get; init; }
    public string? PeriodName { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public string PayFrequency { get; init; } = "MONTHLY";
    public int? PeriodNumber { get; init; }
    public string RunType { get; init; } = Payroll.RunType.Regular;
    public string? Description { get; init; }
    public int EmployeeCount { get; init; }
    public DateTime LastSaved { get; init; }
}

/// <summary>Input of the wizard's first step (DRAFT_SAVE).</summary>
public sealed class PayrollDraftInput
{
    public long? PayrollRunId { get; set; }
    public int CompanyId { get; set; }
    public int PayrollCalendarId { get; set; }
    public int PayrollPeriodId { get; set; }
    public string RunType { get; set; } = Payroll.RunType.Regular;
    public string? Description { get; set; }
    public int? ScopeDepartmentId { get; set; }
    public int? ScopeWorkLocationId { get; set; }
    public string? ScopeEmploymentType { get; set; }
    public string? ScopeNationality { get; set; }
}

/// <summary>One employee of a run - LIST of Payroll.usp_PayrollRunEmployee_Manage.</summary>
public sealed class PayrollRunEmployee
{
    public long RunEmployeeId { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public string? DepartmentName { get; init; }
    public int? CostCenterId { get; init; }
    public bool IsKuwaiti { get; init; }
    public string? EmploymentStatus { get; init; }
    public DateTime? HireDate { get; init; }
    public DateTime? TerminationDate { get; init; }
    public int PeriodDays { get; init; }
    public int PaidDays { get; init; }
    public bool HasBankAccount { get; init; }
    public bool IsExcluded { get; init; }
    public string? ExcludeReason { get; init; }
    public decimal SalaryTotal { get; init; }
    public decimal EarningsTotal { get; init; }
    public decimal DeductionsTotal { get; init; }
    public decimal GrossPay { get; init; }
    public decimal NetPay { get; init; }
    public decimal? PreviousNet { get; init; }
    public int LineCount { get; init; }
    public int AddedLineCount { get; init; }
    public bool HasSalary { get; init; }
    public bool IsJoiner { get; init; }
    public bool IsLeaver { get; init; }
    public int ErrorCount { get; init; }
}

public sealed class ExcludedEmployee
{
    public long RunEmployeeId { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public string? ExcludeReason { get; init; }
    public DateTime? ExcludedDate { get; init; }
    public string? ExcludedByName { get; init; }

    /// <summary>The off-cycle payroll of the period that pays the employee instead (catch-up), if any.</summary>
    public long? PaidByRunId { get; init; }
    public string? PaidByRunCode { get; init; }
    public string? PaidByStage { get; init; }
    public decimal? PaidByNet { get; init; }
}

/// <summary>A calculated line of an employee in a run.</summary>
public sealed class PayrollRunLine
{
    public long RunLineId { get; init; }
    public long EmployeeId { get; init; }
    public int PayComponentId { get; init; }
    public string ItemClass { get; init; } = "EARNING";
    public string ComponentName { get; init; } = string.Empty;
    public string? ComponentArabicName { get; init; }
    public string? Comment { get; init; }
    public string Source { get; init; } = "PAY_ITEM";
    public long? EmployeePayItemId { get; init; }
    public int? InstalmentNo { get; init; }
    public int? InstalmentCount { get; init; }
    public decimal FullAmount { get; init; }
    public decimal Amount { get; init; }

    public bool IsAddedInRun => Source == "RUN";
}

/// <summary>SUMMARY - totals and counts for the KPI tiles and the Check step.</summary>
public sealed class PayrollRunSummary
{
    public int EmployeeCount { get; init; }
    public int FullPeriodCount { get; init; }
    public int JoinerCount { get; init; }
    public int LeaverCount { get; init; }
    public int ExcludedCount { get; init; }
    public int MissingSalaryCount { get; init; }
    public int NoBankCount { get; init; }
    public decimal TotalSalary { get; init; }
    public decimal TotalEarnings { get; init; }
    public decimal TotalDeductions { get; init; }
    public decimal TotalNet { get; init; }
    public int AddedLineCount { get; init; }
    public decimal AddedPlus { get; init; }
    public decimal AddedMinus { get; init; }
    public int PayItemCount { get; init; }
    public decimal PayItemAmount { get; init; }
    public int LoanCount { get; init; }
    public decimal LoanAmount { get; init; }
    public int PifssCount { get; init; }
    public decimal PifssAmount { get; init; }
    public int ProfileSalaryCount { get; init; }
    public bool PifssUnverified { get; init; }
    public string? MissingSalaryNames { get; init; }
}

/// <summary>A pay item type offered by "Add line" (earnings and deductions).</summary>
public sealed class PayComponentOption
{
    public int PayComponentId { get; init; }
    public string ComponentCode { get; init; } = string.Empty;
    public string ComponentName { get; init; } = string.Empty;
    public string? ArabicName { get; init; }
    public string ItemClass { get; init; } = "EARNING";
}

/// <summary>A validation result.</summary>
public sealed class PayrollRunIssue
{
    public long RunIssueId { get; init; }
    public long? EmployeeId { get; init; }
    public string RuleCode { get; init; } = string.Empty;
    public string Severity { get; init; } = "WARNING";
    public string Message { get; init; } = string.Empty;
    public bool IsAcknowledged { get; init; }
    public DateTime? AcknowledgedDate { get; init; }
    public string? AcknowledgeReason { get; init; }
    public string? AcknowledgedByName { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }

    public bool IsError => Severity == "ERROR";
}

public sealed class PayrollRunHistoryEntry
{
    public long RunHistoryId { get; init; }
    public string ActionCode { get; init; } = string.Empty;
    public string? FromStage { get; init; }
    public string? ToStage { get; init; }
    public int? ApprovalLevel { get; init; }
    public string? Comment { get; init; }
    public long? ActionBy { get; init; }
    public DateTime ActionDate { get; init; }
    public string ActionByName { get; init; } = string.Empty;
}

public sealed class RunCompareRow
{
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public decimal? NetA { get; init; }
    public decimal? NetB { get; init; }
    public decimal Difference { get; init; }
}
