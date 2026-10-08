using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Security;
using Microsoft.Extensions.Caching.Memory;

namespace HRMS.Web.Services;

/// <summary>The figures next to the payroll sub-sections in the sidebar (null = the user may not see it).</summary>
public sealed record PayrollNavCountsResult(
    int? OpenPayrolls, int? Calendars, int? OpenPeriods,
    int? PayslipsToGenerate = null, int? PayslipsGenerated = null, int? PayslipsToEmail = null,
    int? BankFilesToMake = null, int? PaymentsOpen = null, int? JournalsToMake = null, int? JournalsToPost = null)
{
    /// <summary>The figure of a sub-section (its slug), or null when it has none.</summary>
    public int? For(string slug) => slug switch
    {
        "payrolls" => OpenPayrolls,
        "calendars" => Calendars,
        "pay-periods" => OpenPeriods,
        "slip-generate" => PayslipsToGenerate,
        "slip-employee" => PayslipsGenerated,
        "slip-email" => PayslipsToEmail,
        "bk-file" => BankFilesToMake,
        "bk-register" => PaymentsOpen,
        "ac-journal" => JournalsToMake,
        "ac-posting" => JournalsToPost,
        _ => null
    };
}

public interface IPayrollNavCounts
{
    /// <summary>
    /// Open payrolls (Registered / Validation / Awaiting approval), active payroll
    /// calendars, open periods of this year (Open / Processing), payslips to
    /// generate, payslips generated and payslip emails to send - for the
    /// companies the user is looking at. Cached for a few seconds per user and
    /// company filter, so every page view does not query the database three times.
    /// </summary>
    Task<PayrollNavCountsResult?> GetAsync(CancellationToken cancellationToken = default);

    /// <summary>Drops every cached figure - call after a change (a payroll created or moved, payslips generated or emailed).</summary>
    void Invalidate();
}

public sealed class PayrollNavCounts : IPayrollNavCounts
{
    private static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(20);

    // Every cached figure expires with this token; Invalidate() swaps it for a new one.
    private static CancellationTokenSource _reset = new();

    private readonly IPayrollRunRepository _runs;
    private readonly IPayrollCalendarRepository _calendars;
    private readonly IPayslipRepository _payslips;
    private readonly IPayrollFinanceRepository _finance;
    private readonly ICurrentUser _user;
    private readonly ICompanyFilter _companyFilter;
    private readonly IMemoryCache _cache;
    private readonly ILogger<PayrollNavCounts> _logger;

    public PayrollNavCounts(IPayrollRunRepository runs, IPayrollCalendarRepository calendars, IPayslipRepository payslips,
                            IPayrollFinanceRepository finance, ICurrentUser user,
                            ICompanyFilter companyFilter, IMemoryCache cache, ILogger<PayrollNavCounts> logger)
    {
        _runs = runs;
        _calendars = calendars;
        _payslips = payslips;
        _finance = finance;
        _user = user;
        _companyFilter = companyFilter;
        _cache = cache;
        _logger = logger;
    }

    public async Task<PayrollNavCountsResult?> GetAsync(CancellationToken cancellationToken = default)
    {
        var canRuns = _user.HasPermission("PAYROLL_RUN_VIEW");
        var canSetup = canRuns || _user.HasPermission("PAYROLL_SETUP_VIEW");
        var canSlips = _user.HasPermission("PAYROLL_SLIP_VIEW") || _user.HasPermission("PAYROLL_SLIP_GENERATE")
                       || _user.HasPermission("PAYROLL_SLIP_EMAIL");
        var canBank = _user.HasPermission("PAYROLL_BANK_VIEW") || _user.HasPermission("PAYROLL_BANK_PROCESS");
        var canGl = _user.HasPermission("PAYROLL_GL_VIEW") || _user.HasPermission("PAYROLL_GL_POST");
        if (!_user.IsAuthenticated || (!canSetup && !canSlips && !canBank && !canGl))
        {
            return null;
        }

        var companyId = _user.ActiveCompanyId;
        var companyCsv = _companyFilter.Csv;
        var key = $"hrms:payroll-nav:{_user.UserId}:{companyId}:{companyCsv}:{canRuns}:{canSetup}:{canSlips}:{canBank}:{canGl}";
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

            int? calendarCount = null, openPeriods = null;
            if (canSetup)
            {
                var calendars = await _calendars.ListAsync(new GridRequest
                {
                    CompanyId = companyId, CompanyIds = companyCsv, IsActive = true, PageSize = 200
                }, cancellationToken).ConfigureAwait(false);
                calendarCount = calendars.TotalCount;
                openPeriods = 0;
                foreach (var calendar in calendars.Items)
                {
                    var periods = await _calendars.PeriodsAsync(calendar.PayrollCalendarId, DateTime.Today.Year, openableOnly: false, cancellationToken)
                                                  .ConfigureAwait(false);
                    openPeriods += periods.Count(p => p.Status is "OPEN" or "PROCESSING");
                }
            }

            PayslipNavCounts? slips = null;
            if (canSlips)
            {
                slips = await _payslips.NavCountsAsync(companyId, companyCsv, cancellationToken).ConfigureAwait(false) ?? new PayslipNavCounts();
            }

            FinanceNavCounts? finance = null;
            if (canBank || canGl)
            {
                finance = await _finance.NavCountsAsync(companyId, companyCsv, cancellationToken).ConfigureAwait(false) ?? new FinanceNavCounts();
            }

            var result = new PayrollNavCountsResult(openPayrolls, calendarCount, openPeriods,
                                                    slips?.ToGenerateCount, slips?.GeneratedCount, slips?.ToEmailCount,
                                                    canBank ? finance?.BankFilesToMake : null, canBank ? finance?.PaymentsOpen : null,
                                                    canGl ? finance?.JournalsToMake : null, canGl ? finance?.JournalsToPost : null);
            _cache.Set(key, result, new MemoryCacheEntryOptions()
                .SetAbsoluteExpiration(CacheFor)
                .AddExpirationToken(new Microsoft.Extensions.Primitives.CancellationChangeToken(Volatile.Read(ref _reset).Token)));
            return result;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // The sidebar must never break a page - show it without figures.
            _logger.LogWarning(ex, "Payroll sidebar counts could not be loaded.");
            return null;
        }
    }

    public void Invalidate()
    {
        var old = Interlocked.Exchange(ref _reset, new CancellationTokenSource());
        old.Cancel();
        old.Dispose();
    }
}
