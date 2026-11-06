using System.Globalization;
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
/// Payroll Components &gt; Collection (db/115). When an employee's Gross Monthly (Basic Salary +
/// Allowances) is below their Work Permit Salary, generating the payroll pays the difference as
/// "Work Permit Collection" and records it here as a receivable. The page picks a company and a
/// payroll month and shows Total / Pending / Collected, the pending ones first; "Mark as received"
/// records the date, a receipt reference and a comment (Payroll.CollectionHistory keeps the audit).
/// Rights: PAYROLL_COLL_VIEW to see, PAYROLL_COLL_EDIT to mark as received or set back.
/// </summary>
[Route("payroll/components/collection")]
public sealed class CollectionsController : Controller
{
    public const string PermView = "PAYROLL_COLL_VIEW";
    public const string PermEdit = "PAYROLL_COLL_EDIT";

    private readonly ICollectionRepository _collections;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _text;

    public CollectionsController(ICollectionRepository collections, ICurrentUser currentUser, ICompanyFilter companyFilter, IUiText text)
    {
        _collections = collections;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _text = text;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private bool CanView => _currentUser.HasPermission(PermView);
    private bool CanEdit => CanView && _currentUser.HasPermission(PermEdit);

    /// <summary>The companies the user may pick: their own company, else those selected on top (none = all).</summary>
    private async Task<IReadOnlyList<LookupItem>> CompaniesAsync()
    {
        var all = await _companyFilter.GetCompaniesAsync(Ct);
        if (_currentUser.ActiveCompanyId is { } own) return all.Where(c => c.Id == own).ToList();
        var selected = _companyFilter.SelectedIds;
        return selected.Count > 0 ? all.Where(c => selected.Contains(c.Id)).ToList() : all;
    }

    /// <summary>The companies the procedure may touch (CSV) - the user's own, else the top-bar selection (null = any).</summary>
    private string? Scope => _currentUser.ActiveCompanyId is { } own ? own.ToString(CultureInfo.InvariantCulture) : _companyFilter.Csv;

    private async Task<bool> MayOpenAsync(int companyId) => (await CompaniesAsync()).Any(c => c.Id == companyId);

    [HttpGet("")]
    public async Task<IActionResult> Index()
    {
        if (!CanView) return Forbid();
        var companies = await CompaniesAsync();
        var preferred = _currentUser.ActiveCompanyId ?? _companyFilter.SingleCompanyId;
        return View(new CollectionPageModel
        {
            Companies = companies,
            SelectedCompanyId = companies.Any(c => c.Id == preferred) ? preferred : companies.FirstOrDefault()?.Id,
            CanEdit = CanEdit
        });
    }

    /// <summary>The payroll months of a company (JSON for the month picker), newest first.</summary>
    [HttpGet("months")]
    public async Task<IActionResult> Months(int companyId)
    {
        if (!CanView || !await MayOpenAsync(companyId)) return Forbid();
        var months = await _collections.MonthsAsync(companyId, Scope, Ct);
        return Json(months.Select(m => new
        {
            value = m.RunMonth.ToString("yyyy-MM", CultureInfo.InvariantCulture),
            text = _text.MonthYear(m.RunMonth),
            pending = m.PendingAmount,
            count = m.CollectionCount
        }));
    }

    /// <summary>The key figures and the list of a company's payroll month.</summary>
    [HttpGet("grid")]
    public async Task<IActionResult> Grid(int companyId, string? month, string? status, string? search)
    {
        if (!CanView || !await MayOpenAsync(companyId)) return Forbid();
        if (!DateTime.TryParseExact(month, "yyyy-MM", CultureInfo.InvariantCulture, DateTimeStyles.None, out var m))
            return PartialView("_Grid", new CollectionGridModel { NoMonth = true, CanEdit = CanEdit });

        var summary = await _collections.SummaryAsync(companyId, Scope, m, Ct);
        var items = await _collections.ListAsync(companyId, Scope, m, status, search, Ct);
        return PartialView("_Grid", new CollectionGridModel
        {
            Month = m,
            Summary = summary,
            Items = items,
            Status = status is CollectionStatus.Pending or CollectionStatus.Collected ? status : null,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || status is CollectionStatus.Pending or CollectionStatus.Collected,
            CanEdit = CanEdit
        });
    }

    [HttpGet("history")]
    public async Task<IActionResult> History(long id)
    {
        if (!CanView) return Forbid();
        return PartialView("_History", await _collections.HistoryAsync(id, Scope, Ct));
    }

    /// <summary>Marks one or more pending collections as received.</summary>
    [HttpPost("collect")]
    public async Task<IActionResult> Collect(string? ids, string? collectedDate, string? reference, string? comment)
    {
        if (!CanEdit) return Denied();
        var list = (ids ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                                        .Select(s => long.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var v) ? v : 0)
                                        .Where(v => v > 0).Distinct().ToList();
        if (list.Count == 0) return Json(ActionResponse.Failed("Select the collections that were received.", "VALIDATION"));
        DateTime? date = null;
        if (!string.IsNullOrWhiteSpace(collectedDate))
        {
            if (!DateTime.TryParseExact(collectedDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
                return Json(ActionResponse.Failed("Enter the date it was received.", "VALIDATION"));
            date = d;
        }
        return Result(await _collections.CollectAsync(list, date, reference, comment, Scope, UserId, Ct));
    }

    /// <summary>Sets a received collection back to pending (a mistake), with the reason.</summary>
    [HttpPost("reopen")]
    public async Task<IActionResult> Reopen(long id, string? comment)
    {
        if (!CanEdit) return Denied();
        return Result(await _collections.ReopenAsync(id, comment, Scope, UserId, Ct));
    }

    private IActionResult Result(SaveResult result) =>
        Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));

    private IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
}
