using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll Settings > the rule screens (db/47-48): Deduction Rules, Proration
/// Rules, Approval Workflow, Bank Formats and GL Mapping. Deduction rules and
/// approval routes have a default for every company (CompanyId null) that a
/// company row overrides; the default is edited only by users not tied to one
/// company, and is never removed.
/// </summary>
public sealed partial class PayrollSettingsController
{
    /// <summary>The defaults (no company) apply to every company: only for users not tied to one.</summary>
    private bool CanSetDefault => OwnCompany is null;

    private RuleListFilter Filter(string? search, string? status, int page, string? kind = null) => new()
    {
        CompanyId = OwnCompany,
        CompanyIds = CompanyCsv,
        Search = search,
        IsActive = ActiveFilter(status),
        Kind = kind,
        Page = Math.Max(1, page)
    };

    /// <summary>A default row (null company) or a row of a company the user may work in.</summary>
    private bool OwnsScoped(int? companyId, bool existing) => companyId is { } cid ? Owns(cid, existing) : CanSetDefault;

    private SettingsGridModel<T> RuleGrid<T>(PagedResult<T> page, bool filtered) => new()
    {
        Page = page,
        Rights = Rights,
        ManyCompanies = ManyCompanies,
        IsFiltered = filtered,
        CanEditDefaults = CanSetDefault
    };

    private IActionResult SettingsPage(string view) =>
        CanView ? View($"~/Views/PayrollSettings/{view}.cshtml", new SettingsPageModel { Rights = Rights }) : Forbid();

    private static IActionResult Options(IEnumerable<LookupItem> list) =>
        new JsonResult(list.Select(i => new { id = i.Id, text = i.Text }));

    // =======================================================================
    // Deduction Rules
    // =======================================================================

    [HttpGet("deduction-rules")]
    public IActionResult DeductionRules() => SettingsPage("DeductionRules");

