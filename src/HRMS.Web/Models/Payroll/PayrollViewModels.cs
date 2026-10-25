using System.Globalization;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;

namespace HRMS.Web.Models.Payroll;

/// <summary>
/// The Payroll menu: one sidebar link per section, and a tab rail per section
/// (same look as the prototypes in ui-prototypes/payroll). Payroll Processing is
/// live; the other sections are embedded as previews and are wired up one by one.
/// </summary>
public static class PayrollNav
{
    public sealed record Tab(string Slug, string Title, bool IsLive = false);

    /// <param name="SubNav">The sidebar opens the section into its pages (sub-sections) instead of a tab rail.</param>
    public sealed record Section(string Key, string Title, string Icon, IReadOnlyList<Tab> Tabs, bool SubNav = false);

    /// <summary>Payroll Settings - shown under Setup in the sidebar, not under Payroll.</summary>
    public const string SettingsKey = "settings";

    public static readonly IReadOnlyList<Section> Sections =
    [
        new("dashboard", "Payroll Dashboard", "grid", [new("payroll-dashboard", "Dashboard", true)]),
        new("processing", "Payroll Processing", "calculator",
        [
            // Payroll Calendar and Period are set up once, under Setup > Payroll Settings:
            // Create Payroll works them out from each employee's calendar and the month
            new("payrolls", "Payrolls", true), new("history", "Payroll History", true),
            new("compare", "Payroll Comparison", true)
        ], SubNav: true),
        new("payitems", "Pay Items", "card", [new("pay-items", "Pay Items", true)]),
        new("settlement", "Final Settlement", "exit",
            [new("fs-list", "Settlements", true), new("fs-new", "New Settlement", true), new("fs-encashment", "Leave Encashment", true)]),
        new("payslips", "Payslips", "receipt",
            [new("slip-generate", "Generate Payslips", true), new("slip-employee", "Employee Payslips", true), new("slip-email", "Email Payslips", true)],
            SubNav: true),
        new("bank", "Bank Processing", "bank",
            [new("bk-file", "Bank File", true), new("bk-register", "Payment Register", true), new("bk-history", "Payment History", true)],
            SubNav: true),
        new("accounting", "Accounting", "book",
            [new("ac-journal", "Payroll Journal", true), new("ac-posting", "GL Posting", true), new("ac-allocation", "Cost Center Allocation", true)],
            SubNav: true),
        // Payroll Reports keeps its tab rail (one page per report family)
        new("reports", "Payroll Reports", "chart",
        [
            new("rp-payroll", "Payroll Reports", true), new("rp-salary", "Salary Reports", true), new("rp-deduction", "Deduction Reports", true),
            new("rp-overtime", "Overtime Reports", true), new("rp-compliance", "Compliance Reports", true)
        ]),
        new("settings", "Payroll Settings", "sliders",
        [
            new("calendars", "Payroll Calendar", true), new("pay-periods", "Period", true),
            new("st-rules", "Payroll Rules", true), new("st-components", "Pay Item Types", true), new("st-deduction-rules", "Deduction Rules", true),
            new("st-proration", "Proration Rules", true), new("st-approval", "Approval Workflow", true), new("st-banks", "Banks & Accounts", true),
            new("st-bank-formats", "Bank Formats", true), new("st-gl-mapping", "GL Mapping", true)
        ], SubNav: true),
    ];

    /// <summary>Preview pages that are not on a tab rail (opened from another page).</summary>
    public static readonly IReadOnlyDictionary<string, string> ExtraPages = new Dictionary<string, string>
    {
        // Payroll Processing pages opened from Payrolls (no entry of their own in the sidebar)
        ["create"] = "processing",
        ["register"] = "processing",
        ["validation"] = "processing",
        ["approval"] = "processing",
        ["calendar"] = "processing",
        ["slip-view"] = "payslips",
        ["slip-my"] = "payslips",
        ["fs-detail"] = "settlement"
    };

