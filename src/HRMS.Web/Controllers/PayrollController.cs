using System.Globalization;
using System.Text;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Domain.Workforce;
using HRMS.Web.Helpers;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll Processing: Payroll Calendar, Create Payroll, Register, Validation,
/// Approval and History (db/34-35). A payroll run moves
/// Registered → Validation → Awaiting Approval (HR, then Finance) → Closed, or is
/// Cancelled; the Register / Validation / Approval tabs work on the payroll
/// selected at the top and only open once the payroll has reached that stage.
/// </summary>
[Route("payroll")]
public sealed class PayrollController : Controller
{
    // ---- permissions (db/32 + db/34) ----
    private const string PermView = "PAYROLL_RUN_VIEW";
    private const string PermProcess = "PAYROLL_RUN_PROCESS";
    private const string PermApproveHr = "PAYROLL_RUN_APPROVE_HR";
    private const string PermApproveFinance = "PAYROLL_RUN_APPROVE_FINANCE";
    private const string PermCancel = "PAYROLL_RUN_CANCEL";
    private const string PermReopen = "PAYROLL_RUN_REOPEN";
    // Payroll Calendar & Pay Periods have their own rights (Security > Create Roles, "PR.CALENDAR");
    // creating and editing a calendar is one right (Write), deleting another (Full).
    private const string PermSetupView = "PAYROLL_CALENDAR_VIEW";
    private const string PermSetupEdit = "PAYROLL_CALENDAR_EDIT";
    private const string PermSetupCreate = "PAYROLL_CALENDAR_EDIT";
    private const string PermSetupDelete = "PAYROLL_CALENDAR_DELETE";
    private const string PermExclude = "PAYROLL_RUN_EXCLUDE";
    private const string PermApproveSelf = "PAYROLL_RUN_APPROVE_SELF";

    /// <summary>Remembers the payroll last opened, so the stage tabs follow it from page to page.</summary>
    internal const string RunCookie = "hrms_pr_run";

    private readonly IPayrollRunRepository _runs;
    private readonly IPayrollCalendarRepository _calendars;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _text;
    private readonly IEmployeePayrollCalendarRepository _employeeCalendars;
    private readonly IEmployeeAuditor _auditor;

