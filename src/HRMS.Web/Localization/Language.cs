using System.Globalization;

namespace HRMS.Web.Localization;

/// <summary>
/// The two UI languages. Only the UI culture changes with the language; number
/// and date formatting stay on the server culture so amounts, Civil IDs and
/// dates keep Western digits in both languages (the Kuwait payroll norm).
/// </summary>
public static class Language
{
    public const string English = "en";
    public const string Arabic  = "ar";

    /// <summary>Remembers the choice between requests and before sign-in.</summary>
    public const string CookieName = "Hrms-Lang";

    /// <summary>Session cookie: the language was picked on the sign-in page (saved at sign-in).</summary>
    public const string ChosenCookieName = "Hrms-Lang-Chosen";

    public static readonly CultureInfo EnglishCulture = CultureInfo.GetCultureInfo("en-US");
    public static readonly CultureInfo ArabicCulture  = CultureInfo.GetCultureInfo("ar-KW");

    /// <summary>Anything other than "ar" is English.</summary>
    public static string Normalize(string? value) =>
        string.Equals(value?.Trim(), Arabic, StringComparison.OrdinalIgnoreCase) ? Arabic : English;

    public static bool IsArabic(CultureInfo culture) =>
        culture.TwoLetterISOLanguageName == Arabic;

    /// <summary>The language of the current request (set by <see cref="LanguageMiddleware"/>).</summary>
    public static string Current => IsArabic(CultureInfo.CurrentUICulture) ? Arabic : English;

    public static void WriteCookie(HttpContext context, string language)
    {
        context.Response.Cookies.Append(CookieName, Normalize(language), new CookieOptions
        {
            Expires     = DateTimeOffset.UtcNow.AddYears(1),
            HttpOnly    = true,
            IsEssential = true,
            SameSite    = SameSiteMode.Lax,
            Secure      = context.Request.IsHttps,
            Path        = "/"
        });
    }
}
