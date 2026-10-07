using Microsoft.AspNetCore.Html;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace HRMS.Web.Helpers;

/// <summary>
/// Inline SVG icon set. Kept as stroke paths on a 24x24 grid so every icon
/// scales cleanly and inherits <c>currentColor</c> from its container - which
/// is what lets the active nav item recolour its icon with one CSS rule.
/// <para>
/// Inline rather than an icon font or sprite sheet: no extra request, no
/// flash of missing glyphs, and nothing to add to the Content-Security-Policy.
/// </para>
/// </summary>
public static class IconHelper
{
    private static readonly Dictionary<string, string> Paths = new(StringComparer.OrdinalIgnoreCase)
    {
        // ---- navigation ----
        ["grid"]      = """<rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="8" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/><rect x="13" y="13" width="8" height="8" rx="2"/>""",
        ["building"]  = """<rect x="4" y="3" width="16" height="18" rx="1.5"/><path d="M7.5 7.5h2M14.5 7.5h2M7.5 11h2M14.5 11h2"/><path d="M10 21v-5h4v5"/>""",
        ["branch"]    = """<rect x="3" y="13" width="6" height="8" rx="1.5"/><rect x="15" y="13" width="6" height="8" rx="1.5"/><rect x="9" y="3" width="6" height="6" rx="1.5"/><path d="M12 9v2.5M6 13v-1.5h12V13"/>""",
        ["layers"]    = """<polygon points="12,3 21,8 12,13 3,8"/><polyline points="3,13 12,18 21,13"/><polyline points="3,17.5 12,22 21,17.5"/>""",
        ["sections"]  = """<rect x="3" y="4" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="6" rx="1.5"/><path d="M14 7.5h7M14 12h7M14 16.5h7"/>""",
        ["badge"]     = """<circle cx="12" cy="9" r="4.5"/><path d="M8.5 13.2 7 21l5-2.2L17 21l-1.5-7.8"/>""",
        ["briefcase"] = """<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7"/><path d="M3 12h18"/>""",
        ["pin"]       = """<path d="M12 21s7-5.6 7-11a7 7 0 1 0-14 0c0 5.4 7 11 7 11z"/><circle cx="12" cy="10" r="2.6"/>""",
        ["wallet"]    = """<path d="M3 7.5C3 6.1 4.1 5 5.5 5H17a2 2 0 0 1 2 2v1"/><rect x="3" y="7.5" width="18" height="12" rx="2"/><circle cx="16.5" cy="13.5" r="1.4" fill="currentColor" stroke="none"/>""",
        ["shield"]    = """<path d="M12 3l7 3v6c0 4.5-3 7.7-7 9-4-1.3-7-4.5-7-9V6z"/><path d="M9 12l2 2 4-4"/>""",
        ["clock"]     = """<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>""",
        ["calendar"]  = """<rect x="3.5" y="5" width="17" height="16" rx="2"/><path d="M3.5 10h17M8 3v3.5M16 3v3.5"/>""",
        ["bolt"]      = """<polygon points="13,2 4,14 11,14 10,22 20,9 13,9"/>""",
        ["card"]      = """<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.6"/><circle cx="6" cy="10" r="0.9" fill="currentColor" stroke="none"/><circle cx="18" cy="14" r="0.9" fill="currentColor" stroke="none"/>""",
        ["exit"]      = """<path d="M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4"/><path d="M15 8l4 4-4 4"/><path d="M19 12H9"/>""",
        ["chart"]     = """<path d="M5 20v-8M12 20V7M19 20v-5M3 20h18"/>""",
        ["sliders"]   = """<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="9" cy="6" r="2.2" fill="#fff"/><circle cx="15" cy="12" r="2.2" fill="#fff"/><circle cx="7" cy="18" r="2.2" fill="#fff"/>""",
        ["users"]     = """<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17.5" cy="9" r="2.6"/><path d="M15.7 14.2c2.9.4 5.3 2.7 5.3 5.8"/>""",
        ["user"]      = """<circle cx="12" cy="8" r="4"/><path d="M4 20c0-4.4 3.6-8 8-8s8 3.6 8 8"/>""",
        ["folder"]    = """<path d="M3 7a2 2 0 0 1 2-2h4l2 2.5h8A2 2 0 0 1 21 9.5V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>""",
        ["id-card"]   = """<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="11" r="2"/><path d="M5.5 16c0-1.7 1.4-3 3-3s3 1.3 3 3"/><path d="M14 9.5h4M14 13h4"/>""",
        ["phone"]     = """<path d="M4.5 4h3.2l1.6 4.4-2 1.6a13 13 0 0 0 6.7 6.7l1.6-2 4.4 1.6v3.2c0 1-.9 1.8-1.9 1.6C10.7 20 4 13.3 2.9 6.4 2.7 5.4 3.5 4.5 4.5 4.5z"/>""",
        ["mail"]      = """<rect x="3" y="5.5" width="18" height="13" rx="2"/><path d="M3.5 6.5 12 13l8.5-6.5"/>""",
        ["camera"]    = """<path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h2l1-2h7l1 2h2A1.5 1.5 0 0 1 20 8.5V18a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18z"/><circle cx="12" cy="13" r="3.4"/>""",
        ["step-check"] = """<circle cx="12" cy="12" r="9"/><polyline points="8,12.5 11,15.5 16,9"/>""",
        ["heart"]     = """<path d="M12 20.5s-7.5-4.6-10-9.2C.4 8 2 4.5 5.5 4c2-.3 3.8.7 6.5 3 2.7-2.3 4.5-3.3 6.5-3 3.5.5 5.1 4 3.5 7.3-2.5 4.6-10 9.2-10 9.2z"/>""",

        // ---- ui ----
        ["search"]    = """<circle cx="10.5" cy="10.5" r="6.5"/><path d="M20 20l-4.7-4.7"/>""",
        ["bell"]      = """<path d="M6 9a6 6 0 1 1 12 0c0 4.5 1.5 6 2 6.5H4c.5-.5 2-2 2-6.5z"/><path d="M9.5 18.5a2.5 2.5 0 0 0 5 0"/>""",
        ["menu"]      = """<path d="M4 7h16M4 12h16M4 17h16"/>""",
        ["close"]     = """<path d="M6 6l12 12M18 6L6 18"/>""",
        ["plus"]      = """<path d="M12 5v14M5 12h14"/>""",
        ["download"]  = """<path d="M12 3v12"/><polyline points="7,10 12,15 17,10"/><path d="M4 20h16"/>""",
        ["edit"]      = """<path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3z"/><path d="M13.5 6.5l3 3"/>""",
        ["trash"]     = """<path d="M4 7h16M10 4h4M9 7v11M15 7v11"/><path d="M6 7l1 13h10l1-13"/>""",
        ["power"]     = """<path d="M12 4v8"/><path d="M7.5 6.5a7.5 7.5 0 1 0 9 0"/>""",
        ["check"]     = """<polyline points="4,12 9,17 20,6"/>""",
        ["alert"]     = """<path d="M12 4l9.5 16H2.5z"/><path d="M12 10v4.5"/><circle cx="12" cy="17.3" r="0.7" fill="currentColor" stroke="none"/>""",
        ["info"]      = """<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><circle cx="12" cy="7.8" r="0.7" fill="currentColor" stroke="none"/>""",
        ["sort"]      = """<path d="M12 5v14"/><polyline points="7,10 12,5 17,10"/>""",
        ["chevron-left"]  = """<polyline points="14,6 8,12 14,18"/>""",
        ["chevron-right"] = """<polyline points="10,6 16,12 10,18"/>""",
        ["chevron-down"]  = """<polyline points="6,9 12,15 18,9"/>""",
        ["filter"]    = """<polygon points="4,4 20,4 14,12.5 14,19 10,21 10,12.5"/>""",
        ["inbox"]     = """<path d="M3 13h5l1.5 3h5L16 13h5"/><path d="M4.6 5.6 3 13v5a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5l-1.6-7.4A2 2 0 0 0 17.5 4h-11a2 2 0 0 0-1.9 1.6z"/>""",
        ["eye"]       = """<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>""",
        ["eye-off"]   = """<path d="M4 4l16 16"/><path d="M9.9 5.2A9.9 9.9 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.3 4.2"/><path d="M6.5 7.3A17 17 0 0 0 2 12s3.6 7 10 7a9.8 9.8 0 0 0 4.2-.9"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>""",
        ["lock"]      = """<rect x="4" y="10" width="16" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>""",
        ["globe"]     = """<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>""",
        ["logout"]    = """<path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/><path d="M9 8l-4 4 4 4"/><path d="M5 12h10"/>""",
        // ---- payroll (db/34+) ----
        ["refresh"]   = """<path d="M20 11a8 8 0 0 0-14.6-4.5L4 8"/><path d="M4 4v4h4"/><path d="M4 13a8 8 0 0 0 14.6 4.5L20 16"/><path d="M20 20v-4h-4"/>""",
        ["send"]      = """<path d="M21 3 10 14"/><path d="M21 3l-7 18-4-7-7-4z"/>""",
        ["percent"]   = """<path d="M19 5 5 19"/><circle cx="7" cy="7" r="2.5"/><circle cx="17" cy="17" r="2.5"/>""",
        ["receipt"]   = """<path d="M6 3h12v18l-2-1.5-2 1.5-2-1.5-2 1.5-2-1.5L6 21z"/><path d="M9 8h6M9 12h6M9 16h3"/>""",
        ["bank"]      = """<path d="M3 10 12 4l9 6"/><path d="M5 10v8M9.5 10v8M14.5 10v8M19 10v8"/><path d="M3 20h18"/>""",
        ["book"]      = """<path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M5 17a3 3 0 0 1 3-3h11"/>""",
        ["calculator"] = """<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8"/><path d="M8.5 11h.01M12 11h.01M15.5 11h.01M8.5 14.5h.01M12 14.5h.01M15.5 14.5h.01M8.5 18h.01M12 18h3.5"/>""",
        ["more"]      = """<circle cx="5" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.6" fill="currentColor" stroke="none"/>""",
        ["history"]   = """<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l3 2"/>""",
        ["file"]      = """<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>""",
        ["printer"]   = """<path d="M7 9V3h10v6"/><rect x="3" y="9" width="18" height="8" rx="2"/><path d="M7 14h10v7H7z"/>""",
        ["x-circle"]  = """<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6M15 9l-6 6"/>""",
        ["undo"]      = """<path d="M9 14 4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/>""",
        ["upload"]    = """<path d="M12 15V3"/><polyline points="7,8 12,3 17,8"/><path d="M4 20h16"/>"""
    };

