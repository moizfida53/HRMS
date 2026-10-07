using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Dashboard;

namespace HRMS.Data.Repositories;

/// <summary>
/// Read-only data for the Dashboard landing page. One call per panel
/// (Employee.usp_Dashboard_Get @Action = KPI, TREND, ...) - small, fast
/// queries, and ISqlExecutor has no multi-result-set API by design.
/// </summary>
public interface IDashboardRepository
{
    /// <param name="companyIds">Top-bar company filter, comma-separated; null = all companies.</param>
    Task<DashboardData> GetAsync(int? companyId, string? companyIds, DateTime monthStart, CancellationToken cancellationToken = default);
}

public sealed class DashboardRepository : IDashboardRepository
{
    private readonly ISqlExecutor _sql;

    public DashboardRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<DashboardData> GetAsync(
        int? companyId, string? companyIds, DateTime monthStart, CancellationToken cancellationToken = default)
    {
        _companyIds = companyIds;

        var month = new DateTime(monthStart.Year, monthStart.Month, 1);

        // Sequential on purpose: one connection per call, and the panels are tiny.
        var kpis = await One<DashboardKpis>("KPI", companyId, month, cancellationToken) ?? new DashboardKpis();
        var trend = await Many<DashboardTrendPoint>("TREND", companyId, month, cancellationToken);
        var companies = await Many<DashboardCompany>("COMPANY", companyId, month, cancellationToken);
        var departments = await Many<DashboardDepartment>("DEPT", companyId, month, cancellationToken);
        var payroll = await One<DashboardPayroll>("PAYROLL", companyId, month, cancellationToken) ?? new DashboardPayroll();
        var actions = await One<DashboardActions>("ACTIONS", companyId, month, cancellationToken) ?? new DashboardActions();
        var events = await Many<DashboardEvent>("EVENTS", companyId, month, cancellationToken);
        var activity = await Many<DashboardActivity>("ACTIVITY", companyId, month, cancellationToken);

        return new DashboardData
        {
            MonthStart = month,
            Kpis = kpis,
            Trend = trend,
            Companies = companies,
            Departments = departments,
            Payroll = payroll,
            Actions = actions,
            Events = events,
            Activity = activity
        };
    }

    private string? _companyIds;

    private Task<T?> One<T>(string action, int? companyId, DateTime month, CancellationToken ct) =>
        _sql.QuerySingleOrDefaultAsync<T>(StoredProcedure.DashboardGet, Parameters(action, companyId, _companyIds, month), ct);

    private Task<IReadOnlyList<T>> Many<T>(string action, int? companyId, DateTime month, CancellationToken ct) =>
        _sql.QueryAsync<T>(StoredProcedure.DashboardGet, Parameters(action, companyId, _companyIds, month), ct);

    private static DynamicParameters Parameters(string action, int? companyId, string? companyIds, DateTime month)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Action", action, DbType.AnsiString, size: 10);
        parameters.Add("@CompanyId", companyId, DbType.Int32);
        parameters.Add("@CompanyIds", companyIds, DbType.String, size: 2000);   // db/24
        parameters.Add("@MonthStart", month, DbType.Date);
        return parameters;
    }
}
