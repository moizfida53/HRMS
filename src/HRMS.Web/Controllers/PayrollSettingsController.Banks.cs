using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll Settings > Banks &amp; Accounts: the bank master (shared by every
/// company - SWIFT, the IBAN bank code, the WPS code) and each company's own
/// salary (debit) accounts - IBAN checked (mod-97), one default per company,
/// WPS employer code and PAM file number for the salary file.
/// </summary>
public sealed partial class PayrollSettingsController
{
    [HttpGet("banks")]
    public IActionResult Banks()
    {
        if (!CanView) return Forbid();
        return View("~/Views/PayrollSettings/Banks.cshtml", new SettingsPageModel { Rights = Rights });
    }

    // ----------------------------------------------------------------- banks

    [HttpGet("banks/grid")]
    public async Task<IActionResult> BanksGrid(string? search, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _banks.BanksAsync(search, ActiveFilter(status), page, Ct);
        return PartialView("~/Views/PayrollSettings/_BanksGrid.cshtml", Grid(result, search, status, null));
    }

    [HttpGet("banks/form")]
    public async Task<IActionResult> BankForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var bank = id > 0 ? await _banks.BankAsync(id, Ct) : new Bank();
        if (bank is null) return NotFound();
        var countries = await _lookups.GetAsync(LookupType.Country, cancellationToken: Ct);
        if (id <= 0) bank.CountryId = countries.FirstOrDefault(c => c.Code is "KW" or "KWT")?.Id;
        return PartialView("~/Views/PayrollSettings/_BankForm.cshtml", new BankFormModel { Bank = bank, Countries = countries });
    }

    [HttpPost("banks/save")]
    public async Task<IActionResult> BankSave()
    {
        var model = new Bank();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.BankId > 0 ? PermEdit : PermCreate)) return Denied();
        return Result(await _banks.SaveBankAsync(model, UserId, Ct));
    }

    [HttpPost("banks/toggle")]
    public async Task<IActionResult> BankToggle(int id) => Can(PermEdit) ? Result(await _banks.ActionAsync("BANK", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("banks/delete")]
    public async Task<IActionResult> BankDelete(int id) => Can(PermDelete) ? Result(await _banks.ActionAsync("BANK", "DELETE", id, UserId, Ct)) : Denied();

    // -------------------------------------------------------------- accounts

    [HttpGet("accounts/grid")]
    public async Task<IActionResult> AccountsGrid(string? search, string? status, int page = 1)
    {
        if (!CanView) return Forbid();
        var result = await _banks.AccountsAsync(OwnCompany, CompanyCsv, search, ActiveFilter(status), page, Ct);
        return PartialView("~/Views/PayrollSettings/_AccountsGrid.cshtml", Grid(result, search, status, null));
    }

    [HttpGet("accounts/form")]
    public async Task<IActionResult> AccountForm(int id = 0)
    {
        if (!Can(id > 0 ? PermEdit : PermCreate)) return Forbid();
        var account = id > 0 ? await _banks.AccountAsync(id, Ct) : new CompanyBankAccount { CompanyId = OwnCompany ?? _companyFilter.SingleCompanyId ?? 0 };
        if (account is null || (id > 0 && !Owns(account.CompanyId, true))) return NotFound();

        var currencies = await _lookups.GetAsync(LookupType.Currency, cancellationToken: Ct);
        if (id <= 0) account.CurrencyId = currencies.FirstOrDefault(c => c.Code == "KWD")?.Id;
        return PartialView("~/Views/PayrollSettings/_AccountForm.cshtml", new AccountFormModel
        {
            Account = account,
            Companies = await CompaniesAsync(includeInactive: id > 0),
            Banks = (await _banks.BanksAsync(null, id > 0 ? null : true, 1, Ct)).Items,
            Currencies = currencies
        });
    }

    [HttpPost("accounts/save")]
    public async Task<IActionResult> AccountSave()
    {
        var model = new CompanyBankAccount();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(CollectErrors()));
        if (!Can(model.CompanyBankAccountId > 0 ? PermEdit : PermCreate)) return Denied();
        if (!Owns(model.CompanyId, false)) return Denied();
        if (model.CompanyBankAccountId > 0 && !await OwnsAccount(model.CompanyBankAccountId)) return Denied();
        return Result(await _banks.SaveAccountAsync(model, UserId, Ct));
    }

    [HttpPost("accounts/toggle")]
    public async Task<IActionResult> AccountToggle(int id) =>
        Can(PermEdit) && await OwnsAccount(id) ? Result(await _banks.ActionAsync("ACCOUNT", "TOGGLE", id, UserId, Ct)) : Denied();

    [HttpPost("accounts/delete")]
    public async Task<IActionResult> AccountDelete(int id) =>
        Can(PermDelete) && await OwnsAccount(id) ? Result(await _banks.ActionAsync("ACCOUNT", "DELETE", id, UserId, Ct)) : Denied();

    private async Task<bool> OwnsAccount(int id) => await _banks.AccountAsync(id, Ct) is { } a && Owns(a.CompanyId, true);
}
