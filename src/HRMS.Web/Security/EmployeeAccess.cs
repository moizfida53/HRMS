namespace HRMS.Web.Security;

/// <summary>
/// What the signed-in user may do on Workforce > Employees (Security > Create Roles,
/// AccessCatalog "WF.*"): the list and each section of the profile - read-only or editable.
/// </summary>
public sealed record EmployeeAccess(
    bool View, bool Create, bool Edit, bool Delete,
    bool ComplianceView, bool ComplianceEdit,
    bool DependentView, bool DependentEdit, bool DependentDelete,
    bool DocumentView, bool DocumentUpload, bool DocumentDelete)
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

    /// <summary>Change a payroll calendar once it is assigned to an employee (db/60) - administrators.</summary>
    public const string PermPayrollCalendarChange = "EMPLOYEE_PAYROLL_CALENDAR_CHANGE";

    /// <summary>Open the employee Audit Report (db/60).</summary>
    public const string PermAuditView = "AUDIT_REPORT_VIEW";
}

public static class EmployeeAccessExtensions
{
    /// <summary>
    /// The user may change an employee's payroll calendar once it is assigned (the first
    /// assignment only needs the right to create / edit the employee). System Administrator always may.
    /// </summary>
    public static bool CanChangePayrollCalendar(this ICurrentUser u) =>
        u.HasPermission(Security.EmployeeAccess.PermPayrollCalendarChange) || u.IsInRole("SYSADMIN");

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
        u.HasPermission(Security.EmployeeAccess.PermDocumentDelete));
}