    /// <summary>
    /// The sidebar sub-section a page belongs to (highlight): a payroll's stage pages and
    /// Create Payroll belong to Payrolls, a payslip to Employee Payslips.
    /// </summary>
    public static string? SubSection(string? slug) => slug switch
    {
        "slip-generate" or "slip-employee" or "slip-email" => slug,
        "bk-file" or "bk-register" or "bk-history" or "ac-journal" or "ac-posting" or "ac-allocation" => slug,
        _ when slug?.StartsWith("st-", StringComparison.Ordinal) == true => slug,
        "slip-view" => "slip-employee",
        "payrolls" or "create" or "register" or "validation" or "approval" => "payrolls",
        "calendars" or "calendar" => "calendars",
        "pay-periods" => "pay-periods",
        "history" => "history",
        "compare" => "compare",
        _ => null
    };

    public static Section? SectionOfSlug(string slug) =>
        Sections.FirstOrDefault(s => s.Tabs.Any(t => t.Slug == slug))
        ?? (ExtraPages.TryGetValue(slug, out var key) ? Sections.FirstOrDefault(s => s.Key == key) : null);

    public static string Url(string slug) => slug.StartsWith("st-", StringComparison.Ordinal) && IsPreview(slug) ? $"/payroll/preview/{slug}" : slug switch
    {
        "payrolls" or "calendars" or "pay-periods" or "calendar" or "create" or "register" or "validation" or "approval" or "history" or "compare"
            or "pay-items" => $"/payroll/{slug}",
        "payroll-dashboard" => "/payroll/dashboard",
        "fs-list" => "/payroll/settlement",
        "fs-new" => "/payroll/settlement/new",
        "fs-encashment" => "/payroll/settlement/encashment",
        "slip-generate" => "/payroll/payslips/generate",
        "slip-employee" => "/payroll/payslips/employees",
        "slip-email" => "/payroll/payslips/email",
        "slip-my" => "/payroll/payslips/my",
        "st-rules" => "/payroll/settings/rules",
        "st-components" => "/payroll/settings/item-types",
        "st-deduction-rules" => "/payroll/settings/deduction-rules",
        "st-proration" => "/payroll/settings/proration",
        "st-approval" => "/payroll/settings/approval",
        "st-banks" => "/payroll/settings/banks",
        "st-bank-formats" => "/payroll/settings/bank-formats",
        "st-gl-mapping" => "/payroll/settings/gl-mapping",
        "bk-file" => "/payroll/bank/file",
        "bk-register" => "/payroll/bank/register",
        "bk-history" => "/payroll/bank/history",
        "ac-journal" => "/payroll/accounting/journal",
        "ac-posting" => "/payroll/accounting/posting",
        "ac-allocation" => "/payroll/accounting/allocation",
        _ when slug.StartsWith("rp-", StringComparison.Ordinal) => $"/payroll/reports/{slug[3..]}",
        _ => $"/payroll/preview/{slug}"
    };

    /// <summary>True for a payroll page that is still a design preview (Views/Payroll/Preview).</summary>
    public static bool IsPreview(string slug) =>
        Sections.SelectMany(s => s.Tabs).FirstOrDefault(t => t.Slug == slug) is { IsLive: false };

    /// <summary>The Final Settlement and Payslips preview pages that were replaced by the live screens (old links still work).</summary>
    public static string? ReplacedPreview(string slug) => slug switch
    {
        _ when Sections.SelectMany(s => s.Tabs).Any(t => t.Slug == slug && t.IsLive)
               && (slug.StartsWith("st-", StringComparison.Ordinal) || slug.StartsWith("bk-", StringComparison.Ordinal)
                   || slug.StartsWith("ac-", StringComparison.Ordinal) || slug.StartsWith("rp-", StringComparison.Ordinal)) => Url(slug),
        "slip-generate" or "slip-employee" or "slip-email" or "slip-my" or "payroll-dashboard" => Url(slug),
        "slip-view" => "/payroll/payslips/employees",
        "fs-history" => "/payroll/settlement",
        "fs-resignation" => "/payroll/settlement/new?type=RESIGNATION",
        "fs-termination" => "/payroll/settlement/new?type=TERMINATION",
        "fs-encashment" => "/payroll/settlement/encashment",
        _ => null
    };

