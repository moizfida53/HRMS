using HRMS.Data.Repositories;
using HRMS.Domain.Payroll;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;

namespace HRMS.Web.Services;

/// <summary>
/// db/123: one workspace per payroll. Builds the header of a payroll's pages (the payroll,
/// its stage Registered … Approved, Execution, Completed, and the tabs that are open at
/// that stage), adds the pay-out status to the payrolls shown in a list, and saves the
/// status after a pay-out action. Until db/123 is run, everything still works without
/// the pay-out status (a closed payroll is shown as Approved).
/// </summary>
public interface IPayrollWorkspace
{
    /// <summary>The header of a payroll's page; null when the payroll does not exist or is out of the user's scope.</summary>
    Task<WorkspaceNav?> NavAsync(long runId, string tab, CancellationToken cancellationToken = default);
    /// <summary>The header for a payroll already loaded (Register / Validation / Approval).</summary>
    Task<WorkspaceNav> NavAsync(PayrollRun run, IReadOnlyList<PayrollRun> runs, string tab, bool canCancel, CancellationToken cancellationToken = default);
    /// <summary>Sets PayoutStatus (and Payout) on the closed payrolls of a list.</summary>
    Task MergeAsync(IEnumerable<PayrollRun> runs, CancellationToken cancellationToken = default);
    Task<PayoutCounts?> CountsAsync(CancellationToken cancellationToken = default);
    /// <summary>Saves the pay-out status of a payroll (null = every closed payroll in scope) after an action.</summary>
    Task SyncAsync(long? runId, CancellationToken cancellationToken = default);
    /// <summary>True when the payroll, or the payroll of one of the payments, is completed - read-only.</summary>
    Task<bool> IsLockedAsync(long? runId, IEnumerable<long>? paymentIds = null, CancellationToken cancellationToken = default);
}

public sealed class PayrollWorkspace : IPayrollWorkspace
{
    private readonly IPayrollRunRepository _runs;
    private readonly IPayoutRepository _payout;
    private readonly ICurrentUser _user;
    private readonly ICompanyFilter _companyFilter;
    private readonly ILogger<PayrollWorkspace> _logger;

    public PayrollWorkspace(IPayrollRunRepository runs, IPayoutRepository payout, ICurrentUser user, ICompanyFilter companyFilter,
                            ILogger<PayrollWorkspace> logger)
    {
        _runs = runs;
        _payout = payout;
        _user = user;
        _companyFilter = companyFilter;
        _logger = logger;
    }

    private int? OwnCompany => _user.ActiveCompanyId;
    private string? CompanyCsv => _companyFilter.Csv;

    public async Task<WorkspaceNav?> NavAsync(long runId, string tab, CancellationToken cancellationToken = default)
    {
        var run = await _runs.GetAsync(runId, cancellationToken).ConfigureAwait(false);
        if (run is null || run.Stage == RunStage.Draft) return null;
        if (OwnCompany is { } own && run.CompanyId != own) return null;
        if (_companyFilter.SelectedIds.Count > 0 && OwnCompany is null && !_companyFilter.SelectedIds.Contains(run.CompanyId)) return null;

        var list = await _runs.ListAsync(new RunListFilter { CompanyId = OwnCompany, CompanyIds = CompanyCsv, PageSize = 60 }, cancellationToken)
                              .ConfigureAwait(false);
        var runs = list.Items.Where(r => !r.IsCancelled || r.PayrollRunId == run.PayrollRunId).ToList();
        if (runs.All(r => r.PayrollRunId != run.PayrollRunId)) runs.Insert(0, run);
        return await NavAsync(run, runs, tab, canCancel: false, cancellationToken).ConfigureAwait(false);
    }

    public async Task<WorkspaceNav> NavAsync(PayrollRun run, IReadOnlyList<PayrollRun> runs, string tab, bool canCancel,
                                             CancellationToken cancellationToken = default)
    {
        await MergeAsync(runs.Append(run), cancellationToken).ConfigureAwait(false);
        return new WorkspaceNav
        {
            Run = run,
            Runs = runs,
            Tab = tab,
            Payout = run.Payout,
            CanCancel = canCancel,
            CanSlips = _user.HasPermission("PAYROLL_SLIP_VIEW") || _user.HasPermission("PAYROLL_SLIP_GENERATE") || _user.HasPermission("PAYROLL_SLIP_EMAIL"),
            CanBank = _user.HasPermission("PAYROLL_BANK_VIEW") || _user.HasPermission("PAYROLL_BANK_PROCESS"),
            CanCollections = _user.HasPermission("PAYROLL_COLL_VIEW"),
            CanGl = _user.HasPermission("PAYROLL_GL_VIEW") || _user.HasPermission("PAYROLL_GL_POST")
        };
    }

    public async Task MergeAsync(IEnumerable<PayrollRun> runs, CancellationToken cancellationToken = default)
    {
        var closed = runs.Where(r => r.IsClosed).GroupBy(r => r.PayrollRunId).ToDictionary(g => g.Key, g => g.ToList());
        if (closed.Count == 0) return;
        try
        {
            foreach (var p in await _payout.ListAsync(closed.Keys, OwnCompany, CompanyCsv, cancellationToken).ConfigureAwait(false))
            {
                if (!closed.TryGetValue(p.PayrollRunId, out var same)) continue;
                foreach (var r in same)
                {
                    r.PayoutStatus = p.PayoutStatus;
                    r.Payout = p;
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // db/123 not run yet: closed payrolls are shown as Approved
            _logger.LogWarning(ex, "The pay-out status could not be read (run db/123).");
        }
    }

    public async Task<PayoutCounts?> CountsAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            return await _payout.CountsAsync(OwnCompany, CompanyCsv, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "The pay-out counts could not be read (run db/123).");
            return null;
        }
    }

    public async Task SyncAsync(long? runId, CancellationToken cancellationToken = default)
    {
        try
        {
            await _payout.SyncAsync(runId, OwnCompany, CompanyCsv, _user.UserId, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "The pay-out status could not be saved (run db/123).");
        }
    }

    public async Task<bool> IsLockedAsync(long? runId, IEnumerable<long>? paymentIds = null, CancellationToken cancellationToken = default)
    {
        try
        {
            return await _payout.IsLockedAsync(runId, paymentIds, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "The pay-out lock could not be read (run db/123).");
            return false;
        }
    }
}
