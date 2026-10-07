using System.Globalization;
using System.Text;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
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
    private const string PermSetupView = "PAYROLL_SETUP_VIEW";
    private const string PermSetupEdit = "PAYROLL_SETUP_EDIT";
    private const string PermSetupCreate = "PAYROLL_SETUP_CREATE";
    private const string PermSetupDelete = "PAYROLL_SETUP_DELETE";

    /// <summary>Remembers the payroll last opened, so the stage tabs follow it from page to page.</summary>
    internal const string RunCookie = "hrms_pr_run";

    private readonly IPayrollRunRepository _runs;
    private readonly IPayrollCalendarRepository _calendars;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _text;

    public PayrollController(
        IPayrollRunRepository runs,
        IPayrollCalendarRepository calendars,
        ILookupRepository lookups,
        ICurrentUser currentUser,
        ICompanyFilter companyFilter,
        IUiText text)
    {
        _runs = runs;
        _calendars = calendars;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _text = text;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool IsSysAdmin => _currentUser.IsInRole("SYSADMIN") || Can("SYSTEM_ADMIN");
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
    public async Task<IActionResult> Payrolls(string? month, string? stage)
    {
        if (!Can(PermView)) return Forbid();

        var months = await _runs.MonthsAsync(OwnCompany, CompanyCsv, Ct);
        ViewData["ActiveRun"] = await RememberedRunAsync();
        return View(new CalendarPageModel
        {
            Months = months,
            SelectedMonth = ParseMonth(month),
            SelectedStage = stage is null ? "LIVE" : stage,
            CanProcess = Can(PermProcess)
        });
    }

    /// <summary>Payroll Calendar: the pay groups (calendars) - add, edit, activate, delete.</summary>
    [HttpGet("calendars")]
    public async Task<IActionResult> Calendars()
    {
        if (!Can(PermView) && !Can(PermSetupView)) return Forbid();
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
        if (!Can(PermView) && !Can(PermSetupView)) return Forbid();

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

    [HttpGet("create")]
    public async Task<IActionResult> Create(long? draft)
    {
        if (!Can(PermProcess)) return Forbid();

        var companies = await _lookups.GetAsync(LookupType.Company, cancellationToken: Ct);
        if (OwnCompany is { } own)
        {
            companies = companies.Where(c => c.Id == own).ToList();
        }
        else if (_companyFilter.SelectedIds.Count > 0)
        {
            companies = companies.Where(c => _companyFilter.SelectedIds.Contains(c.Id)).ToList();
        }

        PayrollRun? resume = null;
        if (draft is > 0)
        {
            resume = await _runs.GetAsync(draft.Value, Ct);
            if (resume is null || resume.Stage != RunStage.Draft || !CanSee(resume))
            {
                return RedirectToAction(nameof(Create));
            }
        }

        var companyId = resume?.CompanyId ?? OwnCompany ?? _companyFilter.SingleCompanyId ?? companies.FirstOrDefault()?.Id;
        var calendars = companyId is { } cid
            ? (await _calendars.ListAsync(new GridRequest { CompanyId = cid, IsActive = true, PageSize = 200 }, Ct)).Items
            : Array.Empty<PayrollCalendar>();

        ViewData["ActiveRun"] = await RememberedRunAsync();
        return View(new CreatePageModel
        {
            Companies = companies,
            CompanyId = companyId,
            Calendars = calendars,
            Departments = companyId is { } d ? await _lookups.GetAsync(LookupType.Department, d, cancellationToken: Ct) : Array.Empty<LookupItem>(),
            Locations = companyId is { } l ? await _lookups.GetAsync(LookupType.Location, l, cancellationToken: Ct) : Array.Empty<LookupItem>(),
            Drafts = await _runs.DraftsAsync(OwnCompany, CompanyCsv, UserId, Ct),
            Draft = resume,
            CanProcess = true
        });
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
        return View(new HistoryPageModel { FinishedRuns = finished.Items.Where(r => r.IsClosed).ToList(), Years = years });
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
            if (pageStage != reached)
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
            IsSelfApprovalBlocked = run is not null && !IsSysAdmin && run.Stage == RunStage.AwaitingApproval
                                    && (run.SubmittedBy == UserId || (run.ApprovalLevel == 1 && run.Level1ApprovedBy == UserId))
        };

        ViewData["ActiveRun"] = run;
        return View(PageName(pageStage), model);
    }

    // =======================================================================
    // Grids and panels (partials)
    // =======================================================================

    [HttpGet("runs-grid")]
    public async Task<IActionResult> RunsGrid(string? mode, string? month, string? stage, string? type, int? year, string? search, int page = 1)
    {
        if (!Can(PermView)) return Forbid();

        var history = mode == "history";
        var filter = new RunListFilter
        {
            CompanyId = OwnCompany,
            CompanyIds = CompanyCsv,
            RunMonth = ParseMonth(month),
            Stage = history ? (string.IsNullOrEmpty(stage) ? "FINISHED" : stage) : NullIfEmpty(stage),
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
            IsFiltered = (!string.IsNullOrEmpty(stage) && stage != "LIVE") || !string.IsNullOrEmpty(type) || year is not null
                         || !string.IsNullOrWhiteSpace(search) || filter.RunMonth is not null,
            OpenOnly = !history && stage == "LIVE"
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
        ViewData["Editable"] = r.IsEditable && Can(PermProcess);
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
            IsFiltered = !string.IsNullOrEmpty(severity) || !string.IsNullOrEmpty(status) || !string.IsNullOrWhiteSpace(search)
        });
    }

    [HttpGet("compare")]
    public async Task<IActionResult> Compare(long a, long b)
    {
        var ra = await LoadRunAsync(a);
        var rb = await LoadRunAsync(b);
        if (ra is null || rb is null) return NotFound();
        return PartialView("_Compare", new RunCompareModel { RunA = ra, RunB = rb, Rows = await _runs.CompareAsync(a, b, Ct) });
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
        if (!Can(PermProcess)) return Denied();
        if (await LoadRunAsync(run) is null) return Denied();
        return Result(await _runs.ExcludeAsync(run, employeeId, true, reason, UserId, Ct));
    }

    [HttpPost("include")]
    public async Task<IActionResult> Include(long run, long employeeId)
    {
        if (!Can(PermProcess)) return Denied();
        if (await LoadRunAsync(run) is null) return Denied();
        return Result(await _runs.ExcludeAsync(run, employeeId, false, null, UserId, Ct));
    }

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

        return Result(await _runs.RunActionAsync("APPROVE", run, UserId, comment: comment, allowSelfApproval: IsSysAdmin, cancellationToken: Ct));
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
        if (!Can(PermView) && !Can(PermSetupView)) return Forbid();
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
        if (!Can(PermView) && !Can(PermSetupView)) return Forbid();
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
        if (calendar is null) return NotFound();

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
        if (period is null) return NotFound();
        return PartialView("_PeriodForm", new PeriodFormModel { Period = period });
    }

    [HttpPost("period-save")]
    public async Task<IActionResult> PeriodSave()
    {
        if (!Can(PermSetupEdit)) return Denied();
        var model = new PayrollPeriodEdit();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        return Result(await _calendars.SavePeriodAsync(model, UserId, Ct));
    }

    [HttpPost("period-delete")]
    public async Task<IActionResult> PeriodDelete(int id)
    {
        if (!Can(PermSetupDelete)) return Denied();
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
    private async Task<PayrollRun?> LoadRunAsync(long runId)
    {
        if (!Can(PermView) && !Can(PermProcess)) return null;
        var run = await _runs.GetAsync(runId, Ct);
        return run is not null && CanSee(run) ? run : null;
    }

    private bool CanSee(PayrollRun run) =>
        (OwnCompany is not { } own || run.CompanyId == own)
        && (run.Stage != RunStage.Draft || run.CreatedBy == UserId || IsSysAdmin);

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

    private IActionResult Result(SaveResult result) =>
        Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));

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
