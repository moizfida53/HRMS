using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Routing;

namespace Jar
{
    public class RouteConfig
    {
        public static void RegisterRoutes(RouteCollection routes)
        {
            routes.IgnoreRoute("{resource}.axd/{*pathInfo}");
            
            //routes.MapMvcAttributeRoutes();

            var Theme= System.Configuration.ConfigurationManager.AppSettings["DesignTheme"].ToString();
            //if (Theme.ToString() == "Design2" || Theme.ToString() == "Design3" || Theme.ToString() == "Design4")
            if (Theme.ToString() == "Design1" || Theme.ToString() == "Design2" || Theme.ToString() == "Design3" || Theme.ToString() == "Design4")
            {
                //routes.MapRoute(
                //    name: "brand",
                //    url: "brand/{name}",
                //    defaults: new { controller = "ItemsViewNew", action = "brand", name = UrlParameter.Optional }
                //);
                routes.MapRoute(
                   name: "Login",
                   url: "Login",
                   defaults: new { controller = "Login", action = "Index"}
               );
                routes.MapRoute(
                   name: "Category",
                   url: "Category",
                   defaults: new { controller = "Category", action = "Index" }
               );
                routes.MapRoute(
                  name: "BranchReservation",
                  url: "BranchReservation",
                  defaults: new { controller = "BranchReservation", action = "IndexNew" }
              );
                routes.MapRoute(
                  "waiterWithName",
                  url: "Waiter/{name}",
                  //"brand/{name}",
                  //"{name}",
                  new { controller = "Waiter", action = "Index", name = UrlParameter.Optional }
              //defaults: new { controller = "ItemsViewNew", action = "brand", name = UrlParameter.Optional }
              );
               // routes.MapRoute(
               //    name: "Waiter",
               //    url: "Waiter",
               //    defaults: new { controller = "Waiter", action = "Index" }
               //);

                //routes.MapRoute(
                //    name: "ItemsViewNew",
                //    url: "{controller}/{action}/{id}",
                //    defaults: new { controller = "ItemsViewNew", action = "Index", id = UrlParameter.Optional }
                //);
                routes.MapRoute(
                   "Default",
                   //url: "brand/{name}",
                   //"brand/{name}",
                   "{name}",
                   new { controller = "ItemsViewNew", action = "brand", name = UrlParameter.Optional }
                   //defaults: new { controller = "ItemsViewNew", action = "brand", name = UrlParameter.Optional }
               );

                routes.MapRoute(
                   "SendMailtoExpiredBrands",
                   url: "{controller}/{action}/{id}",
                   new { controller = "ItemsViewNew", action = "SendMailtoExpiredBrands", name = UrlParameter.Optional }
                   //defaults: new { controller = "ItemsViewNew", action = "brand", name = UrlParameter.Optional }
               );

                routes.MapRoute(
                     name: "Default1",
                     url: "{controller}/{action}/{id}",
                     //defaults: new { controller = "Home", action = "Index", id = UrlParameter.Optional }
                     defaults: new { controller = "ItemsViewNew", action = "Index", id = UrlParameter.Optional }
                 );



                //routes.MapRoute(
                //    name: "Default",
                //    url: "ItemsViewNew",
                //    defaults: new { controller = "ItemsViewNew", action = "Index", id = UrlParameter.Optional }
                //);
            }
            else
            {
                    routes.MapRoute(
                    name: "Default",
                    url: "{controller}/{action}/{id}",
                    //defaults: new { controller = "Home", action = "Index", id = UrlParameter.Optional }
                    defaults: new { controller = "ItemsView", action = "Index", id = UrlParameter.Optional }
                );
            }
            //routes.MapRoute(
            //    "ItemsView",
            //    "ItemsView/{action}/{id}",
            //    new { controller = "Inventory", action = "Index" }
            //);
        }
    }
}