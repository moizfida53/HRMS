using HRMS.Data.Repositories;
using HRMS.Domain.Security;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Account;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HRMS.Web.Controllers;

[Route("account")]
public sealed class AccountController : Controller
{
    private readonly ISignInService _signIn;
    private readonly ILocalizationRepository _localization;
    private readonly ICurrentUser _currentUser;
    private readonly ILogger<AccountController> _logger;

    public AccountController(
        ISignInService signIn,
        ILocalizationRepository localization,
        ICurrentUser currentUser,
        ILogger<AccountController> logger)
    {
        _signIn = signIn;
        _localization = localization;
        _currentUser = currentUser;
        _logger = logger;
    }

    // =======================================================================
    // GET /account/login
    // =======================================================================

    [AllowAnonymous]
    [HttpGet("login")]
    public IActionResult Login(string? returnUrl = null, string? reason = null)
    {
        // Already signed in? Skip the form.
        if (User.Identity?.IsAuthenticated == true)
        {
            return RedirectToLocal(returnUrl);
        }

        var model = new LoginViewModel
        {
            ReturnUrl = SafeReturnUrl(returnUrl),
            InfoMessage = reason switch
            {
                "signedout" => "You have been signed out.",
                "timeout"   => "Your session expired. Please sign in again.",
                "denied"    => null,
                _           => null
            }
        };

        // Input tag helpers prefer ModelState over the model, and the raw
        // ?returnUrl= value is already in ModelState from binding the action
        // parameter. Without this, the hidden field would render the caller's
        // unsanitised string - including an off-site URL that SafeReturnUrl had
        // just rejected. The POST path re-validates too, but the form should
        // never carry a value the server has already refused.
        ModelState.Clear();

        return View(model);
    }

    // =======================================================================
    // POST /account/login
    // =======================================================================

    /// <summary>
    /// Rate limited by IP - see the "login" policy in Program.cs. This is the
    /// outer defence against credential stuffing; the per-account lockout in
    /// the database is the inner one.
    /// </summary>
    [AllowAnonymous]
    [HttpPost("login")]
    [ValidateAntiForgeryToken]
    [EnableRateLimiting("login")]
    public async Task<IActionResult> Login(LoginViewModel model)
    {
        model.ReturnUrl = SafeReturnUrl(model.ReturnUrl);

        if (!ModelState.IsValid)
        {
            return View(model);
        }

        var result = await _signIn.PasswordSignInAsync(
            model.Username, model.Password, model.RememberMe, HttpContext.RequestAborted);

        if (result.Succeeded)
        {
            // The user's saved language (Security.Users.PreferredLanguage) wins
            // over whatever was picked on the sign-in page.
            await ApplyPreferredLanguageAsync(result.User!.UserId);

            if (result.Outcome == LoginOutcome.MustChangePassword)
            {
                // Let the user in; the layout shows a standing banner with a
                // "Change password" button (account menu > Change password)
                // until the initial password is replaced.
                TempData["MustChangePassword"] = true;
            }

            return RedirectToLocal(model.ReturnUrl);
        }

        // Every failure returns the same wording. Telling the user which part was
        // wrong would confirm that a username exists.
        model.ErrorMessage = result.Outcome switch
        {
            LoginOutcome.AccountLockedOut => BuildLockoutMessage(result.LockoutEndUtc),
            LoginOutcome.AccountInactive  => "That account is not active. Contact your HR administrator.",
            _                             => "The username or password is incorrect."
        };

        // Never redisplay the password.
        model.Password = string.Empty;
        ModelState.Remove(nameof(LoginViewModel.Password));

        return View(model);
    }

    // =======================================================================
    // POST /account/logout
    // =======================================================================

    /// <summary>
    /// POST only. A GET sign-out can be triggered by an image tag on any other
    /// site, which is a nuisance-level CSRF.
    /// </summary>
    [HttpPost("logout")]
    [ValidateAntiForgeryToken]
    [Authorize]
    public async Task<IActionResult> Logout()
    {
        await _signIn.SignOutAsync();
        return RedirectToAction(nameof(Login), new { reason = "signedout" });
    }

    // =======================================================================
    // POST /account/change-password   (Change Password dialog, account menu)
    // =======================================================================

