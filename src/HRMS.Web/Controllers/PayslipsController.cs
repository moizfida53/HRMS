using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payslips (db/42-43): generate the payslips of a closed payroll, find and
/// print any employee's payslip, email them (the email links to My Payslips,
/// no salary figures in it) and My Payslips - every employee's own payslips.
/// The figures are always the payroll's own lines; a payslip is never edited.
/// </summary>
[Route("payroll/payslips")]
public sealed class PayslipsController : Controller
{
    private const string PermView = "PAYROLL_SLIP_VIEW";
    private const string PermGenerate = "PAYROLL_SLIP_GENERATE";
    private const string PermEmail = "PAYROLL_SLIP_EMAIL";

    private readonly IPayslipRepository _payslips;
    private readonly IPayrollRunRepository _runs;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly LabelStore _labels;
    private readonly IOptionsMonitor<PayslipEmailOptions> _email;
    private readonly IRefProtector _refs;

    public PayslipsController(IPayslipRepository payslips, IPayrollRunRepository runs, ILookupRepository lookups, ICurrentUser currentUser,
                              ICompanyFilter companyFilter, LabelStore labels, IOptionsMonitor<PayslipEmailOptions> email,
                              IRefProtector refs)
    {
        _payslips = payslips;
        _runs = runs;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _labels = labels;
        _email = email;
        _refs = refs;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private int? OwnCompany => _currentUser.ActiveCompanyId;
    private string? CompanyCsv => _companyFilter.Csv;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool ManyCompanies => _companyFilter.SelectedIds.Count != 1 && OwnCompany is null;

    private PayslipRights Rights => new()
    {
        CanGenerate = Can(PermGenerate),
        CanEmail = Can(PermEmail),
        CanView = Can(PermView) || Can(PermGenerate) || Can(PermEmail)
    };

    // =======================================================================
    // Pages
    //   No database id travels in an address or a posted field: a payroll, or an
    //   employee's payslip, is named by an opaque reference (IRefProtector) - bound
    //   to the signed-in user, signed, time-limited - and the company scope and
    //   permissions still apply to whatever it names.
    // =======================================================================

    [HttpGet("")]
    public IActionResult Index() => RedirectToAction(nameof(Generate));

    /// <summary>
    /// Generate Payslips: the payrolls - by default the closed ones with payslips still to generate.
    /// <paramref name="open"/> (a payroll reference, e.g. from "Goto PaySlips" on Payrolls) opens its popup.
    /// </summary>
    [HttpGet("generate")]
    public async Task<IActionResult> Generate(int? year, string? month, string? show, string? q, string? open)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var runs = await _payslips.RunsAsync(OwnCompany, CompanyCsv, Ct);
        var y = ValidYear(year);
        var m = ParseMonth(month);
        var filter = PayslipShow.Normalize(show);
        var search = string.IsNullOrWhiteSpace(q) ? null : q.Trim();
        if (search?.Length > 100) search = search[..100];

        var rows = runs
            .Where(r => (y is null || r.RunMonth.Year == y) && (m is null || r.RunMonth == m) && PayslipShow.Matches(r, filter))
            .Where(r => search is null
                        || (r.RunCode?.Contains(search, StringComparison.OrdinalIgnoreCase) ?? false)
                        || (r.CompanyName?.Contains(search, StringComparison.OrdinalIgnoreCase) ?? false)
                        || (r.CalendarName?.Contains(search, StringComparison.OrdinalIgnoreCase) ?? false))
            .ToList();

        var openId = _refs.One(RefPurpose.PayslipRun, open);
        var openRun = openId is null ? null : runs.FirstOrDefault(r => r.PayrollRunId == openId);

        return View("~/Views/Payslips/Generate.cshtml", new PayslipGenerateModel
        {
            OpenRef = openRun is null ? null : open,
            OpenTitle = openRun?.RunCode,
            Rights = rights,
            Runs = runs,
            Rows = rows,
            Year = y ?? m?.Year,
            Month = m,
            Show = filter,
            Search = search,
            ManyCompanies = ManyCompanies || runs.Select(r => r.CompanyId).Distinct().Count() > 1,
            EmailConfigured = _email.CurrentValue.IsConfigured
        });
    }