    /// <summary>"fs-resignation" -> "FsResignation" (the preview view's file name).</summary>
    public static string PreviewView(string slug) =>
        string.Concat(slug.Split('-', StringSplitOptions.RemoveEmptyEntries)
            .Select(p => char.ToUpperInvariant(p[0]) + p[1..]));
}

/// <summary>Money, dates and period names for the payroll screens (Western digits in both languages).</summary>
public static class PayrollFormat
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string Money(decimal value) =>
        value < 0 ? "-" + Math.Abs(value).ToString("N3", Inv) : value.ToString("N3", Inv);

    public static string Money(decimal? value, string empty = "—") => value is { } v ? Money(v) : empty;

    public static string Signed(decimal value) =>
        value > 0 ? "+" + value.ToString("N3", Inv) : Money(value);

    public static string Count(int value) => value.ToString("N0", Inv);

    public static string Amount(decimal value) => value.ToString("0.000", Inv);

    /// <summary>"October 2026", or for weekly / bi-weekly calendars "Week 41 (05 Oct – 11 Oct)".</summary>
    public static string Period(IUiText L, string frequency, int? periodNumber, DateTime start, DateTime end, DateTime runMonth)
    {
        if (frequency == "MONTHLY")
        {
            return L.MonthYear(runMonth);
        }

        var label = frequency == "WEEKLY"
            ? L["pr.week_n", periodNumber ?? 0]
            : L["pr.fortnight_n", periodNumber ?? 0];
        return $"{label} ({L.DayMonth(start)} – {L.DayMonth(end)})";
    }

    public static string Period(IUiText L, PayrollRun run) =>
        Period(L, run.PayFrequency, run.PeriodNumber, run.StartDate, run.EndDate, run.RunMonth);

    public static string Period(IUiText L, PayrollPeriodRow p) =>
        Period(L, p.PayFrequency, p.PeriodNumber, p.StartDate, p.EndDate, p.RunMonth);

    /// <summary>Monthly / Weekly / Bi-weekly.</summary>
    public static string Frequency(IUiText L, string? frequency) => frequency switch
    {
        "WEEKLY" => L["pr.weekly"], "BIWEEKLY" => L["pr.bi_weekly"], _ => L["pr.monthly"]
    };

    /// <summary>Pay item class name (SALARY / EARNING / DEDUCTION / LOAN / statutory).</summary>
    public static string ItemClass(IUiText L, string itemClass) => itemClass switch
    {
        "SALARY" => L["pr.salary"], "EARNING" => L["pr.earning"], "DEDUCTION" => L["pr.deduction"],
        "LOAN" => L["pr.loan_advance"], _ => L["pr.statutory"]
    };

    public static string ItemClassBadge(string itemClass) => itemClass switch
    {
        "SALARY" => "info", "EARNING" => "success", "DEDUCTION" => "warning", "LOAN" => "purple", _ => "muted"
    };

    public static string Calendar(IUiText L, string name, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic : name;

    public static string EmployeeName(IUiText L, string? english, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : english ?? string.Empty;

    /// <summary>"+3.4%", "-1.0%", "0.0%" or "—" when there is no percentage.</summary>
    public static string Percent(decimal? pct) =>
        pct is not { } p ? "—" : (p > 0 ? "+" : string.Empty) + p.ToString("0.0", Inv) + "%";

    public static string Signed(decimal? value, string empty = "—") => value is { } v ? Signed(v) : empty;

    /// <summary>pr-pos / pr-neg for a difference.</summary>
    public static string? DiffClass(decimal? value) => value > 0 ? "pr-pos" : value < 0 ? "pr-neg" : null;

    public static string ChangePercent(decimal net, decimal? previous)
    {
        if (previous is not { } prev || prev == 0)
        {
            return "—";
        }

        var pct = (net - prev) * 100m / prev;
        return (pct > 0 ? "+" : string.Empty) + pct.ToString("0.0", Inv) + "%";
    }
}

// ===========================================================================
// Pages
// ===========================================================================

/// <summary>Shared header of Register / Validation / Approval: which payroll, where it is.</summary>
public sealed class RunBarModel
{
    public required PayrollRun Run { get; init; }
    public required IReadOnlyList<PayrollRun> Runs { get; init; }
    /// <summary>0 = Register, 1 = Validation, 2 = Approval.</summary>
    public required int PageStage { get; init; }
    public bool CanCancel { get; init; }
}

public sealed class RunPageModel
{
    public PayrollRun? Run { get; init; }
    public IReadOnlyList<PayrollRun> Runs { get; init; } = Array.Empty<PayrollRun>();
    public PayrollRunSummary Summary { get; init; } = new();
    public IReadOnlyList<PayrollRunHistoryEntry> History { get; init; } = Array.Empty<PayrollRunHistoryEntry>();
    public IReadOnlyList<PayComponentOption> Components { get; init; } = Array.Empty<PayComponentOption>();
    public IReadOnlyList<PayrollRunEmployee> BiggestChanges { get; init; } = Array.Empty<PayrollRunEmployee>();
    public int PageStage { get; init; }
    public bool CanProcess { get; init; }
    public bool CanCancel { get; init; }
    public bool CanReopen { get; init; }
    /// <summary>1 or 2 when the user can take the next approval decision, else 0.</summary>
    public int CanApproveLevel { get; init; }
    public bool IsSelfApprovalBlocked { get; init; }

    public bool IsEditable => Run is { Stage: RunStage.Registered } && CanProcess;

    public RunBarModel Bar => new() { Run = Run!, Runs = Runs, PageStage = PageStage, CanCancel = CanCancel };
}

/// <summary>The Payrolls, Payroll Calendar and Period pages (one model, each page uses its part).</summary>
public sealed class CalendarPageModel
{
    public IReadOnlyList<RunMonthOption> Months { get; init; } = Array.Empty<RunMonthOption>();
    public DateTime? SelectedMonth { get; init; }
    /// <summary>Payrolls: the stage filter - "LIVE" (open payrolls, the default), a stage, or "" for every stage.</summary>
    public string SelectedStage { get; init; } = "LIVE";
    public bool CanProcess { get; init; }
    /// <summary>Payrolls: "Pending Generate PaySlips" ticked (?slips=pending).</summary>
    public bool PayslipPending { get; init; }
    public bool CanCreateCalendar { get; init; }
    public IReadOnlyList<PayrollCalendar> Calendars { get; init; } = Array.Empty<PayrollCalendar>();
    public int? SelectedCalendarId { get; init; }
    public int SelectedYear { get; init; }
    public bool CanSetup { get; init; }
}

/// <summary>Create Payroll, step 1: the month and type the payrolls are made for (create-drafts).</summary>
public sealed class CreateDraftsInput
{
    public int CompanyId { get; set; }
    /// <summary>yyyy-MM</summary>
    public string? Month { get; set; }
    public string? RunType { get; set; }
    /// <summary>The drafts already made on the page (CSV of run ids) - kept, or discarded when no longer needed.</summary>
    public string? Drafts { get; set; }
    public string? Description { get; set; }
    public int? ScopeDepartmentId { get; set; }
    public int? ScopeWorkLocationId { get; set; }
    public string? ScopeEmploymentType { get; set; }
    public string? ScopeNationality { get; set; }
}

public sealed class CreatePageModel
{
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public int? CompanyId { get; init; }
    public IReadOnlyList<LookupItem> Departments { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyList<LookupItem> Locations { get; init; } = Array.Empty<LookupItem>();
    /// <summary>The user's unfinished drafts, grouped by company, month and type (offered to continue).</summary>
    public IReadOnlyList<DraftGroup> DraftGroups { get; init; } = Array.Empty<DraftGroup>();
    /// <summary>The drafts being resumed (?drafts=1,2) - one per payroll calendar, same company / month / type.</summary>
    public IReadOnlyList<PayrollRun> Resume { get; init; } = Array.Empty<PayrollRun>();
    public bool CanProcess { get; init; }
}

/// <summary>Draft payrolls made together by Create Payroll (one per calendar).</summary>
public sealed record DraftGroup(IReadOnlyList<long> Ids, int CompanyId, DateTime RunMonth, string RunType,
                                DateTime LastSaved, IReadOnlyList<string> Calendars);

public sealed class HistoryPageModel
{
    public IReadOnlyList<int> Years { get; init; } = Array.Empty<int>();
    /// <summary>The payroll months (periods) of the closed and cancelled payrolls, newest first.</summary>
    public IReadOnlyList<DateTime> Months { get; init; } = Array.Empty<DateTime>();
}

/// <summary>Payroll Comparison: up to three payrolls of one company, closed or still in progress.</summary>
public sealed class ComparePageModel
{
    public const int MaxRuns = 3;

    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public int? CompanyId { get; init; }
    /// <summary>The company's payrolls that can be compared (every stage but draft and cancelled), newest first.</summary>
    public IReadOnlyList<PayrollRun> Runs { get; init; } = Array.Empty<PayrollRun>();
    /// <summary>The payrolls picked (first = baseline); compared on load when there are two or more.</summary>
    public IReadOnlyList<long> Selected { get; init; } = Array.Empty<long>();
}

public sealed class PreviewPageModel
{
    public required string Slug { get; init; }
    public required PayrollNav.Section Section { get; init; }
}

// ===========================================================================
// Partials
// ===========================================================================

public sealed class RunsGridModel
{
    public required PagedResult<PayrollRun> Page { get; init; }
    /// <summary>"payrolls" (open payrolls, or any stage) or "history" (closed and cancelled).</summary>
    public string Mode { get; init; } = "payrolls";
    public bool IsFiltered { get; init; }
    /// <summary>Only the open payrolls were asked for (the Payrolls default).</summary>
    public bool OpenOnly { get; init; }
    /// <summary>"Pending Generate PaySlips": closed payrolls with payslips still to generate.</summary>
    public bool PayslipPending { get; init; }
    /// <summary>The user may open Generate Payslips (Goto PaySlips).</summary>
    public bool CanSlips { get; init; }
}

public sealed class RunEmployeesGridModel
{
    public required PayrollRun Run { get; init; }
    public required PagedResult<PayrollRunEmployee> Page { get; init; }
    /// <summary>"create" (wizard step 2), "register" or "approval".</summary>
    public string Mode { get; init; } = "register";
    public bool Editable { get; init; }
    public string? Filter { get; init; }
    public string? Search { get; init; }
}

public sealed class RunLinesModel
{
    public required PayrollRun Run { get; init; }
    public required long EmployeeId { get; init; }
    public required IReadOnlyList<PayrollRunLine> Lines { get; init; }
    public IReadOnlyList<PayComponentOption> Components { get; init; } = Array.Empty<PayComponentOption>();
    public bool Editable { get; init; }
    /// <summary>May exclude / include the employee (Security: "Exclude / include employees").</summary>
    public bool CanExclude { get; init; }
    public bool HasSalary { get; init; } = true;
    public bool IsExcluded { get; init; }
    public string? ExcludeReason { get; init; }
}

public sealed class RunIssuesGridModel
{
    public required PayrollRun Run { get; init; }
    public required PagedResult<PayrollRunIssue> Page { get; init; }
    public bool CanAcknowledge { get; init; }
    public bool CanExclude { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class CalendarsGridModel
{
    public required PagedResult<PayrollCalendar> Page { get; init; }
    public bool CanSetup { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class PeriodsGridModel
{
    public PayrollCalendar? Calendar { get; init; }
    public IReadOnlyList<PayrollPeriodRow> Periods { get; init; } = Array.Empty<PayrollPeriodRow>();
    public int Year { get; init; }
    public bool CanSetup { get; init; }
    public string? CompanyName { get; init; }
}

public sealed class CalendarFormModel
{
    public required PayrollCalendar Calendar { get; init; }
    public bool IsNew { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyList<LookupItem> Currencies { get; init; } = Array.Empty<LookupItem>();
    public bool ScheduleLocked { get; init; }
}

public sealed class PeriodFormModel
{
    public required PayrollPeriodEdit Period { get; init; }
}

/// <summary>
/// The comparison of 2-3 payrolls of one company. Runs[0] is the baseline:
/// every difference is "this payroll minus the baseline". Arrays are indexed like Runs.
/// </summary>
public sealed class PayrollComparison
{
    public required IReadOnlyList<PayrollRun> Runs { get; init; }
    public required IReadOnlyList<CompareTotals> Totals { get; init; }
    public required IReadOnlyList<CompareItemRow> Items { get; init; }
    public required IReadOnlyList<CompareEmployeeRow> Employees { get; init; }

    public PayrollRun Baseline => Runs[0];
    public IReadOnlyList<PayrollRun> OpenRuns => Runs.Where(r => !r.IsClosed).ToList();

    /// <summary>value - baseline; null when the payroll has no value (employee or item not in it).</summary>
    public static decimal? Diff(IReadOnlyList<decimal?> values, int index) =>
        values[index] is null && values[0] is null ? null : (values[index] ?? 0) - (values[0] ?? 0);

    /// <summary>Change against the baseline in percent; null when the baseline is zero or missing.</summary>
    public static decimal? Percent(IReadOnlyList<decimal?> values, int index) =>
        values[0] is { } b && b != 0 ? Math.Round(((values[index] ?? 0) - b) / Math.Abs(b) * 100m, 1) : null;
}

/// <summary>Totals of one payroll over its included employees.</summary>
public sealed class CompareTotals
{
    public int Employees { get; init; }
    public int Joiners { get; init; }
    public int Leavers { get; init; }
    public decimal Salary { get; init; }
    public decimal Earnings { get; init; }
    public decimal Deductions { get; init; }
    public decimal Gross { get; init; }
    public decimal Net { get; init; }
}

/// <summary>One pay item type, its total in each payroll.</summary>
public sealed class CompareItemRow
{
    public int PayComponentId { get; init; }
    public required string ItemClass { get; init; }
    public required string Name { get; init; }
    public string? ArabicName { get; init; }
    public required decimal?[] Amounts { get; init; }
    public required int[] Employees { get; init; }
}

/// <summary>One employee, the net pay in each payroll (null = not in that payroll).</summary>
public sealed class CompareEmployeeRow
{
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public string? DepartmentName { get; init; }
    public required decimal?[] Net { get; init; }
    public required decimal?[] Gross { get; init; }

    /// <summary>Not in the baseline but in a later payroll.</summary>
    public bool IsNew => Net[0] is null;
    /// <summary>In the baseline but missing from at least one other payroll.</summary>
    public bool IsMissing => Net[0] is not null && Net.Skip(1).Any(n => n is null);
    public bool IsChanged => Net.Skip(1).Any(n => n != Net[0]);
    /// <summary>"new", "missing", "changed" or "same" - the client-side filter.</summary>
    public string Kind => IsNew ? "new" : IsMissing ? "missing" : IsChanged ? "changed" : "same";
}
