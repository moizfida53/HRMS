using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll Settings: the masters the payroll engine reads - pay item types,
/// statutory rules, banks and accounts, and the rule screens. Every screen is
/// the same pattern: a list (grid partial loaded by wwwroot/js/payroll-settings.js)
/// and an add / edit dialog (form partial) that posts to a save action.
/// </summary>
[Route("payroll/settings")]
public sealed partial class PayrollSettingsController : Controller
{
    private const string PermView = "PAYROLL_SETUP_VIEW";
    private const string PermEdit = "PAYROLL_SETUP_EDIT";
    private const string PermCreate = "PAYROLL_SETUP_CREATE";
    private const string PermDelete = "PAYROLL_SETUP_DELETE";

    private readonly IPayItemTypeRepository _itemTypes;
    private readonly IStatutoryRepository _statutory;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;

    public PayrollSettingsController(IPayItemTypeRepository itemTypes, IStatutoryRepository statutory, ILookupRepository lookups,
                                     ICurrentUser currentUser, ICompanyFilter companyFilter)
    {
        _itemTypes = itemTypes;
        _statutory = statutory;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private int? OwnCompany => _currentUser.ActiveCompanyId;
    private string? CompanyCsv => _companyFilter.Csv;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool CanView => Can(PermView) || Can(PermEdit) || Can(PermCreate);
    private bool ManyCompanies => _companyFilter.SelectedIds.Count != 1 && OwnCompany is null;

    private SettingsRights Rights => new()
    {
        CanCreate = Can(PermCreate),
        CanEdit = Can(PermEdit),
        CanDelete = Can(PermDelete)
    };

    [HttpGet("")]
    public IActionResult Index() => RedirectToAction(nameof(ItemTypes));

    // =======================================================================
    // Pay Item Types (Payroll.PayComponents)
    // =======================================================================

    [HttpGet("item-types")]
    public IActionResult ItemTypes()
    {
        if (!CanView) return Forbid();
        return View("~/Views/PayrollSettings/ItemTypes.cshtml", new SettingsPageModel
        {
            Rights = Rights,
            SeedCompanyId = OwnCompany ?? _companyFilter.SingleCompanyId
        });
    }

    [HttpGet("item-types/grid")]
    public async Task<IActionResult> ItemTypesGrid(string? search, string? type, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _itemTypes.ListAsync(new PayItemTypeFilter
        {
            CompanyId = OwnCompany,
            CompanyIds = CompanyCsv,
            Search = search,
            ComponentType = type is "EARNING" or "DEDUCTION" ? type : null,
            IsActive = status switch { "active" => true, "inactive" => false, _ => null },
            PageNumber = Math.Max(1, page),
            PageSize = 50
        }, Ct);
        return PartialView("~/Views/PayrollSettings/_ItemTypesGrid.cshtml", new SettingsGridModel<PayItemTypeSetting>
        {
            Page = result,
            Rights = Rights,
            ManyCompanies = ManyCompanies,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(type) || !string.IsNullOrEmpty(status)
        });
    }

    [HttpGet("item-types/form")]
    public async Task<IActionResult> ItemTypeForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var item = id > 0
            ? await _itemTypes.GetAsync(id, Ct)
            : new PayItemTypeSetting { CompanyId = OwnCompany ?? _companyFilter.SingleCompanyId ?? 0 };
        if (item is null || !Owns(item.CompanyId, id > 0)) return NotFound();

        var companies = await CompaniesAsync(includeInactive: id > 0);
        var companyId = item.CompanyId > 0 ? item.CompanyId : companies.FirstOrDefault()?.Id;
        return PartialView("~/Views/PayrollSettings/_ItemTypeForm.cshtml", new ItemTypeFormModel
        {
            Item = item,
            Companies = companies,
            CostCenters = companyId is { } cid ? await _lookups.GetAsync(LookupType.CostCenter, cid, cancellationToken: Ct) : Array.Empty<LookupItem>()
        });
    }

    [HttpPost("item-types/save")]
    public async Task<IActionResult> ItemTypeSave()
    {
        var model = new PayItemTypeSetting();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.PayComponentId > 0 ? PermEdit : PermCreate)) return Denied();
        if (!Owns(model.CompanyId, false)) return Denied();
        if (model.PayComponentId > 0 && await _itemTypes.GetAsync(model.PayComponentId, Ct) is { } current && !Owns(current.CompanyId, true)) return Denied();
        return Result(await _itemTypes.SaveAsync(model, UserId, Ct));
    }

    [HttpPost("item-types/toggle")]
    public async Task<IActionResult> ItemTypeToggle(int id) =>
        Can(PermEdit) && await OwnsItemType(id) ? Result(await _itemTypes.ToggleAsync(id, UserId, Ct)) : Denied();

    [HttpPost("item-types/delete")]
    public async Task<IActionResult> ItemTypeDelete(int id) =>
        Can(PermDelete) && await OwnsItemType(id) ? Result(await _itemTypes.DeleteAsync(id, UserId, Ct)) : Denied();

    /// <summary>Adds the standard pay item types (Basic Salary, PIFSS, Loan, ...) the company is missing.</summary>
    [HttpPost("item-types/seed")]
    public async Task<IActionResult> ItemTypeSeed(int companyId) =>
        Can(PermCreate) && companyId > 0 && Owns(companyId, false) ? Result(await _itemTypes.SeedAsync(companyId, UserId, Ct)) : Denied();

    /// <summary>The cost centers of a company (the form reloads them when the company changes).</summary>
    [HttpGet("cost-centers")]
    public async Task<IActionResult> CostCenters(int companyId)
    {
        if (!CanView || !Owns(companyId, false)) return Forbid();
        var list = await _lookups.GetAsync(LookupType.CostCenter, companyId, cancellationToken: Ct);
        return Json(list.Select(c => new { id = c.Id, text = c.Text }));
    }

    private async Task<bool> OwnsItemType(int id) =>
        await _itemTypes.GetAsync(id, Ct) is { } item && Owns(item.CompanyId, true);

    // =======================================================================
    // Helpers
    // =======================================================================

    /// <summary>
    /// The company is one the user may work in: their own company, or one of the
    /// companies selected on top (<paramref name="existing"/>: also any company when
    /// nothing is selected - an existing record is then shown, as in the lists).
    /// </summary>
    private bool Owns(int companyId, bool existing)
    {
        if (OwnCompany is { } own) return companyId == own;
        var selected = _companyFilter.SelectedIds;
        return selected.Count == 0 ? (existing || companyId > 0) : selected.Contains(companyId);
    }

    private async Task<IReadOnlyList<LookupItem>> CompaniesAsync(bool includeInactive)
    {
        var companies = await _lookups.GetAsync(LookupType.Company, includeInactive: includeInactive, cancellationToken: Ct);
        if (OwnCompany is { } own) return companies.Where(c => c.Id == own).ToList();
        var selected = _companyFilter.SelectedIds;
        return selected.Count > 0 ? companies.Where(c => selected.Contains(c.Id)).ToList() : companies;
    }

    private IActionResult Result(SaveResult result)
    {
        if (result.Success)
        {
            HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
        }
        return Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    private IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));

    private Dictionary<string, string[]> CollectErrors() =>
        ModelState.Where(entry => entry.Value?.Errors.Count > 0)
                  .ToDictionary(entry => entry.Key, entry => entry.Value!.Errors.Select(e => e.ErrorMessage).ToArray());
}
