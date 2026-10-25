using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.DataProtection;

namespace HRMS.Web.Security;

/// <summary>
/// Keeps record identifiers out of the address bar.
/// <para>
/// The pages that open one record (an employee, a payroll, a settlement, a payslip ...)
/// are never reached with the id in the URL. A link or form to one of them is posted to
/// <c>POST /go</c> (site.js does it for every link and GET form on its own), which keeps
/// the full address in a short-lived, encrypted ticket cookie and answers with a
/// redirect to the page's clean address (e.g. <c>/employees/profile</c>). That request
/// takes the ticket and is served as the full address - the ticket is used up.
/// </para>
/// <para>
/// So the address bar only ever shows the clean address; typing an id into it, an old
/// bookmark, or reloading the page (the ticket is gone) opens the page's starting
/// screen instead. Server redirects to such a page (RedirectToAction(..., new { run }))
/// are turned into tickets the same way. Background (fetch) requests are not affected:
/// they never show in the address bar and the server checks the user's rights on each.
/// </para>
/// </summary>
public static class PageNavigation
{
    /// <summary>A page that takes record identifiers, its clean address, and where it goes without them.</summary>
    /// <param name="Landing">Where the clean address goes without a ticket; null = serve the page itself (its starting screen).</param>
    public sealed record Rule(Regex Pattern, string Clean, string? Landing, bool IdInPath);

    private static Rule R(string pattern, string clean, string? landing = null, bool idInPath = false) =>
        new(new Regex("^" + pattern + "$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled),
            clean, landing, idInPath);

    /// <summary>
    /// Every page that opens records by id or reference. A page also matches with no id
    /// at all (its clean address) - that is the starting screen.
    /// </summary>
    public static readonly IReadOnlyList<Rule> Rules =
    [
        R(@"/employees/profile/\d+", "/employees/profile", "/employees", idInPath: true),
        R(@"/employees/profile", "/employees/profile", "/employees"),
        R(@"/audit", "/audit"),
        R(@"/payroll/accounting/journal/view", "/payroll/accounting/journal/view", "/payroll/accounting/journal"),
        R(@"/payroll/bank/file", "/payroll/bank/file"),
        R(@"/payroll/bank/register", "/payroll/bank/register"),
        R(@"/payroll/settlement/encashment", "/payroll/settlement/encashment"),
        R(@"/payroll/settlement/new", "/payroll/settlement/new"),
        R(@"/payroll/settlement/\d+", "/payroll/settlement/details", "/payroll/settlement", idInPath: true),
        R(@"/payroll/settlement/details", "/payroll/settlement/details", "/payroll/settlement"),
        R(@"/payroll/settlement/\d+/statement", "/payroll/settlement/statement", "/payroll/settlement", idInPath: true),
        R(@"/payroll/settlement/statement", "/payroll/settlement/statement", "/payroll/settlement"),
        R(@"/payroll/pay-items", "/payroll/pay-items"),
        R(@"/payroll/pay-periods", "/payroll/pay-periods"),
        R(@"/payroll/create", "/payroll/create"),
        R(@"/payroll/run/\d+", "/payroll/run", "/payroll/payrolls", idInPath: true),
        R(@"/payroll/run", "/payroll/run", "/payroll/payrolls"),
        R(@"/payroll/register", "/payroll/register"),
        R(@"/payroll/validation", "/payroll/validation"),
        R(@"/payroll/approval", "/payroll/approval"),
        R(@"/payroll/compare", "/payroll/compare"),
        R(@"/payroll/reports/[a-z0-9-]+", "", null),                 // clean = its own path (department filter)
        R(@"/payroll/payslips/generate", "/payroll/payslips/generate"),
        R(@"/payroll/payslips/employees", "/payroll/payslips/employees"),
        R(@"/payroll/payslips/email", "/payroll/payslips/email"),
        R(@"/payroll/payslips/view/[^/]+", "/payroll/payslips/view", "/payroll/payslips/employees", idInPath: true),
        R(@"/payroll/payslips/view", "/payroll/payslips/view", "/payroll/payslips/employees"),
        R(@"/payroll/payslips/my/[^/]+", "/payroll/payslips/slip", "/payroll/payslips/my", idInPath: true),
        R(@"/payroll/payslips/slip", "/payroll/payslips/slip", "/payroll/payslips/my"),
        R(@"/security/roles", "/security/roles"),
        R(@"/leave", "/leave"),
        R(@"/organizations", "/organizations"),
        R(@"/leave/document", "/leave/document", "/leave")
    ];

    /// <summary>The rule for a path, or null when the page takes no identifiers.</summary>
    public static Rule? Find(PathString path)
    {
        var value = path.Value ?? "";
        if (value.Length > 1) value = value.TrimEnd('/');
        // exports and downloads below a reports page are files, not pages
        if (value.EndsWith("/export", StringComparison.OrdinalIgnoreCase)) return null;
        return Rules.FirstOrDefault(r => r.Pattern.IsMatch(value));
    }

    /// <summary>The clean address of a path under <paramref name="rule"/>.</summary>
    public static string CleanOf(Rule rule, PathString path) =>
        rule.Clean.Length > 0 ? rule.Clean : (path.Value ?? "/").TrimEnd('/');

    /// <summary>The address carries something to hide: an id in the path or anything in the query.</summary>
    public static bool CarriesParameters(Rule rule, PathString path, QueryString query) =>
        rule.IdInPath || (query.HasValue && query.Value!.Length > 1);

    /// <summary>The rules for site.js: which links and GET forms go through POST /go.</summary>
    public static string ClientRulesJson() =>
        JsonSerializer.Serialize(Rules.Select(r => new { p = r.Pattern.ToString(), id = r.IdInPath }));
}

/// <summary>The short-lived tickets: the full address of a page, kept in an encrypted cookie.</summary>
public sealed class NavigationTickets
{
    private const string CookieName = "Hrms-Nav";
    private const int MaxTickets = 6;
    private static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(2);

