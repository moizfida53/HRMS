namespace HRMS.Domain.Workforce;

/// <summary>
/// The transaction types of the employee Audit Report (Employee.EmployeeAuditLog, db/60).
/// The English label of each is translated in the views through Core.UiLabels.
/// </summary>
public static class AuditType
{
    public const string CalendarAssigned = "CALENDAR_ASSIGNED";
    public const string CalendarChanged = "CALENDAR_CHANGED";
    public const string EmployeeCreated = "EMPLOYEE_CREATED";
    public const string EmployeeUpdated = "EMPLOYEE_UPDATED";
    public const string EmployeeActivated = "EMPLOYEE_ACTIVATED";
    public const string EmployeeDeactivated = "EMPLOYEE_DEACTIVATED";
    public const string EmployeeDeleted = "EMPLOYEE_DELETED";
    public const string SalaryChanged = "SALARY_CHANGED";
    public const string BankChanged = "BANK_CHANGED";
    public const string PayrollExcluded = "PAYROLL_EXCLUDED";
    public const string PayrollIncluded = "PAYROLL_INCLUDED";

    /// <summary>Every type, in the order the report's filter lists them, with its group.</summary>
    public static readonly IReadOnlyList<(string Code, string Group)> All =
    [
        (CalendarAssigned, "Payroll calendar"), (CalendarChanged, "Payroll calendar"),
        (EmployeeCreated, "Employee"), (EmployeeUpdated, "Employee"), (EmployeeActivated, "Employee"),
        (EmployeeDeactivated, "Employee"), (EmployeeDeleted, "Employee"),
        (SalaryChanged, "Salary & bank"), (BankChanged, "Salary & bank"),
        (PayrollExcluded, "Payroll"), (PayrollIncluded, "Payroll")
    ];

    public static bool IsKnown(string? code) => code is not null && All.Any(t => t.Code == code);

    public static string Label(string? code) => code switch
    {
        CalendarAssigned => "Payroll calendar assigned",
        CalendarChanged => "Payroll calendar changed",
        EmployeeCreated => "Employee created",
        EmployeeUpdated => "Employee updated",
        EmployeeActivated => "Employee activated",
        EmployeeDeactivated => "Employee deactivated",
        EmployeeDeleted => "Employee deleted",
        SalaryChanged => "Salary changed",
        BankChanged => "Bank details changed",
        PayrollExcluded => "Excluded from payroll",
        PayrollIncluded => "Included in payroll",
        _ => code ?? string.Empty
    };

    public static string Badge(string? code) => code switch
    {
        CalendarAssigned or CalendarChanged => "purple",
        EmployeeCreated or EmployeeActivated or PayrollIncluded => "success",
        EmployeeDeactivated or EmployeeDeleted or PayrollExcluded => "danger",
        SalaryChanged or BankChanged => "warning",
        _ => "info"
    };
}

/// <summary>One audit row to write (ADD).</summary>
public sealed class EmployeeAuditInput
{
    public long EmployeeId { get; init; }
    public required string TransactionType { get; init; }
    public string? FieldName { get; init; }
    public string? OldValue { get; init; }
    public string? NewValue { get; init; }
    public string? Reference { get; init; }
    public string? Remarks { get; init; }
}

/// <summary>One row of the Audit Report (LIST).</summary>
public sealed class EmployeeAuditEntry
{
    public long AuditLogId { get; init; }
    public long EmployeeId { get; init; }
    public int? CompanyId { get; init; }
    public string TransactionType { get; init; } = string.Empty;
    public string? FieldName { get; init; }
    public string? OldValue { get; init; }
    public string? NewValue { get; init; }
    public string? Reference { get; init; }
    public string? Remarks { get; init; }
    public long? ActionBy { get; init; }
    public DateTime ActionDate { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public string? CompanyName { get; init; }
    public string ActionByName { get; init; } = string.Empty;
}

/// <summary>Audit Report filters.</summary>
public sealed class EmployeeAuditFilter
{
    public int? CompanyId { get; set; }
    public string? CompanyIds { get; set; }
    public long? EmployeeId { get; set; }
    /// <summary>Transaction types to show (empty = all).</summary>
    public IReadOnlyList<string> Types { get; set; } = Array.Empty<string>();
    /// <summary>First instant shown (UTC, inclusive) - the start of the user's local "from" day.</summary>
    public DateTime? DateFromUtc { get; set; }
    /// <summary>Instant after the last one shown (UTC, exclusive) - the end of the user's local "to" day.</summary>
    public DateTime? DateToUtc { get; set; }
    public string? Search { get; set; }
    /// <summary>Date (default) / Employee / Type / Field / ChangedBy (db/62).</summary>
    public string? Sort { get; set; }
    /// <summary>ASC / DESC.</summary>
    public string? Direction { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 50;
}

/// <summary>An employee's payroll calendar (GET of Employee.usp_EmployeePayrollCalendar_Manage).</summary>
public sealed class EmployeePayrollCalendar
{
    public long EmployeeId { get; init; }
    public int CompanyId { get; init; }
    public int? PayrollCalendarId { get; init; }
    public string? CalendarCode { get; init; }
    public string? CalendarName { get; init; }
    public string? CalendarArabicName { get; init; }
    public string? PayFrequency { get; init; }
    public bool? CalendarIsActive { get; init; }
    public DateTime? LastChangedDate { get; init; }
}

/// <summary>COUNTS: how many current employees a calendar pays (null calendar = not assigned).</summary>
public sealed class CalendarEmployeeCount
{
    public int? PayrollCalendarId { get; init; }
    public int EmployeeCount { get; init; }
}
