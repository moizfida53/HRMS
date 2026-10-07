using System.Diagnostics;
using HRMS.Web.Models;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

public sealed class HomeController : Controller
{
    /// <summary>The Dashboard is the landing page; this keeps /Home working.</summary>
    public IActionResult Index() => RedirectToAction("Index", "Dashboard");

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error() =>
        View(new ErrorViewModel
        {
            RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier
        });
}
