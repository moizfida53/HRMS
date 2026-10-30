//==============================================================================
//  Areas/POS/Controllers/MenuController.cs
//------------------------------------------------------------------------------
//  Item Management (categories + items) inside the POS panel.
//
//  This controller owns NO functionality of its own. It renders the existing
//  ~/Views/Category/Index.cshtml unchanged, and every AJAX call that view
//  makes still goes to the original Jar.Controllers.CategoryController - the
//  URLs in ~/MainJs/Category.js are root-relative ("/Category/GetBrands" and
//  so on), so they are unaffected by which area the page was served from.
//  Nothing is duplicated: one view, one set of endpoints, one JS file.
//
//  What is different here is the chrome and who may see it:
//      * POS chrome/palette, via _LayoutPOSAdmin (the view picks its layout
//        based on the area - see the top of Index.cshtml).
//      * [POSAuthorize(POSPermission.ManageMasters)], so only a role with the
//        Settings/User Management permission - today just Administrator -
//        can open it. The classic /Category route is untouched and still
//        behaves exactly as it did.
//
//  Named "Menu" rather than "Category" on purpose. A second CategoryController
//  would collide with Jar.Controllers.CategoryController on the root routes,
//  which carry no namespace constraint, and MVC answers that with
//  "Multiple types were found that match the controller named 'Category'".
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Controllers\MenuController.cs" />
//==============================================================================

using System;
using System.Web.Mvc;

namespace Jar.Areas.POS.Controllers
{
    [POSAuthorize(POSPermission.ManageMasters)]
    public class MenuController : Controller
    {
        public ActionResult Index()
        {
            // Category.js and the view reference images as "../Images/...".
            // Those resolve against the PAGE URL, so this page only works one
            // directory deep: at /POS/Menu, "../Images/x" is /Images/x, but at
            // /POS/Menu/Index it becomes /POS/Images/x and every icon 404s.
            // Rather than rewrite 46 asset paths in shared files, send any
            // other spelling of this URL to the canonical one.
            //
            // Compared against Url.Action rather than a literal "/POS/Menu":
            // under a virtual directory the real path is "/app/POS/Menu", and
            // a literal would never match it - redirecting forever.
            string canonical = Url.Action("Index", "Menu", new { area = "POS" });
            if (!string.Equals(Request.Path, canonical, StringComparison.OrdinalIgnoreCase))
                return Redirect(canonical);

            ViewBag.User = POSUser.Current;

            // The view itself, straight from its original location.
            return View("~/Views/Category/Index.cshtml");
        }
    }
}
