using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Html;

namespace HRMS.Web.Localization;

/// <summary>
/// UI text for the current request. Injected into every view as <c>L</c>
/// (see _ViewImports.cshtml):
/// <code>
///   @L["org.add_branch"]                       plain label
///   @L["common.page_of", page, total]          label with {0}, {1} placeholders
///   @L.Tr(Model.Message)                       an English sentence from elsewhere
/// </code>
/// </summary>
public interface IUiText
{
    string this[string key] { get; }

    string this[string key, params object?[] args] { get; }

    /// <summary>
    /// Translates a finished English sentence; returns it unchanged when no label
    /// matches. <paramref name="capture"/>: record an untranslated sentence in
    /// Core.UiLabels so it can be translated there (messages only - never pass
    /// it for data such as names).
    /// </summary>
    string Tr(string? english, bool capture = false);

    /// <summary>"en" or "ar".</summary>
    string Lang { get; }

    bool IsArabic { get; }

    /// <summary>"ltr" or "rtl" - for &lt;html dir&gt;.</summary>
    string Dir { get; }

    /// <summary>JSON of every "js.*" label, for the client-side HRMS.t() helper.</summary>
    IHtmlContent ScriptLabelsJson();

    // ---- dates: Western digits in both languages, month names from the labels ----

    /// <summary>Month name (common.month_1..12); <paramref name="shortName"/> = common.month_short_N.</summary>
    string Month(int month, bool shortName = false);

    /// <summary>"October 2026" / "أكتوبر 2026".</summary>
    string MonthYear(DateTime date);

    /// <summary>"06 Oct 2026" / "06 أكتوبر 2026"; <paramref name="empty"/> when null.</summary>
    string Date(DateTime? date, string empty = "—");

    /// <summary>"06 Oct" / "06 أكتوبر".</summary>
    string DayMonth(DateTime date);
}

public sealed class UiText : IUiText
{
    private readonly LabelStore _store;
    private readonly ILogger<UiText> _logger;

    public UiText(LabelStore store, ILogger<UiText> logger)
    {
        _store = store;
        _logger = logger;
    }

    public bool IsArabic => Language.IsArabic(CultureInfo.CurrentUICulture);

    public string Lang => IsArabic ? Language.Arabic : Language.English;

    public string Dir => IsArabic ? "rtl" : "ltr";

    public string this[string key] => Get(key);

    public string this[string key, params object?[] args] => LabelStore.SafeFormat(Get(key), args);

    public string Tr(string? english, bool capture = false)
    {
        if (string.IsNullOrEmpty(english))
        {
            return english ?? string.Empty;
        }

        if (_store.TryTranslate(english, IsArabic, out var translated))
        {
            return translated;
        }

        if (capture)
        {
            _store.ReportMissing(null, english);
        }

        return english;
    }

    public IHtmlContent ScriptLabelsJson()
    {
        var json = JsonSerializer.Serialize(_store.WithPrefix("js.", IsArabic), new JsonSerializerOptions
        {
            // Inside <script type="application/json">: "<" must stay escaped.
            Encoder = JavaScriptEncoder.Default
        });

        return new HtmlString(json);
    }

    public string Month(int month, bool shortName = false) =>
        Get(shortName ? $"common.month_short_{month}" : $"common.month_{month}");

    public string MonthYear(DateTime date) =>
        $"{Month(date.Month)} {date.Year.ToString(CultureInfo.InvariantCulture)}";

    public string Date(DateTime? date, string empty = "—") =>
        date is { } d
            ? $"{d.Day.ToString("00", CultureInfo.InvariantCulture)} {Month(d.Month, shortName: true)} {d.Year.ToString(CultureInfo.InvariantCulture)}"
            : empty;

    public string DayMonth(DateTime date) =>
        $"{date.Day.ToString("00", CultureInfo.InvariantCulture)} {Month(date.Month, shortName: true)}";

    private string Get(string key)
    {
        var text = _store.Find(key, IsArabic);
        if (text is not null)
        {
            return text;
        }

        var fallback = Humanize(key);
        if (_store.Count > 0)
        {
            _logger.LogDebug("UI label '{Key}' is missing from Core.UiLabels.", key);
            _store.ReportMissing(key, fallback);
        }

        return fallback;
    }

    /// <summary>"org.add_branch" -> "Add branch": readable, and obviously a missing label.</summary>
    private static string Humanize(string key)
    {
        var dot = key.LastIndexOf('.');
        var tail = (dot >= 0 ? key[(dot + 1)..] : key).Replace('_', ' ').Trim();
        return tail.Length == 0 ? key : char.ToUpperInvariant(tail[0]) + tail[1..];
    }
}
