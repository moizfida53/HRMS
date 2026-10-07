using System.Globalization;
using Microsoft.Extensions.Localization;

namespace HRMS.Web.Localization;

/// <summary>
/// Bridges ASP.NET Core's IStringLocalizer to Core.UiLabels, so DataAnnotations
/// ([Display(Name)], [Required(ErrorMessage)], ...) and anything else using
/// IStringLocalizer read their text from the database. The "name" is either a
/// label key or the English text itself.
/// </summary>
public sealed class LabelStringLocalizer : IStringLocalizer
{
    private readonly LabelStore _store;

    public LabelStringLocalizer(LabelStore store) => _store = store;

    private static bool Arabic => Language.IsArabic(CultureInfo.CurrentUICulture);

    public LocalizedString this[string name]
    {
        get
        {
            var key = _store.Find(name, Arabic);
            if (key is not null)
            {
                return new LocalizedString(name, key, false);
            }

            var found = _store.TryTranslate(name, Arabic, out var text);
            return new LocalizedString(name, text, resourceNotFound: !found);
        }
    }

    public LocalizedString this[string name, params object[] arguments]
    {
        get
        {
            var template = this[name];
            return new LocalizedString(name, LabelStore.SafeFormat(template.Value, arguments), template.ResourceNotFound);
        }
    }

    public IEnumerable<LocalizedString> GetAllStrings(bool includeParentCultures) => [];
}

public sealed class LabelStringLocalizerFactory : IStringLocalizerFactory
{
    private readonly LabelStringLocalizer _localizer;

    public LabelStringLocalizerFactory(LabelStore store) => _localizer = new LabelStringLocalizer(store);

    public IStringLocalizer Create(Type resourceSource) => _localizer;

    public IStringLocalizer Create(string baseName, string location) => _localizer;
}
