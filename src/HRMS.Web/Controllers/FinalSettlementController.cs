using HRMS.Data.Repositories;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Final Settlement (db/39-40): the end-of-service settlement of an employee who
/// leaves - pending salary, unpaid pay items, leave encashment, indemnity under
/// the rule set in force, recoveries - and leave encashment without exit.
/// A settlement moves Draft → Pending (HR, then Finance) → Approved → Paid, or is
/// Cancelled; the calculation lives in Payroll.usp_FinalSettlement_Calculate.
/// </summary>
[Route("payroll/settlement")]
public sealed class FinalSettlementController : Controller
{
    private const string PermView = "PAYROLL_FS_VIEW";
    private const string PermProcess = "PAYROLL_FS_PROCESS";
    private const string PermPay = "PAYROLL_FS_PAY";
    private const string PermCancel = "PAYROLL_FS_CANCEL";
    // Approval rights of this process (Security > Create Roles > Approval rights)
    private const string PermApproveHr = "PAYROLL_FS_APPROVE_L1";
    private const string PermApproveFinance = "PAYROLL_FS_APPROVE_L2";
    private const string PermApproveSelf = "PAYROLL_FS_APPROVE_SELF";

    private readonly IFinalSettlementRepository _settlements;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly LabelStore _labels;

    public FinalSettlementController(IFinalSettlementRepository settlements, ICurrentUser currentUser, ICompanyFilter companyFilter, LabelStore labels)
    {
        _settlements = settlements;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _labels = labels;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private int? OwnCompany => _currentUser.ActiveCompanyId;
    private string? CompanyCsv => _companyFilter.Csv;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool IsSysAdmin => _currentUser.IsInRole("SYSADMIN") || Can("SYSTEM_ADMIN");
    /// <summary>May approve their own submissions (System Administrator, or the "approve own" right).</summary>
    private bool CanApproveOwn => IsSysAdmin || Can(PermApproveSelf);
    private bool CanView => Can(PermView) || Can(PermProcess);

    private SettlementRights Rights => new()
    {
        CanProcess = Can(PermProcess),
        CanPay = Can(PermPay),
        CanCancel = Can(PermCancel),
        CanApproveHr = Can(PermApproveHr),
        CanApproveFinance = Can(PermApproveFinance),
        UserId = UserId,
        CanApproveOwn = CanApproveOwn
    };

    // =======================================================================
    // Pages
    // =======================================================================

    [HttpGet("")]
    public IActionResult Index(string? status, string? type, string? q)
    {
        if (!CanView) return Forbid();
        return View("~/Views/FinalSettlement/Index.cshtml", new SettlementListPageModel
        {
            Rights = Rights, Status = status, Type = type, Search = q, Mode = "list"
        });
    }

    [HttpGet("encashment")]
    public async Task<IActionResult> Encashment(long? emp)
    {
        if (!CanView) return Forbid();
        ViewData["Form"] = Rights.CanProcess
            ? new SettlementFormModel
            {
                Employees = (await _settlements.EmployeesAsync(OwnCompany, CompanyCsv, Ct)).Where(e => !e.HasLeft).ToList(),
                EmployeeId = emp,
                Type = SettlementType.Encashment,
                PayMonths = SettlementFormat.PayMonthOptions(DateTime.Today, null)
            }
            : null;
        return View("~/Views/FinalSettlement/Index.cshtml", new SettlementListPageModel
        {
            Rights = Rights, Type = SettlementType.Encashment, Mode = "encashment"
        });
    }

    [HttpGet("new")]
    public async Task<IActionResult> New(string? type, long? emp)
    {
        if (!Can(PermProcess)) return Forbid();
        var kind = SettlementType.IsExit(type) ? type! : SettlementType.Resignation;
        return View("~/Views/FinalSettlement/New.cshtml", new SettlementFormModel
        {
            Employees = await _settlements.EmployeesAsync(OwnCompany, CompanyCsv, Ct),
            EmployeeId = emp,
            Type = kind
        });
    }

    [HttpGet("{id:long}")]
    public async Task<IActionResult> Details(long id)
    {
        if (!CanView) return Forbid();
        var s = await _settlements.GetAsync(id, OwnCompany, CompanyCsv, Ct);
        if (s is null) return NotFound();

        var rights = Rights;
        return View("~/Views/FinalSettlement/Details.cshtml", new SettlementPageModel
        {
            Settlement = s,
            Lines = await _settlements.LinesAsync(id, OwnCompany, CompanyCsv, Ct),
            History = await _settlements.HistoryAsync(id, OwnCompany, CompanyCsv, Ct),
            Rights = rights,
            Form = s.IsDraft && rights.CanProcess
                ? new SettlementFormModel
                {
                    Settlement = s,
                    EmployeeId = s.EmployeeId,
                    Type = s.SettlementType,
                    PayMonths = SettlementFormat.PayMonthOptions(DateTime.Today, s.PayMonth)
                }
                : null
        });
    }

    /// <summary>The bilingual settlement statement (English and Arabic side by side), ready to print.</summary>
    [HttpGet("{id:long}/statement")]
    public async Task<IActionResult> Statement(long id)
    {
        if (!CanView) return Forbid();
        var s = await _settlements.GetAsync(id, OwnCompany, CompanyCsv, Ct);
        if (s is null) return NotFound();

        await _labels.RefreshIfStaleAsync(Ct);
        return View("~/Views/FinalSettlement/Statement.cshtml", new SettlementStatementModel
        {
            Settlement = s,
            Lines = await _settlements.LinesAsync(id, OwnCompany, CompanyCsv, Ct),
            Both = (key, args) => (
                LabelStore.SafeFormat(_labels.Find(key, arabic: false) ?? key, args),
                LabelStore.SafeFormat(_labels.Find(key, arabic: true) ?? _labels.Find(key, arabic: false) ?? key, args))
        });
    }

    // =======================================================================
    // Panels and data
    // =======================================================================

    [HttpGet("grid")]
    public async Task<IActionResult> Grid(string? search, string? type, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _settlements.ListAsync(new FinalSettlementFilter
        {
            CompanyId = OwnCompany,
            CompanyIds = CompanyCsv,
            Type = type is "EXIT" || SettlementType.All.Contains(type ?? "") ? type : null,
            Status = status is "OPEN" or SettlementStatus.Draft or SettlementStatus.Pending or SettlementStatus.Approved
                     or SettlementStatus.Paid or SettlementStatus.Cancelled ? status : "ALL",
            Search = search,
            PageNumber = Math.Max(1, page),
            PageSize = 25
        }, Ct);
        return PartialView("~/Views/FinalSettlement/_Grid.cshtml", new SettlementGridModel
        {
            Page = result,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status) && status != "ALL",
            ManyCompanies = _companyFilter.SelectedIds.Count != 1 && OwnCompany is null,
            Rights = Rights
        });
    }

