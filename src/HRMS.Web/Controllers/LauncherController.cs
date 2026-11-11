using System.Globalization;
using HRMS.Web.Areas.Items.Legacy;
using HRMS.Web.Areas.POS;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// The page every user lands on after signing in ("/" and "/apps"): one tile per
/// application (AccessCatalog.Apps). A tile is shown when one of the user's roles
/// has that app ticked under Security > Create Roles > App access (permission code
/// APP_*, db/103); SYSTEM_ADMIN sees all of them. A tile without an address is a
/// module still being moved over from the old QR Menu project ("Coming soon").
/// The tile only decides what /apps shows - every application still checks its
/// own rights when it is opened.
/// </summary>
public sealed class LauncherController : Controller
{
    private const string OnlineOrderCode = "APP_ONLINE_ORDER";

    private static readonly AppItem SelfServiceTile = new(
        "ess", "APP_ESS", "Self Service", "Punch in and out, your attendance, annual leave and profile.", "clock", "/ess/");

    [HttpGet("/")]
    [HttpGet("/apps")]
    public IActionResult Index(string? notice)
    {
        var (permissions, isAdmin) = Rights();
        var tiles = AccessCatalog.Apps.Where(a => isAdmin || permissions.Contains(a.Code)).ToList();

        // Employee Self Service (/ess, db/146): every user linked to an employee - their own
        // punch, attendance, annual leave and profile, so no role right is needed.
        if (User.HasClaim(c => c.Type == HrmsClaims.EmployeeId))
        {
            tiles.Insert(0, SelfServiceTile);
        }

        ViewData["Title"] = "Apps";
        ViewData["Notice"] = notice == "online-order"
            ? "No branch is set up for your account yet, so the online order menu cannot open. Ask an administrator to assign you a brand and a branch."
            : null;
        return View(tiles);
    }

    /// <summary>
    /// Online Order: opens the customer menu ("/?id=&lt;BrandID&gt;,&lt;BranchID&gt;", the
    /// address in the QR codes) for the user's brand - their first POS branch
    /// (tblPOS_UserBranch_Map), else the brand's first active branch.
    /// </summary>
    [HttpGet("/apps/online-order")]
    public IActionResult OnlineOrder()
    {
        var (permissions, isAdmin) = Rights();
        if (!isAdmin && !permissions.Contains(OnlineOrderCode)) return Forbid();

        POSUser? pos = null;
        try { pos = POSUser.For(HttpContext); } catch { /* database not ready: no branch */ }

        var brandId = pos?.BrandID ?? 0;
        var mapped = pos?.BranchIDs ?? new List<int>();
        var mappedCsv = string.Join(",", mapped.Select(b => b.ToString(CultureInfo.InvariantCulture)));

        // ints only - nothing from the request reaches the SQL text
        var where = "ISNULL(b.IsDeleted, 0) = 0 AND ISNULL(b.IsActive, 1) = 1";
        if (brandId > 0)
            where += " AND b.brandId = " + brandId.ToString(CultureInfo.InvariantCulture);
        else if (!isAdmin)
            where += mapped.Count > 0 ? " AND b.id IN (" + mappedCsv + ")" : " AND 1 = 0";

        var mappedFirst = mapped.Count > 0 ? "CASE WHEN b.id IN (" + mappedCsv + ") THEN 0 ELSE 1 END, " : "";

        try
        {
            var ds = DB.GetData(
                "SELECT TOP (1) BranchID = b.id, BrandID = b.brandId FROM dbo.tblbranch b " +
                "WHERE " + where + " ORDER BY " + mappedFirst + "ISNULL(b.SEQ_NUM, 2147483647), b.id;");

            if (ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0)
            {
                var row = ds.Tables[0].Rows[0];
                var brand = Convert.ToInt32(row["BrandID"], CultureInfo.InvariantCulture);
                var branch = Convert.ToInt32(row["BranchID"], CultureInfo.InvariantCulture);
                return Redirect(FormattableString.Invariant($"/?id={brand},{branch}"));
            }
        }
        catch
        {
            // QR Menu tables missing: fall through to the notice
        }

        return Redirect("/apps?notice=online-order");
    }

    private (HashSet<string> Permissions, bool IsAdmin) Rights()
    {
        var permissions = User.FindAll(HrmsClaims.Permission).Select(c => c.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return (permissions, permissions.Contains("SYSTEM_ADMIN"));
    }
}
