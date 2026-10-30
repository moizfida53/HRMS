using System.Security.Claims;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// The page every user lands on after signing in: one tile per application
/// (POS, HR, Payroll, Setup, Settings, Security, Printer Setup, Item Management).
/// A tile is shown only when the user holds a permission for that application;
/// SYSTEM_ADMIN sees all of them. Tiles without an address yet are modules still
/// being moved over from the old QR Menu project - they show "Coming soon".
/// </summary>
[Route("apps")]
public sealed class LauncherController : Controller
{
    public sealed record AppTile(string Key, string Title, string Description, string Icon, string? Url);

    [HttpGet("")]
    public IActionResult Index()
    {
        var permissions = User.FindAll(HrmsClaims.Permission).Select(c => c.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
        var isAdmin = permissions.Contains("SYSTEM_ADMIN");

        bool Any(params string[] prefixes) =>
            isAdmin || permissions.Any(p => prefixes.Any(x => p.StartsWith(x, StringComparison.OrdinalIgnoreCase)));

        // QR Menu roles carry the RoleCode "QR_<old role number>" (merge script 02).
        var hasQrRole = isAdmin || roles.Any(r => r.StartsWith("QR_", StringComparison.OrdinalIgnoreCase));

        var tiles = new List<AppTile>();
        if (Any("POS_"))
            tiles.Add(new("pos", "POS", "Orders, Dine-In tables, payments and the order dashboard.", "card", null));
        if (Any("EMPLOYEE_", "LEAVE_", "ASSET_"))
            tiles.Add(new("hr", "HR", "Employees, compliance documents, leave and assets.", "users", Url.Action("Index", "Employees")));
        if (Any("PAYROLL_", "PAYCOMPONENT_"))
            tiles.Add(new("payroll", "Payroll", "Pay items, payroll runs, payslips and final settlement.", "wallet", Url.Action("Index", "PayrollDashboard")));
        if (Any("ORGANIZATION_", "ORG_"))
            tiles.Add(new("setup", "Setup", "Companies, branches, departments and other masters.", "building", Url.Action("Index", "Organization")));
        if (hasQrRole)
            tiles.Add(new("settings", "Settings", "Menu theme, tab theme, slide shows and labels.", "sliders", null));
        if (Any("SECURITY_", "AUDIT_"))
            tiles.Add(new("security", "Security", "Users, roles, permissions and the audit report.", "shield", Url.Action("Users", "Security")));
        if (Any("POS_"))
            tiles.Add(new("printers", "Printer Setup", "Kitchen and receipt printers, and the restaurant hubs.", "printer", null));
        if (hasQrRole)
            tiles.Add(new("items", "Item Management", "Categories, items, modifiers, allergens and images.", "layers", "/Category/Index"));

        ViewData["Title"] = "Apps";
        return View(tiles);
    }
}