    [HttpGet("kpis")]
    public async Task<IActionResult> Kpis()
    {
        if (!CanView) return Forbid();
        var summary = await _settlements.SummaryAsync(OwnCompany, CompanyCsv, Ct) ?? new FinalSettlementSummary();
        return PartialView("~/Views/FinalSettlement/_Kpis.cshtml", summary);
    }

    /// <summary>Hire date, service, salary bases and "salary unpaid from" for the form (JSON).</summary>
    [HttpGet("defaults")]
    public async Task<IActionResult> Defaults(long emp, DateTime? lwd)
    {
        if (!Can(PermProcess)) return Forbid();
        var d = await _settlements.DefaultsAsync(emp, lwd, OwnCompany, CompanyCsv, Ct);
        if (d is null) return Json(null);
        return Json(new
        {
            hireDate = d.HireDate?.ToString("yyyy-MM-dd"),
            serviceDays = d.ServiceDays,
            monthlySalary = d.MonthlySalary,
            indemnityBase = d.IndemnityBase,
            leaveBase = d.LeaveBase,
            paidThrough = d.PaidThrough?.ToString("yyyy-MM-dd"),
            paidByRun = d.PaidByRun,
            salaryFrom = d.DefaultSalaryFrom?.ToString("yyyy-MM-dd"),
            ruleSet = d.RuleSetCode,
            ruleSetVerified = d.RuleSetVerified,
            noticeDays = d.NoticePeriodDays,
            department = d.DepartmentName,
            designation = d.DesignationName,
            status = d.EmploymentStatus,
            openNo = d.OpenSettlementNo,
            openUrl = d.OpenSettlementId is { } oid ? Url.Action(nameof(Details), new { id = oid }) : null
        });
    }

    // =======================================================================
    // Changes
    // =======================================================================

