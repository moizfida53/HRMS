namespace HRMS.Data.Infrastructure;

/// <summary>
/// Every stored procedure the application is allowed to call, named once.
/// Repositories reference these constants rather than string literals, so the set
/// of reachable procedures is visible in one place and can be diffed against the
/// GRANT EXECUTE script during a security review.
/// </summary>
public static class StoredProcedure
{
    // ---- Organization Setup: one multi-action procedure per master ----
    public const string CompanyManage     = "Core.usp_Company_Manage";
    public const string BranchManage      = "Core.usp_Branch_Manage";
    public const string DepartmentManage  = "Core.usp_Department_Manage";
    public const string SectionManage     = "Core.usp_Section_Manage";
    public const string DesignationManage = "Core.usp_Designation_Manage";
    public const string JobPositionManage = "Core.usp_JobPosition_Manage";
    public const string LocationManage    = "Core.usp_Location_Manage";
    public const string CostCenterManage  = "Core.usp_CostCenter_Manage";

    // ---- Shared helpers used across the whole application ----

    /// <summary>Serves every dropdown in the system, keyed by @LookupType.</summary>
    public const string LookupGet = "Core.usp_Lookup_Get";

    /// <summary>Shared uniqueness check used by all master forms before save.</summary>
    public const string MasterCheckDuplicate = "Core.usp_Master_CheckDuplicate";

    // ---- Module 1: Authentication & Access Control ----

    /// <summary>The whole sign-in flow: lookup, success, failure, roles, permissions.</summary>
    public const string AuthManage = "Security.usp_Auth_Manage";

    // ---- Module 4: Workforce - Employees & Kuwait Compliance ----

    /// <summary>Full LIST/GET/INSERT/UPDATE/DELETE/TOGGLE envelope, same shape as every other master.</summary>
    public const string EmployeeManage = "Employee.usp_Employee_Manage";

    /// <summary>1:1 child of the employee record - GET/UPSERT only, no paging or delete of its own.</summary>
    public const string EmployeeComplianceManage = "Kuwait.usp_EmployeeCompliance_Manage";

    /// <summary>1:many child list of the employee record, scoped by @EmployeeId - no company-wide paging.</summary>
    public const string EmployeeDependentManage = "Employee.usp_EmployeeDependent_Manage";

    /// <summary>Documents tab: document types grouped by section + the employee's uploaded files.</summary>
    public const string EmployeeDocumentManage = "Documents.usp_EmployeeDocument_Manage";

    // ---- Dashboard (landing page) ----

    /// <summary>Read-only; one @Action per dashboard panel (KPI, TREND, DEPT, ...).</summary>
    public const string DashboardGet = "Employee.usp_Dashboard_Get";

    // ---- Localization (db/33): every UI label lives in Core.UiLabels ----

    /// <summary>ALL = every active label (EN + AR); VERSION = a cheap checksum for cache refresh.</summary>
    public const string UiLabelGet = "Core.usp_UiLabel_Get";

    /// <summary>LIST/GET/INSERT/UPDATE/DELETE/TOGGLE envelope for the label maintenance screen.</summary>
    public const string UiLabelManage = "Core.usp_UiLabel_Manage";

    /// <summary>GET/SET of Security.Users.PreferredLanguage.</summary>
    public const string UserLanguage = "Security.usp_User_Language";

    // ---- Payroll (db/29-30 masters, db/34-35 payroll runs) ----

    public const string PayrollCalendarManage = "Payroll.usp_PayrollCalendar_Manage";

    public const string PayrollPeriodManage = "Payroll.usp_PayrollPeriod_Manage";

    /// <summary>Payroll runs: list, create (draft -> Registered), stage changes, approvals.</summary>
    public const string PayrollRunManage = "Payroll.usp_PayrollRun_Manage";

    /// <summary>Employees and lines of a run: list, add / remove lines, exclude / include.</summary>
    public const string PayrollRunEmployeeManage = "Payroll.usp_PayrollRunEmployee_Manage";

    /// <summary>Validation results of a run: list, acknowledge a warning.</summary>
    public const string PayrollRunIssueManage = "Payroll.usp_PayrollRunIssue_Manage";

    // ---- Pay Items (db/37-38) ----

    /// <summary>Pay items: list, key figures, save, approve, reject, end, delete, history.</summary>
    public const string PayItemManage = "Payroll.usp_PayItem_Manage";

    /// <summary>Pay items from an Excel file - every row or none.</summary>
    public const string PayItemImport = "Payroll.usp_PayItem_Import";

    // ---- Final Settlement (db/39-40) ----

    /// <summary>Final settlements and leave encashment: list, calculate, lines, submit, approve, pay, cancel.</summary>
    public const string FinalSettlementManage = "Payroll.usp_FinalSettlement_Manage";

    // ---- Payslips (db/42-43) ----

    /// <summary>Payslips: payrolls, list, payslip header, generate, email queue and delivery results.</summary>
    public const string PayslipManage = "Payroll.usp_Payslip_Manage";
}

/// <summary>
/// Result codes returned in @ResultCode by the Manage procedures.
/// The UI maps these to friendly, field-level messages.
/// </summary>
public static class ResultCode
{
    public const string Success       = "SUCCESS";
    public const string DuplicateCode = "DUPLICATE_CODE";
    public const string NotFound      = "NOT_FOUND";
    public const string InUse         = "IN_USE";
    public const string CircularRef   = "CIRCULAR_REFERENCE";
    public const string InvalidAction = "INVALID_ACTION";
}
