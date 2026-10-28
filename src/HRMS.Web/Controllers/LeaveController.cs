using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Leave;
using HRMS.Web.Helpers;
using HRMS.Web.Localization;
using HRMS.Web.Models.Leave;
using HRMS.Web.Models.Organization;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Leave, phase 1 (db/68-69): requests with line manager / HR approval, balances,
/// My Leave (self-service) and Settings (leave types, public holidays, weekend).
/// Records open in popups - no ids in the address bar.
/// </summary>
[Route("leave")]
public sealed class LeaveController : Controller
{
    internal const string PermView = "LEAVE_VIEW";
    internal const string PermManage = "LEAVE_MANAGE";
    internal const string PermAdjust = "LEAVE_BALANCE_ADJUST";
    internal const string PermSetupView = "LEAVE_SETUP_VIEW";
    internal const string PermSetupEdit = "LEAVE_SETUP_EDIT";
    internal const string PermApproveL1 = "LEAVE_APPROVE_L1";
    internal const string PermApproveL2 = "LEAVE_APPROVE_L2";
    internal const string PermApproveSelf = "LEAVE_APPROVE_SELF";
    internal const string PermSettle = "LEAVE_SETTLE";
    internal const string PermEliminate = "LEAVE_ELIMINATE";

    private readonly ILeaveRepository _leave;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IDocumentStorage _storage;
    private readonly IUiText _text;
    private readonly ILogger<LeaveController> _logger;

