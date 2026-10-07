using System.Globalization;
using System.Text.Json;
using HRMS.Domain.Dashboard;

namespace HRMS.Web.Models.Dashboard;

public sealed class DashboardViewModel
{
    private static readonly CultureInfo En = CultureInfo.GetCultureInfo("en-GB");

    public required DashboardData Data { get; init; }

    /// <summary>Top-bar company filter label ("All companies", a name, or "3 companies").</summary>
    public string CompanyLabel { get; init; } = "All companies";

    /// <summary>Companies picked in the top-bar filter (empty = all) - highlighted in the company chart.</summary>
    public IReadOnlyList<int> SelectedCompanyIds { get; init; } = Array.Empty<int>();

    public bool IsHighlighted(int companyId) =>
        SelectedCompanyIds.Count == 0 || SelectedCompanyIds.Contains(companyId);

    public int MaxCompanyHeadcount => Math.Max(1, Data.Companies.Select(c => c.Headcount).DefaultIfEmpty(0).Max());

    public int AllCompaniesHeadcount => Data.Companies.Sum(c => c.Headcount);

    /// <summary>yyyy-MM values for the month picker, newest first.</summary>
    public required IReadOnlyList<DateTime> MonthOptions { get; init; }

    public string MonthLabel => Data.MonthStart.ToString("MMMM yyyy", En);

    public static string MonthKey(DateTime month) => month.ToString("yyyy-MM", CultureInfo.InvariantCulture);

    public static string MonthText(DateTime month) => month.ToString("MMMM yyyy", En);

    /// <summary>% change vs the previous month, or null when there is nothing to compare with.</summary>
    public static decimal? Change(int current, int previous) =>
        previous <= 0 ? null : Math.Round((current - previous) * 100m / previous, 1);

    /// <summary>Top 7 departments, the rest folded into "Other".</summary>
    public IReadOnlyList<DashboardDepartment> TopDepartments
    {
        get
        {
            var list = Data.Departments.OrderByDescending(d => d.Headcount).ToList();
            if (list.Count <= 8)
            {
                return list;
            }

            var top = list.Take(7).ToList();
            top.Add(new DashboardDepartment
            {
                DepartmentName = $"Other ({list.Count - 7})",
                Headcount = list.Skip(7).Sum(d => d.Headcount)
            });
            return top;
        }
    }

    public int MaxDepartmentHeadcount => Math.Max(1, Data.Departments.Select(d => d.Headcount).DefaultIfEmpty(0).Max());

    public bool HasPayrollData => Data.Payroll.EmployeesWithSalary > 0;

    public bool HasPayrollTrend => Data.Trend.Any(t => t.GrossPayroll is > 0);

    /// <summary>KWD amounts with 3 decimals, shortened (K / M) for tiles.</summary>
    public static string Kwd(decimal? amount, bool shorten = true)
    {
        if (amount is null)
        {
            return "—";
        }

        var v = amount.Value;
        if (shorten && Math.Abs(v) >= 1_000_000m) return $"KD {v / 1_000_000m:0.##}M";
        if (shorten && Math.Abs(v) >= 10_000m) return $"KD {v / 1_000m:0.#}K";
        return "KD " + v.ToString("N3", CultureInfo.InvariantCulture);
    }

    /// <summary>Series for dashboard.js, read from a JSON data block (never executed).</summary>
    public string ChartJson => ChartJsonFor(
        m => m.ToString("MMM yy", CultureInfo.InvariantCulture),
        m => m.ToString("MMMM yyyy", En));

    /// <summary>Same series, with month captions supplied by the caller (the view passes the user's language).</summary>
    public string ChartJsonFor(Func<DateTime, string> shortMonth, Func<DateTime, string> longMonth) => JsonSerializer.Serialize(new
    {
        months = Data.Trend.Select(t => shortMonth(t.MonthStart)),
        monthsLong = Data.Trend.Select(t => longMonth(t.MonthStart)),
        headcount = Data.Trend.Select(t => t.Headcount),
        joiners = Data.Trend.Select(t => t.Joiners),
        leavers = Data.Trend.Select(t => t.Leavers),
        gross = Data.Trend.Select(t => t.GrossPayroll)
    });
}
