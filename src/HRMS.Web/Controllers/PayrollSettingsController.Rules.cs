using HRMS.Domain.Payroll;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll Settings > Payroll Rules: the Kuwait statutory settings the engine
/// reads - PIFSS contribution rates, end-of-service indemnity rules (service
/// slabs and entitlement factors) and overtime multipliers. Effective-dated:
/// a change is a new row from a date (end-date the current one), so history
/// is kept; every row carries "Verified" for finance to confirm.
/// </summary>
public sealed partial class PayrollSettingsController
{
    [HttpGet("rules")]
    public async Task<IActionResult> Rules()
    {
        if (!CanView) return Forbid();

        // seeded values must be confirmed by finance: count what is still unverified and in force
        var pifss = await _statutory.PifssListAsync(null, true, false, 1, Ct);
        var indemnity = await _statutory.IndemnityListAsync(null, true, 1, Ct);
        var overtime = await _statutory.OvertimeListAsync(OwnCompany, CompanyCsv, null, true, 1, Ct);
        var unverified = pifss.Items.Count(r => !r.IsVerified) + indemnity.Items.Count(r => !r.IsVerified) + overtime.Items.Count(r => !r.IsVerified);

        return View("~/Views/PayrollSettings/Rules.cshtml", new SettingsPageModel { Rights = Rights, UnverifiedCount = unverified });
    }

    // ---------------------------------------------------------------- PIFSS

    [HttpGet("rules/pifss/grid")]
    public async Task<IActionResult> PifssGrid(string? search, string? status, string? when, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _statutory.PifssListAsync(search, ActiveFilter(status), when == "today", page, Ct);
        return PartialView("~/Views/PayrollSettings/_PifssGrid.cshtml", Grid(result, search, status, when));
    }

