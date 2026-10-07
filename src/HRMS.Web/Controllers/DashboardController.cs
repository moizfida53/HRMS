using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Web.Models.Dashboard;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Dashboard - the landing page ("/"). Read-only; every number comes from
/// Employee.usp_Dashboard_Get for the signed-in user's company and the
/// month chosen in the top-bar picker (?month=yyyy-MM).
/// </summary>
public sealed class DashboardController : Controller
{
    private readonly IDashboardRepository _dashboard;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;

    public DashboardController(IDashboardRepository dashboard, ICurrentUser currentUser, ICompanyFilter companyFilter)
    {
        _dashboard = dashboard;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
    }

    [HttpGet("/")]
    [HttpGet("/dashboard")]
    public async Task<IActionResult> Index(string? month = null)
    {
        var thisMonth = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);

        var selected = DateTime.TryParseExact(month, "yyyy-MM", CultureInfo.InvariantCulture,
                           DateTimeStyles.None, out var parsed) && parsed <= thisMonth && parsed >= thisMonth.AddYears(-5)
            ? parsed
            : thisMonth;

        var data = await _dashboard.GetAsync(
            _currentUser.ActiveCompanyId, _companyFilter.Csv, selected, HttpContext.RequestAborted);

        return View("~/Views/Dashboard/Index.cshtml", new DashboardViewModel
        {
            Data = data,
            CompanyLabel = await _companyFilter.GetLabelAsync(HttpContext.RequestAborted),
            SelectedCompanyIds = _companyFilter.SelectedIds,
            MonthOptions = Enumerable.Range(0, 12).Select(i => thisMonth.AddMonths(-i)).ToList()
        });
    }
}