    public PayrollController(
        IPayrollRunRepository runs,
        IPayrollCalendarRepository calendars,
        ILookupRepository lookups,
        ICurrentUser currentUser,
        ICompanyFilter companyFilter,
        IUiText text,
        IEmployeePayrollCalendarRepository employeeCalendars,
        IEmployeeAuditor auditor)
    {
        _runs = runs;
        _calendars = calendars;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _text = text;
        _employeeCalendars = employeeCalendars;
        _auditor = auditor;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool IsSysAdmin => _currentUser.IsInRole("SYSADMIN") || Can("SYSTEM_ADMIN");
    /// <summary>May approve a payroll they submitted or approved at level 1 (Security > approval rights).</summary>
    private bool CanApproveOwn => IsSysAdmin || Can(PermApproveSelf);
    private string? CompanyCsv => _companyFilter.Csv;
    private int? OwnCompany => _currentUser.ActiveCompanyId;

    // =======================================================================
    // Pages
    // =======================================================================

    [HttpGet("")]
    public IActionResult Index() => RedirectToAction(nameof(Payrolls));

    /// <summary>The old combined page (payrolls + calendars + periods) - now three sections.</summary>
    [HttpGet("calendar")]
    public IActionResult Calendar(string? month) => RedirectToAction(nameof(Payrolls), new { month });

    /// <summary>Payrolls: the open payrolls (any stage on request) - opening one goes to the page of its stage.</summary>
    [HttpGet("payrolls")]
    public async Task<IActionResult> Payrolls(string? month, string? stage, string? slips)
    {
        if (!Can(PermView)) return Forbid();

        var months = await _runs.MonthsAsync(OwnCompany, CompanyCsv, Ct);
        ViewData["ActiveRun"] = await RememberedRunAsync();
        return View(new CalendarPageModel
        {
            Months = months,
            SelectedMonth = ParseMonth(month),
            SelectedStage = stage is null ? "LIVE" : stage,
            CanProcess = Can(PermProcess),
            PayslipPending = slips == "pending"
        });
    }

    /// <summary>Payroll Calendar: the pay groups (calendars) - add, edit, activate, delete.</summary>
    [HttpGet("calendars")]
    public async Task<IActionResult> Calendars()
    {
        if (!Can(PermSetupView)) return Forbid();   // Payroll Calendar & Pay Periods (Security: "PR.CALENDAR")
        ViewData["ActiveRun"] = await RememberedRunAsync();
        return View(new CalendarPageModel
        {
            CanSetup = Can(PermSetupEdit) || Can(PermSetupCreate),
            CanCreateCalendar = Can(PermSetupCreate)
        });
    }

    /// <summary>Period: the periods of one calendar and year - generate a year, edit or delete an open period.</summary>
    [HttpGet("pay-periods")]
    public async Task<IActionResult> PayPeriods(int? calendar, int? year)
    {
        if (!Can(PermSetupView)) return Forbid();   // Payroll Calendar & Pay Periods (Security: "PR.CALENDAR")

        var calendars = await _calendars.ListAsync(new GridRequest { CompanyId = OwnCompany, CompanyIds = CompanyCsv, PageSize = 200 }, Ct);
        var selected = calendars.Items.FirstOrDefault(c => c.PayrollCalendarId == calendar)
                       ?? calendars.Items.FirstOrDefault(c => c.IsDefault && c.IsActive)
                       ?? calendars.Items.FirstOrDefault();

        ViewData["ActiveRun"] = await RememberedRunAsync();
        return View(new CalendarPageModel
        {
            Calendars = calendars.Items,
            SelectedCalendarId = selected?.PayrollCalendarId,
            SelectedYear = year is >= 2000 and <= 2100 ? year.Value : DateTime.Today.Year,
            CanSetup = Can(PermSetupEdit) || Can(PermSetupCreate)
        });
    }

    /// <summary>
    /// Create Payroll. Each employee is paid by their own payroll calendar (db/60), so the
    /// user picks the company and the month; one draft payroll is made per calendar in use
    /// (create-plan). ?drafts=1,2 (or the older ?draft=1) resumes a set of drafts.
    /// </summary>
    [HttpGet("create")]
    public async Task<IActionResult> Create(long? draft, string? drafts)
    {
        if (!Can(PermProcess)) return Forbid();

        var companies = await VisibleCompaniesAsync();

        // the drafts resumed: same company, month and type as the first one
        var ids = ParseRunIds(drafts);
        if (draft is > 0 && !ids.Contains(draft.Value)) ids.Insert(0, draft.Value);
        var resume = new List<PayrollRun>();
        foreach (var id in ids)
        {
            var r = await _runs.GetAsync(id, Ct);
            if (r is null || r.Stage != RunStage.Draft || !CanSee(r)) continue;
            if (resume.Count > 0 && (r.CompanyId != resume[0].CompanyId || r.RunMonth != resume[0].RunMonth || r.RunType != resume[0].RunType)) continue;
            resume.Add(r);
        }
        if (ids.Count > 0 && resume.Count == 0)
        {
            return RedirectToAction(nameof(Create));
        }

        var companyId = resume.FirstOrDefault()?.CompanyId ?? OwnCompany ?? _companyFilter.SingleCompanyId ?? companies.FirstOrDefault()?.Id;

        ViewData["ActiveRun"] = await RememberedRunAsync();
        return View(new CreatePageModel
        {
            Companies = companies,
            CompanyId = companyId,
            Departments = companyId is { } d ? await _lookups.GetAsync(LookupType.Department, d, cancellationToken: Ct) : Array.Empty<LookupItem>(),
            Locations = companyId is { } l ? await _lookups.GetAsync(LookupType.Location, l, cancellationToken: Ct) : Array.Empty<LookupItem>(),
            DraftGroups = resume.Count > 0 ? Array.Empty<DraftGroup>() : await DraftGroupsAsync(),
            Resume = resume,
            CanProcess = true
        });
    }

    /// <summary>The user's unfinished drafts, one group per company, month and type (made together).</summary>
    private async Task<IReadOnlyList<DraftGroup>> DraftGroupsAsync()
    {
        var list = await _runs.DraftsAsync(OwnCompany, CompanyCsv, UserId, Ct);
        var runs = new List<(PayrollDraft Draft, DateTime Month)>();
        foreach (var d in list.Take(30))
        {
            if (await _runs.GetAsync(d.PayrollRunId, Ct) is { } r) runs.Add((d, r.RunMonth));
        }
        return runs
            .GroupBy(x => (x.Draft.CompanyId, x.Month, x.Draft.RunType))
            .Select(g => new DraftGroup(
                g.Select(x => x.Draft.PayrollRunId).ToList(),
                g.Key.CompanyId, g.Key.Month, g.Key.RunType,
                g.Max(x => x.Draft.LastSaved),
                g.Select(x => x.Draft.CalendarName).Distinct().ToList()))
            .OrderByDescending(g => g.LastSaved)
            .ToList();
    }

    /// <summary>
    /// One payroll Create Payroll makes for a month: a payroll calendar its employees are
    /// assigned to, and that calendar's period of the month (weekly / bi-weekly calendars
    /// have several). State: "ready" (to create), "generate" (ready - its period is generated
    /// on Next), "exists" (a regular payroll is already created), "later" (a weekly period of
    /// the month that has not started yet), "closed" (the period is no
    /// longer open), "no-period" (the calendar has no period in the month), "none" (nobody
    /// is paid by the calendar).
    /// </summary>
    private sealed record PlanGroup(PayrollCalendar Calendar, int Employees, int Unassigned, PayrollPeriodRow? Period, string State, string? Regular);

    private sealed record MonthPlan(IReadOnlyList<PlanGroup> Groups, int Unassigned, int OnInactive, bool HasDefault, bool CalendarsReady,
                                    bool HasWeekly, int OtherFrequencyEmployees, bool MonthlyToCreate);

    /// <summary>Kuwait pays monthly: Create Payroll makes the monthly payrolls; weekly / bi-weekly
    /// calendars (an exception set up in Payroll Settings) are made separately.</summary>
    private const string FreqMonthly = "MONTHLY", FreqWeekly = "WEEKLY";

    private static bool IsFrequency(PayrollCalendar c, string frequency) =>
        frequency == FreqWeekly ? c.PayFrequency != "MONTHLY" : c.PayFrequency == "MONTHLY";

    /// <summary>
    /// A company with no active monthly calendar gets one when its first monthly payroll is
    /// made: "Monthly Payroll", calendar months, cut-off and payment on the last day. It becomes
    /// the default (employees without a calendar are paid by it) unless a monthly default exists.
    /// </summary>
    private async Task<SaveResult> CreateMonthlyCalendarAsync(int companyId, IReadOnlyList<PayrollCalendar> calendars)
    {
        var all = (await _calendars.ListAsync(new GridRequest { CompanyId = companyId, PageSize = 200 }, Ct)).Items;
        var code = "MONTHLY";
        for (var n = 2; all.Any(c => string.Equals(c.CalendarCode, code, StringComparison.OrdinalIgnoreCase)); n++) code = "MONTHLY" + n;
        return await _calendars.SaveAsync(new PayrollCalendar
        {
            CompanyId = companyId,
            CalendarCode = code,
            CalendarName = "Monthly Payroll",
            ArabicName = "الرواتب الشهرية",
            PayFrequency = "MONTHLY",
            // periods can be made from the start of last year (Create Payroll offers 12 months back)
            FirstPeriodStartDate = new DateTime(DateTime.Today.Year - 1, 1, 1),
            CutOffDay = 31,
            PaymentDay = 31,
            WorkingDaysBasis = "CALENDAR",
            FixedDaysPerMonth = null,
            Description = "Created by Create Payroll - Kuwait payroll is monthly.",
            IsDefault = !calendars.Any(c => c.IsDefault && c.PayFrequency == "MONTHLY"),
            IsActive = true
        }, UserId, Ct);
    }

    /// <summary>
    /// The payrolls of a company and month, worked out from each employee's payroll calendar
    /// (Employee.PayrollCalendarId; no calendar = the default calendar). With generate, a
    /// calendar that has no period in the month gets its periods of that year first.
    /// </summary>
    private async Task<MonthPlan> BuildMonthPlanAsync(int companyId, DateTime month, string runType, bool generate, string frequency = FreqMonthly)
    {
        var calendars = (await _calendars.ListAsync(new GridRequest { CompanyId = companyId, IsActive = true, PageSize = 200 }, Ct)).Items;

        // monthly by default: a company without a monthly calendar gets one (on Next)
        var monthlyToCreate = frequency == FreqMonthly && !calendars.Any(c => c.PayFrequency == "MONTHLY");
        if (monthlyToCreate && generate && (await CreateMonthlyCalendarAsync(companyId, calendars)).Success)
        {
            calendars = (await _calendars.ListAsync(new GridRequest { CompanyId = companyId, IsActive = true, PageSize = 200 }, Ct)).Items;
            monthlyToCreate = false;
        }

        IReadOnlyList<CalendarEmployeeCount> counts;
        var calendarsReady = true;
        try
        {
            counts = await _employeeCalendars.CountsAsync(companyId, Ct);
        }
        catch (Exception)
        {
            // db/60 not run yet: no employee has a calendar, the default calendar pays everyone
            counts = Array.Empty<CalendarEmployeeCount>();
            calendarsReady = false;
        }

        // no calendar, or one since deactivated: paid by the default calendar (db/80)
        var unassigned = counts.Where(c => c.PayrollCalendarId is not { } id || calendars.All(x => x.PayrollCalendarId != id)).Sum(c => c.EmployeeCount);
        var onInactive = 0;
        var defaultCal = calendars.FirstOrDefault(c => c.IsDefault);

        // employees without a calendar go to the default one - or, before the monthly calendar
        // exists, to the monthly payroll that will create it
        // (the monthly calendar made on Next becomes the default)
        var unassignedHere = monthlyToCreate ? unassigned
            : defaultCal is not null && IsFrequency(defaultCal, frequency) ? unassigned : 0;

        int Employees(PayrollCalendar c) =>
            counts.Where(x => x.PayrollCalendarId == c.PayrollCalendarId).Sum(x => x.EmployeeCount)
            + (c.PayrollCalendarId == defaultCal?.PayrollCalendarId ? unassigned : 0);

        async Task<List<PayrollPeriodRow>> PeriodsOfMonth(PayrollCalendar c) =>
            (await _calendars.PeriodsAsync(c.PayrollCalendarId, null, openableOnly: false, Ct))
                .Where(p => p.RunMonth.Year == month.Year && p.RunMonth.Month == month.Month)
                .OrderBy(p => p.StartDate).ToList();

        var hasWeekly = calendars.Any(c => c.PayFrequency != "MONTHLY");
        var otherEmployees = calendars.Where(c => !IsFrequency(c, frequency)).Sum(Employees);
        var groups = new List<PlanGroup>();
        if (monthlyToCreate)
        {
            // shown as the payroll it will be: made with its calendar and period on Next
            groups.Add(new PlanGroup(new PayrollCalendar { CalendarName = "Monthly Payroll", ArabicName = "الرواتب الشهرية", PayFrequency = "MONTHLY", IsDefault = defaultCal is null },
                                     unassignedHere, unassignedHere, null, unassignedHere > 0 ? "generate" : "none", null));
        }
        foreach (var c in calendars.Where(c => IsFrequency(c, frequency)).OrderByDescending(Employees).ThenBy(c => c.CalendarName, StringComparer.OrdinalIgnoreCase))
        {
            var employees = Employees(c);
            var paysUnassigned = c.PayrollCalendarId == defaultCal?.PayrollCalendarId ? unassigned : 0;
            if (employees == 0)
            {
                groups.Add(new PlanGroup(c, 0, 0, null, "none", null));
                continue;
            }

            var periods = await PeriodsOfMonth(c);
            // a calendar can only have periods from its first period on
            var canGenerate = c.FirstPeriodStartDate is not { } first || first <= month.AddMonths(1).AddDays(-1);
            if (periods.Count == 0 && generate && canGenerate)
            {
                await _calendars.GeneratePeriodsAsync(c.PayrollCalendarId, month.Year, UserId, Ct);
                periods = await PeriodsOfMonth(c);
            }
            if (periods.Count == 0)
            {
                groups.Add(new PlanGroup(c, employees, paysUnassigned, null, canGenerate && !generate ? "generate" : "no-period", null));
                continue;
            }

            var open = periods.Where(p => p.Status is "OPEN" or "PROCESSING" || (runType == RunType.OffCycle && p.Status == "APPROVED")).ToList();
            if (open.Count == 0)
            {
                groups.Add(new PlanGroup(c, employees, paysUnassigned, periods[0], "closed", null));
                continue;
            }

            if (runType == RunType.OffCycle)
            {
                // an off-cycle payroll goes to the period running today, else the first open one
                var p = open.FirstOrDefault(x => x.StartDate <= DateTime.Today && x.EndDate >= DateTime.Today) ?? open[0];
                groups.Add(new PlanGroup(c, employees, paysUnassigned, p, "ready", null));
                continue;
            }
            // weekly / bi-weekly: the weeks of the month that have started (a future month: its
            // first week, made in advance); a later week is made when it starts
            var due = open.Where(p => p.StartDate <= DateTime.Today).ToList();
            if (due.Count == 0) due = open.Take(1).ToList();
            foreach (var p in open)
            {
                if (!due.Contains(p))
                {
                    groups.Add(new PlanGroup(c, employees, paysUnassigned, p, "later", null));
                    continue;
                }
                var next = await _runs.NextCodeAsync(p.PayrollPeriodId, Ct);
                groups.Add(new PlanGroup(c, employees, paysUnassigned, p, next?.RegularRunCode is { Length: > 0 } ? "exists" : "ready", next?.RegularRunCode));
            }
        }
        return new MonthPlan(groups, unassignedHere, onInactive, defaultCal is not null || monthlyToCreate, calendarsReady,
                             hasWeekly, otherEmployees, monthlyToCreate);
    }

    private bool MayCreateFor(int companyId) =>
        (OwnCompany is not { } own || own == companyId)
        && (_companyFilter.SelectedIds.Count == 0 || _companyFilter.SelectedIds.Contains(companyId));

    /// <summary>
    /// What Create Payroll will make for a company and month: the months that can be chosen
    /// (12 back to 3 ahead), and the payrolls of the month - one per payroll calendar its
    /// employees are assigned to, with the period worked out (not chosen by the user).
    /// </summary>
    [HttpGet("create-plan")]
    public async Task<IActionResult> CreatePlan(int companyId, string? month, string? type, string? frequency)
    {
        if (!Can(PermProcess)) return Forbid();
        if (!MayCreateFor(companyId)) return Forbid();

        var thisMonth = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
        var months = Enumerable.Range(-12, 16).Select(thisMonth.AddMonths).ToList();
        var selected = ParseMonth(month) ?? thisMonth;
        if (!months.Contains(selected)) { months.Add(selected); months.Sort(); }
        var runType = type == RunType.OffCycle ? RunType.OffCycle : RunType.Regular;

        var freq = frequency == FreqWeekly ? FreqWeekly : FreqMonthly;
        var plan = await BuildMonthPlanAsync(companyId, selected, runType, generate: false, freq);

        // the payroll number continues per company and month: the first new one gets NextSeq
        NextRunCode? code = null;
        foreach (var g in plan.Groups.Where(g => g.Period is not null))
        {
            code = await _runs.NextCodeAsync(g.Period!.PayrollPeriodId, Ct);
            if (code is not null) break;
        }

        return Json(new
        {
            month = selected.ToString("yyyy-MM", CultureInfo.InvariantCulture),
            months = months.Select(x => new
            {
                value = x.ToString("yyyy-MM", CultureInfo.InvariantCulture),
                text = _text.MonthYear(x) + (x == thisMonth ? " · " + _text["pr.cr_this_month"] : "")
            }),
            groups = plan.Groups.Select(g => new
            {
                calendarId = g.Calendar.PayrollCalendarId,
                periodId = g.Period?.PayrollPeriodId,
                name = PayrollFormat.Calendar(_text, g.Calendar.CalendarName, g.Calendar.ArabicName),
                frequency = PayrollFormat.Frequency(_text, g.Calendar.PayFrequency),
                isDefault = g.Calendar.IsDefault,
                employees = g.Employees,
                unassigned = g.Unassigned,
                period = g.Period is { } p ? PayrollFormat.Period(_text, p) : null,
                // a weekly period's name already carries its dates
                dates = g.Period is { } d && g.Calendar.PayFrequency == "MONTHLY" ? $"{_text.DayMonth(d.StartDate)} – {_text.Date(d.EndDate)}" : null,
                state = g.State,
                regular = g.Regular
            }),
            unassigned = plan.Unassigned,
            onInactive = plan.OnInactive,
            hasDefault = plan.HasDefault,
            calendarsReady = plan.CalendarsReady,
            frequency = freq,
            hasWeekly = plan.HasWeekly,
            otherEmployees = plan.OtherFrequencyEmployees,
            nextSeq = code?.NextSeq ?? 1,
            nextCode = code?.RunCode
        });
    }

    /// <summary>
    /// Makes (or refreshes) the drafts of a month in one go: one per payroll of the month plan,
    /// generating a calendar's periods when it has none in the month yet. The drafts already
    /// made on the page (drafts=1,2) are kept for the same calendar and period, and discarded
    /// when no longer part of the plan. A regular payroll is never made twice for a period,
    /// and the engine (db/80) pays an employee in one regular payroll per month.
    /// </summary>
    [HttpPost("create-drafts")]
    public async Task<IActionResult> CreateDrafts(CreateDraftsInput input)
    {
        if (!Can(PermProcess)) return Denied();
        if (!MayCreateFor(input.CompanyId)) return Denied();
        if (ParseMonth(input.Month) is not { } month)
            return Json(ActionResponse.Failed(_text["pr.cr_no_month"], "VALIDATION"));
        var runType = input.RunType == RunType.OffCycle ? RunType.OffCycle : RunType.Regular;

        // the drafts made on this page so far
        var existing = new List<PayrollRun>();
        foreach (var id in ParseRunIds(input.Drafts))
        {
            if (await _runs.GetAsync(id, Ct) is { } r && r.Stage == RunStage.Draft && CanSee(r)) existing.Add(r);
        }

        var plan = await BuildMonthPlanAsync(input.CompanyId, month, runType, generate: true,
                                             input.Frequency == FreqWeekly ? FreqWeekly : FreqMonthly);
        var targets = plan.Groups.Where(g => g.State == "ready" && g.Period is not null).ToList();
        if (targets.Count == 0)
        {
            var why = plan.Groups.Any(g => g.State == "exists") ? _text["pr.cr_all_created", _text.MonthYear(month)]
                : plan.Groups.Any(g => g.State == "closed") ? _text["pr.cr_month_closed", _text.MonthYear(month)]
                : plan.Groups.All(g => g.State == "none") ? _text["pr.cr_nobody_to_pay"]
                : _text["pr.cr_no_open_period_in", _text.MonthYear(month)];
            return Json(ActionResponse.Failed(why, "NOTHING_TO_CREATE"));
        }

        var made = new List<object>();
        var kept = new HashSet<long>();
        foreach (var g in targets)
        {
            var prev = existing.FirstOrDefault(r => r.PayrollCalendarId == g.Calendar.PayrollCalendarId
                                                    && r.PayrollPeriodId == g.Period!.PayrollPeriodId && !kept.Contains(r.PayrollRunId));
            var result = await _runs.SaveDraftAsync(new PayrollDraftInput
            {
                PayrollRunId = prev?.PayrollRunId,
                CompanyId = input.CompanyId,
                PayrollCalendarId = g.Calendar.PayrollCalendarId,
                PayrollPeriodId = g.Period!.PayrollPeriodId,
                RunType = runType,
                Description = NullIfEmpty(input.Description),
                ScopeDepartmentId = input.ScopeDepartmentId,
                ScopeWorkLocationId = input.ScopeWorkLocationId,
                ScopeEmploymentType = NullIfEmpty(input.ScopeEmploymentType),
                ScopeNationality = NullIfEmpty(input.ScopeNationality)
            }, UserId, Ct);
            if (!result.Success)
            {
                return Json(new { success = false, message = _text.Tr(result.Message), errorCode = result.ErrorCode, drafts = made });
            }
            kept.Add(result.Id);
            made.Add(new
            {
                runId = result.Id.ToString(CultureInfo.InvariantCulture),
                calendarId = g.Calendar.PayrollCalendarId,
                periodId = g.Period.PayrollPeriodId,
                name = PayrollFormat.Calendar(_text, g.Calendar.CalendarName, g.Calendar.ArabicName),
                period = PayrollFormat.Period(_text, g.Period),
                employees = g.Employees
            });
        }

        // drafts of this page that are no longer part of the month's plan
        foreach (var r in existing.Where(r => !kept.Contains(r.PayrollRunId)))
        {
            await _runs.RunActionAsync("DISCARD", r.PayrollRunId, UserId, cancellationToken: Ct);
        }

        HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
        return Json(new { success = true, drafts = made });
    }

    [HttpGet("run/{id:long}")]
    public async Task<IActionResult> Open(long id)
    {
        var run = await _runs.GetAsync(id, Ct);
        if (run is null || !CanSee(run)) return NotFound();
        if (run.Stage == RunStage.Draft) return RedirectToAction(nameof(Create), new { draft = id });
        return RedirectToAction(StagePage(run.Stage), new { run = id });
    }

    [HttpGet("register")]
    public Task<IActionResult> Register(long? run) => RunPage(run, 0);

    [HttpGet("validation")]
    public Task<IActionResult> Validation(long? run) => RunPage(run, 1);

    [HttpGet("approval")]
    public Task<IActionResult> Approval(long? run) => RunPage(run, 2);

    /// <summary>
    /// The payroll pages that are not built yet, embedded as design previews
    /// (sample data, nothing is saved) - Views/Payroll/Preview/*.cshtml.
    /// </summary>
    [HttpGet("preview/{slug}")]
    public async Task<IActionResult> Preview(string slug)
    {
        if (!Can(PermView) && !Can(PermSetupView)) return Forbid();
        if (PayrollNav.ReplacedPreview(slug) is { } live) return LocalRedirect(Request.PathBase + live);
        if (string.IsNullOrEmpty(slug) || !PayrollNav.IsPreview(slug)) return NotFound();

        ViewData["ActiveRun"] = await RememberedRunAsync();
        ViewData["PayrollPage"] = slug;   // sidebar highlight when the section has sub-sections
        return View($"~/Views/Payroll/Preview/{PayrollNav.PreviewView(slug)}.cshtml");
    }

    [HttpGet("history")]
    public async Task<IActionResult> History()
    {
        if (!Can(PermView)) return Forbid();

        var finished = await _runs.ListAsync(new RunListFilter
        {
            CompanyId = OwnCompany, CompanyIds = CompanyCsv, Stage = "FINISHED", PageSize = 200
        }, Ct);
        var years = finished.Items.Select(r => r.RunMonth.Year).Distinct().OrderByDescending(y => y).ToList();
        ViewData["ActiveRun"] = await RememberedRunAsync();
        var months = finished.Items.Select(r => r.RunMonth).Distinct().OrderByDescending(m => m).ToList();
        return View(new HistoryPageModel { Years = years, Months = months });
    }

    /// <summary>
    /// Payroll Comparison: 2-3 payrolls of ONE company side by side - totals,
    /// pay items and employees. Payrolls still in progress can be picked (to
    /// check the current month against a closed one); their stage is shown.
    /// </summary>
    [HttpGet("compare")]
    public async Task<IActionResult> Compare(int? company, string? runs)
    {
        if (!Can(PermView)) return Forbid();

        var companies = await VisibleCompaniesAsync();
        var picked = ParseRunIds(runs);

        // a link with payrolls but no company opens the company of the first payroll
        if (company is null && picked.Count > 0 && await LoadRunAsync(picked[0]) is { } first)
        {
            company = first.CompanyId;
        }
        var companyId = company is { } c && companies.Any(x => x.Id == c)
            ? c
            : OwnCompany ?? _companyFilter.SingleCompanyId ?? companies.FirstOrDefault()?.Id;

        var list = companyId is { } cid
            ? (await _runs.ListAsync(new RunListFilter { CompanyId = cid, CompanyIds = CompanyCsv, PageSize = 200 }, Ct)).Items
                .Where(IsComparable).ToList()
            : new List<PayrollRun>();

        var selected = picked.Where(id => list.Any(r => r.PayrollRunId == id)).Take(ComparePageModel.MaxRuns).ToList();
        if (selected.Count == 0)
        {
            // first visit: the latest regular payroll against the one before it
            var regular = list.Where(r => r.RunType == RunType.Regular).Take(2).ToList();
            if (regular.Count < 2) regular = list.Take(2).ToList();
            selected = regular.Select(r => r.PayrollRunId).Reverse().ToList();
        }

        ViewData["ActiveRun"] = await RememberedRunAsync();
        return View(new ComparePageModel { Companies = companies, CompanyId = companyId, Runs = list, Selected = selected });
    }

    private async Task<IActionResult> RunPage(long? runId, int pageStage)
    {
        if (!Can(PermView)) return Forbid();

        var list = await _runs.ListAsync(new RunListFilter { CompanyId = OwnCompany, CompanyIds = CompanyCsv, PageSize = 60 }, Ct);
        PayrollRun? run = null;

        if (runId is > 0)
        {
            run = await _runs.GetAsync(runId.Value, Ct);
            if (run is null || !CanSee(run) || run.Stage == RunStage.Draft)
            {
                return RedirectToAction(PageName(pageStage));
            }
        }
        else
        {
            // the remembered payroll when it is at this stage, else the latest one at this stage,
            // else the remembered / latest one (which then opens on the page of its own stage)
            var remembered = long.TryParse(Request.Cookies[RunCookie], out var rid) ? list.Items.FirstOrDefault(r => r.PayrollRunId == rid) : null;
            var wanted = pageStage switch { 0 => RunStage.Registered, 1 => RunStage.Validation, _ => RunStage.AwaitingApproval };
            var pick = (remembered?.Stage == wanted ? remembered : null)
                       ?? list.Items.FirstOrDefault(r => r.Stage == wanted) ?? remembered ?? list.Items.FirstOrDefault();
            if (pick is not null)
            {
                run = await _runs.GetAsync(pick.PayrollRunId, Ct);
            }
        }

        if (run is null && pageStage > 0)
        {
            return RedirectToAction(nameof(Register));
        }

        if (run is not null)
        {
            // A payroll is shown only on the page of its own stage (Register, Validation or
            // Approval - a closed payroll on Approval, a cancelled one on Register).
            var reached = run.IsCancelled ? 0 : Math.Min(run.StageIndex, 2);
            // the Register is the payroll's full list of employees: a payroll asked for by number
            // opens there read-only at any stage ("Open full register (read-only)" on Approval)
            var readOnlyRegister = pageStage == 0 && runId is > 0;
            if (pageStage != reached && !readOnlyRegister)
            {
                return RedirectToAction(PageName(reached), new { run = run.PayrollRunId });
            }

            Response.Cookies.Append(RunCookie, run.PayrollRunId.ToString(CultureInfo.InvariantCulture),
                new CookieOptions { HttpOnly = true, SameSite = SameSiteMode.Lax, IsEssential = true, Secure = Request.IsHttps });
        }

        var runs = list.Items.ToList();
        if (run is not null && runs.All(r => r.PayrollRunId != run.PayrollRunId))
        {
            runs.Insert(0, run);
        }

        var model = new RunPageModel
        {
            Run = run,
            Runs = runs,
            PageStage = pageStage,
            CanProcess = Can(PermProcess),
            CanCancel = Can(PermCancel) && run is { Stage: RunStage.Registered or RunStage.Validation or RunStage.AwaitingApproval },
            CanReopen = Can(PermReopen) && run is { Stage: RunStage.Closed },
            Summary = run is null ? new PayrollRunSummary() : await _runs.SummaryAsync(run.PayrollRunId, Ct),
            History = run is null ? Array.Empty<PayrollRunHistoryEntry>() : await _runs.HistoryAsync(run.PayrollRunId, Ct),
            Components = run is { Stage: RunStage.Registered } ? await _runs.ComponentsAsync(run.PayrollRunId, Ct) : Array.Empty<PayComponentOption>(),
            BiggestChanges = run is not null && pageStage == 2
                ? (await _runs.EmployeesAsync(run.PayrollRunId, new RunEmployeeFilter { Filter = "changed", Sort = "Change", PageSize = 8 }, Ct)).Items
                : Array.Empty<PayrollRunEmployee>(),
            CanApproveLevel = run is null ? 0 : ApprovalLevelFor(run),
            IsSelfApprovalBlocked = run is not null && !CanApproveOwn && run.Stage == RunStage.AwaitingApproval
                                    && (run.SubmittedBy == UserId || (run.ApprovalLevel == 1 && run.Level1ApprovedBy == UserId))
        };

        ViewData["ActiveRun"] = run;
        return View(PageName(pageStage), model);
    }

    // =======================================================================
    // Grids and panels (partials)
    // =======================================================================

    [HttpGet("runs-grid")]
    public async Task<IActionResult> RunsGrid(string? mode, string? month, string? stage, string? type, int? year, string? search, bool pending = false, int page = 1)
    {
        if (!Can(PermView)) return Forbid();

        var history = mode == "history";
        // "Pending Generate PaySlips" (Payrolls): closed payrolls with payslips to generate, whatever stage is chosen
        pending = pending && !history;
        var filter = new RunListFilter
        {
            CompanyId = OwnCompany,
            CompanyIds = CompanyCsv,
            RunMonth = ParseMonth(month),
            Stage = pending ? null : history ? (string.IsNullOrEmpty(stage) ? "FINISHED" : stage) : NullIfEmpty(stage),
            PayslipPending = pending,
            Type = NullIfEmpty(type),
            Year = year,
            Search = search,
            PageNumber = page,
            PageSize = history ? 25 : 50
        };
        var result = await _runs.ListAsync(filter, Ct);
        return PartialView("_RunsGrid", new RunsGridModel
        {
            Page = result,
            Mode = history ? "history" : "payrolls",
            IsFiltered = pending || (!string.IsNullOrEmpty(stage) && stage != "LIVE") || !string.IsNullOrEmpty(type) || year is not null
                         || !string.IsNullOrWhiteSpace(search) || filter.RunMonth is not null,
            OpenOnly = !history && !pending && stage == "LIVE",
            PayslipPending = pending,
            CanSlips = Can("PAYROLL_SLIP_GENERATE") || Can("PAYROLL_SLIP_VIEW") || Can("PAYROLL_SLIP_EMAIL")
        });
    }

    [HttpGet("employees-grid")]
    public async Task<IActionResult> EmployeesGrid(long run, string? mode, string? filter, string? search, int page = 1)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();

        var pageSize = mode == "approval" ? 25 : 25;
        var result = await _runs.EmployeesAsync(run, new RunEmployeeFilter
        {
            Filter = string.IsNullOrEmpty(filter) ? (r.RunType == RunType.OffCycle && r.Stage != RunStage.Draft ? "included" : "all") : filter,
            Search = search,
            PageNumber = page,
            PageSize = pageSize
        }, Ct);

        return PartialView("_EmployeesGrid", new RunEmployeesGridModel
        {
            Run = r,
            Page = result,
            Mode = mode ?? "register",
            Editable = r.IsEditable && Can(PermProcess),
            Filter = filter,
            Search = search
        });
    }