    [HttpGet("rules/pifss/form")]
    public async Task<IActionResult> PifssForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var rate = id > 0 ? await _statutory.PifssGetAsync(id, Ct) : new PifssRate { EffectiveFrom = FirstOfNextMonth() };
        return rate is null ? NotFound() : PartialView("~/Views/PayrollSettings/_PifssForm.cshtml", rate);
    }

    [HttpPost("rules/pifss/save")]
    public async Task<IActionResult> PifssSave()
    {
        var model = new PifssRate();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.PifssRateId > 0 ? PermEdit : PermCreate)) return Denied();
        return Result(await _statutory.PifssSaveAsync(model, UserId, Ct));
    }

    [HttpPost("rules/pifss/toggle")]
    public async Task<IActionResult> PifssToggle(int id) => Can(PermEdit) ? Result(await _statutory.ActionAsync("PIFSS", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("rules/pifss/delete")]
    public async Task<IActionResult> PifssDelete(int id) => Can(PermDelete) ? Result(await _statutory.ActionAsync("PIFSS", "DELETE", id, UserId, Ct)) : Denied();

    // ------------------------------------------------------------ INDEMNITY

    [HttpGet("rules/indemnity/grid")]
    public async Task<IActionResult> IndemnityGrid(string? search, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _statutory.IndemnityListAsync(search, ActiveFilter(status), page, Ct);
        return PartialView("~/Views/PayrollSettings/_IndemnityGrid.cshtml", Grid(result, search, status, null));
    }

    [HttpGet("rules/indemnity/form")]
    public async Task<IActionResult> IndemnityForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var set = id > 0
            ? await _statutory.IndemnityGetAsync(id, Ct)
            : new IndemnityRuleSet
            {
                EffectiveFrom = FirstOfNextMonth(),
                MaxIndemnityMonths = 18,
                // Labour Law 6/2010 shape as a starting point - to be confirmed (Verified) by finance
                Slabs = [new() { FromYears = 0, ToYears = 5, EntitlementUnit = "DAYS", EntitlementValue = 15 },
                         new() { FromYears = 5, ToYears = null, EntitlementUnit = "MONTHS", EntitlementValue = 1 }],
                Factors = [new() { SeparationType = "TERMINATION", FromYears = 0, EntitlementPercent = 100 }]
            };
        return set is null ? NotFound() : PartialView("~/Views/PayrollSettings/_IndemnityForm.cshtml", set);
    }

    [HttpPost("rules/indemnity/save")]
    public async Task<IActionResult> IndemnitySave()
    {
        var model = new IndemnityRuleSet();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.IndemnityRuleSetId > 0 ? PermEdit : PermCreate)) return Denied();
        model.Slabs = model.Slabs.Where(s => s.EntitlementValue > 0 || s.FromYears > 0 || s.ToYears is not null).ToList();
        if (model.Slabs.Count == 0)
        {
            return Json(ActionResponse.Failed("Add at least one service slab.", "VALIDATION"));
        }
        return Result(await _statutory.IndemnitySaveAsync(model, UserId, Ct));
    }

    [HttpPost("rules/indemnity/toggle")]
    public async Task<IActionResult> IndemnityToggle(int id) => Can(PermEdit) ? Result(await _statutory.ActionAsync("INDEMNITY", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("rules/indemnity/delete")]
    public async Task<IActionResult> IndemnityDelete(int id) => Can(PermDelete) ? Result(await _statutory.ActionAsync("INDEMNITY", "DELETE", id, UserId, Ct)) : Denied();

    // ------------------------------------------------------------- OVERTIME

    [HttpGet("rules/overtime/grid")]
    public async Task<IActionResult> OvertimeGrid(string? search, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _statutory.OvertimeListAsync(OwnCompany, CompanyCsv, search, ActiveFilter(status), page, Ct);
        return PartialView("~/Views/PayrollSettings/_OvertimeGrid.cshtml", Grid(result, search, status, null));
    }

    [HttpGet("rules/overtime/form")]
    public async Task<IActionResult> OvertimeForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var rate = id > 0 ? await _statutory.OvertimeGetAsync(id, Ct) : new OvertimeRate { EffectiveFrom = FirstOfNextMonth() };
        if (rate is null || (rate.CompanyId is { } cid && !Owns(cid, true))) return NotFound();
        return PartialView("~/Views/PayrollSettings/_OvertimeForm.cshtml", new OvertimeFormModel
        {
            Rate = rate,
            Companies = await CompaniesAsync(includeInactive: id > 0),
            // the statutory default (no company) applies to every company: only for users not tied to one
            CanSetDefault = OwnCompany is null
        });
    }

    [HttpPost("rules/overtime/save")]
    public async Task<IActionResult> OvertimeSave()
    {
        var model = new OvertimeRate();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.OvertimeRateId > 0 ? PermEdit : PermCreate)) return Denied();
        if (model.CompanyId is { } cid ? !Owns(cid, false) : OwnCompany is not null) return Denied();
        return Result(await _statutory.OvertimeSaveAsync(model, UserId, Ct));
    }

    [HttpPost("rules/overtime/toggle")]
    public async Task<IActionResult> OvertimeToggle(int id) =>
        Can(PermEdit) && await OwnsOvertime(id) ? Result(await _statutory.ActionAsync("OVERTIME", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("rules/overtime/delete")]
    public async Task<IActionResult> OvertimeDelete(int id) =>
        Can(PermDelete) && await OwnsOvertime(id) ? Result(await _statutory.ActionAsync("OVERTIME", "DELETE", id, UserId, Ct)) : Denied();

    private async Task<bool> OwnsOvertime(int id) =>
        await _statutory.OvertimeGetAsync(id, Ct) is { } r && (r.CompanyId is { } cid ? Owns(cid, true) : OwnCompany is null);

    // ---------------------------------------------------------------- shared

    private static bool? ActiveFilter(string? status) => status switch { "active" => true, "inactive" => false, _ => null };

    private static DateTime FirstOfNextMonth() => new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1).AddMonths(1);

    private SettingsGridModel<T> Grid<T>(Domain.Common.PagedResult<T> page, string? search, string? status, string? when) => new()
    {
        Page = page,
        Rights = Rights,
        ManyCompanies = ManyCompanies,
        IsFiltered = !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status) || !string.IsNullOrEmpty(when)
    };
}
