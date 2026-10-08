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

    // ---- Payroll Settings (db/29-30 masters) ----

    /// <summary>Pay item types (earning / deduction components): list, get, insert, update, delete, toggle, seed.</summary>
    public const string PayComponentManage = "Payroll.usp_PayComponent_Manage";

    /// <summary>PIFSS contribution rates (effective-dated, verified flag).</summary>
    public const string PifssRateManage = "Payroll.usp_PifssRate_Manage";

    /// <summary>End-of-service indemnity rule sets with their service slabs and entitlement factors.</summary>
    public const string IndemnityRuleSetManage = "Payroll.usp_IndemnityRuleSet_Manage";

    /// <summary>Overtime multipliers (statutory default or a company's own).</summary>
    public const string OvertimeRateManage = "Payroll.usp_OvertimeRate_Manage";

    /// <summary>The bank master (SWIFT, IBAN bank code, WPS code).</summary>
    public const string BankManage = "Payroll.usp_Bank_Manage";

    /// <summary>The company's own salary accounts (IBAN mod-97 checked, one default per company).</summary>
    public const string CompanyBankAccountManage = "Payroll.usp_CompanyBankAccount_Manage";
    public const string DeductionPolicyManage = "Payroll.usp_DeductionPolicy_Manage";
    public const string ProrationRuleManage = "Payroll.usp_ProrationRule_Manage";
    public const string ApprovalProcessManage = "Payroll.usp_ApprovalProcess_Manage";
    public const string BankFileFormatManage = "Payroll.usp_BankFileFormat_Manage";
    public const string GLMappingManage = "Payroll.usp_GLMapping_Manage";
    public const string BankFileManage = "Payroll.usp_BankFile_Manage";
    public const string BankPaymentManage = "Payroll.usp_BankPayment_Manage";
    public const string JournalManage = "Payroll.usp_Journal_Manage";
    public const string CostAllocationManage = "Payroll.usp_CostAllocation_Manage";
    public const string PayrollFinanceNavCounts = "Payroll.usp_PayrollFinance_NavCounts";
    public const string PayrollReport = "Payroll.usp_PayrollReport";
    public const string PayrollReportPeriods = "Payroll.usp_PayrollReport_Periods";
    public const string PayrollDashboard = "Payroll.usp_PayrollDashboard";

    // ---- Payslips (db/42-43) ----

    /// <summary>Payslips: payrolls, list, payslip header, generate, email queue and delivery results.</summary>
    public const string PayslipManage = "Payroll.usp_Payslip_Manage";

    /// <summary>Security > Create Roles / Assign Roles (db/57).</summary>
    public const string SecurityAdminManage = "Security.usp_SecurityAdmin_Manage";
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
