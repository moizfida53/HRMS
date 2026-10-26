namespace HRMS.Domain.Leave;

/// <summary>Request status (Leave.LeaveRequests.Status, db/68).</summary>
public static class LeaveStatus
{
    public const string Pending = "PENDING";
    public const string Approved = "APPROVED";
    public const string Rejected = "REJECTED";
    public const string Cancelled = "CANCELLED";

    public static string Badge(string? status) => status switch
    {
        Approved => "success",
        Pending => "warning",
        Rejected => "danger",
        _ => "muted"
    };
}

/// <summary>How a leave type's balance works (Leave.LeaveTypes.BalanceMode).</summary>
public static class LeaveBalanceMode
{
    public const string Accrue = "ACCRUE";
    public const string Yearly = "YEARLY";
    public const string Once = "ONCE";
    public const string Unlimited = "UNLIMITED";
    public static readonly IReadOnlyList<string> All = [Accrue, Yearly, Once, Unlimited];
}

public static class LeaveCategory
{
    public static readonly IReadOnlyList<string> All = ["ANNUAL", "SICK", "EMERGENCY", "HAJJ", "MATERNITY", "BEREAVEMENT", "UNPAID", "OTHER"];
}

/// <summary>A leave type with its rules (Settings > Leave types).</summary>
public sealed class LeaveTypeSetting
{
    public int LeaveTypeId { get; set; }
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string TypeCode { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public string? ArabicName { get; set; }
    public string Category { get; set; } = "OTHER";
    public string BalanceMode { get; set; } = LeaveBalanceMode.Yearly;
    public decimal? DaysPerYear { get; set; }
    public string? AccrualMethod { get; set; }
    public string PayType { get; set; } = "FULL";
    public short EligibleAfterMonths { get; set; }
    public string? Gender { get; set; }
    public string CountMode { get; set; } = "WORKING";
    public bool ExcludeHolidays { get; set; }
    public bool AllowHalfDay { get; set; }
    public bool AllowNegative { get; set; }
    public bool RequiresDocument { get; set; }
    public short MinNoticeDays { get; set; }
    public short? MaxDaysPerRequest { get; set; }
    public string? Color { get; set; }
    public short SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
    /// <summary>Pay bands "1-15:100,16-25:75".</summary>
    public string? Tiers { get; set; }
    public int UsageCount { get; set; }
}

public sealed class LeaveTypeInput
{
    public int LeaveTypeId { get; set; }
    public int? CompanyId { get; set; }
    public string? TypeCode { get; set; }
    public string? TypeName { get; set; }
    public string? ArabicName { get; set; }
    public string? Category { get; set; }
    public string? BalanceMode { get; set; }
    public decimal? DaysPerYear { get; set; }
    public string? AccrualMethod { get; set; }
    public string? PayType { get; set; }
    public short? EligibleAfterMonths { get; set; }
    public string? Gender { get; set; }
    public string? CountMode { get; set; }
    public bool ExcludeHolidays { get; set; }
    public bool AllowHalfDay { get; set; }
    public bool AllowNegative { get; set; }
    public bool RequiresDocument { get; set; }
    public short? MinNoticeDays { get; set; }
    public short? MaxDaysPerRequest { get; set; }
    public string? Color { get; set; }
    public short? SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
    public string? Tiers { get; set; }
}

public sealed class LeaveHoliday
{
    public int HolidayId { get; set; }
    public int? CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string HolidayName { get; set; } = string.Empty;
    public string? ArabicName { get; set; }
    public DateTime FromDate { get; set; }
    public DateTime ToDate { get; set; }
    public int DayCount { get; set; }
}

public sealed class LeaveHolidayInput
{
    public int HolidayId { get; set; }
    public int? CompanyId { get; set; }
    public bool AllCompanies { get; set; }
    public string? HolidayName { get; set; }
    public string? ArabicName { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
}

/// <summary>Weekend days and approval route of one company.</summary>
public sealed class LeaveCompanySetting
{
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    /// <summary>ISO days, comma separated: 1 Monday ... 5 Friday, 6 Saturday, 7 Sunday.</summary>
    public string WeekendDays { get; set; } = "5,6";
    public bool ManagerApproval { get; set; } = true;

