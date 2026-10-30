using System.Security.Claims;
using HRMS.Web.Areas.POS;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// The page every user lands on after signing in ("/" and "/apps"): one tile per
/// application. A tile is shown only when the user has access to that
/// application; SYSTEM_ADMIN sees all of them. A tile without an address is a
/// module still being moved over from the old QR Menu project ("Coming soon").
/// </summary>
public sealed class LauncherController : Controller
{
    public sealed record AppTile(string Key, string Title, string Description, string Icon, string? Url);

    [HttpGet("/")]
    [HttpGet("/apps")]
    public IActionResult Index()
    {
        var permissions = User.FindAll(HrmsClaims.Permission).Select(c => c.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
        var isAdmin = permissions.Contains("SYSTEM_ADMIN");

        bool Any(params string[] prefixes) =>
            isAdmin || permissions.Any(p => prefixes.Any(x => p.StartsWith(x, StringComparison.OrdinalIgnoreCase)));

        // QR Menu roles carry the RoleCode "QR_<old role number>" (merge script 02).
        var hasQrRole = isAdmin || roles.Any(r => r.StartsWith("QR_", StringComparison.OrdinalIgnoreCase));

        // POS access comes from the user's QR role flags and POS_* permissions (Areas/POS/POSAuth.cs).
        POSUser? pos = null;
        try { pos = POSUser.For(HttpContext); } catch { /* database not ready: POS tiles hidden */ }
        var hasPos = isAdmin || pos?.HasAnyPosAccess == true;
        var posAdmin = isAdmin || pos?.CanManageMasters == true;

        // The HRMS dashboard is open to anyone with an HRMS permission or an employee record.
        var hasHrms = Any("EMPLOYEE_", "LEAVE_", "PAYROLL_", "PAYCOMPONENT_", "PAYSLIP_", "ORGANIZATION_", "ORG_",
                          "ASSET_", "SECURITY_", "AUDIT_", "DASHBOARD_")
                      || !string.IsNullOrEmpty(User.FindFirstValue(HrmsClaims.EmployeeId));

        var tiles = new List<AppTile>();
        if (hasHrms)
            tiles.Add(new("hrms", "HRMS", "Employees, leave, payroll, payslips and company setup.", "users", "/dashboard"));
        if (hasPos)
            tiles.Add(new("pos", "POS", "Dine-In tables, take away and online orders, payments and the order dashboard.", "card", "/POS/DineIn"));
        if (Any("ASSET_"))
            tiles.Add(new("assets", "Assets", "Company assets, who holds them and their history.", "box", "/assets"));
        if (hasQrRole)
            tiles.Add(new("feedback", "Feedback", "Customer feedback from the QR menu, by question and branch.", "message", "/FeedBackReport/Index"));
        if (hasQrRole)
            tiles.Add(new("menucolors", "Menu Colors", "Menu design, colours and banner images, with a live preview.", "palette", "/MenuColors/Index"));
        if (hasQrRole)
            tiles.Add(new("items", "Item Management", "Categories, items, modifiers, allergens and images.", "layers", "/Category/Index"));
        if (posAdmin)
            tiles.Add(new("printers", "Printer Setup", "Kitchen and receipt printers of each branch.", "printer", "/POS/Print"));
        if (hasQrRole)
            tiles.Add(new("settings", "Settings", "Tab theme, slide shows and menu labels.", "tool", null));
        if (Any("SECURITY_", "AUDIT_"))
            tiles.Add(new("security", "Security", "Roles, permissions, user accounts and the audit report.", "shield", "/security/roles"));
        if (posAdmin)
            tiles.Add(new("users", "Users", "Restaurant staff: POS role, branches and POS password.", "user", "/POS/Users"));

        ViewData["Title"] = "Apps";
        return View(tiles);
    }
}
