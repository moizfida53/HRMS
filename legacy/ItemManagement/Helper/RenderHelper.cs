//==============================================================================
//  Helper/RenderHelper.cs
//------------------------------------------------------------------------------
//  Renders a partial view to a string so it can be returned inside a JSON
//  response. The Dashboard's detail tabs work this way: one AJAX call brings
//  back both the chart data and the HTML the chart sits in, so the tab appears
//  in one step rather than flashing an empty panel first.
//
//  Add to the .csproj:
//      <Compile Include="Helper\RenderHelper.cs" />
//==============================================================================

using System;
using System.IO;
using System.Web.Mvc;

namespace Jar.Helper
{
    public static class RenderHelper
    {
        /// <summary>
        /// viewName may be a name the view engine can find, or a full path
        /// beginning "~/". A path is the safer form from an Area: the engine
        /// searches Area folders first and can surprise you otherwise.
        /// </summary>
        public static string PartialView(Controller controller, string viewName, object model)
        {
            controller.ViewData.Model = model;

            using (var sw = new StringWriter())
            {
                ViewEngineResult result = ViewEngines.Engines
                    .FindPartialView(controller.ControllerContext, viewName);

                if (result.View == null)
                    throw new InvalidOperationException(
                        "Partial view '" + viewName + "' was not found. Searched: "
                        + string.Join(", ", result.SearchedLocations ?? new string[0]));

                var ctx = new ViewContext(controller.ControllerContext, result.View,
                                          controller.ViewData, controller.TempData, sw);

                result.View.Render(ctx, sw);
                result.ViewEngine.ReleaseView(controller.ControllerContext, result.View);

                return sw.GetStringBuilder().ToString();
            }
        }
    }
}
