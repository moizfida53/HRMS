using System.Collections.Concurrent;
using System.Collections.Frozen;
using System.Text.Json;
using System.Text.RegularExpressions;
using HRMS.Data.Repositories;

namespace HRMS.Web.Localization;

/// <summary>
/// In-memory copy of Core.UiLabels, shared by every request.
/// <para>
/// The table is the single source of truth for UI text: correcting a label is an
/// UPDATE on Core.UiLabels, never a code change. The store asks the database for
/// a cheap checksum at most every <see cref="CheckInterval"/>, and reloads only
/// when it changed, so an edit made directly in SQL shows up within ~30 seconds
/// without restarting the site.
/// </para>
/// </summary>
public sealed class LabelStore
{
    public static readonly TimeSpan CheckInterval = TimeSpan.FromSeconds(30);

    private readonly IServiceScopeFactory _scopes;
    private readonly ILogger<LabelStore> _logger;
    private readonly SemaphoreSlim _gate = new(1, 1);

    private volatile Snapshot _snapshot = Snapshot.Empty;

    // Text asked for but not found; written to Core.UiLabels on the next check.
    private readonly ConcurrentDictionary<string, (string? Key, string Text)> _missing = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, byte> _reported = new(StringComparer.Ordinal);
    private string? _version;
    private DateTime _nextCheckUtc = DateTime.MinValue;

    public LabelStore(IServiceScopeFactory scopes, ILogger<LabelStore> logger)
    {
        _scopes = scopes;
        _logger = logger;
    }

    /// <summary>Number of labels loaded (0 until the first successful load).</summary>
    public int Count => _snapshot.ByKey.Count;

