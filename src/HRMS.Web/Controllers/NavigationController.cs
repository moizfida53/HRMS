using HRMS.Web.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// POST /go: opens a page that takes record identifiers without putting them in the
/// address bar (see <see cref="PageNavigation"/>). site.js posts every link and GET form
/// to such a page here; the answer is a redirect to the page's clean address, or - for
/// page script (?json) - that address, e.g. to load it in a frame.
/// </summary>
[Authorize]
public sealed class NavigationController : Controller
{
    private readonly NavigationTickets _tickets;

    public NavigationController(NavigationTickets tickets) => _tickets = tickets;

    [HttpPost("/go")]
    public IActionResult Go([FromForm] string? url, [FromQuery] bool json = false)
    {
        var local = string.IsNullOrWhiteSpace(url) ? null : PageNavigationMiddleware.Local(HttpContext, url.Trim());
        if (local is null) return BadRequest();

        var (path, query) = PageNavigationMiddleware.Split(local);
        var target = local;
        if (PageNavigation.Find(path) is { } rule && PageNavigation.CarriesParameters(rule, path, query))
        {
            target = _tickets.Issue(HttpContext, rule, path, path + query);
        }

        target = Request.PathBase + target;
        return json ? Json(new { url = target }) : new RedirectResult(target) { PreserveMethod = false };
    }
}