    private readonly ITimeLimitedDataProtector _protector;

    public NavigationTickets(IDataProtectionProvider provider) =>
        _protector = provider.CreateProtector("HRMS.PageNavigation.v1").ToTimeLimitedDataProtector();

    private sealed record Ticket(string Clean, string Url, long Expires);

    private List<Ticket> Read(HttpContext context)
    {
        var raw = context.Request.Cookies[CookieName];
        if (string.IsNullOrEmpty(raw)) return [];
        try
        {
            var list = JsonSerializer.Deserialize<List<Ticket>>(_protector.Unprotect(raw)) ?? [];
            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            return list.Where(t => t.Expires > now).ToList();
        }
        catch (Exception)
        {
            return [];   // altered or expired: no tickets
        }
    }

    private void Write(HttpContext context, List<Ticket> tickets)
    {
        if (tickets.Count == 0)
        {
            context.Response.Cookies.Delete(CookieName, new CookieOptions { Path = "/" });
            return;
        }
        var payload = _protector.Protect(JsonSerializer.Serialize(tickets), Lifetime);
        context.Response.Cookies.Append(CookieName, payload, new CookieOptions
        {
            HttpOnly = true,
            Secure = context.Request.IsHttps,
            SameSite = SameSiteMode.Lax,
            Path = "/",
            IsEssential = true,
            MaxAge = Lifetime
        });
    }

    /// <summary>Keeps <paramref name="url"/> (a local page address) and returns its clean address.</summary>
    public string Issue(HttpContext context, PageNavigation.Rule rule, PathString path, string url)
    {
        var clean = PageNavigation.CleanOf(rule, path);
        var tickets = Read(context);
        tickets.Add(new Ticket(clean, url, DateTimeOffset.UtcNow.Add(Lifetime).ToUnixTimeSeconds()));
        if (tickets.Count > MaxTickets) tickets.RemoveRange(0, tickets.Count - MaxTickets);
        Write(context, tickets);
        return clean;
    }

    /// <summary>Takes (uses up) the oldest ticket for <paramref name="clean"/>; null when there is none.</summary>
    public string? Take(HttpContext context, string clean)
    {
        var tickets = Read(context);
        var ticket = tickets.FirstOrDefault(t => string.Equals(t.Clean, clean, StringComparison.OrdinalIgnoreCase));
        if (ticket is null) return null;
        tickets.Remove(ticket);
        Write(context, tickets);
        return ticket.Url;
    }
}

/// <summary>
/// Serves a clean page address from its ticket, refuses an address with identifiers typed
/// into the address bar, and turns server redirects to such addresses into tickets.
/// Runs before routing, so the rewritten address is what the controllers see.
/// </summary>
public sealed class PageNavigationMiddleware
{
    private readonly RequestDelegate _next;
    private readonly NavigationTickets _tickets;

