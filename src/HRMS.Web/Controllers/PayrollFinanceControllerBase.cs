using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// What Bank Processing, Accounting and Payroll Reports share: the user's company
/// scope, the Year / Month filter values (the months that have closed payrolls),
/// and the JSON answer of an action.
/// </summary>
public abstract class PayrollFinanceControllerBase : Controller
{
    protected readonly ICurrentUser CurrentUser;
    protected readonly ICompanyFilter CompanyFilter;

    protected PayrollFinanceControllerBase(ICurrentUser currentUser, ICompanyFilter companyFilter)
    {
        CurrentUser = currentUser;
        CompanyFilter = companyFilter;
    }

    protected CancellationToken Ct => HttpContext.RequestAborted;
    protected long? UserId => CurrentUser.UserId;
    protected int? OwnCompany => CurrentUser.ActiveCompanyId;
    protected string? CompanyCsv => CompanyFilter.Csv;
    protected bool ManyCompanies => CompanyFilter.SelectedIds.Count != 1 && OwnCompany is null;
    protected bool Can(string permission) => CurrentUser.HasPermission(permission);

    /// <summary>The year and month to show: as chosen, else the newest month that has closed payrolls.</summary>
    protected static (int? Year, DateTime? Month) PickPeriod(IReadOnlyList<DateTime> months, int? year, string? month, bool defaultToLatest)
    {
        var m = FinancePeriod.ParseMonth(month);
        var y = FinancePeriod.ValidYear(year) ?? m?.Year;
        if (m is null && y is null && defaultToLatest && months.Count > 0)
        {
            m = months[0];
            y = m.Value.Year;
        }
        if (m is { } chosen && y is { } yy && chosen.Year != yy) m = null;   // a month of another year
        return (y, m);
    }

    protected static IReadOnlyList<int> YearsOf(IReadOnlyList<DateTime> months)
    {
        var years = months.Select(m => m.Year).Distinct().ToList();
        if (!years.Contains(DateTime.Today.Year)) years.Add(DateTime.Today.Year);
        return years.OrderByDescending(y => y).ToList();
    }

    protected static IReadOnlyList<DateTime> MonthsOf(IEnumerable<FinanceRun> runs) =>
        runs.Select(r => r.RunMonth).Distinct().OrderByDescending(m => m).ToList();

    protected IActionResult Result(SaveResult result)
    {
        if (result.Success)
        {
            HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
        }
        return Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    protected IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));

    protected IActionResult Invalid(string message) => Json(ActionResponse.Failed(message, "VALIDATION"));

    /// <summary>"1,5,9" or repeated ids -> the ids.</summary>
    protected static IReadOnlyList<long> Ids(IEnumerable<string>? raw) =>
        (raw ?? Array.Empty<string>())
            .SelectMany(v => (v ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            .Select(v => long.TryParse(v, out var id) ? id : 0).Where(id => id > 0).Distinct().ToList();
}
