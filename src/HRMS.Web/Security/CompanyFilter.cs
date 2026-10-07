using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;

namespace HRMS.Web.Security;

/// <summary>
/// The company filter in the top bar. The choice lives in a cookie
/// (<see cref="CookieName"/>: "all" or comma-separated CompanyIds), so it
/// follows the user from page to page - Dashboard, Employees, Setup grids -
/// without being picked again. A user whose account is tied to one company
/// (ICurrentUser.ActiveCompanyId) is always locked to that company,
/// whatever the cookie says.
/// </summary>
public interface ICompanyFilter
{
    /// <summary>Selected company ids; empty means all companies.</summary>
    IReadOnlyList<int> SelectedIds { get; }

    /// <summary>"1,3" for the procedures' @CompanyIds, or null for all companies.</summary>
    string? Csv { get; }

    /// <summary>The one selected company, when exactly one is selected (used as the default for new records).</summary>
    int? SingleCompanyId { get; }

    /// <summary>True when the user's account is tied to one company and cannot change the filter.</summary>
    bool IsLocked { get; }

    /// <summary>Companies offered in the dropdown (empty if they could not be loaded).</summary>
    Task<IReadOnlyList<LookupItem>> GetCompaniesAsync(CancellationToken cancellationToken = default);

    /// <summary>"All companies", the company name, or "3 companies".</summary>
    Task<string> GetLabelAsync(CancellationToken cancellationToken = default);
}

public sealed class CookieCompanyFilter : ICompanyFilter
{
    public const string CookieName = "hrms_companies";
    private const int MaxSelected = 50;

    private readonly ILookupRepository _lookups;
    private readonly ILogger<CookieCompanyFilter> _logger;
    private IReadOnlyList<LookupItem>? _companies;

    public CookieCompanyFilter(
        IHttpContextAccessor http, ICurrentUser currentUser,
        ILookupRepository lookups, ILogger<CookieCompanyFilter> logger)
    {
        _lookups = lookups;
        _logger = logger;

        if (currentUser.ActiveCompanyId is { } own)
        {
            IsLocked = true;
            SelectedIds = [own];
            return;
        }

        var raw = http.HttpContext?.Request.Cookies[CookieName];
        SelectedIds = Parse(raw);
    }

    public IReadOnlyList<int> SelectedIds { get; }

    public bool IsLocked { get; }

    public string? Csv => SelectedIds.Count == 0
        ? null
        : string.Join(',', SelectedIds.Select(id => id.ToString(CultureInfo.InvariantCulture)));

    public int? SingleCompanyId => SelectedIds.Count == 1 ? SelectedIds[0] : null;

    public async Task<IReadOnlyList<LookupItem>> GetCompaniesAsync(CancellationToken cancellationToken = default)
    {
        if (_companies is not null)
        {
            return _companies;
        }

        try
        {
            _companies = await _lookups.GetAsync(LookupType.Company, cancellationToken: cancellationToken);
        }
        catch (Exception ex)
        {
            // The layout renders this on every page (including the error page) -
            // a lookup failure must never take the whole page down.
            _logger.LogWarning(ex, "Company list for the top-bar filter could not be loaded.");
            _companies = Array.Empty<LookupItem>();
        }

        return _companies;
    }

    public async Task<string> GetLabelAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedIds.Count == 0)
        {
            return "All companies";
        }

        if (SelectedIds.Count == 1)
        {
            var companies = await GetCompaniesAsync(cancellationToken);
            return companies.FirstOrDefault(c => c.Id == SelectedIds[0])?.Text ?? "1 company";
        }

        return $"{SelectedIds.Count} companies";
    }

    private static IReadOnlyList<int> Parse(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw) || raw.Equals("all", StringComparison.OrdinalIgnoreCase))
        {
            return Array.Empty<int>();
        }

        return Uri.UnescapeDataString(raw)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => int.TryParse(part, NumberStyles.None, CultureInfo.InvariantCulture, out var id) ? id : 0)
            .Where(id => id > 0)
            .Distinct()
            .Take(MaxSelected)
            .ToList();
    }
}