    [HttpGet("employees")]
    public Task<IActionResult> Employees([FromQuery(Name = "ref")] string? runRef, int? dept, string? status, string? q, int? year, string? month) =>
        Page("employees", runRef, dept, status, q, year, month);

    [HttpGet("email")]
    public Task<IActionResult> Email([FromQuery(Name = "ref")] string? runRef, string? status, int? year, string? month) =>
        Page("email", runRef, null, status, null, year, month);

    /// <summary>One employee's payslip in one payroll, ready to print (?lang=both|en|ar previews another language).</summary>
    [HttpGet("view/{slipRef}")]
    public async Task<IActionResult> Slip(string slipRef, string? lang)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        // an altered or expired reference opens the list instead (it names nothing)
        if (_refs.Unprotect(RefPurpose.Payslip, slipRef, 2) is not [var runId, var employeeId]) return RedirectToAction(nameof(Employees));

        var slip = await _payslips.GetAsync(runId, employeeId, OwnCompany, CompanyCsv, cancellationToken: Ct);
        if (slip is null) return NotFound();

        return await Document(slip, LangTemplate(lang) ?? slip.Template, isSelf: false, rights.CanGenerate,
                              Url.Action(nameof(Employees), new { @ref = _refs.Protect(RefPurpose.PayslipRun, runId) }), slipRef);
    }

    /// <summary>My Payslips: the signed-in employee's own payslips (closed payrolls, generated).</summary>
    [HttpGet("my")]
    public async Task<IActionResult> My(int page = 1)
    {
        var employeeId = _currentUser.EmployeeId;
        var model = new MyPayslipsModel { HasEmployee = employeeId is not null };
        if (employeeId is { } emp)
        {
            model = new MyPayslipsModel
            {
                HasEmployee = true,
                Page = await _payslips.ListAsync(new PayslipListFilter
                {
                    SelfEmployeeId = emp, PageNumber = Math.Max(1, page), PageSize = 24
                }, Ct)
            };
        }
        return View("~/Views/Payslips/My.cshtml", model);
    }

    [HttpGet("my/{runRef}")]
    public async Task<IActionResult> MyPayslip(string runRef, string? lang)
    {
        if (_currentUser.EmployeeId is not { } emp) return NotFound();
        if (_refs.One(RefPurpose.MyPayslip, runRef) is not { } runId) return RedirectToAction(nameof(My));

        // No company scope: an employee always sees their own payslips, whatever company is selected on top.
        var slip = await _payslips.GetAsync(runId, emp, null, null, selfEmployeeId: emp, cancellationToken: Ct);
        if (slip is null) return NotFound();

        await _payslips.MarkViewedAsync(runId, emp, Ct);
        return await Document(slip, LangTemplate(lang) ?? slip.Template, isSelf: true, canGenerate: false, Url.Action(nameof(My)), null);
    }

    // =======================================================================
    // Panels (POST: the reference travels in the body, with the anti-forgery token)
    // =======================================================================

    /// <summary>The View popup of Generate Payslips: figures and the generate form of one payroll.</summary>
    [HttpPost("panel")]
    public async Task<IActionResult> RunPanel([FromForm(Name = "ref")] string? runRef)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        if (await FindRunAsync(runRef) is not { } run) return NotFound();

        return PartialView("~/Views/Payslips/_RunPanel.cshtml", new PayslipRunPanelModel
        {
            Run = run,
            Ref = runRef!,
            Summary = await _payslips.SummaryAsync(run.PayrollRunId, OwnCompany, CompanyCsv, Ct) ?? new PayslipSummary(),
            Departments = await _lookups.GetAsync(LookupType.Department, run.CompanyId, cancellationToken: Ct),
            Rights = rights
        });
    }

    /// <summary>The View Payslips popup: the employees of one payroll (the list itself comes from Grid).</summary>
    [HttpPost("slips")]
    public async Task<IActionResult> SlipsPanel([FromForm(Name = "ref")] string? runRef)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        if (await FindRunAsync(runRef) is not { } run) return NotFound();

        return PartialView("~/Views/Payslips/_SlipsPanel.cshtml", new PayslipSlipsPanelModel
        {
            Run = run,
            Ref = runRef!,
            Departments = await _lookups.GetAsync(LookupType.Department, run.CompanyId, cancellationToken: Ct),
            Rights = rights
        });
    }

    [HttpPost("grid")]
    public async Task<IActionResult> Grid([FromForm] string? mode, [FromForm(Name = "ref")] string? runRef, [FromForm] int? dept, [FromForm] string? status,
                                          [FromForm] string? search, [FromForm] int? year, [FromForm] string? month, [FromForm] int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        long? run = null;
        if (!string.IsNullOrEmpty(runRef))
        {
            run = _refs.One(RefPurpose.PayslipRun, runRef);
            if (run is null) return NotFound();
        }

        var view = mode is "email" ? "email" : "employees";
        if (view == "email" && run is null) return BadRequest();

        var filter = PayslipFilter.Normalize(status);
        var result = await _payslips.ListAsync(new PayslipListFilter
        {
            CompanyId = OwnCompany,
            CompanyIds = CompanyCsv,
            RunId = run,
            Year = run is null ? ValidYear(year) : null,
            RunMonth = run is null ? ParseMonth(month) : null,
            DepartmentId = dept,
            Status = filter,
            Search = search,
            PageNumber = Math.Max(1, page),
            PageSize = 25
        }, Ct);

        return PartialView("~/Views/Payslips/_Grid.cshtml", new PayslipGridModel
        {
            Mode = view,
            Page = result,
            Rights = rights,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || filter != PayslipFilter.All || dept is not null
                         || (run is null && (ValidYear(year) is not null || ParseMonth(month) is not null)),
            ManyCompanies = ManyCompanies,
            AllRuns = run is null
        });
    }

    // =======================================================================
    // Changes
    // =======================================================================

    /// <summary>Generate the payslips of a payroll (ref): everyone, a department, or one payslip (slip).</summary>
    [HttpPost("generate")]
    public async Task<IActionResult> GeneratePayslips([FromForm(Name = "ref")] string? runRef, [FromForm] string? slip, [FromForm] string? template, [FromForm] int? dept)
    {
        if (!Can(PermGenerate)) return Denied();
        if (!TryTarget(runRef, slip, out var run, out var employees)) return Json(ActionResponse.Failed("Select a payroll.", "VALIDATION"));
        return Result(await _payslips.GenerateAsync(run, PayslipTemplate.Normalize(template), dept, employees, OwnCompany, CompanyCsv, UserId, Ct));
    }

    /// <summary>Queue payslip emails of a payroll (ref): every one not sent, or one payslip (slip).</summary>
    [HttpPost("email")]
    public async Task<IActionResult> QueueEmail([FromForm(Name = "ref")] string? runRef, [FromForm] string? slip, [FromForm] bool resend = false)
    {
        if (!Can(PermEmail)) return Denied();
        if (!TryTarget(runRef, slip, out var run, out var employees)) return Json(ActionResponse.Failed("Select a payroll.", "VALIDATION"));
        return Result(await _payslips.QueueEmailAsync(run, employees, resend, OwnCompany, CompanyCsv, UserId, Ct));
    }

    // =======================================================================
    // Helpers
    // =======================================================================

    /// <summary>A payroll reference, or a payslip reference (payroll + that one employee).</summary>
    private bool TryTarget(string? runRef, string? slipRef, out long run, out long[]? employees)
    {
        employees = null;
        if (!string.IsNullOrEmpty(slipRef))
        {
            if (_refs.Unprotect(RefPurpose.Payslip, slipRef, 2) is [var r, var e])
            {
                run = r;
                employees = [e];
                return true;
            }
            run = 0;
            return false;
        }
        run = _refs.One(RefPurpose.PayslipRun, runRef) ?? 0;
        return run > 0;
    }

    /// <summary>The payroll a reference names, if it is in the user's company scope.</summary>
    private async Task<PayslipRun?> FindRunAsync(string? runRef)
    {
        if (_refs.One(RefPurpose.PayslipRun, runRef) is not { } id) return null;
        var runs = await _payslips.RunsAsync(OwnCompany, CompanyCsv, Ct);
        return runs.FirstOrDefault(r => r.PayrollRunId == id);
    }

    private async Task<IActionResult> Page(string mode, string? runRef, int? dept, string? status, string? search, int? year, string? month)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var runs = await _payslips.RunsAsync(OwnCompany, CompanyCsv, Ct);
        PayslipRun? run = null;
        if (!string.IsNullOrEmpty(runRef))
        {
            var id = _refs.One(RefPurpose.PayslipRun, runRef);
            run = id is null ? null : runs.FirstOrDefault(r => r.PayrollRunId == id);
            // an altered or expired reference (or a payroll out of scope) opens the page without it
            if (run is null) return RedirectToAction(mode == "email" ? nameof(Email) : nameof(Employees));
        }
        else if (mode != "employees")
        {
            // Email opens on the latest closed payroll of the chosen year / period
            // (else the latest one of them, else the latest payroll).
            var y = ValidYear(year);
            var m = ParseMonth(month);
            var matching = runs.Where(r => (y is null || r.RunMonth.Year == y) && (m is null || r.RunMonth == m)).ToList();
            run = matching.FirstOrDefault(r => r.IsClosed) ?? matching.FirstOrDefault() ?? runs.FirstOrDefault(r => r.IsClosed) ?? runs.FirstOrDefault();
        }

        var summary = run is null ? null : await _payslips.SummaryAsync(run.PayrollRunId, OwnCompany, CompanyCsv, Ct);
        var companyId = run?.CompanyId ?? OwnCompany ?? _companyFilter.SingleCompanyId;
        var departments = mode != "email" && companyId is { } cid
            ? await _lookups.GetAsync(LookupType.Department, cid, cancellationToken: Ct)
            : Array.Empty<LookupItem>();

        return View("~/Views/Payslips/Index.cshtml", new PayslipPageModel
        {
            Mode = mode,
            Rights = rights,
            Runs = runs,
            Run = run,
            RunRef = run is null ? null : _refs.Protect(RefPurpose.PayslipRun, run.PayrollRunId),
            Summary = summary,
            Departments = departments,
            DepartmentId = dept,
            Status = PayslipFilter.Normalize(status),
            Search = search,
            // the Year / Period filters as chosen (they only narrow the payroll list)
            Year = ValidYear(year) ?? ParseMonth(month)?.Year,
            Month = ParseMonth(month),
            EmailConfigured = _email.CurrentValue.IsConfigured,
            ManyCompanies = ManyCompanies
        });
    }

    private async Task<IActionResult> Document(Payslip slip, string? template, bool isSelf, bool canGenerate, string? backUrl, string? slipRef)
    {
        await _labels.RefreshIfStaleAsync(Ct);
        return View("~/Views/Payslips/Payslip.cshtml", new PayslipDocumentModel
        {
            Slip = slip,
            Lines = await _runs.LinesAsync(slip.PayrollRunId, slip.EmployeeId, Ct),
            Template = PayslipTemplate.Normalize(template),
            IsSelf = isSelf,
            CanGenerate = canGenerate,
            BackUrl = backUrl,
            SlipRef = slipRef,
            Both = (key, args) => (
                LabelStore.SafeFormat(_labels.Find(key, arabic: false) ?? key, args),
                LabelStore.SafeFormat(_labels.Find(key, arabic: true) ?? _labels.Find(key, arabic: false) ?? key, args))
        });
    }

    private static int? ValidYear(int? year) => year is >= 2000 and <= 2100 ? year : null;

    /// <summary>"2026-09" -> 1 Sep 2026.</summary>
    private static DateTime? ParseMonth(string? month) =>
        DateTime.TryParseExact(month, "yyyy-MM", System.Globalization.CultureInfo.InvariantCulture,
                               System.Globalization.DateTimeStyles.None, out var d) ? d : null;

    private static string? LangTemplate(string? lang) => lang switch
    {
        "en" => PayslipTemplate.English,
        "ar" => PayslipTemplate.Arabic,
        "both" => PayslipTemplate.Bilingual,
        _ => null
    };

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
}
