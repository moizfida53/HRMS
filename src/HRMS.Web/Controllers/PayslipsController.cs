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

    public PayslipsController(IPayslipRepository payslips, IPayrollRunRepository runs, ILookupRepository lookups, ICurrentUser currentUser,
                              ICompanyFilter companyFilter, LabelStore labels, IOptionsMonitor<PayslipEmailOptions> email)
    {
        _payslips = payslips;
        _runs = runs;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _labels = labels;
        _email = email;
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
    // =======================================================================

    [HttpGet("")]
    public IActionResult Index() => RedirectToAction(nameof(Generate));

    [HttpGet("generate")]
    public Task<IActionResult> Generate(long? run) => Page("generate", run, null, null, null);

    [HttpGet("employees")]
    public Task<IActionResult> Employees(long? run, int? dept, string? status, string? q) => Page("employees", run, dept, status, q);

    [HttpGet("email")]
    public Task<IActionResult> Email(long? run, string? status) => Page("email", run, null, status, null);

    /// <summary>One employee's payslip in one payroll, ready to print (?lang=both|en|ar previews another language).</summary>
    [HttpGet("{runId:long}/{employeeId:long}")]
    public async Task<IActionResult> Slip(long runId, long employeeId, string? lang)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var slip = await _payslips.GetAsync(runId, employeeId, OwnCompany, CompanyCsv, cancellationToken: Ct);
        if (slip is null) return NotFound();

        return await Document(slip, LangTemplate(lang) ?? slip.Template, isSelf: false, rights.CanGenerate,
                              Url.Action(nameof(Employees), new { run = runId }));
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

    [HttpGet("my/{runId:long}")]
    public async Task<IActionResult> MyPayslip(long runId, string? lang)
    {
        if (_currentUser.EmployeeId is not { } emp) return NotFound();

        // No company scope: an employee always sees their own payslips, whatever company is selected on top.
        var slip = await _payslips.GetAsync(runId, emp, null, null, selfEmployeeId: emp, cancellationToken: Ct);
        if (slip is null) return NotFound();

        await _payslips.MarkViewedAsync(runId, emp, Ct);
        return await Document(slip, LangTemplate(lang) ?? slip.Template, isSelf: true, canGenerate: false, Url.Action(nameof(My)));
    }

    // =======================================================================
    // Panels
    // =======================================================================

    [HttpGet("grid")]
    public async Task<IActionResult> Grid(string? mode, long? run, int? dept, string? status, string? search, int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var view = mode is "email" ? "email" : "employees";
        if (view == "email" && run is null) return BadRequest();

        var filter = PayslipFilter.Normalize(status);
        var result = await _payslips.ListAsync(new PayslipListFilter
        {
            CompanyId = OwnCompany,
            CompanyIds = CompanyCsv,
            RunId = run,
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
            IsFiltered = !string.IsNullOrWhiteSpace(search) || filter != PayslipFilter.All || dept is not null,
            ManyCompanies = ManyCompanies,
            AllRuns = run is null
        });
    }

    // =======================================================================
    // Changes
    // =======================================================================

    [HttpPost("generate")]
    public async Task<IActionResult> GeneratePayslips(long run, string? template, int? dept, [FromForm] long[]? employeeIds)
    {
        if (!Can(PermGenerate)) return Denied();
        if (run <= 0) return Json(ActionResponse.Failed("Select a payroll.", "VALIDATION"));
        return Result(await _payslips.GenerateAsync(run, PayslipTemplate.Normalize(template), dept, employeeIds, OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpPost("email")]
    public async Task<IActionResult> QueueEmail(long run, [FromForm] long[]? employeeIds, bool resend = false)
    {
        if (!Can(PermEmail)) return Denied();
        if (run <= 0) return Json(ActionResponse.Failed("Select a payroll.", "VALIDATION"));
        return Result(await _payslips.QueueEmailAsync(run, employeeIds, resend, OwnCompany, CompanyCsv, UserId, Ct));
    }

    // =======================================================================
    // Helpers
    // =======================================================================

    private async Task<IActionResult> Page(string mode, long? runId, int? dept, string? status, string? search)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var runs = await _payslips.RunsAsync(OwnCompany, CompanyCsv, Ct);
        PayslipRun? run = null;
        if (runId is > 0)
        {
            run = runs.FirstOrDefault(r => r.PayrollRunId == runId);
            if (run is null) return NotFound();
        }
        else if (mode != "employees")
        {
            // Generate / Email open on the latest closed payroll (else the latest one).
            run = runs.FirstOrDefault(r => r.IsClosed) ?? runs.FirstOrDefault();
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
            Summary = summary,
            Departments = departments,
            DepartmentId = dept,
            Status = PayslipFilter.Normalize(status),
            Search = search,
            EmailConfigured = _email.CurrentValue.IsConfigured,
            ManyCompanies = ManyCompanies
        });
    }

    private async Task<IActionResult> Document(Payslip slip, string? template, bool isSelf, bool canGenerate, string? backUrl)
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
            Both = (key, args) => (
                LabelStore.SafeFormat(_labels.Find(key, arabic: false) ?? key, args),
                LabelStore.SafeFormat(_labels.Find(key, arabic: true) ?? _labels.Find(key, arabic: false) ?? key, args))
        });
    }

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
