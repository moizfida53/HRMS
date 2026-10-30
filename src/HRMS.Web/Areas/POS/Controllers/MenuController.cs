using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Areas.POS.Controllers
{
    /// <summary>The POS "Menu" drawer entry is the Item Management page itself.</summary>
    [POSAuthorize(POSPermission.ManageMasters)]
    public class MenuController : PosController
    {
        public IActionResult Index() => Redirect("/Category/Index");
    }
}
