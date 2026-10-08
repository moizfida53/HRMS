using System.Globalization;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Web.Models.Payroll;

// ===========================================================================
// Bank Processing, Accounting and Payroll Reports (db/49-51)
// ===========================================================================

/// <summary>A select of the filter bar: query name, aria label, (value, text) options, the chosen value.</summary>
public sealed record FinanceSelect(string Name, string Label, IReadOnlyList<(string Value, string Text)> Options, string? Selected);

/// <summary>
/// The filter row of the Bank Processing / Accounting / Reports pages (_FinanceFilters):
/// a GET form with Year and Month (the month list follows the year), extra selects,
/// an optional search, and the record count badge - all in one row.
/// </summary>
public sealed class FinanceFilterBar
{
    public required string Action { get; init; }
    public IReadOnlyList<int> Years { get; init; } = Array.Empty<int>();
    /// <summary>The months offered (first day of the month).</summary>
    public IReadOnlyList<DateTime> Months { get; init; } = Array.Empty<DateTime>();
    public int? Year { get; init; }
    public DateTime? Month { get; init; }
    /// <summary>Offer "All months" (lists); off where a month must be chosen (reports).</summary>
    public bool AllMonths { get; init; } = true;
    public bool AllYears { get; init; }
    public IReadOnlyList<FinanceSelect> Selects { get; init; } = Array.Empty<FinanceSelect>();
    /// <summary>Kept as hidden fields (e.g. the chosen report).</summary>
    public IReadOnlyDictionary<string, string?> Hidden { get; init; } = new Dictionary<string, string?>();
    public string? Search { get; init; }
    public string? SearchPlaceholder { get; init; }
    /// <summary>The text of the count badge (null = no badge).</summary>
    public string? CountText { get; init; }
}

public sealed class FinanceRights
{
    public bool CanView { get; init; }
    public bool CanAct { get; init; }
}

/// <summary>"2026-09" -> 1 Sep 2026; the months / years offered by the filters.</summary>
public static class FinancePeriod
{
    public static int? ValidYear(int? year) => year is >= 2000 and <= 2100 ? year : null;

    public static DateTime? ParseMonth(string? month) =>
        DateTime.TryParseExact(month, "yyyy-MM", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;

    public static string Key(DateTime month) => month.ToString("yyyy-MM", CultureInfo.InvariantCulture);

    /// <summary>The 12 months of the years given (newest first) - for screens not tied to payrolls.</summary>
    public static IReadOnlyList<DateTime> MonthsOf(IEnumerable<int> years) =>
        years.SelectMany(y => Enumerable.Range(1, 12).Select(m => new DateTime(y, m, 1))).OrderByDescending(d => d).ToList();
}

// ------------------------------------------------------------------ bank

public sealed class BankFilePageModel
{
    public required FinanceFilterBar Filters { get; init; }
    public required FinanceRights Rights { get; init; }
    public IReadOnlyList<FinanceRun> Runs { get; init; } = Array.Empty<FinanceRun>();
    public FinanceRun? Run { get; init; }
    public IReadOnlyList<BankReviewRow> Review { get; init; } = Array.Empty<BankReviewRow>();
    public IReadOnlyList<BankReviewRow> RetryReview { get; init; } = Array.Empty<BankReviewRow>();
    public IReadOnlyList<CompanyBankAccount> Accounts { get; init; } = Array.Empty<CompanyBankAccount>();
    public IReadOnlyList<BankFileFormat> Formats { get; init; } = Array.Empty<BankFileFormat>();
    public IReadOnlyList<BankFile> Files { get; init; } = Array.Empty<BankFile>();