    public bool IsWeekend(int isoDay) => WeekendDays.Split(',').Contains(isoDay.ToString(System.Globalization.CultureInfo.InvariantCulture));
}

/// <summary>A leave request as listed and opened.</summary>
public sealed class LeaveRequest
{
    public long LeaveRequestId { get; set; }
    public string RequestNo { get; set; } = string.Empty;
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? EmployeeArabicName { get; set; }
    public string? DepartmentName { get; set; }
    public long? ReportingManagerId { get; set; }
    public string? ManagerEmployeeName { get; set; }
    public int LeaveTypeId { get; set; }
    public string? TypeName { get; set; }
    public string? TypeArabicName { get; set; }
    public string? Color { get; set; }
    public string? Category { get; set; }
    public string? CountMode { get; set; }
    public bool AllowHalfDay { get; set; }
    public bool RequiresDocument { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public DateTime? ActualEndDate { get; set; }
    public DateTime? ActualReturnDate { get; set; }
    public bool HalfDay { get; set; }
    public decimal Days { get; set; }
    public decimal PlannedDays { get; set; }
    public string Status { get; set; } = LeaveStatus.Pending;
    /// <summary>While pending: 1 line manager, 2 HR.</summary>
    public int ApprovalLevel { get; set; }
    public string? Reason { get; set; }
    public long? ManagerUserId { get; set; }
    public string? ManagerName { get; set; }
    public long? ManagerApprovedBy { get; set; }
    public DateTime? ManagerApprovedDate { get; set; }
    public long? DecidedBy { get; set; }
    public string? DecidedByName { get; set; }
    public DateTime? DecidedDate { get; set; }
    public string? DecisionComment { get; set; }
    public DateTime? CancelledDate { get; set; }
    public bool HasDocument { get; set; }
    public string? DocumentName { get; set; }
    public string? DocumentType { get; set; }
    public long? DocumentSize { get; set; }
    public string? DocumentPath { get; set; }
    public bool EnteredByHr { get; set; }
    public long? CreatedBy { get; set; }
    public string? CreatedByName { get; set; }
    public DateTime CreatedDate { get; set; }
    public long? SubmitterEmployeeId { get; set; }
    // db/86
    /// <summary>The days over the balance, taken unpaid (agreed by the employee).</summary>
    public decimal UnpaidDays { get; set; }
    /// <summary>Back at work - for reference only, no effect on the balance.</summary>
    public DateTime? ResumeDate { get; set; }
    public string? PayType { get; set; }
    public string? BalanceMode { get; set; }
    /// <summary>How the leave salary is paid: PAYROLL, CASH, or null (not settled: the monthly payroll).</summary>
    public string? SettlementMode { get; set; }
    public decimal? SettlementAmount { get; set; }
    public decimal? SettlementDailyRate { get; set; }
    public DateTime? SettlementDate { get; set; }
    public string? SettlementRemarks { get; set; }
    public long? SettledBy { get; set; }
    public string? SettledByName { get; set; }
    public DateTime? SettledDate { get; set; }

    public DateTime LastDay => ActualEndDate ?? EndDate;
    public decimal PaidDays => PayType == "UNPAID" ? 0 : Days - UnpaidDays;
    public bool IsCash => SettlementMode == LeaveSettlementMode.Cash;
    public bool IsPending => Status == LeaveStatus.Pending;
    public bool IsApproved => Status == LeaveStatus.Approved;
}

public sealed class LeaveRequestInput
{
    public long LeaveRequestId { get; set; }
    public long? EmployeeId { get; set; }
    public int? LeaveTypeId { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public bool HalfDay { get; set; }
    public string? Reason { get; set; }
    /// <summary>HR with the final approval right: approve as it is saved.</summary>
    public bool ApproveNow { get; set; }
    /// <summary>db/86: blank = the next working day after the leave.</summary>
    public DateTime? ResumeDate { get; set; }
    /// <summary>db/86: the days over the balance may be taken unpaid (the employee confirmed it).</summary>
    public bool AcceptUnpaid { get; set; }
}

/// <summary>How an approved leave's salary is paid (db/86).</summary>
public static class LeaveSettlementMode
{
    /// <summary>With the monthly payroll, as usual.</summary>
    public const string Payroll = "PAYROLL";
    /// <summary>In cash before the leave; the payroll of the leave month(s) recovers it.</summary>
    public const string Cash = "CASH";
}

/// <summary>The figures of a leave's salary settlement (HR, db/86).</summary>
public sealed class LeaveSettlement
{
    public long LeaveRequestId { get; set; }
    public string RequestNo { get; set; } = string.Empty;
    public string Status { get; set; } = LeaveStatus.Approved;
    public DateTime StartDate { get; set; }
    public DateTime LastDay { get; set; }
    public decimal Days { get; set; }
    public decimal PaidDays { get; set; }
    public decimal UnpaidDays { get; set; }
    public decimal MonthlySalary { get; set; }
    /// <summary>The salary components that count for leave salary (else the monthly salary).</summary>
    public decimal LeaveSalary { get; set; }
    public decimal Divisor { get; set; }
    public decimal DailyRate { get; set; }
    public decimal DailyLeaveRate { get; set; }
    /// <summary>Paid days x daily leave salary.</summary>
    public decimal SuggestedAmount { get; set; }
    /// <summary>Unpaid days x daily rate - deducted by the payroll.</summary>
    public decimal UnpaidDeduction { get; set; }
    public string? SettlementMode { get; set; }
    public decimal? SettlementAmount { get; set; }
    public decimal? SettlementDailyRate { get; set; }
    public DateTime? SettlementDate { get; set; }
    public string? SettlementRemarks { get; set; }
    public string? SettledByName { get; set; }
    public DateTime? SettledDate { get; set; }
    /// <summary>A payroll has started to recover the cash: the settlement is fixed.</summary>
    public bool CashInPayroll { get; set; }
}

/// <summary>A pay item a leave made: the unpaid days deduction or the cash recovery (db/86).</summary>
public sealed class LeavePayItem
{
    public long EmployeePayItemId { get; set; }
    /// <summary>UNPAID or CASH.</summary>
    public string Kind { get; set; } = "UNPAID";
    public string? ComponentName { get; set; }
    public string? ComponentArabicName { get; set; }
    public DateTime StartMonth { get; set; }
    public decimal Amount { get; set; }
    public string? Comment { get; set; }
    public bool InPayroll { get; set; }
}

public sealed class LeaveSettlementInput
{
    public long Id { get; set; }
    public string? Mode { get; set; }
    public decimal? Amount { get; set; }
    public DateTime? PaidOn { get; set; }
    public string? Remarks { get; set; }
}

public sealed class LeaveHistoryEntry
{
    public long HistoryId { get; set; }
    public string ActionCode { get; set; } = string.Empty;
    public long? ActionBy { get; set; }
    public string? ActionByName { get; set; }
    public DateTime ActionDate { get; set; }
    public string? Comment { get; set; }
}

/// <summary>The counts on top of the Leave page and on the Dashboard.</summary>
public sealed class LeaveSummary
{
    public int PendingTotal { get; set; }
    public int PendingForMe { get; set; }
    public int OnLeaveToday { get; set; }
    public int StartingThisWeek { get; set; }
    public int ApprovedThisMonth { get; set; }
    public int AnnualInMonth { get; set; }
    public int SickInMonth { get; set; }
    public int EmergencyInMonth { get; set; }
    public int OtherInMonth { get; set; }
    public int DueBack { get; set; }
}

/// <summary>What a request would count and leave - checked as the form is filled.</summary>
public sealed class LeavePreview
{
    public decimal Days { get; set; }
    public decimal? Entitled { get; set; }
    public decimal? Taken { get; set; }
    public decimal? Pending { get; set; }
    public decimal? Available { get; set; }
    public decimal? After { get; set; }
    /// <summary>db/86: the days covered by the balance, and those over it (unpaid).</summary>
    public decimal PaidDays { get; set; }
    public decimal UnpaidDays { get; set; }
    /// <summary>db/86: the suggested resume date (next working day).</summary>
    public DateTime? ResumeDate { get; set; }
    /// <summary>Messages separated by "|".</summary>
    public string? Problems { get; set; }
}

/// <summary>One employee's balance of one leave type on a date.</summary>
public sealed class LeaveBalance
{
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? EmployeeArabicName { get; set; }
    public string? CompanyName { get; set; }
    public string? DepartmentName { get; set; }
    public DateTime? HireDate { get; set; }
    public int LeaveTypeId { get; set; }
    public string? TypeCode { get; set; }
    public string? TypeName { get; set; }
    public string? TypeArabicName { get; set; }
    public string? Color { get; set; }
    public string? Category { get; set; }
    public string BalanceMode { get; set; } = LeaveBalanceMode.Yearly;
    public string? AccrualMethod { get; set; }
    public decimal? DaysPerYear { get; set; }
    public string? PayType { get; set; }
    public DateTime? WinStart { get; set; }
    public DateTime? OpeningDate { get; set; }
    public decimal OpeningDays { get; set; }
    public decimal Earned { get; set; }
    public decimal Adjusted { get; set; }
    public decimal? Entitled { get; set; }
    public decimal Taken { get; set; }
    public decimal Pending { get; set; }
    public decimal? Available { get; set; }

