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

    public sealed record Section(string Key, string Title, string Icon, IReadOnlyList<Tab> Tabs);

    public static readonly IReadOnlyList<Section> Sections =
    [
        new("dashboard", "Payroll Dashboard", "grid", [new("payroll-dashboard", "Dashboard")]),
        new("processing", "Payroll Processing", "calculator",
        [
            new("calendar", "Payroll Calendar", true), new("create", "Create Payroll", true), new("register", "Payroll Register", true),
            new("validation", "Payroll Validation", true), new("approval", "Payroll Approval", true), new("history", "Payroll History", true)
        ]),
        new("payitems", "Pay Items", "card", [new("pay-items", "Pay Items", true)]),
        new("settlement", "Final Settlement", "exit",
            [new("fs-list", "Settlements", true), new("fs-new", "New Settlement", true), new("fs-encashment", "Leave Encashment", true)]),
        new("payslips", "Payslips", "receipt",
            [new("slip-generate", "Generate Payslips", true), new("slip-employee", "Employee Payslips", true), new("slip-email", "Email Payslips", true)]),
        new("bank", "Bank Processing", "bank",
            [new("bk-file", "Bank File"), new("bk-register", "Payment Register"), new("bk-history", "Payment History")]),
        new("accounting", "Accounting", "book",
            [new("ac-journal", "Payroll Journal"), new("ac-posting", "GL Posting"), new("ac-allocation", "Cost Center Allocation")]),
        new("reports", "Payroll Reports", "chart",
        [
            new("rp-payroll", "Payroll Reports"), new("rp-salary", "Salary Reports"), new("rp-deduction", "Deduction Reports"),
            new("rp-overtime", "Overtime Reports"), new("rp-compliance", "Compliance Reports")
        ]),
        new("settings", "Payroll Settings", "sliders",
        [
            new("st-rules", "Payroll Rules"), new("st-components", "Pay Item Types"), new("st-deduction-rules", "Deduction Rules"),
            new("st-proration", "Proration Rules"), new("st-approval", "Approval Workflow"), new("st-banks", "Banks & Accounts"),
            new("st-bank-formats", "Bank Formats"), new("st-gl-mapping", "GL Mapping")
        ]),
    ];

    /// <summary>Preview pages that are not on a tab rail (opened from another page).</summary>
    public static readonly IReadOnlyDictionary<string, string> ExtraPages = new Dictionary<string, string>
    {
        ["slip-view"] = "payslips",
        ["slip-my"] = "payslips",
        ["fs-detail"] = "settlement"
    };

    public static Section? SectionOfSlug(string slug) =>
        Sections.FirstOrDefault(s => s.Tabs.Any(t => t.Slug == slug))
        ?? (ExtraPages.TryGetValue(slug, out var key) ? Sections.FirstOrDefault(s => s.Key == key) : null);

    public static string Url(string slug) => slug switch
    {
        "calendar" or "create" or "register" or "validation" or "approval" or "history" or "pay-items" => $"/payroll/{slug}",
        "fs-list" => "/payroll/settlement",
        "fs-new" => "/payroll/settlement/new",
        "fs-encashment" => "/payroll/settlement/encashment",
        "slip-generate" => "/payroll/payslips/generate",
        "slip-employee" => "/payroll/payslips/employees",
        "slip-email" => "/payroll/payslips/email",
        "slip-my" => "/payroll/payslips/my",
        _ => $"/payroll/preview/{slug}"
    };

    /// <summary>True for a payroll page that is still a design preview (Views/Payroll/Preview).</summary>
    public static bool IsPreview(string slug) =>
        SectionOfSlug(slug) is { } section && section.Key is not ("processing" or "settlement" or "payslips") && slug != "pay-items";

    /// <summary>The Final Settlement and Payslips preview pages that were replaced by the live screens (old links still work).</summary>
    public static string? ReplacedPreview(string slug) => slug switch
    {
        "slip-generate" or "slip-employee" or "slip-email" or "slip-my" => Url(slug),
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

    public static string Calendar(IUiText L, string name, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic : name;

    public static string EmployeeName(IUiText L, string? english, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : english ?? string.Empty;

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

public sealed class CalendarPageModel
{
    public IReadOnlyList<RunMonthOption> Months { get; init; } = Array.Empty<RunMonthOption>();
    public DateTime? SelectedMonth { get; init; }
    public IReadOnlyList<PayrollCalendar> Calendars { get; init; } = Array.Empty<PayrollCalendar>();
    public int? SelectedCalendarId { get; init; }
    public int SelectedYear { get; init; }
    public bool CanSetup { get; init; }
}

public sealed class CreatePageModel
{
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public int? CompanyId { get; init; }
    public IReadOnlyList<PayrollCalendar> Calendars { get; init; } = Array.Empty<PayrollCalendar>();
    public IReadOnlyList<LookupItem> Departments { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyList<LookupItem> Locations { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyList<PayrollDraft> Drafts { get; init; } = Array.Empty<PayrollDraft>();
    /// <summary>A draft being resumed (?draft=id).</summary>
    public PayrollRun? Draft { get; init; }
    public bool CanProcess { get; init; }
}

public sealed class HistoryPageModel
{
    public IReadOnlyList<PayrollRun> FinishedRuns { get; init; } = Array.Empty<PayrollRun>();
    public IReadOnlyList<int> Years { get; init; } = Array.Empty<int>();
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
    /// <summary>"calendar" (live + all stages) or "history" (closed and cancelled).</summary>
    public string Mode { get; init; } = "calendar";
    public bool IsFiltered { get; init; }
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
    public bool HasSalary { get; init; } = true;
    public bool IsExcluded { get; init; }
    public string? ExcludeReason { get; init; }
}

public sealed class RunIssuesGridModel
{
    public required PayrollRun Run { get; init; }
    public required PagedResult<PayrollRunIssue> Page { get; init; }
    public bool CanAcknowledge { get; init; }
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

public sealed class RunCompareModel
{
    public required PayrollRun RunA { get; init; }
    public required PayrollRun RunB { get; init; }
    public required IReadOnlyList<RunCompareRow> Rows { get; init; }
}
