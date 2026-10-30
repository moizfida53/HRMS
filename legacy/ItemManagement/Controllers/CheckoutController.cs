using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace Jar.Controllers
{
    public class CheckoutController : Controller
    {
        //
        // GET: /Checkout/

        public ActionResult Index(string CartDetails,int? BrandId, int? Branchid)
        {
            return View();
        }

    }
}
