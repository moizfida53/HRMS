using HRMS.Data.Repositories;
using HRMS.Domain.Payroll;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll > Payroll Dashboard (db/53): one payroll month at a glance - the main
/// payroll and its stage, employees paid, net pay and employer cost against the
/// month before, the 12-month net trend, gross cost by department, the payroll
/// calendar around the month, what needs attention, and quick actions.
/// </summary>
[Route("payroll/dashboard")]
public sealed class PayrollDashboardController : PayrollFinanceControllerBase
{
    // Security > Create Roles: "Payroll dashboard" (db/57 grants it to every role that had a payroll view right)
    private static readonly string[] ViewPermissions = ["PAYROLL_DASHBOARD_VIEW"];

    private readonly IPayrollFinanceRepository _finance;
    private readonly ICollectionRepository _collections;
    private readonly ILogger<PayrollDashboardController> _logger;

    public PayrollDashboardController(IPayrollFinanceRepository finance, ICollectionRepository collections, ICurrentUser currentUser,
                                      ICompanyFilter companyFilter, ILogger<PayrollDashboardController> logger)
        : base(currentUser, companyFilter)
    {
        _finance = finance;
        _collections = collections;
        _logger = logger;
    }

    /// <summary>db/115: the month's Work Permit Collections for those who may see them (null = not shown).</summary>
    private async Task<CollectionSummary?> CollectionsAsync(DateTime month)
    {
        if (!Can(CollectionsController.PermView)) return null;
        try
        {
            return await _collections.DashboardAsync(OwnCompany, CompanyCsv, month, Ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Collections could not be read for the dashboard (run db/115).");
            return null;
        }
    }

    [HttpGet("")]
    public async Task<IActionResult> Index(string? month)
    {
        if (!ViewPermissions.Any(Can)) return Forbid();

        // the chosen month, else the newest month with a payroll, else this month
        var months = await _finance.DashboardMonthsAsync(OwnCompany, CompanyCsv, Ct);
        var m = FinancePeriod.ParseMonth(month)
                ?? (months.Count > 0 ? months[0] : new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1));
        var offered = months.ToList();
        if (!offered.Contains(m)) offered.Add(m);
        var thisMonth = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
        if (!offered.Contains(thisMonth)) offered.Add(thisMonth);

        return View("~/Views/PayrollDashboard/Index.cshtml", new PayrollDashboardModel
        {
            Month = m,
            Months = offered.OrderByDescending(x => x).ToList(),
            Summary = await _finance.DashboardSummaryAsync(m, OwnCompany, CompanyCsv, Ct) ?? new DashboardSummary { RunMonth = m },
            Trend = await _finance.DashboardTrendAsync(m, OwnCompany, CompanyCsv, Ct),
            TrendByCompany = await _finance.DashboardTrendByCompanyAsync(m, OwnCompany, CompanyCsv, Ct),
            Departments = await _finance.DashboardDepartmentsAsync(m, OwnCompany, CompanyCsv, Ct),
            Calendar = await _finance.DashboardCalendarAsync(m, OwnCompany, CompanyCsv, Ct),
            Attention = await _finance.DashboardAttentionAsync(m, OwnCompany, CompanyCsv, Ct) ?? new DashboardAttention(),
            Collections = await CollectionsAsync(m),
            ManyCompanies = ManyCompanies,
            CanRun = Can("PAYROLL_RUN_VIEW") || Can("PAYROLL_RUN_CREATE"),
            CanSlips = Can("PAYROLL_SLIP_GENERATE") || Can("PAYROLL_SLIP_VIEW"),
            CanBank = Can("PAYROLL_BANK_VIEW") || Can("PAYROLL_BANK_PROCESS"),
            CanGl = Can("PAYROLL_GL_VIEW") || Can("PAYROLL_GL_POST"),
            CanReports = Can("PAYROLL_REPORT_VIEW")
        });
    }
}