    [HttpGet("lines")]
    public async Task<IActionResult> Lines(long run, long employeeId)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();

        var lines = await _runs.LinesAsync(run, employeeId, Ct);
        var emp = (await _runs.EmployeesAsync(run, new RunEmployeeFilter { EmployeeId = employeeId, PageSize = 1 }, Ct)).Items.FirstOrDefault();
        var editable = r.IsEditable && Can(PermProcess);

        return PartialView("_RunLines", new RunLinesModel
        {
            Run = r,
            EmployeeId = employeeId,
            Lines = lines,
            Components = editable ? await _runs.ComponentsAsync(run, Ct) : Array.Empty<PayComponentOption>(),
            Editable = editable,
            CanExclude = r.CanExclude && Can(PermExclude),
            HasSalary = emp?.HasSalary ?? true,
            IsExcluded = emp?.IsExcluded ?? false,
            ExcludeReason = emp?.ExcludeReason
        });
    }

    [HttpGet("components")]
    public async Task<IActionResult> Components(long run)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();
        var list = await _runs.ComponentsAsync(run, Ct);
        return Json(list.Select(c => new
        {
            id = c.PayComponentId,
            text = _text.IsArabic && !string.IsNullOrWhiteSpace(c.ArabicName) ? c.ArabicName : c.ComponentName,
            cls = c.ItemClass
        }));
    }

    [HttpGet("kpis")]
    public async Task<IActionResult> Kpis(long run, string? mode)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();
        ViewData["Mode"] = mode ?? "register";
        ViewData["Run"] = r;
        return PartialView("_RunKpis", await _runs.SummaryAsync(run, Ct));
    }

    [HttpGet("check")]
    public async Task<IActionResult> Check(long run)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();
        ViewData["Run"] = r;
        return PartialView("_RunCheck", await _runs.SummaryAsync(run, Ct));
    }

    [HttpGet("excluded")]
    public async Task<IActionResult> Excluded(long run)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();
        ViewData["Run"] = r;
        ViewData["Editable"] = r.CanExclude && Can(PermExclude);
        return PartialView("_Excluded", await _runs.ExcludedAsync(run, Ct));
    }

    [HttpGet("issues-grid")]
    public async Task<IActionResult> IssuesGrid(long run, string? severity, string? status, string? search, int page = 1)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();
        var result = await _runs.IssuesAsync(run, NullIfEmpty(severity), NullIfEmpty(status), search, page, 50, Ct);
        return PartialView("_IssuesGrid", new RunIssuesGridModel
        {
            Run = r,
            Page = result,
            CanAcknowledge = r.Stage == RunStage.Validation && Can(PermProcess),
            CanExclude = r.CanExclude && Can(PermExclude),
            IsFiltered = !string.IsNullOrEmpty(severity) || !string.IsNullOrEmpty(status) || !string.IsNullOrWhiteSpace(search)
        });
    }

    [HttpGet("compare-grid")]
    public async Task<IActionResult> CompareGrid(string? runs)
    {
        if (!Can(PermView)) return Forbid();
        var (comparison, error) = await BuildComparisonAsync(runs);
        return comparison is null ? PartialView("_CompareError", error) : PartialView("_CompareGrid", comparison);
    }

    /// <summary>The comparison as an Excel workbook: Summary, Pay items and Employees sheets.</summary>
    [HttpGet("compare-export")]
    public async Task<IActionResult> CompareExport(string? runs)
    {
        if (!Can(PermView)) return Forbid();
        var (cmp, error) = await BuildComparisonAsync(runs);
        if (cmp is null) return BadRequest(_text.Tr(error));

        var L = _text;
        var n = cmp.Runs.Count;
        var codes = cmp.Runs.Select(r => r.RunCode ?? r.PayrollRunId.ToString(CultureInfo.InvariantCulture)).ToList();
        var diffHeaders = Enumerable.Range(1, n - 1).Select(i => $"{codes[i]} − {codes[0]}").ToList();
        var pctHeaders = Enumerable.Range(1, n - 1).Select(i => $"{codes[i]} − {codes[0]} (%)").ToList();
        string Name(string? en, string? ar) => L.IsArabic && !string.IsNullOrWhiteSpace(ar) ? ar : en ?? string.Empty;
        object? Pct(decimal? v) => v is { } p ? (double)p : null;

        // ---- Summary: one column per payroll, then the differences against the baseline
        var summary = new List<IReadOnlyList<object?>>
        {
            Info(L["common.company"], r => r.CompanyName),
            Info(L["pr.period"], r => PayrollFormat.Period(L, r)),
            Info(L["pr.calendar"], r => PayrollFormat.Calendar(L, r.CalendarName, r.CalendarArabicName)),
            Info(L["org.type"], r => L.Tr(RunType.Label(r.RunType))),
            Info(L["pr.stage"], r => L.Tr(RunStage.Label(r.Stage))),
            Info(L["pr.cmp_figures"], r => r.IsClosed ? L["pr.cmp_final"] : L["pr.cmp_not_closed_may_change"])
        };
        void Metric(string label, Func<CompareTotals, decimal> pick, bool count = false)
        {
            var values = cmp.Totals.Select(t => (decimal?)pick(t)).ToList();
            object? Cell(decimal? v) => count && v is { } d ? (int)d : v;
            var row = new List<object?> { label };
            row.AddRange(values.Select(Cell));
            row.AddRange(Enumerable.Range(1, n - 1).Select(i => Cell(PayrollComparison.Diff(values, i))));
            row.AddRange(Enumerable.Range(1, n - 1).Select(i => Pct(PayrollComparison.Percent(values, i))));
            summary.Add(row);
        }
        Metric(L["common.employees"], t => t.Employees, count: true);
        Metric(L["pr.cmp_joiners"], t => t.Joiners, count: true);
        Metric(L["pr.cmp_leavers"], t => t.Leavers, count: true);
        Metric(L["pr.salary"], t => t.Salary);
        Metric(L["pr.earnings"], t => t.Earnings);
        Metric(L["pr.deductions"], t => t.Deductions);
        Metric(L["pr.gross"], t => t.Gross);
        Metric(L["pr.net_kwd"], t => t.Net);

        List<object?> Info(string label, Func<PayrollRun, string> pick)
        {
            var row = new List<object?> { label };
            row.AddRange(cmp.Runs.Select(r => (object?)pick(r)));
            return row;
        }

        // ---- Pay items
        var items = cmp.Items.Select(i =>
        {
            var row = new List<object?> { PayrollFormat.ItemClass(L, i.ItemClass), Name(i.Name, i.ArabicName) };
            row.AddRange(i.Amounts.Cast<object?>());
            row.AddRange(Enumerable.Range(1, n - 1).Select(x => (object?)PayrollComparison.Diff(i.Amounts, x)));
            row.AddRange(Enumerable.Range(1, n - 1).Select(x => Pct(PayrollComparison.Percent(i.Amounts, x))));
            return (IReadOnlyList<object?>)row;
        });

        // ---- Employees
        var employees = cmp.Employees.Select(e =>
        {
            var row = new List<object?> { e.EmployeeNo, Name(e.EmployeeName, e.ArabicName), e.DepartmentName };
            row.AddRange(e.Net.Cast<object?>());
            row.AddRange(Enumerable.Range(1, n - 1).Select(x => (object?)PayrollComparison.Diff(e.Net, x)));
            row.Add(L[e.Kind switch { "new" => "pr.cmp_kind_new", "missing" => "pr.cmp_kind_missing", "changed" => "pr.cmp_kind_changed", _ => "pr.cmp_kind_same" }]);
            return (IReadOnlyList<object?>)row;
        });

        var money = Enumerable.Repeat(16d, n + 2 * (n - 1)).ToList();
        var bytes = XlsxFile.Write(
        [
            new XlsxSheet(L["pr.cmp_sheet_summary"], [L["pr.cmp_measure"], .. codes, .. diffHeaders, .. pctHeaders], summary, [26, .. money]),
            new XlsxSheet(L["pr.cmp_sheet_items"], [L["pr.class"], L["pr.cmp_pay_item"], .. codes, .. diffHeaders, .. pctHeaders], items, [14, 30, .. money]),
            new XlsxSheet(L["pr.cmp_sheet_employees"], [L["emp.employee_no"], L["pr.employee"], L["common.department"], .. codes, .. diffHeaders, L["pr.cmp_change"]],
                          employees, [14, 30, 22, .. Enumerable.Repeat(16d, n + n - 1), 14])
        ], rightToLeft: L.IsArabic);

        var file = $"payroll-comparison-{string.Join("-vs-", codes.Select(SafeFilePart))}.xlsx";
        return File(bytes, XlsxFile.ContentType, file);
    }

    [HttpGet("export")]
    public async Task<IActionResult> Export(long run)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return NotFound();

        var rows = (await _runs.EmployeesAsync(run, new RunEmployeeFilter { PageSize = 5000 }, Ct)).Items;
        var inv = CultureInfo.InvariantCulture;
        var sb = new StringBuilder();
        sb.AppendLine(string.Join(',', new[]
        {
            "Employee No", "Employee", "Arabic name", "Department", "Paid days", "Period days",
            "Salary", "Earnings", "Deductions", "Net", "Previous net", "Excluded", "Exclusion reason"
        }.Select(h => Csv(_text.Tr(h)))));
        foreach (var e in rows)
        {
            sb.AppendLine(string.Join(',',
                Csv(e.EmployeeNo), Csv(e.EmployeeName), Csv(e.ArabicName), Csv(e.DepartmentName),
                e.PaidDays.ToString(inv), e.PeriodDays.ToString(inv),
                e.SalaryTotal.ToString("0.000", inv), e.EarningsTotal.ToString("0.000", inv), e.DeductionsTotal.ToString("0.000", inv),
                e.NetPay.ToString("0.000", inv), e.PreviousNet?.ToString("0.000", inv) ?? string.Empty,
                e.IsExcluded ? "1" : "0", Csv(e.ExcludeReason)));
        }

        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"{r.RunCode ?? "payroll"}.csv");
    }

    // =======================================================================
    // Create Payroll (draft → Registered)
    // =======================================================================

    [HttpGet("periods")]
    public async Task<IActionResult> Periods(int calendarId)
    {
        if (!Can(PermView)) return Forbid();
        if (!await OwnsCalendar(calendarId)) return NotFound();
        var periods = await _calendars.PeriodsAsync(calendarId, null, openableOnly: true, Ct);
        return Json(periods.Select(p => new
        {
            id = p.PayrollPeriodId,
            text = PayrollFormat.Period(_text, p),
            dates = $"{_text.DayMonth(p.StartDate)} – {_text.Date(p.EndDate)}",
            status = p.Status,
            statusText = _text.Tr(PeriodStatusLabel(p.Status)),
            runs = p.RunCount,
            current = p.StartDate <= DateTime.Today && p.EndDate >= DateTime.Today,
            month = p.RunMonth.ToString("yyyy-MM", CultureInfo.InvariantCulture)
        }));
    }

    [HttpGet("calendars-for")]
    public async Task<IActionResult> CalendarsFor(int companyId)
    {
        if (!Can(PermView)) return Forbid();
        if (OwnCompany is { } own && own != companyId) return Forbid();
        var list = await _calendars.ListAsync(new GridRequest { CompanyId = companyId, IsActive = true, PageSize = 200 }, Ct);
        var departments = await _lookups.GetAsync(LookupType.Department, companyId, cancellationToken: Ct);
        var locations = await _lookups.GetAsync(LookupType.Location, companyId, cancellationToken: Ct);
        return Json(new
        {
            calendars = list.Items.Select(c => new { id = c.PayrollCalendarId, text = PayrollFormat.Calendar(_text, c.CalendarName, c.ArabicName), isDefault = c.IsDefault }),
            departments = departments.Select(d => new { id = d.Id, text = d.Text }),
            locations = locations.Select(l => new { id = l.Id, text = l.Text })
        });
    }

    [HttpGet("next-code")]
    public async Task<IActionResult> NextCode(int periodId)
    {
        if (!Can(PermView)) return Forbid();
        if (!await OwnsPeriod(periodId)) return NotFound();
        var next = await _runs.NextCodeAsync(periodId, Ct);
        if (next is null) return Json(new { ok = false });

        string hint;
        if (next.IssuedCount == 0)
        {
            hint = _text["pr.first_payroll_hint", _text.MonthYear(next.RunMonth)];
        }
        else if (next.CancelledCount > 0)
        {
            hint = _text["pr.issued_hint_cancelled", next.IssuedCount, _text.MonthYear(next.RunMonth), next.CancelledCount, next.NextSeq];
        }
        else
        {
            hint = _text["pr.issued_hint", next.IssuedCount, _text.MonthYear(next.RunMonth), next.NextSeq];
        }

        return Json(new
        {
            ok = true,
            code = next.RunCode,
            seq = next.NextSeq,
            issued = next.IssuedCount,
            cancelled = next.CancelledCount,
            regular = next.RegularRunCode,
            hint
        });
    }

    [HttpPost("draft-save")]
    public async Task<IActionResult> DraftSave(PayrollDraftInput input)
    {
        if (!Can(PermProcess)) return Denied();
        if (OwnCompany is { } own && input.CompanyId != own) return Denied();
        if (input.PayrollRunId is > 0 && await LoadRunAsync(input.PayrollRunId.Value) is null) return Denied();

        var result = await _runs.SaveDraftAsync(input, UserId, Ct);
        return Result(result);
    }

    [HttpPost("draft-discard")]
    public Task<IActionResult> DraftDiscard(long run) => RunAction(run, PermProcess, "DISCARD");

    [HttpPost("finalize")]
    public Task<IActionResult> FinalizeRun(long run) => RunAction(run, PermProcess, "FINALIZE");

    [HttpPost("recalc")]
    public Task<IActionResult> Recalc(long run) => RunAction(run, PermProcess, "RECALC");

    [HttpPost("revalidate")]
    public Task<IActionResult> Revalidate(long run) => RunAction(run, PermProcess, "VALIDATE");

    // =======================================================================
    // Lines and employees of a run
    // =======================================================================

    [HttpPost("add-line")]
    public async Task<IActionResult> AddLine(long run, string? employeeIds, int componentId, string? amount, string? comment)
    {
        if (!Can(PermProcess)) return Denied();
        if (await LoadRunAsync(run) is null) return Denied();

        var ids = (employeeIds ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => long.TryParse(x, NumberStyles.None, CultureInfo.InvariantCulture, out var v) ? v : 0)
            .Where(v => v > 0).Distinct().ToList();

        if (!decimal.TryParse((amount ?? string.Empty).Replace(",", string.Empty), NumberStyles.Number, CultureInfo.InvariantCulture, out var value)
            || value <= 0 || value > 9_999_999m || string.IsNullOrWhiteSpace(comment) || ids.Count == 0 || componentId <= 0)
        {
            return Json(ActionResponse.Failed("Enter an amount and a comment.", "VALIDATION"));
        }

        return Result(await _runs.AddLineAsync(run, ids, componentId, Math.Round(value, 3), comment, UserId, Ct));
    }

    [HttpPost("remove-line")]
    public async Task<IActionResult> RemoveLine(long run, long lineId)
    {
        if (!Can(PermProcess)) return Denied();
        if (await LoadRunAsync(run) is null) return Denied();
        return Result(await _runs.RemoveLineAsync(run, lineId, UserId, Ct));
    }

    [HttpPost("exclude")]
    public async Task<IActionResult> Exclude(long run, long employeeId, string? reason)
    {
        if (!Can(PermExclude)) return Denied();
        if (await LoadRunAsync(run) is not { } r) return Denied();
        var result = await _runs.ExcludeAsync(run, employeeId, true, reason, UserId, Ct);
        if (result.Success) await _auditor.PayrollInclusionAsync(employeeId, true, RunReference(r), reason);
        return Result(result);
    }

    [HttpPost("include")]
    public async Task<IActionResult> Include(long run, long employeeId)
    {
        if (!Can(PermExclude)) return Denied();
        if (await LoadRunAsync(run) is not { } r) return Denied();
        var result = await _runs.ExcludeAsync(run, employeeId, false, null, UserId, Ct);
        if (result.Success) await _auditor.PayrollInclusionAsync(employeeId, false, RunReference(r), null);
        return Result(result);
    }

    /// <summary>The payroll an audit row refers to: its code, or "Draft · calendar · period" before it has one.</summary>
    private string RunReference(PayrollRun r) =>
        r.RunCode ?? $"Draft · {r.CalendarName} · {PayrollFormat.Period(_text, r)}";

    // =======================================================================
    // Stages, approval, cancel
    // =======================================================================

    [HttpPost("stage")]
    public Task<IActionResult> Stage(long run, string stage, string? comment) =>
        RunAction(run, PermProcess, "SET_STAGE", stage, comment);

    [HttpPost("approve")]
    public async Task<IActionResult> Approve(long run, string? comment)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return Denied();
        if (ApprovalLevelFor(r) == 0)
        {
            return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        }

        return Result(await _runs.RunActionAsync("APPROVE", run, UserId, comment: comment, allowSelfApproval: CanApproveOwn, cancellationToken: Ct));
    }

    [HttpPost("return")]
    public async Task<IActionResult> ReturnForCorrection(long run, string? comment)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return Denied();
        if (ApprovalLevelFor(r) == 0) return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        return Result(await _runs.RunActionAsync("SET_STAGE", run, UserId, RunStage.Validation, comment, cancellationToken: Ct));
    }

    [HttpPost("cancel")]
    public async Task<IActionResult> CancelRun(long run, string? comment)
    {
        var r = await LoadRunAsync(run);
        if (r is null) return Denied();
        // An approver may reject (= cancel) the payroll waiting for them.
        if (!Can(PermCancel) && !(r.Stage == RunStage.AwaitingApproval && ApprovalLevelFor(r) > 0)) return Denied();
        return Result(await _runs.RunActionAsync("CANCEL", run, UserId, comment: comment, cancellationToken: Ct));
    }

    [HttpPost("reopen")]
    public Task<IActionResult> Reopen(long run, string? comment) => RunAction(run, PermReopen, "REOPEN", null, comment);

    [HttpPost("ack")]
    public async Task<IActionResult> Acknowledge(long run, long issueId, string? reason)
    {
        if (!Can(PermProcess)) return Denied();
        if (await LoadRunAsync(run) is null) return Denied();
        return Result(await _runs.AcknowledgeAsync(run, issueId, reason, UserId, Ct));
    }

    // =======================================================================
    // Payroll calendars and periods (Phase 1 procedures)
    // =======================================================================

    [HttpGet("calendars-grid")]
    public async Task<IActionResult> CalendarsGrid(string? search, string? status, int page = 1)
    {
        if (!Can(PermSetupView)) return Forbid();   // Payroll Calendar & Pay Periods (Security: "PR.CALENDAR")
        var request = new GridRequest
        {
            CompanyId = OwnCompany,
            CompanyIds = CompanyCsv,
            Search = search,
            IsActive = status switch { "active" => true, "inactive" => false, _ => null },
            PageNumber = page,
            PageSize = 25
        };
        return PartialView("_CalendarsGrid", new CalendarsGridModel
        {
            Page = await _calendars.ListAsync(request, Ct),
            CanSetup = Can(PermSetupEdit),
            IsFiltered = !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status)
        });
    }

    [HttpGet("periods-grid")]
    public async Task<IActionResult> PeriodsGrid(int calendarId, int? year)
    {
        if (!Can(PermSetupView)) return Forbid();   // Payroll Calendar & Pay Periods (Security: "PR.CALENDAR")
        var calendar = calendarId > 0 ? await _calendars.GetByIdAsync(calendarId, Ct) : null;
        if (calendar is not null && OwnCompany is { } own && calendar.CompanyId != own) return NotFound();
        var y = year ?? DateTime.Today.Year;
        string? companyName = calendar?.CompanyName;
        if (calendar is not null && string.IsNullOrEmpty(companyName))
        {
            companyName = (await _lookups.GetAsync(LookupType.Company, includeInactive: true, cancellationToken: Ct))
                .FirstOrDefault(c => c.Id == calendar.CompanyId)?.Text;
        }
        return PartialView("_PeriodsGrid", new PeriodsGridModel
        {
            Calendar = calendar,
            CompanyName = companyName,
            Year = y,
            Periods = calendar is null ? Array.Empty<PayrollPeriodRow>() : await _calendars.PeriodsAsync(calendarId, y, false, Ct),
            CanSetup = Can(PermSetupEdit)
        });
    }

    [HttpGet("calendar-form")]
    public async Task<IActionResult> CalendarForm(int id = 0)
    {
        if (!Can(id > 0 ? PermSetupEdit : PermSetupCreate)) return Forbid();
        var isNew = id <= 0;
        var calendar = isNew
            ? new PayrollCalendar { CompanyId = OwnCompany ?? _companyFilter.SingleCompanyId ?? 0, FirstPeriodStartDate = new DateTime(DateTime.Today.Year, 1, 1), CutOffDay = 25, PaymentDay = 28 }
            : await _calendars.GetByIdAsync(id, Ct);
        // another company's calendar answers "not found", like a missing one
        if (calendar is null || (OwnCompany is { } mine && !isNew && calendar.CompanyId != mine)) return NotFound();

        var companies = await _lookups.GetAsync(LookupType.Company, includeInactive: !isNew, cancellationToken: Ct);
        if (OwnCompany is { } own) companies = companies.Where(c => c.Id == own).ToList();

        var locked = !isNew && (await _calendars.PeriodsAsync(id, null, false, Ct)).Any(p => p.Status != "OPEN");
        return PartialView("_CalendarForm", new CalendarFormModel
        {
            Calendar = calendar,
            IsNew = isNew,
            Companies = companies,
            Currencies = await _lookups.GetAsync(LookupType.Currency, cancellationToken: Ct),
            ScheduleLocked = locked
        });
    }

    [HttpPost("calendar-save")]
    public async Task<IActionResult> CalendarSave()
    {
        var model = new PayrollCalendar();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.PayrollCalendarId > 0 ? PermSetupEdit : PermSetupCreate)) return Denied();
        if (OwnCompany is { } own && model.CompanyId != own) return Denied();
        return Result(await _calendars.SaveAsync(model, UserId, Ct));
    }

    [HttpPost("calendar-delete")]
    public async Task<IActionResult> CalendarDelete(int id)
    {
        if (!Can(PermSetupDelete)) return Denied();
        if (!await OwnsCalendar(id)) return Denied();
        return Result(await _calendars.DeleteAsync(id, UserId, Ct));
    }

    [HttpPost("calendar-toggle")]
    public async Task<IActionResult> CalendarToggle(int id)
    {
        if (!Can(PermSetupEdit)) return Denied();
        if (!await OwnsCalendar(id)) return Denied();
        return Result(await _calendars.ToggleActiveAsync(id, UserId, Ct));
    }

    [HttpPost("periods-generate")]
    public async Task<IActionResult> PeriodsGenerate(int calendarId, int year)
    {
        if (!Can(PermSetupCreate) && !Can(PermSetupEdit)) return Denied();
        if (!await OwnsCalendar(calendarId)) return Denied();
        return Result(await _calendars.GeneratePeriodsAsync(calendarId, year, UserId, Ct));
    }

    [HttpGet("period-form")]
    public async Task<IActionResult> PeriodForm(int id)
    {
        if (!Can(PermSetupEdit)) return Forbid();
        var period = await _calendars.GetPeriodAsync(id, Ct);
        if (period is null || (OwnCompany is { } own && period.CompanyId != own)) return NotFound();
        return PartialView("_PeriodForm", new PeriodFormModel { Period = period });
    }

    [HttpPost("period-save")]
    public async Task<IActionResult> PeriodSave()
    {
        if (!Can(PermSetupEdit)) return Denied();
        var model = new PayrollPeriodEdit();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!await OwnsPeriod(model.PayrollPeriodId)) return Denied();
        return Result(await _calendars.SavePeriodAsync(model, UserId, Ct));
    }

    [HttpPost("period-delete")]
    public async Task<IActionResult> PeriodDelete(int id)
    {
        if (!Can(PermSetupDelete)) return Denied();
        if (!await OwnsPeriod(id)) return Denied();
        return Result(await _calendars.DeletePeriodAsync(id, UserId, Ct));
    }

    // =======================================================================
    // helpers
    // =======================================================================

    private async Task<IActionResult> RunAction(long run, string permission, string action, string? stage = null, string? comment = null)
    {
        if (!Can(permission)) return Denied();
        if (await LoadRunAsync(run) is null) return Denied();
        return Result(await _runs.RunActionAsync(action, run, UserId, stage, comment, cancellationToken: Ct));
    }

    /// <summary>The payroll last opened in this browser (drives the stage tabs on the other pages).</summary>
    private async Task<PayrollRun?> RememberedRunAsync()
    {
        if (!long.TryParse(Request.Cookies[RunCookie], NumberStyles.None, CultureInfo.InvariantCulture, out var id) || id <= 0)
        {
            return null;
        }

        var run = await _runs.GetAsync(id, Ct);
        return run is not null && CanSee(run) && run.Stage != RunStage.Draft ? run : null;
    }

    /// <summary>The run, if the user may see it (company scope).</summary>
    /// <summary>The companies this user works with (own company, or the company filter's selection).</summary>
    private async Task<IReadOnlyList<LookupItem>> VisibleCompaniesAsync()
    {
        var companies = await _lookups.GetAsync(LookupType.Company, cancellationToken: Ct);
        if (OwnCompany is { } own)
        {
            return companies.Where(c => c.Id == own).ToList();
        }
        if (_companyFilter.SelectedIds.Count > 0)
        {
            return companies.Where(c => _companyFilter.SelectedIds.Contains(c.Id)).ToList();
        }
        return companies;
    }

    /// <summary>A payroll that has figures to compare: any stage from Registered to Closed.</summary>
    private static bool IsComparable(PayrollRun run) => run.Stage is not (RunStage.Draft or RunStage.Cancelled);

    /// <summary>"12,15,9" -> distinct positive ids, in the order given (the first one is the baseline).</summary>
    private static List<long> ParseRunIds(string? csv) =>
        (csv ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => long.TryParse(x, NumberStyles.None, CultureInfo.InvariantCulture, out var v) ? v : 0)
            .Where(v => v > 0).Distinct().Take(10).ToList();

    /// <summary>
    /// Loads 2-3 payrolls of the same company and lines them up by pay item and
    /// by employee (included employees only). Returns an English error otherwise.
    /// </summary>
    private async Task<(PayrollComparison? Comparison, string Error)> BuildComparisonAsync(string? runs)
    {
        var ids = ParseRunIds(runs);
        if (ids.Count < 2) return (null, "Choose at least two different payrolls to compare.");
        if (ids.Count > ComparePageModel.MaxRuns) return (null, "Up to three payrolls can be compared at a time.");

        var list = new List<PayrollRun>();
        foreach (var id in ids)
        {
            var run = await LoadRunAsync(id);
            if (run is null || !IsComparable(run)) return (null, "A selected payroll was not found, or it is cancelled.");
            list.Add(run);
        }
        if (list.Select(r => r.CompanyId).Distinct().Count() > 1)
        {
            return (null, "Only payrolls of the same company can be compared.");
        }

        var employees = new List<IReadOnlyList<PayrollRunEmployee>>();
        var lines = new List<IReadOnlyList<PayrollRunLine>>();
        foreach (var run in list)
        {
            var emps = (await _runs.EmployeesAsync(run.PayrollRunId, new RunEmployeeFilter { Filter = "included", PageSize = 5000 }, Ct)).Items;
            var included = emps.Select(e => e.EmployeeId).ToHashSet();
            employees.Add(emps);
            lines.Add((await _runs.LinesAsync(run.PayrollRunId, null, Ct)).Where(l => included.Contains(l.EmployeeId)).ToList());
        }

        var n = list.Count;
        var totals = list.Select((run, i) => new CompareTotals
        {
            Employees = employees[i].Count,
            Joiners = employees[i].Count(e => e.IsJoiner),
            Leavers = employees[i].Count(e => e.IsLeaver),
            Salary = employees[i].Sum(e => e.SalaryTotal),
            Earnings = employees[i].Sum(e => e.EarningsTotal),
            Deductions = employees[i].Sum(e => e.DeductionsTotal),
            Gross = employees[i].Sum(e => e.GrossPay),
            Net = employees[i].Sum(e => e.NetPay)
        }).ToList();

        var items = lines.SelectMany((ls, i) => ls.Select(l => (Index: i, Line: l)))
            .GroupBy(x => x.Line.PayComponentId)
            .Select(g =>
            {
                var first = g.First().Line;
                var amounts = new decimal?[n];
                var counts = new int[n];
                foreach (var byRun in g.GroupBy(x => x.Index))
                {
                    amounts[byRun.Key] = byRun.Sum(x => x.Line.Amount);
                    counts[byRun.Key] = byRun.Select(x => x.Line.EmployeeId).Distinct().Count();
                }
                return new CompareItemRow
                {
                    PayComponentId = g.Key,
                    ItemClass = first.ItemClass,
                    Name = first.ComponentName,
                    ArabicName = first.ComponentArabicName,
                    Amounts = amounts,
                    Employees = counts
                };
            })
            .OrderBy(r => ItemClassOrder(r.ItemClass)).ThenBy(r => r.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var people = employees.SelectMany((es, i) => es.Select(e => (Index: i, Emp: e)))
            .GroupBy(x => x.Emp.EmployeeId)
            .Select(g =>
            {
                var net = new decimal?[n];
                var gross = new decimal?[n];
                foreach (var x in g)
                {
                    net[x.Index] = x.Emp.NetPay;
                    gross[x.Index] = x.Emp.GrossPay;
                }
                var latest = g.OrderByDescending(x => x.Index).First().Emp;
                return new CompareEmployeeRow
                {
                    EmployeeId = g.Key,
                    EmployeeNo = latest.EmployeeNo,
                    EmployeeName = latest.EmployeeName,
                    ArabicName = latest.ArabicName,
                    DepartmentName = latest.DepartmentName,
                    Net = net,
                    Gross = gross
                };
            })
            // biggest change first, then by name
            .OrderByDescending(r => Enumerable.Range(1, n - 1).Max(i => Math.Abs(PayrollComparison.Diff(r.Net, i) ?? 0)))
            .ThenBy(r => r.EmployeeName, StringComparer.OrdinalIgnoreCase)
            .ToList();

        return (new PayrollComparison { Runs = list, Totals = totals, Items = items, Employees = people }, string.Empty);
    }

    private static int ItemClassOrder(string itemClass) => itemClass switch
    {
        "SALARY" => 0, "EARNING" => 1, "DEDUCTION" => 2, "LOAN" => 3, _ => 4
    };

    private static string SafeFilePart(string text) =>
        new(text.Select(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' ? ch : '-').ToArray());

    private async Task<PayrollRun?> LoadRunAsync(long runId)
    {
        if (!Can(PermView) && !Can(PermProcess)) return null;
        var run = await _runs.GetAsync(runId, Ct);
        return run is not null && CanSee(run) ? run : null;
    }

    private bool CanSee(PayrollRun run) =>
        (OwnCompany is not { } own || run.CompanyId == own)
        && (run.Stage != RunStage.Draft || run.CreatedBy == UserId || IsSysAdmin);

    /// <summary>The period an id names exists and its calendar is in the user's company.</summary>
    private async Task<bool> OwnsPeriod(int periodId)
    {
        if (periodId <= 0) return false;
        if (OwnCompany is not { } own) return true;
        var p = await _calendars.GetPeriodAsync(periodId, Ct);
        return p is not null && p.CompanyId == own;
    }

    private async Task<bool> OwnsCalendar(int calendarId)
    {
        if (OwnCompany is not { } own) return true;
        var c = await _calendars.GetByIdAsync(calendarId, Ct);
        return c is not null && c.CompanyId == own;
    }

    /// <summary>1 or 2 when this user can take the next approval decision on the run, else 0.</summary>
    private int ApprovalLevelFor(PayrollRun run)
    {
        if (run.Stage != RunStage.AwaitingApproval) return 0;
        var level = run.ApprovalLevel + 1;
        return level switch
        {
            1 when Can(PermApproveHr) => 1,
            2 when Can(PermApproveFinance) => 2,
            _ => 0
        };
    }

    private IActionResult Result(SaveResult result)
    {
        if (result.Success)
        {
            // the sidebar figures (open payrolls, payslips to generate / email) may have changed
            HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
        }
        return Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    private IActionResult Denied() =>
        Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));

    internal static string StagePage(string stage) => stage switch
    {
        RunStage.Validation => nameof(Validation),
        RunStage.AwaitingApproval or RunStage.Closed => nameof(Approval),
        _ => nameof(Register)
    };

    private static string PageName(int stage) => stage switch { 1 => nameof(Validation), 2 => nameof(Approval), _ => nameof(Register) };

    internal static string PeriodStatusLabel(string? status) => status switch
    {
        "OPEN" => "Open",
        "PROCESSING" => "Processing",
        "APPROVED" => "Approved",
        "POSTED" => "Posted",
        "CLOSED" => "Closed",
        _ => status ?? string.Empty
    };

    private static DateTime? ParseMonth(string? month) =>
        DateTime.TryParseExact(month, "yyyy-MM", CultureInfo.InvariantCulture, DateTimeStyles.None, out var m) ? m : null;

    private static string? NullIfEmpty(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string Csv(string? value)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;
        // Spreadsheet formula injection: a leading = + - @ is neutralised.
        if ("=+-@".Contains(value[0])) value = "'" + value;
        return value.Contains(',') || value.Contains('"') || value.Contains('\n') ? $"\"{value.Replace("\"", "\"\"")}\"" : value;
    }

    private Dictionary<string, string[]> CollectErrors() =>
        ModelState.Where(entry => entry.Value?.Errors.Count > 0)
                  .ToDictionary(entry => entry.Key, entry => entry.Value!.Errors.Select(e => e.ErrorMessage).ToArray());
}
