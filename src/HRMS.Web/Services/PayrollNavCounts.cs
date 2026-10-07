using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Security;
using Microsoft.Extensions.Caching.Memory;

namespace HRMS.Web.Services;

/// <summary>The figures next to Payroll Processing's sub-sections in the sidebar (null = the user may not see it).</summary>
public sealed record PayrollNavCountsResult(int? OpenPayrolls, int? Calendars, int? OpenPeriods);

public interface IPayrollNavCounts
{
    /// <summary>
    /// Open payrolls (Registered / Validation / Awaiting approval), active payroll
    /// calendars and open periods of this year (Open / Processing) - for the
    /// companies the user is looking at. Cached for a few seconds per user and
    /// company filter, so every page view does not query the database three times.
    /// </summary>
    Task<PayrollNavCountsResult?> GetAsync(CancellationToken cancellationToken = default);
}

public sealed class PayrollNavCounts : IPayrollNavCounts
{
    private static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(20);

    private readonly IPayrollRunRepository _runs;
    private readonly IPayrollCalendarRepository _calendars;
    private readonly ICurrentUser _user;
    private readonly ICompanyFilter _companyFilter;
    private readonly IMemoryCache _cache;
    private readonly ILogger<PayrollNavCounts> _logger;

    public PayrollNavCounts(IPayrollRunRepository runs, IPayrollCalendarRepository calendars, ICurrentUser user,
                            ICompanyFilter companyFilter, IMemoryCache cache, ILogger<PayrollNavCounts> logger)
    {
        _runs = runs;
        _calendars = calendars;
        _user = user;
        _companyFilter = companyFilter;
        _cache = cache;
        _logger = logger;
    }

    public async Task<PayrollNavCountsResult?> GetAsync(CancellationToken cancellationToken = default)
    {
        var canRuns = _user.HasPermission("PAYROLL_RUN_VIEW");
        var canSetup = canRuns || _user.HasPermission("PAYROLL_SETUP_VIEW");
        if (!_user.IsAuthenticated || !canSetup)
        {
            return null;
        }

        var companyId = _user.ActiveCompanyId;
        var companyCsv = _companyFilter.Csv;
        var key = $"hrms:payroll-nav:{_user.UserId}:{companyId}:{companyCsv}:{canRuns}";
        if (_cache.TryGetValue(key, out PayrollNavCountsResult? cached))
        {
            return cached;
        }

        try
        {
            int? openPayrolls = null;
            if (canRuns)
            {
                var live = await _runs.ListAsync(new RunListFilter
                {
                    CompanyId = companyId, CompanyIds = companyCsv, Stage = "LIVE", PageSize = 1
                }, cancellationToken).ConfigureAwait(false);
                openPayrolls = live.TotalCount;
            }

            var calendars = await _calendars.ListAsync(new GridRequest
            {
                CompanyId = companyId, CompanyIds = companyCsv, IsActive = true, PageSize = 200
            }, cancellationToken).ConfigureAwait(false);

            var openPeriods = 0;
            foreach (var calendar in calendars.Items)
            {
                var periods = await _calendars.PeriodsAsync(calendar.PayrollCalendarId, DateTime.Today.Year, openableOnly: false, cancellationToken)
                                              .ConfigureAwait(false);
                openPeriods += periods.Count(p => p.Status is "OPEN" or "PROCESSING");
            }

            var result = new PayrollNavCountsResult(openPayrolls, calendars.TotalCount, openPeriods);
            _cache.Set(key, result, CacheFor);
            return result;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // The sidebar must never break a page - show it without figures.
            _logger.LogWarning(ex, "Payroll sidebar counts could not be loaded.");
            return null;
        }
    }
}