    public LeaveController(ILeaveRepository leave, ICurrentUser currentUser, ICompanyFilter companyFilter,
        IDocumentStorage storage, IUiText text, ILogger<LeaveController> logger)
    {
        _leave = leave;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _storage = storage;
        _text = text;
        _logger = logger;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool IsSysAdmin => _currentUser.IsInRole("SYSADMIN") || Can("SYSTEM_ADMIN");

    private LeaveRights Rights => new()
    {
        CanView = Can(PermView),
        CanManage = Can(PermManage),
        CanAdjust = Can(PermAdjust),
        CanApproveL1 = Can(PermApproveL1),
        CanApproveL2 = Can(PermApproveL2),
        CanApproveOwn = IsSysAdmin || Can(PermApproveSelf),
        CanSetupView = Can(PermSetupView) || Can(PermSetupEdit),
        CanSetupEdit = Can(PermSetupEdit),
        CanSettle = Can(PermSettle),
        CanEliminate = Can(PermEliminate),
        UserId = _currentUser.UserId,
        EmployeeId = _currentUser.EmployeeId
    };

    /// <summary>The user's companies and rights, for the procedures.</summary>
    private LeaveScope Scope(bool asHr = true)
    {
        var r = Rights;
        return new LeaveScope
        {
            CompanyId = _currentUser.ActiveCompanyId,
            CompanyIds = _companyFilter.Csv,
            UserId = _currentUser.UserId,
            IsHr = asHr && r.CanManage,
            CanApproveL1 = r.CanApproveL1,
            CanApproveL2 = r.CanApproveL2,
            AllowSelf = r.CanApproveOwn
        };
    }

    /// <summary>The settlement acts as HR in the user's companies (the right is LEAVE_SETTLE, not LEAVE_MANAGE).</summary>
    private LeaveScope SettleScope()
    {
        var r = Rights;
        return new LeaveScope
        {
            CompanyId = _currentUser.ActiveCompanyId,
            CompanyIds = _companyFilter.Csv,
            UserId = _currentUser.UserId,
            IsHr = r.CanSettle,
            CanApproveL1 = r.CanApproveL1,
            CanApproveL2 = r.CanApproveL2,
            AllowSelf = r.CanApproveOwn
        };
    }

    private bool ManyCompanies => _companyFilter.SelectedIds.Count != 1 && _currentUser.ActiveCompanyId is null;

    // =======================================================================
    // Requests (HR and approvers)
    // =======================================================================

    [HttpGet("")]
    public async Task<IActionResult> Index(string? status)
    {
        var r = Rights;
        if (!r.CanView && !r.AnyApproval)
        {
            return _currentUser.EmployeeId is not null ? RedirectToAction(nameof(My)) : Forbid();
        }
        return View("~/Views/Leave/Index.cshtml", new LeavePageModel
        {
            Rights = r,
            Employees = r.CanView || r.CanManage ? await _leave.EmployeesAsync(Scope(), Ct) : Array.Empty<LeaveEmployeeOption>(),
            Types = await _leave.TypesAsync(Scope(), null, Ct),
            Status = status is "PENDING" or "MINE" or "APPROVED" or "RETURNED" or "DUEBACK" or "ONLEAVE" or "UPCOMING" or "REJECTED" or "CANCELLED" or "ALL"
                ? status : (r.AnyApproval ? "MINE" : "ALL"),
            ManyCompanies = ManyCompanies
        });
    }

    [HttpGet("kpis")]
    public async Task<IActionResult> Kpis()
    {
        var r = Rights;
        if (!r.CanView && !r.AnyApproval) return Forbid();
        return PartialView("~/Views/Leave/_Kpis.cshtml", await _leave.SummaryAsync(Scope(), null, Ct));
    }

    [HttpGet("requests-grid")]
    public async Task<IActionResult> RequestsGrid(string? status, int? type, long? emp, DateTime? from, DateTime? to, string? search, int page = 1)
    {
        var r = Rights;
        if (!r.CanView && !r.AnyApproval) return Forbid();
        // approvers without the list right see only what waits for them
        if (!r.CanView) status = "MINE";
        var result = await _leave.ListAsync(new LeaveRequestFilter
        {
            Status = status, LeaveTypeId = type, EmployeeId = emp, FromDate = from, ToDate = to, Search = search,
            PageNumber = page, PageSize = 25
        }, Scope(), Ct);
        return PartialView("~/Views/Leave/_RequestsGrid.cshtml", new LeaveRequestsGridModel
        {
            Page = result, Rights = r, Mode = "hr", ManyCompanies = ManyCompanies,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || type is not null || emp is not null || from is not null || to is not null
        });
    }

    [HttpGet("export")]
    public async Task<IActionResult> Export(string? status, int? type, long? emp, DateTime? from, DateTime? to, string? search)
    {
        if (!Can(PermView)) return Forbid();
        var L = _text;
        var result = await _leave.ListAsync(new LeaveRequestFilter
        {
            Status = status, LeaveTypeId = type, EmployeeId = emp, FromDate = from, ToDate = to, Search = search, PageSize = 1000
        }, Scope(), Ct);
        string[] headers =
        [
            L.Tr("Request No"), L.Tr("Employee No"), L.Tr("Employee"), L.Tr("Company"), L.Tr("Department"), L.Tr("Leave type"),
            L.Tr("From"), L.Tr("To"), L.Tr("Days"), L.Tr("Status"), L.Tr("Returned on"), L.Tr("Reason")
        ];
        var rows = result.Items.Select(i => (IReadOnlyList<object?>)new object?[]
        {
            i.RequestNo, i.EmployeeNo, LeaveFormat.Name(L, i.EmployeeName, i.EmployeeArabicName), i.CompanyName, i.DepartmentName,
            LeaveFormat.Name(L, i.TypeName, i.TypeArabicName), i.StartDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            i.LastDay.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), i.Days, LeaveFormat.StatusLabel(L, i),
            i.ActualReturnDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), i.Reason
        });
        var bytes = XlsxFile.Write(L.Tr("Leave requests"), headers, rows, [14, 14, 26, 20, 18, 20, 12, 12, 8, 18, 12, 40], rightToLeft: L.IsArabic);
        return File(bytes, XlsxFile.ContentType, $"leave-requests-{DateTime.Today:yyyyMMdd}.xlsx");
    }

    // =======================================================================
    // One request: form, preview, save, detail, decisions
    // =======================================================================

    /// <summary>The request popup. mode=my: the user's own leave; hr: any employee in scope (LEAVE_MANAGE).</summary>
    [HttpGet("form")]
    public async Task<IActionResult> Form(long id = 0, string? mode = null, long? emp = null)
    {
        var r = Rights;
        var asHr = mode != "my" && r.CanManage;
        if (!asHr && _currentUser.EmployeeId is null) return Forbid();

        LeaveRequest? request = null;
        if (id > 0)
        {
            request = await _leave.GetAsync(id, Ct);
            if (request is null || !r.CanEdit(request) || !CanSee(request, r)) return NotFound();
            if (!asHr && request.EmployeeId != _currentUser.EmployeeId) return NotFound();
        }

        var employeeId = request?.EmployeeId ?? (asHr ? emp : _currentUser.EmployeeId);
        return PartialView("~/Views/Leave/_RequestForm.cshtml", new LeaveRequestFormModel
        {
            Request = request,
            Rights = r,
            Mode = asHr ? "hr" : "my",
            Employees = asHr ? await _leave.EmployeesAsync(Scope(), Ct) : Array.Empty<LeaveEmployeeOption>(),
            EmployeeId = employeeId,
            Types = employeeId is { } e ? await _leave.TypesForAsync(e, null, Ct) : Array.Empty<LeaveTypeOption>(),
            MaxFileBytes = _storage.MaxFileSizeBytes
        });
    }

    /// <summary>The leave types of an employee, with their balance (the form, after the employee is picked).</summary>
    [HttpGet("types-for")]
    public async Task<IActionResult> TypesFor(long emp)
    {
        if (!await MayActForAsync(emp)) return Forbid();
        var L = _text;
        var types = await _leave.TypesForAsync(emp, null, Ct);
        return Json(types.Select(t => new
        {
            id = t.LeaveTypeId,
            name = LeaveFormat.Name(L, t.TypeName, t.ArabicName),
            half = t.AllowHalfDay,
            doc = t.RequiresDocument,
            unlimited = t.BalanceMode == LeaveBalanceMode.Unlimited,
            available = t.Available - (t.Pending ?? 0),
            color = LeaveFormat.Swatch(t.Color)
        }));
    }

    [HttpPost("preview")]
    public async Task<IActionResult> Preview(LeaveRequestInput input, string? mode)
    {
        var asHr = mode != "my" && Rights.CanManage;
        if (!asHr) input.EmployeeId = _currentUser.EmployeeId;
        if (input.EmployeeId is null || input.LeaveTypeId is null || input.StartDate is null || input.EndDate is null)
        {
            return Json(new { ready = false });
        }
        var (preview, error) = await _leave.PreviewAsync(input, Scope(asHr), Ct);
        if (error is not null) return Json(new { ready = true, ok = false, problems = new[] { _text.Tr(error.Message) } });
        var problems = (preview?.Problems ?? string.Empty).Split('|', StringSplitOptions.RemoveEmptyEntries).Select(m => _text.Tr(m)).ToArray();
        return Json(new
        {
            ready = true,
            ok = problems.Length == 0,
            days = preview?.Days,
            daysText = LeaveFormat.DaysText(_text, preview?.Days ?? 0),
            available = preview?.Available is { } a ? a - (preview.Pending ?? 0) : (decimal?)null,
            after = preview?.After,
            // db/86: the days over the balance are unpaid; the suggested day back at work
            paidDays = preview?.PaidDays,
            unpaidDays = preview?.UnpaidDays ?? 0,
            resumeDate = preview?.ResumeDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            problems
        });
    }

    [HttpPost("save")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> Save(LeaveRequestInput input, string? mode, IFormFile? document)
    {
        var r = Rights;
        var asHr = mode != "my" && r.CanManage;
        if (!asHr)
        {
            if (_currentUser.EmployeeId is null) return Denied();
            input.EmployeeId = _currentUser.EmployeeId;
            input.ApproveNow = false;
        }
        if (input.EmployeeId is null) return Json(ActionResponse.Failed("Choose the employee.", "VALIDATION"));

        // a leave type that needs a document (e.g. a medical certificate): the employee attaches it; HR may add it later
        LeaveRequest? existing = input.LeaveRequestId > 0 ? await _leave.GetAsync(input.LeaveRequestId, Ct) : null;
        var types = await _leave.TypesForAsync(input.EmployeeId.Value, null, Ct);
        var type = types.FirstOrDefault(t => t.LeaveTypeId == input.LeaveTypeId);
        if (type is { RequiresDocument: true } && document is null && existing?.HasDocument != true && !asHr)
        {
            return Json(ActionResponse.Invalid(new Dictionary<string, string[]> { ["document"] = [_text.Tr("Attach the supporting document (PDF, JPG or PNG).")] }));
        }

        LeaveDocument? stored = null;
        if (document is { Length: > 0 })
        {
            var (doc, error) = await _storage.SaveAsync(input.EmployeeId.Value, document, Ct);
            if (doc is null) return Json(ActionResponse.Invalid(new Dictionary<string, string[]> { ["document"] = [_text.Tr(error ?? "The file could not be saved.")] }));
            stored = new LeaveDocument(doc.RelativePath, doc.OriginalFileName, doc.ContentType, doc.SizeBytes);
        }

        var result = await _leave.SaveAsync(input, stored, Scope(asHr), Ct);
        return Result(result);
    }

    [HttpGet("detail")]
    public async Task<IActionResult> Detail(long id)
    {
        var r = Rights;
        var request = await _leave.GetAsync(id, Ct);
        if (request is null || !CanSee(request, r)) return NotFound();
        var balances = await _leave.EmployeeBalancesAsync(request.EmployeeId, request.StartDate, null, Ct);

        return PartialView("~/Views/Leave/_RequestDetail.cshtml", new LeaveRequestDetailModel
        {
            Request = request,
            Rights = r,
            History = await _leave.HistoryAsync(id, Ct),
            Balance = balances.FirstOrDefault(b => b.LeaveTypeId == request.LeaveTypeId)
        });
    }

    [HttpGet("document")]
    public async Task<IActionResult> Document(long id, bool download = false)
    {
        var request = await _leave.GetAsync(id, Ct);
        if (request is null || request.DocumentPath is null || !CanSee(request, Rights)) return NotFound();
        var path = _storage.Resolve(request.DocumentPath);
        if (path is null) return NotFound();
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return download
            ? PhysicalFile(path, request.DocumentType ?? "application/octet-stream", request.DocumentName ?? "document")
            : PhysicalFile(path, request.DocumentType ?? "application/octet-stream");
    }

    [HttpPost("approve")]
    public async Task<IActionResult> Approve(long id, string? comment, int? level) =>
        Result(await _leave.DecideAsync("APPROVE", id, comment, level, Scope(), Ct));

    [HttpPost("reject")]
    public async Task<IActionResult> Reject(long id, string? comment, int? level) =>
        Result(await _leave.DecideAsync("REJECT", id, comment, level, Scope(), Ct));

    [HttpPost("cancel")]
    public async Task<IActionResult> Cancel(long id, string? comment) =>
        Result(await _leave.CancelAsync(id, comment, Scope(), Ct));

    [HttpPost("return")]
    public async Task<IActionResult> Return(long id, DateTime? returnDate, string? comment)
    {
        if (!Can(PermManage)) return Denied();
        return Result(await _leave.ReturnAsync(id, returnDate, comment, Scope(), Ct));
    }

    /// <summary>db/86: the leave salary settlement popup (row menu) - with the monthly payroll or in cash before the leave.</summary>
    [HttpGet("settlement")]
    public async Task<IActionResult> Settlement(long id)
    {
        var r = Rights;
        if (!r.CanSettle) return Forbid();
        var request = await _leave.GetAsync(id, Ct);
        if (request is null || !CanSee(request, r) || !r.CanSettleRequest(request)) return NotFound();
        var figures = await _leave.SettlementAsync(id, SettleScope(), Ct);
        if (figures is null) return NotFound();
        return PartialView("~/Views/Leave/_SettlementForm.cshtml", new LeaveSettlementModel
        {
            Request = request,
            Settlement = figures,
            Items = await _leave.PayItemsAsync(id, SettleScope(), Ct)
        });
    }

    [HttpPost("settle")]
    public async Task<IActionResult> Settle(LeaveSettlementInput input)
    {
        if (!Can(PermSettle)) return Denied();
        return Result(await _leave.SettleAsync(input, SettleScope(), Ct));
    }

    // =======================================================================
    // Balances
    // =======================================================================

    [HttpGet("balances")]
    public async Task<IActionResult> Balances()
    {
        var r = Rights;
        if (!r.CanView) return Forbid();
        return View("~/Views/Leave/Balances.cshtml", new LeaveBalancesPageModel
        {
            Rights = r,
            Types = await _leave.TypesAsync(Scope(), null, Ct),
            Employees = await _leave.EmployeesAsync(Scope(), Ct)
        });
    }

    [HttpGet("balances-grid")]
    public async Task<IActionResult> BalancesGrid(string? category, int? type, long? emp, string? search, DateTime? asOf, int page = 1)
    {
        var r = Rights;
        if (!r.CanView) return Forbid();
        var date = asOf ?? DateTime.Today;
        var result = await _leave.BalancesAsync(new LeaveBalanceFilter
        {
            AsOf = date, Category = string.IsNullOrEmpty(category) ? null : category, LeaveTypeId = type, EmployeeId = emp,
            Search = search, PageNumber = page, PageSize = 25
        }, Scope(), Ct);
        return PartialView("~/Views/Leave/_BalancesGrid.cshtml", new LeaveBalancesGridModel
        {
            Page = result, Rights = r, AsOf = date,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || type is not null || emp is not null
        });
    }

    [HttpGet("balances-export")]
    public async Task<IActionResult> BalancesExport(string? category, int? type, long? emp, string? search, DateTime? asOf)
    {
        if (!Can(PermView)) return Forbid();
        var L = _text;
        var date = asOf ?? DateTime.Today;
        var result = await _leave.BalancesAsync(new LeaveBalanceFilter
        {
            AsOf = date, Category = string.IsNullOrEmpty(category) ? null : category, LeaveTypeId = type, EmployeeId = emp, Search = search, PageSize = 5000
        }, Scope(), Ct);
        string[] headers =
        [
            L.Tr("Employee No"), L.Tr("Employee"), L.Tr("Company"), L.Tr("Department"), L.Tr("Leave type"),
            L.Tr("Opening"), L.Tr("Earned"), L.Tr("Adjusted"), L.Tr("Entitled"), L.Tr("Taken"), L.Tr("Pending"), L.Tr("Available")
        ];
        var rows = result.Items.Select(b => (IReadOnlyList<object?>)new object?[]
        {
            b.EmployeeNo, LeaveFormat.Name(L, b.EmployeeName, b.EmployeeArabicName), b.CompanyName, b.DepartmentName,
            LeaveFormat.Name(L, b.TypeName, b.TypeArabicName), b.OpeningDays, b.Earned, b.Adjusted, b.Entitled, b.Taken, b.Pending, b.Available
        });
        var bytes = XlsxFile.Write(L.Tr("Leave balances"), headers, rows, [14, 26, 20, 18, 20, 10, 10, 10, 10, 10, 10, 10], rightToLeft: L.IsArabic);
        return File(bytes, XlsxFile.ContentType, $"leave-balances-{date:yyyyMMdd}.xlsx");
    }

    [HttpGet("ledger")]
    public async Task<IActionResult> Ledger(long emp, int type, string? category = null)
    {
        var r = Rights;
        var self = emp == _currentUser.EmployeeId;
        if (!r.CanView && !self) return Forbid();
        var scope = self && !r.CanView ? null : Scope();
        var balances = await _leave.EmployeeBalancesAsync(emp, DateTime.Today, scope, Ct);
        // type 0 + category: the employee's leave of that category (the Employees list opens ANNUAL)
        var balance = type > 0
            ? balances.FirstOrDefault(b => b.LeaveTypeId == type)
            : balances.FirstOrDefault(b => string.Equals(b.Category, category, StringComparison.OrdinalIgnoreCase));
        if (balance is null) return NotFound();
        var left = (balance.Available ?? 0) - balance.Pending;
        return PartialView("~/Views/Leave/_Ledger.cshtml", new LeaveLedgerModel
        {
            Balance = balance,
            Lines = await _leave.LedgerAsync(emp, balance.LeaveTypeId, scope, Ct),
            CanAdjust = r.CanAdjust && !self,
            // db/98: a large annual balance - over 60 days, down to 30 at the least
            EliminateMax = r.CanEliminate && !self && balance.Category == "ANNUAL" && balance.Available is not null
                ? LeaveElimination.MaxDays(left) : 0m
        });
    }

    [HttpPost("adjust")]
    public async Task<IActionResult> Adjust(long emp, int type, string? entryType, DateTime? entryDate, decimal? days, string? comment)
    {
        if (!Can(PermAdjust)) return Denied();
        if (emp == _currentUser.EmployeeId && !IsSysAdmin) return Json(ActionResponse.Failed("You cannot adjust your own balance.", "FORBIDDEN"));
        return Result(await _leave.AdjustAsync(emp, type, entryType == "OPENING" ? "OPENING" : "ADJUST", entryDate, days, comment, Scope(), Ct));
    }

    /// <summary>db/98: forces days off an annual balance over 60 days (30 always remain), with remarks.</summary>
    [HttpPost("eliminate")]
    public async Task<IActionResult> Eliminate(long emp, int type, decimal? days, string? remarks)
    {
        if (!Can(PermEliminate)) return Denied();
        if (emp == _currentUser.EmployeeId && !IsSysAdmin) return Json(ActionResponse.Failed("You cannot eliminate your own leave.", "FORBIDDEN"));
        return Result(await _leave.EliminateAsync(emp, type, days, remarks, Scope(), Ct));
    }

    [HttpPost("delete-entry")]
    public async Task<IActionResult> DeleteEntry(long id)
    {
        if (!Can(PermAdjust)) return Denied();
        return Result(await _leave.DeleteEntryAsync(id, Scope(), Ct));
    }

    /// <summary>The Leave tab of the employee profile: balances and the latest requests.</summary>
    [HttpGet("employee-panel")]
    public async Task<IActionResult> EmployeePanel(long emp)
    {
        var r = Rights;
        var self = emp == _currentUser.EmployeeId;
        if (!r.CanView && !self) return Forbid();
        var scope = self && !r.CanView ? null : Scope();
        var requests = await _leave.ListAsync(new LeaveRequestFilter
        {
            EmployeeId = emp, Status = "ALL", PageSize = 10, SelfEmployeeId = scope is null ? emp : null
        }, scope ?? Scope(false), Ct);
        return PartialView("~/Views/Leave/_EmployeePanel.cshtml", new LeaveEmployeePanelModel
        {
            EmployeeId = emp,
            Balances = await _leave.EmployeeBalancesAsync(emp, DateTime.Today, scope, Ct),
            Requests = requests.Items,
            CanOpenLeave = r.CanView
        });
    }

    // =======================================================================
    // My Leave (self-service)
    // =======================================================================

    [HttpGet("my")]
    public async Task<IActionResult> My()
    {
        var r = Rights;
        var model = new LeaveMyPageModel { Rights = r, HasEmployee = _currentUser.EmployeeId is not null };
        if (_currentUser.EmployeeId is { } emp)
        {
            var team = await _leave.ListAsync(new LeaveRequestFilter { TeamOnly = true, Status = "MINE", PageSize = 1 }, Scope(false), Ct);
            model = new LeaveMyPageModel
            {
                Rights = r,
                HasEmployee = true,
                Balances = await _leave.EmployeeBalancesAsync(emp, DateTime.Today, null, Ct),
                TeamPending = team.TotalCount
            };
        }
        return View("~/Views/Leave/My.cshtml", model);
    }

    [HttpGet("my-grid")]
    public async Task<IActionResult> MyGrid(string? status, int page = 1)
    {
        if (_currentUser.EmployeeId is not { } emp) return Forbid();
        var result = await _leave.ListAsync(new LeaveRequestFilter
        {
            SelfEmployeeId = emp, Status = string.IsNullOrEmpty(status) ? "ALL" : status, PageNumber = page, PageSize = 15
        }, Scope(false), Ct);
        return PartialView("~/Views/Leave/_RequestsGrid.cshtml", new LeaveRequestsGridModel { Page = result, Rights = Rights, Mode = "my" });
    }

    /// <summary>Requests of the user's team (they are the reporting manager) - waiting for them, or all.</summary>
    [HttpGet("team-grid")]
    public async Task<IActionResult> TeamGrid(string? status, int page = 1)
    {
        if (_currentUser.EmployeeId is null) return Forbid();
        var result = await _leave.ListAsync(new LeaveRequestFilter
        {
            TeamOnly = true, Status = string.IsNullOrEmpty(status) ? "MINE" : status, PageNumber = page, PageSize = 15
        }, Scope(false), Ct);
        return PartialView("~/Views/Leave/_RequestsGrid.cshtml", new LeaveRequestsGridModel { Page = result, Rights = Rights, Mode = "team" });
    }

    // =======================================================================
    // Settings
    // =======================================================================

    [HttpGet("settings")]
    public async Task<IActionResult> Settings()
    {
        var r = Rights;
        if (!r.CanSetupView) return Forbid();
        return View("~/Views/Leave/Settings.cshtml", new LeaveSettingsPageModel
        {
            Rights = r,
            Companies = await _leave.SettingsAsync(Scope(), Ct),
            AllCompaniesUser = _currentUser.ActiveCompanyId is null
        });
    }

    [HttpGet("settings/types-grid")]
    public async Task<IActionResult> TypesGrid()
    {
        if (!Rights.CanSetupView) return Forbid();
        var types = await _leave.TypesAsync(Scope(), null, Ct);
        return PartialView("~/Views/Leave/_TypesGrid.cshtml", new LeaveTypesGridModel
        {
            Types = types, CanEdit = Rights.CanSetupEdit, ManyCompanies = types.Select(t => t.CompanyId).Distinct().Count() > 1
        });
    }

    [HttpGet("settings/type-form")]
    public async Task<IActionResult> TypeForm(int id = 0)
    {
        if (!Rights.CanSetupEdit) return Forbid();
        LeaveTypeSetting? type = null;
        if (id > 0)
        {
            type = (await _leave.TypesAsync(Scope(), null, Ct)).FirstOrDefault(t => t.LeaveTypeId == id);
            if (type is null) return NotFound();
        }
        return PartialView("~/Views/Leave/_TypeForm.cshtml", new LeaveTypeFormModel
        {
            Type = type, Companies = await _leave.SettingsAsync(Scope(), Ct)
        });
    }

    [HttpPost("settings/type-save")]
    public async Task<IActionResult> TypeSave(LeaveTypeInput input)
    {
        if (!Can(PermSetupEdit)) return Denied();
        return Result(await _leave.SaveTypeAsync(input, Scope(), Ct));
    }

    [HttpPost("settings/type-toggle")]
    public async Task<IActionResult> TypeToggle(int id)
    {
        if (!Can(PermSetupEdit)) return Denied();
        return Result(await _leave.TypeActionAsync("TYPE_TOGGLE", id, Scope(), Ct));
    }

    [HttpPost("settings/type-delete")]
    public async Task<IActionResult> TypeDelete(int id)
    {
        if (!Can(PermSetupEdit)) return Denied();
        return Result(await _leave.TypeActionAsync("TYPE_DELETE", id, Scope(), Ct));
    }

    [HttpGet("settings/holidays-grid")]
    public async Task<IActionResult> HolidaysGrid(int? year)
    {
        if (!Rights.CanSetupView) return Forbid();
        var y = year is >= 2000 and <= 2100 ? year.Value : DateTime.Today.Year;
        return PartialView("~/Views/Leave/_HolidaysGrid.cshtml", new LeaveHolidaysGridModel
        {
            Holidays = await _leave.HolidaysAsync(y, Scope(), Ct), CanEdit = Rights.CanSetupEdit, Year = y
        });
    }

    [HttpGet("settings/holiday-form")]
    public async Task<IActionResult> HolidayForm(int id = 0, int? year = null)
    {
        if (!Rights.CanSetupEdit) return Forbid();
        LeaveHoliday? holiday = null;
        if (id > 0)
        {
            holiday = (await _leave.HolidaysAsync(year ?? DateTime.Today.Year, Scope(), Ct)).FirstOrDefault(h => h.HolidayId == id);
            if (holiday is null) return NotFound();
        }
        return PartialView("~/Views/Leave/_HolidayForm.cshtml", new LeaveHolidayFormModel
        {
            Holiday = holiday, Companies = await _leave.SettingsAsync(Scope(), Ct), AllCompaniesUser = _currentUser.ActiveCompanyId is null
        });
    }

    [HttpPost("settings/holiday-save")]
    public async Task<IActionResult> HolidaySave(LeaveHolidayInput input)
    {
        if (!Can(PermSetupEdit)) return Denied();
        return Result(await _leave.SaveHolidayAsync(input, Scope(), Ct));
    }

    [HttpPost("settings/holiday-delete")]
    public async Task<IActionResult> HolidayDelete(int id)
    {
        if (!Can(PermSetupEdit)) return Denied();
        return Result(await _leave.DeleteHolidayAsync(id, Scope(), Ct));
    }

    /// <summary>Weekend days and the line manager step of one company.</summary>
    [HttpPost("settings/company")]
    public async Task<IActionResult> CompanySave(int companyId, int[]? weekend, bool managerApproval)
    {
        if (!Can(PermSetupEdit)) return Denied();
        var days = (weekend ?? []).Where(d => d is >= 1 and <= 7).Distinct().OrderBy(d => d);
        return Result(await _leave.SaveSettingsAsync(companyId, string.Join(",", days), managerApproval, Scope(), Ct));
    }

    // =======================================================================
    // Helpers
    // =======================================================================

    /// <summary>
    /// The user may open the request: their own; HR / approvers in their companies; the
    /// employee's line manager (or whoever the manager step waits for).
    /// </summary>
    private bool CanSee(LeaveRequest request, LeaveRights r)
    {
        if (request.EmployeeId == _currentUser.EmployeeId) return true;
        if (request.ManagerUserId == _currentUser.UserId && _currentUser.UserId is not null) return true;
        if (request.ReportingManagerId is { } m && m == _currentUser.EmployeeId) return true;
        if (!r.CanView && !r.AnyApproval) return false;
        return _currentUser.Allows(request.CompanyId)
               && (_companyFilter.SelectedIds.Count == 0 || _companyFilter.SelectedIds.Contains(request.CompanyId));
    }

    /// <summary>The form may be filled for this employee: the user's own, or any in scope for HR.</summary>
    private async Task<bool> MayActForAsync(long employeeId)
    {
        if (employeeId == _currentUser.EmployeeId) return true;
        if (!Can(PermManage)) return false;
        var employees = await _leave.EmployeesAsync(Scope(), Ct);
        return employees.Any(e => e.EmployeeId == employeeId);
    }

    private IActionResult Result(SaveResult result) =>
        Json(result.Success ? ActionResponse.Ok(result.Id, _text.Tr(result.Message)) : ActionResponse.Failed(_text.Tr(result.Message), result.ErrorCode));

    private IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
}
