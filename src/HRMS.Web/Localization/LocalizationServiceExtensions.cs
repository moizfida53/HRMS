using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Options;

namespace HRMS.Web.Localization;

public static class LocalizationServiceExtensions
{
    /// <summary>
    /// Database-driven bilingual UI (English / Arabic). See db/33_Localization.sql.
    /// </summary>
    public static IServiceCollection AddHrmsLocalization(this IServiceCollection services)
    {
        services.AddSingleton<LabelStore>();
        services.AddScoped<IUiText, UiText>();
        services.AddSingleton<IStringLocalizerFactory, LabelStringLocalizerFactory>();
        services.AddSingleton(typeof(IStringLocalizer<>), typeof(StringLocalizer<>));
        services.AddScoped<ActionResponseLocalizationFilter>();
        services.AddSingleton<IConfigureOptions<MvcOptions>, ModelBindingMessagesSetup>();
        return services;
    }
}

/// <summary>
/// The model binder's built-in English messages ("The value 'x' is not valid
/// for Salary.") are routed through the labels too.
/// </summary>
internal sealed class ModelBindingMessagesSetup : IConfigureOptions<MvcOptions>
{
    private readonly LabelStore _store;

    public ModelBindingMessagesSetup(LabelStore store) => _store = store;

    public void Configure(MvcOptions options)
    {
        var m = options.ModelBindingMessageProvider;
        m.SetValueMustNotBeNullAccessor(v => T("The value '{0}' is invalid.", v));
        m.SetAttemptedValueIsInvalidAccessor((v, f) => T("The value '{0}' is not valid for {1}.", v, f));
        m.SetValueIsInvalidAccessor(v => T("The value '{0}' is invalid.", v));
        m.SetValueMustBeANumberAccessor(f => T("The field {0} must be a number.", f));
        m.SetMissingBindRequiredValueAccessor(f => T("A value for the '{0}' parameter or property was not provided.", f));
        m.SetMissingKeyOrValueAccessor(() => T("A value is required."));
        m.SetUnknownValueIsInvalidAccessor(f => T("The supplied value is invalid for {0}.", f));
        m.SetNonPropertyAttemptedValueIsInvalidAccessor(v => T("The value '{0}' is not valid.", v));
        m.SetNonPropertyUnknownValueIsInvalidAccessor(() => T("The supplied value is invalid."));
        m.SetNonPropertyValueMustBeANumberAccessor(() => T("The field must be a number."));
        m.SetMissingRequestBodyRequiredValueAccessor(() => T("A non-empty request body is required."));
    }

    private string T(string english, params object?[] args)
    {
        var arabic = Language.Current == Language.Arabic;
        var template = _store.TryTranslate(english, arabic, out var t) ? t : english;
        return LabelStore.SafeFormat(template, args);
    }
}
