//==============================================================================
//  Areas/POS/POSAreaRegistration.cs
//------------------------------------------------------------------------------
//  Registers the POS Area. MVC discovers this automatically via
//  AreaRegistration.RegisterAllAreas() in Global.asax.cs -- confirm that call
//  is present in Application_Start; if it is not, add it BEFORE the existing
//  RouteConfig registration, or none of the /POS routes will resolve.
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\POSAreaRegistration.cs" />
//==============================================================================

using System.Web.Mvc;

namespace Jar.Areas.POS
{
    public class POSAreaRegistration : AreaRegistration
    {
        public override string AreaName { get { return "POS"; } }

        public override void RegisterArea(AreaRegistrationContext context)
        {
            context.MapRoute(
                name: "POS_default",
                url: "POS/{controller}/{action}/{id}",
                defaults: new { controller = "Dashboard", action = "Index", id = UrlParameter.Optional },
                namespaces: new[] { "Jar.Areas.POS.Controllers" }   // stops the router picking
            );                                                       // a same-named root controller
        }
    }
}
