namespace HRMS.Web.Localization;

public static class UiTextNames
{
    /// <summary>
    /// The Arabic name in Arabic mode, else the English one - also when the Arabic name is empty.
    /// For names stored in both languages (employees, companies, types ...).
    /// </summary>
    public static string Name(this IUiText L, string? english, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic.Trim() : english ?? string.Empty;
}
