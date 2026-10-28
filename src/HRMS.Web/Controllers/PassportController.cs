using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Workforce;
using HRMS.Web.Helpers;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Workforce;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Workforce > Employees > Actions > Passport In / Out (db/93): who holds the employee's
/// passport - the company or the employee - with every hand-over kept as a log (exportable).
/// </summary>
[Route("employees/passport")]
public sealed class PassportController : Controller
{
    private const string Views = "~/Views/Workforce/Passport/";
    private readonly IPassportCustodyRepository _passports;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _text;

    public PassportController(IPassportCustodyRepository passports, ICurrentUser currentUser, ICompanyFilter companyFilter, IUiText text)
    {
        _passports = passports;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _text = text;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private AssetScope Scope => new(_currentUser.ActiveCompanyId, _companyFilter.Csv, _currentUser.UserId);

    /// <summary>The popup: the passport, who holds it, and the hand-over form.</summary>
    [HttpGet("panel")]
    public async Task<IActionResult> Panel(long id)
    {
        if (!_currentUser.CanViewPassportCustody()) return Forbid();
        var status = await _passports.StatusAsync(id, Scope, Ct);
        if (status is null) return NotFound();
        return PartialView(Views + "_Panel.cshtml", new PassportPanelModel { Status = status, CanEdit = _currentUser.CanEditPassportCustody() });
    }

    [HttpGet("log")]
    public async Task<IActionResult> Log(long id)
    {
        if (!_currentUser.CanViewPassportCustody()) return Forbid();
        return PartialView(Views + "_Log.cshtml", await _passports.LogAsync(id, Scope, Ct));
    }

    [HttpPost("save")]
    public async Task<IActionResult> Save(long id, string? heldBy, DateTime? date, string? remarks)
    {
        if (!_currentUser.CanEditPassportCustody())
            return Json(ActionResponse.Failed(_text.Tr("You do not have permission to do this."), "FORBIDDEN"));
        var result = await _passports.SaveAsync(id, heldBy, date, remarks, Scope, Ct);
        return Json(result.Success
            ? ActionResponse.Ok(result.Id, _text.Tr(result.Message))
            : ActionResponse.Failed(_text.Tr(result.Message), result.ErrorCode));
    }

    /// <summary>The log as an Excel file.</summary>
    [HttpGet("export")]
    public async Task<IActionResult> Export(long id)
    {
        if (!_currentUser.CanViewPassportCustody()) return Forbid();
        var status = await _passports.StatusAsync(id, Scope, Ct);
        if (status is null) return NotFound();
        var L = _text;
        var log = await _passports.LogAsync(id, Scope, Ct);
        string[] headers = [L.Tr("Date"), L.Tr("Passport with"), L.Tr("Passport no."), L.Tr("Remarks"), L.Tr("Entered by"), L.Tr("Entered on")];
        var rows = log.Select(m => (IReadOnlyList<object?>)new object?[]
        {
            m.MovementDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), PassportFormat.Holder(L, m.HeldBy),
            m.PassportNumber, m.Remarks, m.CreatedByName, m.CreatedDate.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture)
        });
        var bytes = XlsxFile.Write(L.Tr("Passport In / Out"), headers, rows, [12, 16, 16, 40, 18, 18], rightToLeft: L.IsArabic);
        var who = string.Concat((status.EmployeeCode ?? status.EmployeeId.ToString(CultureInfo.InvariantCulture)).Where(char.IsLetterOrDigit));
        return File(bytes, XlsxFile.ContentType, $"passport-in-out-{who}-{DateTime.Today:yyyyMMdd}.xlsx");
    }
}
