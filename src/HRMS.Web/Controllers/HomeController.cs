using System.Diagnostics;
using HRMS.Web.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

public sealed class HomeController : Controller
{
    /// <summary>The Dashboard is the landing page; this keeps /Home working.</summary>
    public IActionResult Index() => RedirectToAction("Index", "Launcher");

    // Anonymous: the error page must never send to the login page - when the login page
    // itself fails, that went login -> error -> login ... until the address was too long (IIS 404.15)
    [AllowAnonymous]
    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error() =>
        View(new ErrorViewModel
        {
            RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier
        });
}
