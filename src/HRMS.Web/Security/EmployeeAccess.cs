namespace HRMS.Web.Security;

/// <summary>
/// What the signed-in user may do on Workforce > Employees (Security > Create Roles,
/// AccessCatalog "WF.*"): the list and each tab of the profile - hidden, read-only or editable
/// (db/82: Personal Info, Employment and Leave have their own rights like the other tabs;
/// Edit = Personal Info edit).
/// </summary>
public sealed record EmployeeAccess(
    bool View, bool Create, bool Edit, bool Delete,
    bool ComplianceView, bool ComplianceEdit,
    bool DependentView, bool DependentEdit, bool DependentDelete,
    bool DocumentView, bool DocumentUpload, bool DocumentDelete,
    bool PersonalView, bool EmploymentView, bool EmploymentEdit, bool LeaveView)
{
    public const string PermView = "EMPLOYEE_VIEW";
    public const string PermCreate = "EMPLOYEE_CREATE";
    public const string PermEdit = "EMPLOYEE_EDIT";
    public const string PermDelete = "EMPLOYEE_DELETE";
    public const string PermComplianceView = "EMPLOYEE_COMPLIANCE_VIEW";
    public const string PermComplianceEdit = "EMPLOYEE_COMPLIANCE_EDIT";
    public const string PermDependentView = "EMPLOYEE_DEPENDENT_VIEW";
    public const string PermDependentEdit = "EMPLOYEE_DEPENDENT_EDIT";
    public const string PermDependentDelete = "EMPLOYEE_DEPENDENT_DELETE";
    public const string PermDocumentView = "EMPLOYEE_DOCUMENT_VIEW";
    public const string PermDocumentUpload = "EMPLOYEE_DOCUMENT_UPLOAD";
    public const string PermDocumentDelete = "EMPLOYEE_DOCUMENT_DELETE";
    public const string PermPersonalView = "EMPLOYEE_PERSONAL_VIEW";
    public const string PermEmploymentView = "EMPLOYEE_EMPLOYMENT_VIEW";
    public const string PermEmploymentEdit = "EMPLOYEE_EMPLOYMENT_EDIT";
    public const string PermLeaveView = "EMPLOYEE_LEAVE_VIEW";

    /// <summary>Change a payroll calendar once it is assigned to an employee (db/60) - administrators.</summary>
    public const string PermPayrollCalendarChange = "EMPLOYEE_PAYROLL_CALENDAR_CHANGE";

    /// <summary>Open the employee Audit Report (db/60).</summary>
    public const string PermAuditView = "AUDIT_REPORT_VIEW";

    /// <summary>Set the alerts on the employee date fields (db/65) - administrators.</summary>
    public const string PermDateAlerts = "EMPLOYEE_DATE_ALERTS";

    /// <summary>Passport In / Out (db/93): see the holder and the log / record a hand-over.</summary>
    public const string PermPassportView = "EMPLOYEE_PASSPORT_VIEW";
    public const string PermPassportEdit = "EMPLOYEE_PASSPORT_EDIT";
}

public static class EmployeeAccessExtensions
{
    /// <summary>
    /// The user may change an employee's payroll calendar once it is assigned (the first
    /// assignment only needs the right to create / edit the employee). System Administrator always may.
    /// </summary>
    public static bool CanChangePayrollCalendar(this ICurrentUser u) =>
        u.HasPermission(Security.EmployeeAccess.PermPayrollCalendarChange) || u.IsInRole("SYSADMIN");

    /// <summary>The bell next to a date field: set its alerts (for every employee). System Administrator always may.</summary>
    public static bool CanManageDateAlerts(this ICurrentUser u) =>
        u.HasPermission(Security.EmployeeAccess.PermDateAlerts) || u.IsInRole("SYSADMIN");

    /// <summary>db/93: see where an employee's passport is (company / employee) and its log.</summary>
    public static bool CanViewPassportCustody(this ICurrentUser u) =>
        u.HasPermission(Security.EmployeeAccess.PermPassportView) || u.HasPermission(Security.EmployeeAccess.PermPassportEdit) || u.IsInRole("SYSADMIN");

    /// <summary>db/93: record a passport handed to / received from the employee.</summary>
    public static bool CanEditPassportCustody(this ICurrentUser u) =>
        u.HasPermission(Security.EmployeeAccess.PermPassportEdit) || u.IsInRole("SYSADMIN");

    public static bool CanViewAudit(this ICurrentUser u) =>
        u.HasPermission(Security.EmployeeAccess.PermAuditView) || u.IsInRole("SYSADMIN");

    public static EmployeeAccess EmployeeAccess(this ICurrentUser u) => new(
        u.HasPermission(Security.EmployeeAccess.PermView),
        u.HasPermission(Security.EmployeeAccess.PermCreate),
        u.HasPermission(Security.EmployeeAccess.PermEdit),
        u.HasPermission(Security.EmployeeAccess.PermDelete),
        u.HasPermission(Security.EmployeeAccess.PermComplianceView) || u.HasPermission(Security.EmployeeAccess.PermComplianceEdit),
        u.HasPermission(Security.EmployeeAccess.PermComplianceEdit),
        u.HasPermission(Security.EmployeeAccess.PermDependentView) || u.HasPermission(Security.EmployeeAccess.PermDependentEdit),
        u.HasPermission(Security.EmployeeAccess.PermDependentEdit),
        u.HasPermission(Security.EmployeeAccess.PermDependentDelete),
        u.HasPermission(Security.EmployeeAccess.PermDocumentView) || u.HasPermission(Security.EmployeeAccess.PermDocumentUpload),
        u.HasPermission(Security.EmployeeAccess.PermDocumentUpload),
        u.HasPermission(Security.EmployeeAccess.PermDocumentDelete),
        u.HasPermission(Security.EmployeeAccess.PermPersonalView) || u.HasPermission(Security.EmployeeAccess.PermEdit),
        u.HasPermission(Security.EmployeeAccess.PermEmploymentView) || u.HasPermission(Security.EmployeeAccess.PermEmploymentEdit),
        u.HasPermission(Security.EmployeeAccess.PermEmploymentEdit),
        u.HasPermission(Security.EmployeeAccess.PermLeaveView));
}
