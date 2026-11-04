using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Web.Security;
using Microsoft.Extensions.Caching.Memory;

namespace HRMS.Web.Services;

/// <summary>One kind of record waiting for the user's approval, ready for the sidebar and the side alert.</summary>
public sealed record ApprovalNotice(string Kind, int Count, DateTime? Oldest, string TitleKey, string Icon, string Url);

/// <summary>Everything waiting for the user's approval (empty when nothing is, or the user approves nothing).</summary>
public sealed record ApprovalSummary(IReadOnlyList<ApprovalNotice> Items)
{
    public static readonly ApprovalSummary Empty = new(Array.Empty<ApprovalNotice>());

    public int Total => Items.Sum(i => i.Count);

    /// <summary>The count of a kind (PAYROLL, SALREV, EARN, DED, LOAN, SETTLEMENT, LEAVE); 0 = none.</summary>
    public int For(string kind) => Items.FirstOrDefault(i => i.Kind == kind)?.Count ?? 0;

    /// <summary>The four Payroll Components pages together (db/111).</summary>
    public int Components => For("SALREV") + For("EARN") + For("DED") + For("LOAN");

    /// <summary>The count of a sidebar sub-section (its slug); 0 = none.</summary>
    public int ForSlug(string slug) => slug switch
    {
        "payrolls" => For("PAYROLL"),
        "pc-salary" => For("SALREV"),
        "pc-earnings" => For("EARN"),
        "pc-deductions" => For("DED"),
        "pc-loans" => For("LOAN"),
        _ => 0
    };

    /// <summary>Changes whenever a count changes - the side alert closed with × stays closed until then.</summary>
    public string Signature => string.Join("|", Items.Select(i => $"{i.Kind}:{i.Count}"));
}

/// <summary>
/// What waits for the signed-in user's approval (db/110): payrolls, pay items, final settlements
/// and leave requests, each at the levels the user's rights allow (a record they submitted only
/// with the SELF right; leave level 1 also for the employee's line manager). Shown as badges in
/// the sidebar, on the bell and in the side alert after sign-in. Cached for a few seconds per user
/// and company filter; IPayrollNavCounts.Invalidate() refreshes it too.
/// </summary>
public interface IApprovalNotifications
{
    Task<ApprovalSummary> GetAsync(CancellationToken cancellationToken = default);
}

public sealed class ApprovalNotifications : IApprovalNotifications
{
    private static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(15);

    private readonly IApprovalRepository _approvals;
    private readonly ICurrentUser _user;
    private readonly ICompanyFilter _companyFilter;
    private readonly IMemoryCache _cache;
    private readonly ILogger<ApprovalNotifications> _logger;
    private ApprovalSummary? _request;   // one query per request, however often the layout asks

    public ApprovalNotifications(IApprovalRepository approvals, ICurrentUser user, ICompanyFilter companyFilter,
                                 IMemoryCache cache, ILogger<ApprovalNotifications> logger)
    {
        _approvals = approvals;
        _user = user;
        _companyFilter = companyFilter;
        _cache = cache;
        _logger = logger;
    }