    public PageNavigationMiddleware(RequestDelegate next, NavigationTickets tickets)
    {
        _next = next;
        _tickets = tickets;
    }

    /// <summary>A browser navigation (address bar, link, form, frame) - not a fetch from page script.</summary>
    private static bool IsNavigation(HttpRequest request)
    {
        var mode = request.Headers["Sec-Fetch-Mode"].ToString();
        if (mode.Length > 0) return string.Equals(mode, "navigate", StringComparison.OrdinalIgnoreCase);
        // older browsers: page script marks its own requests
        return !string.Equals(request.Headers["X-Requested-With"], "XMLHttpRequest", StringComparison.OrdinalIgnoreCase);
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var request = context.Request;

        if (HttpMethods.IsGet(request.Method) && IsNavigation(request) && PageNavigation.Find(request.Path) is { } rule)
        {
            var clean = PageNavigation.CleanOf(rule, request.Path);

            if (PageNavigation.CarriesParameters(rule, request.Path, request.QueryString))
            {
                // typed / bookmarked / pasted: never served from the address bar - the starting screen instead
                context.Response.Redirect(request.PathBase + (rule.Landing ?? clean));
                return;
            }

            if (_tickets.Take(context, clean) is { } url)
            {
                var q = url.IndexOf('?');
                request.Path = q < 0 ? url : url[..q];
                request.QueryString = q < 0 ? QueryString.Empty : new QueryString(url[q..]);
            }
            else if (rule.Landing is not null)
            {
                // reloaded, or opened without a record: where the record pages start
                context.Response.Redirect(request.PathBase + rule.Landing);
                return;
            }
        }

        // a redirect to a page with identifiers becomes a ticket + its clean address
        context.Response.OnStarting(() =>
        {
            var response = context.Response;
            if (response.StatusCode is >= 300 and < 400 && response.Headers.Location.ToString() is { Length: > 0 } location
                && Local(context, location) is { } local && Split(local) is var (path, query)
                && PageNavigation.Find(path) is { } target && PageNavigation.CarriesParameters(target, path, query))
            {
                response.Headers.Location = context.Request.PathBase + _tickets.Issue(context, target, path, local);
            }
            return Task.CompletedTask;
        });

        await _next(context);
    }

    /// <summary>The local address (path + query, without the path base) of a redirect, or null for another site.</summary>
    internal static string? Local(HttpContext context, string location)
    {
        // "/x" first: on Linux Uri also reads it as an absolute file:// address
        if (!location.StartsWith('/') && Uri.TryCreate(location, UriKind.Absolute, out var absolute))
        {
            if (absolute.Scheme is not ("http" or "https")) return null;
            if (!string.Equals(absolute.Authority, context.Request.Host.Value, StringComparison.OrdinalIgnoreCase)) return null;
            location = absolute.PathAndQuery;
        }
        if (!location.StartsWith('/') || location.StartsWith("//") || location.StartsWith("/\\")) return null;
        var pathBase = context.Request.PathBase.Value ?? "";
        if (pathBase.Length > 0 && location.StartsWith(pathBase, StringComparison.OrdinalIgnoreCase))
        {
            location = location[pathBase.Length..];
            if (!location.StartsWith('/')) location = "/" + location;
        }
        return location;
    }

    internal static (PathString Path, QueryString Query) Split(string local)
    {
        var hash = local.IndexOf('#');
        if (hash >= 0) local = local[..hash];
        var q = local.IndexOf('?');
        return q < 0 ? (new PathString(local), QueryString.Empty) : (new PathString(local[..q]), new QueryString(local[q..]));
    }
}

public static class PageNavigationExtensions
{
    public static IServiceCollection AddPageNavigation(this IServiceCollection services) =>
        services.AddSingleton<NavigationTickets>();

    public static IApplicationBuilder UsePageNavigation(this IApplicationBuilder app) =>
        app.UseMiddleware<PageNavigationMiddleware>();
}
