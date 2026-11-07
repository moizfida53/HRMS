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
    private readonly IBankRepository _banks;
    private readonly IPayrollRulesRepository _rules;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;

    public PayrollSettingsController(IPayItemTypeRepository itemTypes, IStatutoryRepository statutory, IBankRepository banks,
                                     IPayrollRulesRepository rules, ILookupRepository lookups, ICurrentUser currentUser, ICompanyFilter companyFilter)
    {
        _banks = banks;
        _rules = rules;
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
            // "Add standard types" works on every company the user works in
            SeedCompanyId = OwnCompany ?? _companyFilter.SingleCompanyId ?? 0
        });
    }

    /// <summary>
    /// Every pay item type row in the user's scope, grouped by code: one line per pay item type
    /// with the companies it is created for.
    /// </summary>
    private async Task<List<ItemTypeGroup>> ItemTypeGroupsAsync()
    {
        var rows = new List<PayItemTypeSetting>();
        for (var page = 1; ; page++)
        {
            var batch = await _itemTypes.ListAsync(new PayItemTypeFilter
            {
                CompanyId = OwnCompany, CompanyIds = CompanyCsv, PageNumber = page, PageSize = 200
            }, Ct);
            rows.AddRange(batch.Items);
            if (batch.Items.Count < 200 || rows.Count >= batch.TotalCount || page >= 50) break;
        }

        var scope = (await CompaniesAsync(includeInactive: false)).Select(c => c.Id).ToHashSet();
        var preferred = OwnCompany ?? _companyFilter.SingleCompanyId;
        return rows
            .GroupBy(r => r.ComponentCode.Trim().ToUpperInvariant())
            .Select(g =>
            {
                var list = g.OrderBy(r => r.CompanyName, StringComparer.CurrentCultureIgnoreCase).ToList();
                var shown = list.FirstOrDefault(r => r.CompanyId == preferred) ?? list.FirstOrDefault(r => r.IsActive) ?? list[0];
                return new ItemTypeGroup
                {
                    Item = shown,
                    Rows = list,
                    AllCompanies = scope.Count > 1 && scope.All(id => list.Any(r => r.CompanyId == id))
                };
            })
            .OrderBy(g => g.Item.DisplayOrder).ThenBy(g => g.Item.ComponentCode, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>The group of the pay item type a row id names (null when it is out of the user's scope).</summary>
    private async Task<ItemTypeGroup?> ItemTypeGroupAsync(int id)
    {
        if (id <= 0) return null;
        var groups = await ItemTypeGroupsAsync();
        return groups.FirstOrDefault(g => g.Rows.Any(r => r.PayComponentId == id));
    }

    [HttpGet("item-types/grid")]
    public async Task<IActionResult> ItemTypesGrid(string? search, string? type, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        // grouped by code first (one line per pay item type, with its companies), then filtered and paged
        var q = string.IsNullOrWhiteSpace(search) ? null : search.Trim();
        var componentType = ComponentTypes.IsValid(type) ? type : null;
        var groups = (await ItemTypeGroupsAsync())
            .Where(g => componentType is null || g.Item.ComponentType == componentType)
            .Where(g => status switch { "active" => g.AnyActive, "inactive" => !g.AnyActive, _ => true })
            .Where(g => q is null
                        || g.Item.ComponentCode.Contains(q, StringComparison.OrdinalIgnoreCase)
                        || g.Rows.Any(r => r.ComponentName.Contains(q, StringComparison.OrdinalIgnoreCase)
                                           || (r.ArabicName?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false)
                                           || (r.CompanyName?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false)))
            .ToList();
        const int size = 50;
        var number = Math.Max(1, Math.Min(page, Math.Max(1, (int)Math.Ceiling(groups.Count / (double)size))));
        var result = new PagedResult<ItemTypeGroup>
        {
            Items = groups.Skip((number - 1) * size).Take(size).ToList(), TotalCount = groups.Count, PageNumber = number, PageSize = size
        };
        return PartialView("~/Views/PayrollSettings/_ItemTypesGrid.cshtml", new SettingsGridModel<ItemTypeGroup>
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
        // An existing pay item type is edited for every company it is created for (its group); a new one
        // starts ticked for every company the user works in - it is created once per company ticked.
        var group = id > 0 ? await ItemTypeGroupAsync(id) : null;
        if (id > 0 && group is null) return NotFound();
        var item = group?.Rows.FirstOrDefault(r => r.PayComponentId == id) ?? group?.Item
                   ?? new PayItemTypeSetting { CompanyId = OwnCompany ?? _companyFilter.SingleCompanyId ?? 0 };

        var companies = (await CompaniesAsync(includeInactive: id > 0)).ToList();
        // a company that has it but is no longer active is still listed (ticked)
        foreach (var r in group?.Rows ?? [])
        {
            if (companies.All(c => c.Id != r.CompanyId)) companies.Add(new LookupItem { Id = r.CompanyId, Text = r.CompanyName ?? r.CompanyId.ToString(System.Globalization.CultureInfo.InvariantCulture) });
        }
        var selected = group is not null ? group.Rows.Select(r => r.CompanyId).ToList() : companies.Select(c => c.Id).ToList();
        // cost centers belong to one company: offered when it is created for one company only
        var costCompany = selected.Count == 1 ? selected[0] : (int?)null;
        return PartialView("~/Views/PayrollSettings/_ItemTypeForm.cshtml", new ItemTypeFormModel
        {
            Item = item,
            Companies = companies,
            SelectedCompanyIds = selected,
            FixedCompanyIds = item.IsStandard && group is not null ? group.Rows.Select(r => r.CompanyId).ToList() : [],
            CostCenters = costCompany is { } cid ? await _lookups.GetAsync(LookupType.CostCenter, cid, cancellationToken: Ct) : Array.Empty<LookupItem>()
        });
    }

    [HttpPost("item-types/save")]
    public async Task<IActionResult> ItemTypeSave()
    {
        var model = new PayItemTypeSetting();
        // the companies come as CompanyIds (one per ticked company); CompanyId is not posted any more
        await TryUpdateModelAsync(model);
        ModelState.Remove(nameof(PayItemTypeSetting.CompanyId));
        if (!ModelState.IsValid) return Json(ActionResponse.Invalid(CollectErrors()));
        var editing = model.PayComponentId > 0;
        if (!Can(editing ? PermEdit : PermCreate)) return Denied();

        var picked = Request.Form["CompanyIds"]
            .SelectMany(v => (v ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            .Select(v => int.TryParse(v, out var n) ? n : 0).Where(n => n > 0).Distinct().ToList();
        if (picked.Count == 0)
            return Json(ActionResponse.Invalid(new Dictionary<string, string[]> { ["CompanyIds"] = ["Select the companies it is created for."] }));

        var group = editing ? await ItemTypeGroupAsync(model.PayComponentId) : null;
        if (editing && group is null) return Denied();
        var existing = group?.Rows ?? [];
        // a company it already has stays editable; a new company must be one the user works in
        if (picked.Any(c => existing.All(r => r.CompanyId != c) && !Owns(c, false))) return Denied();
        if (editing && !Can(PermCreate) && picked.Any(c => existing.All(r => r.CompanyId != c))) return Denied();

        var names = (await CompaniesAsync(includeInactive: true)).ToDictionary(c => c.Id, c => c.Text);
        string Name(int companyId) => names.TryGetValue(companyId, out var n) ? n : companyId.ToString(System.Globalization.CultureInfo.InvariantCulture);
        var failures = new List<string>();
        var done = 0;
        long lastId = model.PayComponentId;

        foreach (var companyId in picked)
        {
            var row = existing.FirstOrDefault(r => r.CompanyId == companyId);
            var copy = CopyItemType(model);
            copy.CompanyId = companyId;
            copy.PayComponentId = row?.PayComponentId ?? 0;
            if (row is not null && row.IsStandard)
            {
                // a standard type keeps its code and type in every company
                copy.ComponentCode = row.ComponentCode;
                copy.ComponentType = row.ComponentType;
            }
            // a cost center belongs to one company: kept as each company has it when several are ticked
            copy.CostCenterId = picked.Count == 1 ? model.CostCenterId : row?.CostCenterId;
            if (row is { IsBasic: true }) copy.IsActive = true;
            var saved = await _itemTypes.SaveAsync(copy, UserId, Ct);
            if (saved.Success) { done++; lastId = saved.Id; }
            else failures.Add(Name(companyId) + ": " + saved.Message);
        }

        // a company that was unticked loses it (refused while pay items or payrolls use it - deactivate it instead)
        foreach (var row in existing.Where(r => !picked.Contains(r.CompanyId)))
        {
            if (row.IsStandard) { failures.Add(Name(row.CompanyId) + ": a standard pay item type cannot be removed - deactivate it instead."); continue; }
            if (!Can(PermDelete)) { failures.Add(Name(row.CompanyId) + ": you may not remove it."); continue; }
            var removed = await _itemTypes.DeleteAsync(row.PayComponentId, UserId, Ct);
            if (!removed.Success) failures.Add(Name(row.CompanyId) + ": " + removed.Message);
        }

        if (failures.Count > 0)
        {
            HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
            var message = (done > 0 ? $"Saved for {done} of {picked.Count} companies. " : string.Empty) + string.Join(" ", failures);
            return Json(ActionResponse.Failed(message, done > 0 ? "PARTIAL" : "VALIDATION"));
        }
        return Result(SaveResult.Ok(lastId, picked.Count == 1 ? "Pay item type saved." : $"Pay item type saved for {picked.Count} companies."));
    }

    private static PayItemTypeSetting CopyItemType(PayItemTypeSetting m) => new()
    {
        ComponentCode = m.ComponentCode, ComponentName = m.ComponentName, ArabicName = m.ArabicName, PayslipLabel = m.PayslipLabel,
        ComponentType = m.ComponentType, ValueType = m.ValueType, CalculationMethod = m.CalculationMethod, CalculationBase = m.CalculationBase,
        DefaultAmount = m.DefaultAmount, DefaultPercentage = m.DefaultPercentage, Formula = m.Formula, MinAmount = m.MinAmount, MaxAmount = m.MaxAmount,
        IsTaxable = m.IsTaxable, IsPifssApplicable = m.IsPifssApplicable, IsIndemnityApplicable = m.IsIndemnityApplicable,
        IsOvertimeApplicable = m.IsOvertimeApplicable, IsLeaveSalaryApplicable = m.IsLeaveSalaryApplicable, IsRecurring = m.IsRecurring,
        IsProrated = m.IsProrated, ShowOnPayslip = m.ShowOnPayslip, GLAccountCode = m.GLAccountCode, GLAccountName = m.GLAccountName,
        CostCenterId = m.CostCenterId, DisplayOrder = m.DisplayOrder, Description = m.Description, IsActive = m.IsActive
    };

    /// <summary>Activates / deactivates the pay item type in every company it is created for.</summary>
    [HttpPost("item-types/toggle")]
    public async Task<IActionResult> ItemTypeToggle(int id)
    {
        if (!Can(PermEdit) || await ItemTypeGroupAsync(id) is not { } group) return Denied();
        var activate = !group.AnyActive;
        var rows = group.Rows.Where(r => r.IsActive != activate && !(r.IsBasic && !activate)).ToList();
        return Result(await ManyAsync(rows, r => _itemTypes.ToggleAsync(r.PayComponentId, UserId, Ct),
                                      activate ? "Pay item type activated." : "Pay item type deactivated."));
    }

    /// <summary>Deletes the pay item type in every company it is created for (refused where it is used).</summary>
    [HttpPost("item-types/delete")]
    public async Task<IActionResult> ItemTypeDelete(int id)
    {
        if (!Can(PermDelete) || await ItemTypeGroupAsync(id) is not { } group) return Denied();
        return Result(await ManyAsync(group.Rows.Where(r => !r.IsStandard).ToList(),
                                      r => _itemTypes.DeleteAsync(r.PayComponentId, UserId, Ct), "Pay item type deleted."));
    }

    /// <summary>One action on several companies' rows: one answer naming the companies where it failed.</summary>
    private static async Task<SaveResult> ManyAsync(IReadOnlyList<PayItemTypeSetting> rows, Func<PayItemTypeSetting, Task<SaveResult>> action, string ok)
    {
        var failures = new List<string>();
        foreach (var r in rows)
        {
            var res = await action(r);
            if (!res.Success) failures.Add((r.CompanyName ?? "") + ": " + res.Message);
        }
        return failures.Count == 0 ? SaveResult.Ok(rows.FirstOrDefault()?.PayComponentId ?? 0, ok)
                                   : SaveResult.Fail(string.Join(" ", failures), "VALIDATION");
    }

    /// <summary>Adds the standard pay item types (Basic Salary, PIFSS, Loan, ...) the companies are missing (0 = every company the user works in).</summary>
    [HttpPost("item-types/seed")]
    public async Task<IActionResult> ItemTypeSeed(int companyId)
    {
        if (!Can(PermCreate)) return Denied();
        if (companyId > 0) return Owns(companyId, false) ? Result(await _itemTypes.SeedAsync(companyId, UserId, Ct)) : Denied();
        var companies = await CompaniesAsync(includeInactive: false);
        SaveResult? last = null;
        foreach (var c in companies)
        {
            last = await _itemTypes.SeedAsync(c.Id, UserId, Ct);
            if (!last.Success) return Result(last);
        }
        return Result(last ?? SaveResult.Fail("Select a company.", "VALIDATION"));
    }

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