    /// <summary>
    /// Reloads the labels when the table changed. Cheap when called on every
    /// request: it returns immediately until the check interval has passed, and
    /// only one request at a time ever talks to the database.
    /// </summary>
    public async Task RefreshIfStaleAsync(CancellationToken cancellationToken = default)
    {
        if (DateTime.UtcNow < _nextCheckUtc)
        {
            return;
        }

        // First load blocks (so the very first page is not rendered without text);
        // later checks never make a request wait behind another one.
        var firstLoad = _version is null;
        if (!await _gate.WaitAsync(firstLoad ? TimeSpan.FromSeconds(15) : TimeSpan.Zero, cancellationToken).ConfigureAwait(false))
        {
            return;
        }

        try
        {
            if (DateTime.UtcNow < _nextCheckUtc)
            {
                return;
            }

            using var scope = _scopes.CreateScope();
            var repository = scope.ServiceProvider.GetRequiredService<ILocalizationRepository>();

            try
            {
                await FlushMissingAsync(repository, CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                // A failed capture must not stop the labels from refreshing.
                _logger.LogWarning(ex, "Could not record missing UI labels.");
            }

            // Shared cache: one request disconnecting must not cancel the load for everyone.
            var version = await repository.GetLabelsVersionAsync(CancellationToken.None).ConfigureAwait(false);
            if (version is not null && version == _version)
            {
                return;
            }

            var labels = await repository.GetAllLabelsAsync(CancellationToken.None).ConfigureAwait(false);
            _snapshot = Snapshot.Build(labels);
            _version = version ?? string.Empty;
            _logger.LogInformation("Loaded {Count} UI labels (version {Version}).", labels.Count, version);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Missing table (db/33 not run yet) or a transient failure: keep what
            // we have and fall back to readable keys rather than failing the page.
            _logger.LogWarning(ex, "Could not load UI labels from Core.UiLabels; using the cached copy.");
        }
        finally
        {
            _nextCheckUtc = DateTime.UtcNow.Add(CheckInterval);
            _gate.Release();
        }
    }

    /// <summary>
    /// Queues a label key or an English message that has no row yet. Each is
    /// reported once per application lifetime; nothing is captured until the
    /// table has loaded (so a missing db/33 does not flood anything).
    /// </summary>
    public void ReportMissing(string? key, string text)
    {
        // Already-Arabic text is never "missing English": it comes from a label.
        if (_version is null || string.IsNullOrWhiteSpace(text) || text.Length > 1000 || ContainsArabic(text)
            || _reported.Count >= MaxReported)
        {
            return;
        }

        var id = key ?? Snapshot.Normalize(text);
        if (_reported.TryAdd(id, 0))
        {
            _missing[id] = (key, Snapshot.Normalize(text));
        }
    }

    private const int MaxReported = 5000;

    private static bool ContainsArabic(string text)
    {
        foreach (var c in text)
        {
            if (c is >= '\u0600' and <= '\u06FF')
            {
                return true;
            }
        }

        return false;
    }

    private async Task FlushMissingAsync(ILocalizationRepository repository, CancellationToken cancellationToken)
    {
        if (_missing.IsEmpty)
        {
            return;
        }

        var batch = new List<object>();
        foreach (var id in _missing.Keys.Take(200))
        {
            if (_missing.TryRemove(id, out var item))
            {
                batch.Add(new { key = item.Key, text = item.Text });
            }
        }

        await repository.CaptureMissingAsync(JsonSerializer.Serialize(batch), cancellationToken).ConfigureAwait(false);

        // The captured rows change the checksum, so force the reload below.
        _version = string.Empty;
    }

    /// <summary>Forces the next request to re-check the database.</summary>
    public void Invalidate() => _nextCheckUtc = DateTime.MinValue;

    /// <summary>The text for a key, or null when the key is unknown.</summary>
    public string? Find(string key, bool arabic)
    {
        if (!_snapshot.ByKey.TryGetValue(key, out var label))
        {
            return null;
        }

        return arabic && !string.IsNullOrWhiteSpace(label.ArabicText) ? label.ArabicText : label.EnglishText;
    }

    /// <summary>
    /// Translates a finished English sentence (a stored-procedure message, a
    /// validation message, a controller message) by matching it against the
    /// labels' SourceText / EnglishText. Templates with {0}, {1} placeholders
    /// match sentences with variable parts, which are carried into the Arabic.
    /// </summary>
    public bool TryTranslate(string text, bool arabic, out string translated)
    {
        translated = text;
        if (string.IsNullOrWhiteSpace(text) || text.Length > 1000)
        {
            return false;
        }

        var snapshot = _snapshot;
        var normalized = Snapshot.Normalize(text);

        if (snapshot.BySource.TryGetValue(normalized, out var exact))
        {
            translated = Pick(exact, arabic);
            return true;
        }

        foreach (var (pattern, label, slots) in snapshot.Templates)
        {
            Match match;
            try
            {
                match = pattern.Match(normalized);
            }
            catch (RegexMatchTimeoutException)
            {
                continue;
            }

            if (!match.Success)
            {
                continue;
            }

            // slots[i] = the placeholder number of capture group i+1, so
            // "{1} must be before {0}." keeps each value with its own number.
            var args = new object[slots.Length == 0 ? 0 : slots.Max() + 1];
            for (var i = 0; i < slots.Length; i++)
            {
                args[slots[i]] = match.Groups[i + 1].Value;
            }

            translated = SafeFormat(Pick(label, arabic), args);
            return true;
        }

        return false;
    }

    /// <summary>Every label whose key starts with <paramref name="prefix"/> (for the JavaScript bundle).</summary>
    public IReadOnlyDictionary<string, string> WithPrefix(string prefix, bool arabic)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, label) in _snapshot.ByKey)
        {
            if (key.StartsWith(prefix, StringComparison.Ordinal))
            {
                result[key] = Pick(label, arabic);
            }
        }

        return result;
    }

    public static string SafeFormat(string format, object?[] args)
    {
        if (args.Length == 0)
        {
            return format;
        }

        try
        {
            return string.Format(format, args);
        }
        catch (FormatException)
        {
            return format;
        }
    }

    private static string Pick(UiLabel label, bool arabic) =>
        arabic && !string.IsNullOrWhiteSpace(label.ArabicText) ? label.ArabicText! : label.EnglishText;

    private sealed class Snapshot
    {
        public static readonly Snapshot Empty = new(
            FrozenDictionary<string, UiLabel>.Empty,
            FrozenDictionary<string, UiLabel>.Empty,
            []);

        private Snapshot(
            FrozenDictionary<string, UiLabel> byKey,
            FrozenDictionary<string, UiLabel> bySource,
            IReadOnlyList<(Regex, UiLabel, int[])> templates)
        {
            ByKey = byKey;
            BySource = bySource;
            Templates = templates;
        }

        public FrozenDictionary<string, UiLabel> ByKey { get; }
        public FrozenDictionary<string, UiLabel> BySource { get; }
        public IReadOnlyList<(Regex Pattern, UiLabel Label, int[] Slots)> Templates { get; }

        private static readonly Regex Placeholder = new(@"\{(\d+)\}", RegexOptions.Compiled);
        private static readonly Regex Spaces = new(@"\s+", RegexOptions.Compiled);

        public static string Normalize(string text) => Spaces.Replace(text.Trim(), " ");

        public static Snapshot Build(IReadOnlyList<UiLabel> labels)
        {
            var byKey = new Dictionary<string, UiLabel>(StringComparer.Ordinal);
            var bySource = new Dictionary<string, UiLabel>(StringComparer.Ordinal);
            var templates = new List<(Regex, UiLabel, int[])>();

            foreach (var label in labels)
            {
                byKey[label.LabelKey] = label;

                var source = Normalize(label.SourceText ?? string.Empty);
                if (source.Length == 0)
                {
                    continue;
                }

                if (Placeholder.IsMatch(source))
                {
                    // "Code '{0}' already exists." -> ^Code '(.+?)' already exists\.$
                    var pattern = "^" + Placeholder.Replace(Regex.Escape(source).Replace(@"\{", "{"), "(.+?)") + "$";
                    var slots = Placeholder.Matches(source).Select(m => int.Parse(m.Groups[1].Value)).ToArray();
                    templates.Add((new Regex(pattern, RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(50)), label, slots));
                }
                else
                {
                    bySource.TryAdd(source, label);
                }
            }

            // English text doubles as a lookup source when no SourceText is given,
            // so a message that happens to equal a label is translated too.
            foreach (var label in labels)
            {
                var english = Normalize(label.EnglishText);
                if (english.Length > 0 && !Placeholder.IsMatch(english))
                {
                    bySource.TryAdd(english, label);
                }
            }

            // Longest templates first, so the most specific sentence wins.
            templates.Sort((a, b) => b.Item1.ToString().Length.CompareTo(a.Item1.ToString().Length));

            return new Snapshot(byKey.ToFrozenDictionary(StringComparer.Ordinal), bySource.ToFrozenDictionary(StringComparer.Ordinal), templates);
        }
    }
}