    private static readonly HashSet<string> Directional = ["chevron-left", "chevron-right", "logout", "exit"];

    /// <summary>Renders an icon. Unknown names render nothing rather than throwing.</summary>
    public static IHtmlContent Icon(
        this IHtmlHelper _,
        string name,
        int size = 18,
        string? cssClass = null,
        string? strokeWidth = "1.8")
    {
        if (!Paths.TryGetValue(name, out var path))
        {
            return HtmlString.Empty;
        }

        // Arrows that point "forward" or "back" are mirrored in Arabic (RTL);
        // the hrms-flip-rtl class does that in CSS (see _layout.scss).
        if (Directional.Contains(name))
        {
            cssClass = string.IsNullOrWhiteSpace(cssClass) ? "hrms-flip-rtl" : cssClass + " hrms-flip-rtl";
        }

        var classAttribute = string.IsNullOrWhiteSpace(cssClass)
            ? string.Empty
            : $" class=\"{System.Net.WebUtility.HtmlEncode(cssClass)}\"";

        return new HtmlString(
            $"""<svg{classAttribute} width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" """ +
            $"""stroke="currentColor" stroke-width="{strokeWidth}" stroke-linecap="round" """ +
            $"""stroke-linejoin="round" aria-hidden="true" focusable="false">{path}</svg>""");
    }
}
