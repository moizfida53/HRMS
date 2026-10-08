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
    private static readonly string[] ViewPermissions =
    [
        "PAYROLL_RUN_VIEW", "PAYROLL_SETUP_VIEW", "PAYROLL_REPORT_VIEW", "PAYROLL_SLIP_VIEW", "PAYROLL_BANK_VIEW", "PAYROLL_GL_VIEW"
    ];

    private readonly IPayrollFinanceRepository _finance;

    public PayrollDashboardController(IPayrollFinanceRepository finance, ICurrentUser currentUser, ICompanyFilter companyFilter)
        : base(currentUser, companyFilter)
    {
        _finance = finance;
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
            ManyCompanies = ManyCompanies,
            CanRun = Can("PAYROLL_RUN_VIEW") || Can("PAYROLL_RUN_CREATE"),
            CanSlips = Can("PAYROLL_SLIP_GENERATE") || Can("PAYROLL_SLIP_VIEW"),
            CanBank = Can("PAYROLL_BANK_VIEW") || Can("PAYROLL_BANK_PROCESS"),
            CanGl = Can("PAYROLL_GL_VIEW") || Can("PAYROLL_GL_POST"),
            CanReports = Can("PAYROLL_REPORT_VIEW")
        });
    }
}