    /// <summary>
    /// Called with fetch() from the dialog in _Layout; answers in the same
    /// ActionResponse JSON shape as every other AJAX save in the app.
    /// Rate limited like sign-in, since it also checks a password.
    /// </summary>
    [HttpPost("change-password")]
    [ValidateAntiForgeryToken]
    [Authorize]
    [EnableRateLimiting("login")]
    public async Task<IActionResult> ChangePassword(ChangePasswordViewModel model)
    {
        if (!ModelState.IsValid)
        {
            return Json(ActionResponse.Invalid(
                ModelState
                    .Where(entry => entry.Value?.Errors.Count > 0)
                    .ToDictionary(
                        entry => entry.Key,
                        entry => entry.Value!.Errors.Select(e => e.ErrorMessage).ToArray())));
        }

        var result = await _signIn.ChangePasswordAsync(
            model.CurrentPassword, model.NewPassword, HttpContext.RequestAborted);

        return result.Outcome switch
        {
            ChangePasswordOutcome.Changed =>
                Json(ActionResponse.Ok(0, "Password changed. You stay signed in here; other sessions have been signed out.")),

            ChangePasswordOutcome.WrongCurrentPassword =>
                Json(ActionResponse.Invalid(new Dictionary<string, string[]>
                {
                    [nameof(ChangePasswordViewModel.CurrentPassword)] = ["The current password is incorrect."]
                })),

            ChangePasswordOutcome.LockedOut =>
                Json(ActionResponse.Failed(BuildLockoutMessage(result.LockoutEndUtc), "LOCKED_OUT")),

            _ => Json(ActionResponse.Failed("Your session has ended. Sign in again, then change your password.", "NOT_SIGNED_IN"))
        };
    }

    // =======================================================================
    // GET /account/denied
    // =======================================================================

    // Reachable whether or not the visitor is signed in - an authenticated
    // user without the right permission lands here just as an anonymous
    // one does when a [Authorize(Policy = ...)] check fails.
    [AllowAnonymous]
    [HttpGet("denied")]
    public IActionResult Denied() => View();

    // =======================================================================
    // POST /account/language   (EN / AR toggle in the top bar and sign-in page)
    // =======================================================================

    /// <summary>
    /// Switches the UI language and reloads the page the user was on. Signed-in
    /// users have the choice saved to Security.Users.PreferredLanguage, so it
    /// follows them to the next sign-in on any device.
    /// </summary>
    [AllowAnonymous]
    [HttpPost("language")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SetLanguage(string? lang, string? returnUrl = null)
    {
        var language = Language.Normalize(lang);
        Language.WriteCookie(HttpContext, language);

        // Chosen on the sign-in page: remembered for this browser session so
        // the sign-in that follows saves it as the user's preference.
        if (User.Identity?.IsAuthenticated != true)
        {
            Response.Cookies.Append(Language.ChosenCookieName, "1", new CookieOptions
            {
                HttpOnly = true, IsEssential = true, SameSite = SameSiteMode.Lax, Secure = Request.IsHttps
            });
        }

        if (User.Identity?.IsAuthenticated == true && _currentUser.UserId is { } userId)
        {
            try
            {
                await _localization.SetUserLanguageAsync(userId, language, HttpContext.RequestAborted);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // The cookie already carries the choice for this browser.
                _logger.LogWarning(ex, "Could not save the preferred language for user {UserId}.", userId);
            }
        }

        return RedirectToLocal(returnUrl);
    }

    // =======================================================================
    // helpers
    // =======================================================================

    private async Task ApplyPreferredLanguageAsync(long userId)
    {
        try
        {
            // Language picked on the sign-in page just now -> becomes the saved
            // preference. Otherwise the saved preference wins over the cookie.
            if (Request.Cookies.ContainsKey(Language.ChosenCookieName))
            {
                Response.Cookies.Delete(Language.ChosenCookieName);
                var chosen = Language.Normalize(Request.Cookies[Language.CookieName]);
                await _localization.SetUserLanguageAsync(userId, chosen, HttpContext.RequestAborted);
                return;
            }

            var saved = await _localization.GetUserLanguageAsync(userId, HttpContext.RequestAborted);
            if (!string.IsNullOrWhiteSpace(saved))
            {
                Language.WriteCookie(HttpContext, saved);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Could not read the preferred language for user {UserId}.", userId);
        }
    }

    private static string BuildLockoutMessage(DateTime? lockoutEndUtc)
    {
        if (!lockoutEndUtc.HasValue)
        {
            return "This account is temporarily locked after too many failed attempts.";
        }

        var minutes = (int)Math.Ceiling((lockoutEndUtc.Value - DateTime.UtcNow).TotalMinutes);
        minutes = Math.Max(minutes, 1);

        // Two fixed sentences rather than a pluralised one, so each has an exact
        // Arabic counterpart in Core.UiLabels.
        return minutes == 1
            ? "This account is locked after too many failed attempts. Try again in 1 minute."
            : $"This account is locked after too many failed attempts. Try again in {minutes} minutes.";
    }

    /// <summary>
    /// Only local URLs are ever honoured, so a crafted ?returnUrl= cannot bounce
    /// a freshly authenticated user to an attacker's site.
    /// </summary>
    private string? SafeReturnUrl(string? returnUrl) =>
        !string.IsNullOrWhiteSpace(returnUrl) && Url.IsLocalUrl(returnUrl) ? returnUrl : null;

    private IActionResult RedirectToLocal(string? returnUrl) =>
        !string.IsNullOrWhiteSpace(returnUrl) && Url.IsLocalUrl(returnUrl)
            ? Redirect(returnUrl)
            : RedirectToAction("Index", "Dashboard");
}