    [HttpPost("save")]
    public async Task<IActionResult> Save(FinalSettlementInput input)
    {
        if (!Can(PermProcess)) return Denied();
        if (!ModelState.IsValid)
        {
            return Json(ActionResponse.Failed("Check the dates and numbers - one of them is not a valid value.", "VALIDATION"));
        }
        return Result(await _settlements.SaveAsync(input, OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpPost("{id:long}/recalc")]
    public async Task<IActionResult> Recalc(long id) =>
        Can(PermProcess) ? Result(await _settlements.ActionAsync("RECALC", id, OwnCompany, CompanyCsv, UserId, cancellationToken: Ct)) : Denied();

    [HttpPost("{id:long}/add-line")]
    public async Task<IActionResult> AddLine(long id, string? section, string? description, decimal? amount)
    {
        if (!Can(PermProcess)) return Denied();
        if (!ModelState.IsValid) return Json(ActionResponse.Failed("Enter an amount greater than zero.", "VALIDATION"));
        return Result(await _settlements.AddLineAsync(id, section, description, amount, OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpPost("{id:long}/remove-line")]
    public async Task<IActionResult> RemoveLine(long id, long lineId) =>
        Can(PermProcess)
            ? Result(await _settlements.ActionAsync("REMOVE_LINE", id, OwnCompany, CompanyCsv, UserId, new SettlementActionArgs { LineId = lineId }, Ct))
            : Denied();

    [HttpPost("{id:long}/toggle-line")]
    public async Task<IActionResult> ToggleLine(long id, long lineId) =>
        Can(PermProcess)
            ? Result(await _settlements.ActionAsync("TOGGLE_LINE", id, OwnCompany, CompanyCsv, UserId, new SettlementActionArgs { LineId = lineId }, Ct))
            : Denied();

    [HttpPost("{id:long}/submit")]
    public async Task<IActionResult> Submit(long id, bool ack, string? comment) =>
        Can(PermProcess)
            ? Result(await _settlements.ActionAsync("SUBMIT", id, OwnCompany, CompanyCsv, UserId,
                                                    new SettlementActionArgs { AckUnverified = ack, Comment = comment }, Ct))
            : Denied();

    [HttpPost("{id:long}/approve")]
    public async Task<IActionResult> Approve(long id, string? comment)
    {
        var s = await _settlements.GetAsync(id, OwnCompany, CompanyCsv, Ct);
        if (s is null) return Json(ActionResponse.Failed("This settlement no longer exists.", "NOT_FOUND"));
        if (!s.IsPending || !Rights.CanApprove(s.ApprovalLevel)) return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        return Result(await _settlements.ActionAsync("APPROVE", id, OwnCompany, CompanyCsv, UserId, new SettlementActionArgs
        {
            Comment = comment, AllowSelfApproval = CanApproveOwn, ExpectedLevel = s.ApprovalLevel
        }, Ct));
    }

    [HttpPost("{id:long}/return")]
    public Task<IActionResult> Return(long id, string? comment) => Decide("RETURN", id, comment);

    [HttpPost("{id:long}/reject")]
    public Task<IActionResult> Reject(long id, string? comment) => Decide("REJECT", id, comment);

    [HttpPost("{id:long}/pay")]
    public async Task<IActionResult> Pay(long id, DateTime? paidDate, string? method, string? reference, string? comment) =>
        Can(PermPay)
            ? Result(await _settlements.ActionAsync("PAY", id, OwnCompany, CompanyCsv, UserId, new SettlementActionArgs
            {
                PaidDate = paidDate, PaymentMethod = method, PaymentRef = reference, Comment = comment
            }, Ct))
            : Denied();

    [HttpPost("{id:long}/cancel")]
    public async Task<IActionResult> Cancel(long id, string? comment) =>
        Can(PermCancel)
            ? Result(await _settlements.ActionAsync("CANCEL", id, OwnCompany, CompanyCsv, UserId, new SettlementActionArgs { Comment = comment }, Ct))
            : Denied();

    // =======================================================================
    // Helpers
    // =======================================================================

    private async Task<IActionResult> Decide(string action, long id, string? comment)
    {
        if (!Rights.IsApprover) return Denied();
        var s = await _settlements.GetAsync(id, OwnCompany, CompanyCsv, Ct);
        if (s is null) return Json(ActionResponse.Failed("This settlement no longer exists.", "NOT_FOUND"));
        if (!s.IsPending || !Rights.CanApprove(s.ApprovalLevel)) return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        return Result(await _settlements.ActionAsync(action, id, OwnCompany, CompanyCsv, UserId, new SettlementActionArgs { Comment = comment }, Ct));
    }

    private IActionResult Result(Domain.Common.SaveResult result) =>
        Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));

    private IActionResult Denied() =>
        Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
}