    [HttpGet("deduction-rules/grid")]
    public async Task<IActionResult> DeductionRulesGrid(string? search, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _rules.DeductionPoliciesAsync(Filter(search, status, page), Ct);
        return PartialView("~/Views/PayrollSettings/_DeductionGrid.cshtml",
            RuleGrid(result, !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status)));
    }

    [HttpGet("deduction-rules/form")]
    public async Task<IActionResult> DeductionRuleForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var policy = id > 0
            ? await _rules.DeductionPolicyAsync(id, Ct)
            : new DeductionPolicy { CompanyId = OwnCompany ?? _companyFilter.SingleCompanyId, Priorities = PayrollRuleCodes.DefaultPriorities() };
        if (policy is null || (id > 0 && !OwnsScoped(policy.CompanyId, true))) return NotFound();

        var companies = await CompaniesAsync(includeInactive: id > 0);
        if (id <= 0) policy.CompanyId ??= companies.FirstOrDefault()?.Id;
        return PartialView("~/Views/PayrollSettings/_DeductionForm.cshtml", new DeductionFormModel
        {
            Policy = policy,
            Companies = companies,
            Calendars = policy.CompanyId is { } cid ? await _rules.CalendarsAsync(cid, policy.PayrollCalendarId, Ct) : Array.Empty<LookupItem>()
        });
    }

    [HttpPost("deduction-rules/save")]
    public async Task<IActionResult> DeductionRuleSave()
    {
        var model = new DeductionPolicy();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.DeductionPolicyId > 0 ? PermEdit : PermCreate)) return Denied();
        if (model.DeductionPolicyId > 0)
        {
            // the default keeps no company (the procedure enforces it); a company row may move only within the user's companies
            if (await _rules.DeductionPolicyAsync(model.DeductionPolicyId, Ct) is not { } current || !OwnsScoped(current.CompanyId, true)) return Denied();
            if (current.IsDefault) model.CompanyId = null;
        }
        if (model.CompanyId is { } cid && !Owns(cid, false)) return Denied();
        return Result(await _rules.SaveDeductionPolicyAsync(model, UserId, Ct));
    }

    [HttpPost("deduction-rules/toggle")]
    public async Task<IActionResult> DeductionRuleToggle(int id) =>
        Can(PermEdit) && await OwnsDeduction(id) ? Result(await _rules.ActionAsync("DEDUCTION", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("deduction-rules/delete")]
    public async Task<IActionResult> DeductionRuleDelete(int id) =>
        Can(PermDelete) && await OwnsDeduction(id) ? Result(await _rules.ActionAsync("DEDUCTION", "DELETE", id, UserId, Ct)) : Denied();

    /// <summary>The payroll calendars of a company (the form reloads them when the company changes).</summary>
    [HttpGet("deduction-rules/calendars")]
    public async Task<IActionResult> DeductionRuleCalendars(int companyId) =>
        CanView && Owns(companyId, false) ? Options(await _rules.CalendarsAsync(companyId, null, Ct)) : Forbid();

    private async Task<bool> OwnsDeduction(int id) =>
        await _rules.DeductionPolicyAsync(id, Ct) is { } d && OwnsScoped(d.CompanyId, true);

    // =======================================================================
    // Proration Rules (one per payroll calendar; id = PayrollCalendarId)
    // =======================================================================

    [HttpGet("proration")]
    public IActionResult Proration() => SettingsPage("Proration");

    [HttpGet("proration/grid")]
    public async Task<IActionResult> ProrationGrid(string? search, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _rules.ProrationRulesAsync(Filter(search, status, page), Ct);
        return PartialView("~/Views/PayrollSettings/_ProrationGrid.cshtml",
            RuleGrid(result, !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status)));
    }

    [HttpGet("proration/form")]
    public async Task<IActionResult> ProrationForm(int id)
    {
        if (!Can(PermEdit)) return Forbid();
        var rule = await _rules.ProrationRuleAsync(id, Ct);
        if (rule is null || !Owns(rule.CompanyId, true)) return NotFound();
        return PartialView("~/Views/PayrollSettings/_ProrationForm.cshtml", rule);
    }

    [HttpPost("proration/save")]
    public async Task<IActionResult> ProrationSave()
    {
        var model = new ProrationRule();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(PermEdit)) return Denied();
        if (await _rules.ProrationRuleAsync(model.PayrollCalendarId, Ct) is not { } current || !Owns(current.CompanyId, true)) return Denied();
        return Result(await _rules.SaveProrationRuleAsync(model, UserId, Ct));
    }

    // =======================================================================
    // Approval Workflow
    // =======================================================================

    [HttpGet("approval")]
    public IActionResult Approval() => SettingsPage("Approval");

    [HttpGet("approval/grid")]
    public async Task<IActionResult> ApprovalGrid(string? search, string? status, string? process, int page = 1)
    {
        if (!CanView) return Forbid();
        var code = PayrollRuleCodes.Processes.Contains(process ?? "") ? process : null;
        var result = await _rules.ApprovalProcessesAsync(Filter(search, status, page, code), Ct);
        return PartialView("~/Views/PayrollSettings/_ApprovalGrid.cshtml",
            RuleGrid(result, !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status) || code is not null));
    }

    [HttpGet("approval/form")]
    public async Task<IActionResult> ApprovalForm(int id = 0, string? process = null)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var route = id > 0
            ? await _rules.ApprovalProcessAsync(id, Ct)
            : new ApprovalProcess
            {
                CompanyId = OwnCompany ?? _companyFilter.SingleCompanyId,
                ProcessCode = PayrollRuleCodes.Processes.Contains(process ?? "") ? process! : "PAYROLL_RUN"
            };
        if (route is null || (id > 0 && !OwnsScoped(route.CompanyId, true))) return NotFound();

        var companies = await CompaniesAsync(includeInactive: id > 0);
        if (id <= 0) route.CompanyId ??= companies.FirstOrDefault()?.Id;
        return PartialView("~/Views/PayrollSettings/_ApprovalForm.cshtml", new ApprovalFormModel
        {
            Process = route,
            Companies = companies,
            Roles = await _rules.RolesAsync(route.CompanyId, Ct),
            Users = await _rules.UsersAsync(route.CompanyId, Ct)
        });
    }

    [HttpPost("approval/save")]
    public async Task<IActionResult> ApprovalSave()
    {
        var model = new ApprovalProcess();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.ApprovalProcessId > 0 ? PermEdit : PermCreate)) return Denied();
        if (model.ApprovalProcessId > 0)
        {
            // process and company of a route are fixed - the procedure keeps the stored ones
            if (await _rules.ApprovalProcessAsync(model.ApprovalProcessId, Ct) is not { } current || !OwnsScoped(current.CompanyId, true)) return Denied();
        }
        else if (model.CompanyId is not { } cid || !Owns(cid, false))
        {
            return Denied();
        }
        return Result(await _rules.SaveApprovalProcessAsync(model, UserId, Ct));
    }

    [HttpPost("approval/toggle")]
    public async Task<IActionResult> ApprovalToggle(int id) =>
        Can(PermEdit) && await OwnsApproval(id) ? Result(await _rules.ActionAsync("APPROVAL", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("approval/delete")]
    public async Task<IActionResult> ApprovalDelete(int id) =>
        Can(PermDelete) && await OwnsApproval(id) ? Result(await _rules.ActionAsync("APPROVAL", "DELETE", id, UserId, Ct)) : Denied();

    /// <summary>The roles / users of a company (the form reloads them when the company changes).</summary>
    [HttpGet("approval/roles")]
    public async Task<IActionResult> ApprovalRoles(int companyId) =>
        CanView && Owns(companyId, false) ? Options(await _rules.RolesAsync(companyId, Ct)) : Forbid();

    [HttpGet("approval/users")]
    public async Task<IActionResult> ApprovalUsers(int companyId) =>
        CanView && Owns(companyId, false) ? Options(await _rules.UsersAsync(companyId, Ct)) : Forbid();

    private async Task<bool> OwnsApproval(int id) =>
        await _rules.ApprovalProcessAsync(id, Ct) is { } a && OwnsScoped(a.CompanyId, true);

    // =======================================================================
    // Bank Formats (shared by every company, like the bank master)
    // =======================================================================

    [HttpGet("bank-formats")]
    public IActionResult BankFormats() => SettingsPage("BankFormats");

    [HttpGet("bank-formats/grid")]
    public async Task<IActionResult> BankFormatsGrid(string? search, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _rules.BankFileFormatsAsync(Filter(search, status, page), Ct);
        return PartialView("~/Views/PayrollSettings/_BankFormatsGrid.cshtml",
            RuleGrid(result, !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status)));
    }

    [HttpGet("bank-formats/form")]
    public async Task<IActionResult> BankFormatForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var format = id > 0
            ? await _rules.BankFileFormatAsync(id, Ct)
            : new BankFileFormat
            {
                Fields =
                [
                    new() { FieldName = "EmployeeCode", SourceCode = "EMPLOYEE_CODE" },
                    new() { FieldName = "Name", SourceCode = "EMPLOYEE_NAME" },
                    new() { FieldName = "IBAN", SourceCode = "IBAN" },
                    new() { FieldName = "Amount", SourceCode = "NET_AMOUNT" }
                ]
            };
        if (format is null) return NotFound();
        return PartialView("~/Views/PayrollSettings/_BankFormatForm.cshtml", new BankFormatFormModel
        {
            Format = format,
            Banks = await _rules.FormatBanksAsync(format.BankId, Ct)
        });
    }

    [HttpPost("bank-formats/save")]
    public async Task<IActionResult> BankFormatSave()
    {
        var model = new BankFileFormat();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.BankFileFormatId > 0 ? PermEdit : PermCreate)) return Denied();
        return Result(await _rules.SaveBankFileFormatAsync(model, UserId, Ct));
    }

    [HttpPost("bank-formats/toggle")]
    public async Task<IActionResult> BankFormatToggle(int id) =>
        Can(PermEdit) ? Result(await _rules.ActionAsync("FORMAT", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("bank-formats/delete")]
    public async Task<IActionResult> BankFormatDelete(int id) =>
        Can(PermDelete) ? Result(await _rules.ActionAsync("FORMAT", "DELETE", id, UserId, Ct)) : Denied();

    // =======================================================================
    // GL Mapping
    // =======================================================================

    [HttpGet("gl-mapping")]
    public IActionResult GLMappings() => SettingsPage("GLMapping");

    [HttpGet("gl-mapping/grid")]
    public async Task<IActionResult> GLMappingGrid(string? search, string? status, string? type, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _rules.GLMappingsAsync(Filter(search, status, page, type), Ct);
        return PartialView("~/Views/PayrollSettings/_GLMappingGrid.cshtml",
            RuleGrid(result, !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(status) || !string.IsNullOrEmpty(type)));
    }

    [HttpGet("gl-mapping/form")]
    public async Task<IActionResult> GLMappingForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var mapping = id > 0 ? await _rules.GLMappingAsync(id, Ct) : new GLMapping { CompanyId = OwnCompany ?? _companyFilter.SingleCompanyId ?? 0 };
        if (mapping is null || (id > 0 && !Owns(mapping.CompanyId, true))) return NotFound();

        var companies = await CompaniesAsync(includeInactive: id > 0);
        if (mapping.CompanyId <= 0) mapping.CompanyId = companies.FirstOrDefault()?.Id ?? 0;
        return PartialView("~/Views/PayrollSettings/_GLMappingForm.cshtml", new GLMappingFormModel
        {
            Mapping = mapping,
            Companies = companies,
            Components = mapping.CompanyId > 0 ? await _rules.ComponentsAsync(mapping.CompanyId, mapping.PayComponentId, Ct) : Array.Empty<LookupItem>(),
            CostCenters = mapping.CompanyId > 0 ? await _lookups.GetAsync(LookupType.CostCenter, mapping.CompanyId, cancellationToken: Ct) : Array.Empty<LookupItem>()
        });
    }

    [HttpPost("gl-mapping/save")]
    public async Task<IActionResult> GLMappingSave()
    {
        var model = new GLMapping();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.GLMappingId > 0 ? PermEdit : PermCreate)) return Denied();
        if (model.GLMappingId > 0 && !await OwnsGLMapping(model.GLMappingId)) return Denied();
        // the company is the pay item type's own
        if (await _itemTypes.GetAsync(model.PayComponentId, Ct) is { } item && !Owns(item.CompanyId, false)) return Denied();
        return Result(await _rules.SaveGLMappingAsync(model, UserId, Ct));
    }

    [HttpPost("gl-mapping/toggle")]
    public async Task<IActionResult> GLMappingToggle(int id) =>
        Can(PermEdit) && await OwnsGLMapping(id) ? Result(await _rules.ActionAsync("GL", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("gl-mapping/delete")]
    public async Task<IActionResult> GLMappingDelete(int id) =>
        Can(PermDelete) && await OwnsGLMapping(id) ? Result(await _rules.ActionAsync("GL", "DELETE", id, UserId, Ct)) : Denied();

    /// <summary>The pay item types of a company (the form reloads them when the company changes).</summary>
    [HttpGet("gl-mapping/components")]
    public async Task<IActionResult> GLMappingComponents(int companyId) =>
        CanView && Owns(companyId, false) ? Options(await _rules.ComponentsAsync(companyId, null, Ct)) : Forbid();

    private async Task<bool> OwnsGLMapping(int id) =>
        await _rules.GLMappingAsync(id, Ct) is { } g && Owns(g.CompanyId, true);
}
