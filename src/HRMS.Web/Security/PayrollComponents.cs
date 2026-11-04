using HRMS.Data.Repositories;
using HRMS.Domain.Payroll;

namespace HRMS.Web.Security;

/// <summary>
/// Payroll Components (db/111): the four pages that replace Pay Items. The salary of the
/// employment contract is the default component (no approval, db/107); each page holds the
/// exceptions of one class and has its own rights and approval:
/// PAYROLL_{Prefix}_VIEW / _EDIT / _DELETE / _APPROVE_L1 / _APPROVE_L2 / _APPROVE_SELF.
/// </summary>
public sealed record ComponentPage(string ItemClass, string Slug, string Route, string Prefix, string Title, string TitleKey,
                                   string SubtitleKey, string Icon, string ApprovalKind)
{
    public string View => $"PAYROLL_{Prefix}_VIEW";
    public string Edit => $"PAYROLL_{Prefix}_EDIT";
    public string Delete => $"PAYROLL_{Prefix}_DELETE";
    public string ApproveL1 => $"PAYROLL_{Prefix}_APPROVE_L1";
    public string ApproveL2 => $"PAYROLL_{Prefix}_APPROVE_L2";
    public string ApproveSelf => $"PAYROLL_{Prefix}_APPROVE_SELF";
    public string Url => $"/payroll/components/{Route}";
}

public static class PayrollComponents
{
    public static readonly IReadOnlyList<ComponentPage> Pages =
    [
        new(ItemClass.Salary, "pc-salary", "salary", "SALREV", "Salary Revisions", "pc.salary", "pc.salary_sub", "trend", "SALREV"),
        new(ItemClass.Earning, "pc-earnings", "earnings", "EARN", "Earnings & Allowances", "pc.earnings", "pc.earnings_sub", "percent", "EARN"),
        new(ItemClass.Deduction, "pc-deductions", "deductions", "DED", "Deductions", "pc.deductions", "pc.deductions_sub", "wallet", "DED"),
        new(ItemClass.Loan, "pc-loans", "loans", "LOAN", "Loans & Advances", "pc.loans", "pc.loans_sub", "inbox", "LOAN")
    ];

    public static ComponentPage? ForClass(string? cls) => Pages.FirstOrDefault(p => p.ItemClass == cls);
    public static ComponentPage? ForRoute(string? route) => Pages.FirstOrDefault(p => string.Equals(p.Route, route, StringComparison.OrdinalIgnoreCase));
    public static ComponentPage? ForSlug(string? slug) => Pages.FirstOrDefault(p => p.Slug == slug);
}

/// <summary>What the user may do on one Payroll Components page.</summary>
public sealed class ComponentScope
{
    public required ComponentPage Page { get; init; }
    public bool CanView { get; init; }
    public bool CanEdit { get; init; }
    public bool CanDelete { get; init; }
    public bool CanApproveL1 { get; init; }
    public bool CanApproveL2 { get; init; }
    public bool CanApproveOwn { get; init; }
    /// <summary>The item types (codes) the user is limited to; null = every type of the page.</summary>
    public IReadOnlySet<string>? AllowedCodes { get; init; }

    public bool Allows(string? componentCode) =>
        AllowedCodes is null || (componentCode is not null && AllowedCodes.Contains(componentCode));
}

/// <summary>The user's rights on the Payroll Components pages, worked out once per request.</summary>
public interface IComponentAccess
{
    Task<ComponentScope> ForAsync(string itemClass, CancellationToken cancellationToken = default);
    /// <summary>The first page the user may open (null = none).</summary>
    Task<ComponentPage?> FirstPageAsync(CancellationToken cancellationToken = default);
}

public sealed class ComponentAccess : IComponentAccess
{
    private readonly ICurrentUser _user;
    private readonly IComponentRightsRepository _rights;
    private readonly ILogger<ComponentAccess> _logger;
    private Dictionary<string, HashSet<string>?>? _types;   // class -> codes (null = every type)

    public ComponentAccess(ICurrentUser user, IComponentRightsRepository rights, ILogger<ComponentAccess> logger)
    {
        _user = user;
        _rights = rights;
        _logger = logger;
    }

    private bool IsAdmin => _user.HasPermission("SYSTEM_ADMIN") || _user.IsInRole("SYSADMIN");

    public async Task<ComponentScope> ForAsync(string itemClass, CancellationToken cancellationToken = default)
    {
        var page = PayrollComponents.ForClass(itemClass) ?? PayrollComponents.Pages[1];
        bool Can(string code) => _user.HasPermission(code);
        var view = Can(page.View);
        HashSet<string>? allowed = null;
        if (view && !IsAdmin)
        {
            var types = await TypesAsync(cancellationToken);
            allowed = types.TryGetValue(page.ItemClass, out var set) ? set : null;
        }
        return new ComponentScope
        {
            Page = page,
            CanView = view,
            CanEdit = view && Can(page.Edit),
            CanDelete = view && Can(page.Delete),
            CanApproveL1 = view && Can(page.ApproveL1),
            CanApproveL2 = view && Can(page.ApproveL2),
            CanApproveOwn = IsAdmin || Can(page.ApproveSelf),
            AllowedCodes = allowed
        };
    }

    public Task<ComponentPage?> FirstPageAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult(PayrollComponents.Pages.FirstOrDefault(p => _user.HasPermission(p.View)));

    private async Task<Dictionary<string, HashSet<string>?>> TypesAsync(CancellationToken cancellationToken)
    {
        if (_types is not null) return _types;
        var map = new Dictionary<string, HashSet<string>?>(StringComparer.Ordinal);
        if (_user.UserId is { } userId)
        {
            try
            {
                foreach (var g in await _rights.UserTypesAsync(userId, cancellationToken))
                {
                    if (g.Unrestricted) { map[g.ItemClass] = null; continue; }
                    if (map.TryGetValue(g.ItemClass, out var set) && set is null) continue;
                    if (set is null) map[g.ItemClass] = set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    if (g.ComponentCode is not null) set.Add(g.ComponentCode);
                }
                // a page the query does not return at all: the user has the right through a
                // permission claim only (e.g. SYSTEM_ADMIN) - every type
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogWarning(ex, "Item type limits could not be read (run db/111) - every item type is offered.");
            }
        }
        return _types = map;
    }
}