    public bool IsUnlimited => BalanceMode == LeaveBalanceMode.Unlimited;
}

/// <summary>A line of how a balance is made up: an opening / adjustment entry, or a request.</summary>
public sealed class LeaveLedgerLine
{
    public string Kind { get; set; } = "ENTRY";
    public long RefId { get; set; }
    public string Code { get; set; } = string.Empty;
    public DateTime OnDate { get; set; }
    public DateTime? ToDate { get; set; }
    public decimal Days { get; set; }
    public string? Comment { get; set; }
    public string? ByName { get; set; }
    public DateTime CreatedDate { get; set; }
    public string? RequestNo { get; set; }
    public string? Status { get; set; }
}

public sealed class LeaveEmployeeOption
{
    public long EmployeeId { get; set; }
    public int CompanyId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? ArabicName { get; set; }
    public string? Gender { get; set; }
    public DateTime? HireDate { get; set; }
}

/// <summary>A leave type an employee can take, with their balance today.</summary>
public sealed class LeaveTypeOption
{
    public int LeaveTypeId { get; set; }
    public int CompanyId { get; set; }
    public string TypeCode { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public string? ArabicName { get; set; }
    public string? Category { get; set; }
    public string BalanceMode { get; set; } = LeaveBalanceMode.Yearly;
    public string? PayType { get; set; }
    public string? CountMode { get; set; }
    public bool AllowHalfDay { get; set; }
    public bool RequiresDocument { get; set; }
    public short MinNoticeDays { get; set; }
    public short? MaxDaysPerRequest { get; set; }
    public string? Color { get; set; }
    public short EligibleAfterMonths { get; set; }
    public decimal? Entitled { get; set; }
    public decimal? Taken { get; set; }
    public decimal? Pending { get; set; }
    public decimal? Available { get; set; }
}
