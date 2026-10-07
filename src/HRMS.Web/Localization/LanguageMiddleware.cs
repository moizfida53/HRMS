using System.Globalization;

namespace HRMS.Web.Localization;

/// <summary>
/// Applies the user's language to the request: the Hrms-Lang cookie (written
/// at sign-in from Security.Users.PreferredLanguage, and by the language
/// toggle) decides the UI culture. Also keeps the label cache fresh.
/// </summary>
public sealed class LanguageMiddleware
{
    private readonly RequestDelegate _next;

    public LanguageMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context, LabelStore labels)
    {
        var language = Language.Normalize(context.Request.Cookies[Language.CookieName]);
        CultureInfo.CurrentUICulture = language == Language.Arabic ? Language.ArabicCulture : Language.EnglishCulture;

        await labels.RefreshIfStaleAsync(context.RequestAborted);
        await _next(context);
    }
}

public static class LanguageMiddlewareExtensions
{
    public static IApplicationBuilder UseHrmsLanguage(this IApplicationBuilder app) =>
        app.UseMiddleware<LanguageMiddleware>();
}