    public async Task<ApprovalSummary> GetAsync(CancellationToken cancellationToken = default)
    {
        if (_request is not null) return _request;
        if (!_user.IsAuthenticated || _user.UserId is not { } userId) return _request = ApprovalSummary.Empty;

        bool Can(string code) => _user.HasPermission(code);
        var rights = new PendingApprovalRights
        {
            UserId = userId,
            EmployeeId = _user.EmployeeId,
            CompanyId = _user.ActiveCompanyId,
            CompanyIds = _companyFilter.Csv,
            PayrollL1 = Can("PAYROLL_RUN_APPROVE_HR"), PayrollL2 = Can("PAYROLL_RUN_APPROVE_FINANCE"), PayrollSelf = Can("PAYROLL_RUN_APPROVE_SELF"),
            // db/111: one approval per Payroll Components page (limited to the user's item types in the procedure)
            SalRevL1 = Can("PAYROLL_SALREV_APPROVE_L1"), SalRevL2 = Can("PAYROLL_SALREV_APPROVE_L2"), SalRevSelf = Can("PAYROLL_SALREV_APPROVE_SELF"),
            EarnL1 = Can("PAYROLL_EARN_APPROVE_L1"), EarnL2 = Can("PAYROLL_EARN_APPROVE_L2"), EarnSelf = Can("PAYROLL_EARN_APPROVE_SELF"),
            DedL1 = Can("PAYROLL_DED_APPROVE_L1"), DedL2 = Can("PAYROLL_DED_APPROVE_L2"), DedSelf = Can("PAYROLL_DED_APPROVE_SELF"),
            LoanL1 = Can("PAYROLL_LOAN_APPROVE_L1"), LoanL2 = Can("PAYROLL_LOAN_APPROVE_L2"), LoanSelf = Can("PAYROLL_LOAN_APPROVE_SELF"),
            IsAdmin = Can("SYSTEM_ADMIN"),
            SettlementL1 = Can("PAYROLL_FS_APPROVE_L1"), SettlementL2 = Can("PAYROLL_FS_APPROVE_L2"), SettlementSelf = Can("PAYROLL_FS_APPROVE_SELF"),
            LeaveL1 = Can("LEAVE_APPROVE_L1"), LeaveL2 = Can("LEAVE_APPROVE_L2"), LeaveSelf = Can("LEAVE_APPROVE_SELF")
        };

        var key = $"hrms:approvals:{userId}:{rights.CompanyId}:{rights.CompanyIds}";
        if (_cache.TryGetValue(key, out ApprovalSummary? cached) && cached is not null) return _request = cached;

        try
        {
            var rows = await _approvals.PendingAsync(rights, cancellationToken).ConfigureAwait(false);
            var items = rows.Where(r => r.Count > 0).Select(r => r.Kind switch
            {
                "PAYROLL" => new ApprovalNotice(r.Kind, r.Count, r.Oldest, "ap.kind_payroll", "calculator", "/payroll/payrolls?stage=AWAITING_APPROVAL"),
                "SALREV" => new ApprovalNotice(r.Kind, r.Count, r.Oldest, "ap.kind_salrev", "trend", "/payroll/components/salary?status=PENDING"),
                "EARN" => new ApprovalNotice(r.Kind, r.Count, r.Oldest, "ap.kind_earn", "percent", "/payroll/components/earnings?status=PENDING"),
                "DED" => new ApprovalNotice(r.Kind, r.Count, r.Oldest, "ap.kind_ded", "wallet", "/payroll/components/deductions?status=PENDING"),
                "LOAN" => new ApprovalNotice(r.Kind, r.Count, r.Oldest, "ap.kind_loan", "inbox", "/payroll/components/loans?status=PENDING"),
                "SETTLEMENT" => new ApprovalNotice(r.Kind, r.Count, r.Oldest, "ap.kind_settlement", "exit", "/payroll/settlement?status=PENDING"),
                "LEAVE" => new ApprovalNotice(r.Kind, r.Count, r.Oldest, "ap.kind_leave", "calendar", "/leave?status=MINE"),
                _ => null
            }).OfType<ApprovalNotice>().ToList();

            var summary = items.Count == 0 ? ApprovalSummary.Empty : new ApprovalSummary(items);
            _cache.Set(key, summary, new MemoryCacheEntryOptions()
                .SetAbsoluteExpiration(CacheFor)
                .AddExpirationToken(PayrollNavCounts.ChangeToken()));
            return _request = summary;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // never break a page over the badges (db/110 not run yet, database busy ...)
            _logger.LogWarning(ex, "Pending approvals could not be counted (run db/110).");
            return _request = ApprovalSummary.Empty;
        }
    }
}