    public bool HasLiveFile => Files.Any(f => f.Status != "SUPERSEDED" && f.FileKind == "FULL");
    public int? DefaultFormatId => Formats.FirstOrDefault(f => f.IsDefault)?.BankFileFormatId ?? Formats.FirstOrDefault()?.BankFileFormatId;
}

public sealed class PaymentRegisterModel
{
    public required FinanceFilterBar Filters { get; init; }
    public required FinanceRights Rights { get; init; }
    public required PagedResult<BankPayment> Page { get; init; }
    public PaymentSummary Summary { get; init; } = new();
    public bool ManyCompanies { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class PaymentHistoryModel
{
    public required FinanceFilterBar Filters { get; init; }
    public required FinanceRights Rights { get; init; }
    public required PagedResult<BankFile> Page { get; init; }
    public bool ManyCompanies { get; init; }
    public bool IsFiltered { get; init; }
}

// ------------------------------------------------------------ accounting

public sealed class JournalPageModel
{
    public required FinanceFilterBar Filters { get; init; }
    public required FinanceRights Rights { get; init; }
    public IReadOnlyList<FinanceRun> Runs { get; init; } = Array.Empty<FinanceRun>();
    public FinanceRun? Run { get; init; }
    public PayrollJournal? Journal { get; init; }
    public IReadOnlyList<JournalLine> Lines { get; init; } = Array.Empty<JournalLine>();
    public AccountingDefaults? Defaults { get; init; }

    public decimal TotalDebit => Lines.Sum(l => l.Debit);
    public decimal TotalCredit => Lines.Sum(l => l.Credit);
    public int UnmappedCount => Lines.Count(l => l.IsUnmapped);
}

public sealed class PostingPageModel
{
    public required FinanceFilterBar Filters { get; init; }
    public required FinanceRights Rights { get; init; }
    public required PagedResult<PayrollJournal> Page { get; init; }
    public bool ManyCompanies { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class AllocationFormModel
{
    public required CostAllocation Allocation { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public int? CompanyId { get; init; }
    public IReadOnlyList<LookupItem> Employees { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyList<LookupItem> CostCenters { get; init; } = Array.Empty<LookupItem>();
}

/// <summary>Label keys and badges of the finance screens.</summary>
public static class FinanceFormat
{
    public static string FileStatusKey(string? s) => s switch { "SENT" => "fin.file_sent", "SUPERSEDED" => "fin.file_superseded", _ => "fin.file_generated" };
    public static string FileStatusBadge(string? s) => s switch { "SENT" => "success", "SUPERSEDED" => "muted", _ => "info" };

    public static string PaymentStatusKey(string? s) => s switch
    {
        "PAID" => "fin.pay_paid", "FAILED" => "fin.pay_failed", "IN_FILE" => "fin.pay_in_file", _ => "fin.pay_pending"
    };
    public static string PaymentStatusBadge(string? s) => s switch { "PAID" => "success", "FAILED" => "danger", "IN_FILE" => "info", _ => "warning" };

    public static string JournalStatusKey(string? s) => s switch
    {
        "EXPORTED" => "fin.jv_exported", "POSTED" => "fin.jv_posted", "REVERSED" => "fin.jv_reversed", _ => "fin.jv_ready"
    };
    public static string JournalStatusBadge(string? s) => s switch { "EXPORTED" => "info", "POSTED" => "success", "REVERSED" => "muted", _ => "warning" };

    /// <summary>KW81 NBOK 0000 ... (groups of four).</summary>
    public static string Iban(string? iban) =>
        string.IsNullOrEmpty(iban) ? "—" : System.Text.RegularExpressions.Regex.Replace(iban, ".{4}(?!$)", "$0 ");
}

// --------------------------------------------------------------- reports

public enum ReportColumnKind { Text, Code, Money, Number, Percent, Date, Month, Status }

public sealed record ReportColumn(string Key, string LabelKey, ReportColumnKind Kind = ReportColumnKind.Text, bool Total = false);

public sealed record ReportDefinition(string Code, string Family, string TitleKey, string HintKey, string Icon, IReadOnlyList<ReportColumn> Columns,
                                      bool UsesDepartment = true, string? NoteKey = null);

/// <summary>The payroll reports, by tab (family): payroll, salary, deduction, overtime, compliance.</summary>
public static class ReportCatalog
{
    private static ReportColumn Emp => new("EmployeeNo", "fin.col_employee_no", ReportColumnKind.Code);
    private static ReportColumn Name => new("EmployeeName", "pr.employee");
    private static ReportColumn Dept => new("DepartmentName", "common.department");
    private static ReportColumn Money(string key, string label) => new(key, label, ReportColumnKind.Money, true);

    public static readonly IReadOnlyList<ReportDefinition> All =
    [
        new("PAY_REGISTER", "payroll", "prv.payroll_register", "prv.every_employee_every_component", "receipt",
            [Emp, Name, Dept, new("RunCode", "fin.col_payroll", ReportColumnKind.Code), Money("Salary", "fin.col_salary"),
             Money("Earnings", "pr.earnings"), Money("Deductions", "pr.deductions"), Money("Net", "pr.net_kwd")]),
        new("PAY_DEPT", "payroll", "prv.summary_by_department", "fin.dept_hint", "layers",
            [Dept, new("Employees", "common.employees", ReportColumnKind.Number, true), Money("Gross", "prv.gross_kwd"),
             Money("Deductions", "pr.deductions"), Money("Net", "pr.net_kwd")]),
        new("PAY_VARIANCE", "payroll", "prv.variance_month_on_month", "fin.variance_hint", "chart",
            [Emp, Name, Dept, Money("PreviousNet", "fin.col_previous_net"), Money("CurrentNet", "fin.col_current_net"),
             Money("Difference", "fin.col_difference"), new("ChangePercent", "fin.col_change", ReportColumnKind.Percent),
             new("ChangeType", "common.status", ReportColumnKind.Status)]),
        new("PAY_COST", "payroll", "prv.employer_cost", "fin.cost_hint", "building",
            [Dept, new("Employees", "common.employees", ReportColumnKind.Number, true), Money("Gross", "prv.gross_kwd"),
             Money("EmployerPifss", "prv.employer_share"), Money("TotalCost", "fin.col_total_cost")], NoteKey: "fin.cost_note"),

        new("SAL_GRADE", "salary", "fin.rep_sal_grade", "fin.grade_hint", "badge",
            [new("GradeName", "common.grade"), new("Employees", "common.employees", ReportColumnKind.Number, true),
             new("MinSalary", "fin.col_min_salary", ReportColumnKind.Money), new("AvgSalary", "fin.col_avg_salary", ReportColumnKind.Money),
             new("MaxSalary", "fin.col_max_salary", ReportColumnKind.Money)]),
        new("SAL_REVISIONS", "salary", "prv.revision_history", "prv.all_revisions_in_a_date_range", "history",
            [new("ChangeDate", "fin.col_date", ReportColumnKind.Date), Emp, Name, new("ComponentName", "prv.component"),
             new("OldAmount", "fin.col_old", ReportColumnKind.Money), new("NewAmount", "fin.col_new", ReportColumnKind.Money),
             new("Difference", "fin.col_difference", ReportColumnKind.Money), new("Comment", "pr.reason"), new("ChangedBy", "prv.user")]),
        new("SAL_TREND", "salary", "prv.headcount_and_cost_trend", "fin.trend_hint", "chart",
            [new("RunMonth", "pr.period", ReportColumnKind.Month), new("Employees", "common.employees", ReportColumnKind.Number),
             Money("Gross", "prv.gross_kwd"), Money("Deductions", "pr.deductions"), Money("Net", "pr.net_kwd")]),

        new("DED_COMPONENT", "deduction", "prv.deductions_by_component", "prv.per_period", "percent",
            [new("ComponentName", "prv.component"), new("ComponentCode", "common.code", ReportColumnKind.Code),
             new("Employees", "common.employees", ReportColumnKind.Number), Money("Amount", "pr.amount_kwd")]),
        new("DED_EMPLOYEE", "deduction", "fin.rep_ded_employee", "fin.rep_ded_employee_hint", "users",
            [Emp, Name, Dept, Money("Pifss", "fin.col_pifss"), Money("Loans", "fin.col_loans"), Money("Other", "fin.col_other"),
             Money("Total", "fin.col_total")]),
        new("DED_LOANS", "deduction", "prv.loans_outstanding", "fin.loans_hint", "wallet",
            [Emp, Name, new("ComponentName", "prv.component"), Money("TotalAmount", "fin.col_loan_total"),
             new("Instalment", "fin.col_instalment", ReportColumnKind.Money), Money("Recovered", "fin.col_recovered"),
             Money("Balance", "fin.col_balance"), new("InstalmentsLeft", "fin.col_left", ReportColumnKind.Number),
             new("StartMonth", "fin.col_start", ReportColumnKind.Month)]),

        new("OT_EMPLOYEE", "overtime", "fin.rep_ot_employee", "fin.rep_ot_employee_hint", "clock",
            [Emp, Name, Dept, new("Lines", "fin.col_entries", ReportColumnKind.Number, true), Money("Amount", "pr.amount_kwd"),
             new("PercentOfSalary", "fin.col_pct_salary", ReportColumnKind.Percent)], NoteKey: "fin.ot_note"),
        new("OT_DEPT", "overtime", "fin.rep_ot_dept", "fin.rep_ot_dept_hint", "layers",
            [Dept, new("Employees", "common.employees", ReportColumnKind.Number, true), new("Lines", "fin.col_entries", ReportColumnKind.Number, true),
             Money("Amount", "pr.amount_kwd")], NoteKey: "fin.ot_note"),

        new("CMP_PIFSS", "compliance", "prv.pifss_contribution_report", "prv.employee_employer_share_kuwaiti_staff", "shield",
            [Emp, Name, new("CivilId", "prv.civil_id", ReportColumnKind.Code), Money("ContributorySalary", "prv.contributory_salary"),
             Money("EmployeeShare", "prv.employee_share"), Money("EmployerShare", "prv.employer_share"), Money("Total", "fin.col_total")]),
        new("CMP_WPS", "compliance", "prv.wps_submission_report", "prv.files_sent_per_period", "bank",
            [new("FileNo", "fin.col_file", ReportColumnKind.Code), new("RunCode", "fin.col_payroll", ReportColumnKind.Code),
             new("BankName", "prv.bank"), new("FileKind", "prv.type", ReportColumnKind.Status),
             new("LineCount", "pr.lines", ReportColumnKind.Number, true), Money("TotalAmount", "pr.amount_kwd"),
             new("ValueDate", "fin.col_value_date", ReportColumnKind.Date), new("Status", "common.status", ReportColumnKind.Status),
             new("PaidCount", "fin.col_paid", ReportColumnKind.Number, true), new("FailedCount", "fin.col_failed", ReportColumnKind.Number, true)],
            UsesDepartment: false),
        new("CMP_AUDIT", "compliance", "prv.audit_report", "fin.audit_hint", "history",
            [new("ActionDate", "prv.when", ReportColumnKind.Date), new("RunCode", "fin.col_payroll", ReportColumnKind.Code),
             new("ActionCode", "fin.col_action", ReportColumnKind.Status), new("FromStage", "fin.col_from", ReportColumnKind.Status),
             new("ToStage", "fin.col_to", ReportColumnKind.Status), new("Comment", "pr.reason"), new("ActionBy", "prv.user")],
            UsesDepartment: false)
    ];

    public static readonly IReadOnlyList<string> Families = ["payroll", "salary", "deduction", "overtime", "compliance"];

    public static IReadOnlyList<ReportDefinition> Of(string family) => All.Where(r => r.Family == family).ToList();

    public static ReportDefinition? Find(string? code) => All.FirstOrDefault(r => string.Equals(r.Code, code, StringComparison.OrdinalIgnoreCase));
}

public sealed class ReportPageModel
{
    public required string Family { get; init; }
    public required ReportDefinition Report { get; init; }
    public required FinanceFilterBar Filters { get; init; }
    public IReadOnlyList<ReportDefinition> Reports { get; init; } = Array.Empty<ReportDefinition>();
    public IReadOnlyList<IDictionary<string, object?>> Rows { get; init; } = Array.Empty<IDictionary<string, object?>>();
    public bool HasPeriods { get; init; }
    public string ExportUrl { get; init; } = string.Empty;
}
