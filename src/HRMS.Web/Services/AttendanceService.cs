using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Attendance;
using HRMS.Domain.Common;
using HRMS.Web.Security;
using Microsoft.Extensions.Caching.Memory;

namespace HRMS.Web.Services;

/// <summary>A column of the preview: what was found, and the role chosen.</summary>
public sealed record AttPreviewColumn(int Index, string Header, string Role, string Basis, string Sample, string Kind);

/// <summary>An ID in the file and the employee it was matched to (or the choices).</summary>
public sealed class AttPreviewPerson
{
    public string DeviceId { get; init; } = string.Empty;
    public string? FileName { get; init; }
    public int Days { get; init; }
    public long? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public string? EmployeeNo { get; set; }
    public string? CompanyName { get; set; }
    /// <summary>device, number, name, chosen, or none / ambiguous.</summary>
    public string MatchedBy { get; set; } = "none";
}

/// <summary>What the file holds, before it is imported.</summary>
public sealed class AttPreview
{
    public string Token { get; init; } = string.Empty;
    public string FileName { get; init; } = string.Empty;
    public string Format { get; init; } = "PAIRED";
    public int HeaderRow { get; init; }
    public bool DayFirst { get; init; }
    public IReadOnlyList<AttPreviewColumn> Columns { get; init; } = [];
    public string? Problem { get; init; }
    public IReadOnlyList<string> Warnings { get; init; } = [];
    public int DataRows { get; init; }
    public int Days { get; init; }
    public int Skipped { get; init; }
    public IReadOnlyList<string> SkipReasons { get; init; } = [];
    public string? From { get; init; }
    public string? To { get; init; }
    public IReadOnlyList<AttPreviewPerson> People { get; init; } = [];
    /// <summary>The first days read (to check the times).</summary>
    public IReadOnlyList<object> Sample { get; init; } = [];
    public int Matched => People.Count(p => p.EmployeeId is not null);
    public int Unmatched => People.Count(p => p.EmployeeId is null);
}

public interface IAttendanceService
{
    AttScope Scope { get; }
    /// <summary>Reads a file (kept for 30 minutes) and works out its columns and employees.</summary>
    Task<AttPreview> PreviewAsync(string fileName, List<string[]> rows, CancellationToken ct = default);
    /// <summary>The same file with the columns chosen on the preview.</summary>
    Task<AttPreview?> RepreviewAsync(string token, IReadOnlyDictionary<int, AttColumn> roles, CancellationToken ct = default);
    /// <summary>Imports the file: the IDs linked on the preview to employees (remembered as their device ID when asked).</summary>
    Task<SaveResult> ConfirmAsync(string token, IReadOnlyDictionary<int, AttColumn> roles, IReadOnlyDictionary<string, long> links, bool remember,
                                  CancellationToken ct = default);
    /// <summary>Works the months out again (after an import, a change of a day, a pattern or an assignment).</summary>
    Task RecalculateAsync(IEnumerable<AttMonth> months, long? employeeId = null, CancellationToken ct = default);
}

public sealed class AttendanceService : IAttendanceService
{
    private static readonly TimeSpan Keep = TimeSpan.FromMinutes(30);
    private readonly IAttendanceRepository _repo;
    private readonly ICurrentUser _user;
    private readonly ICompanyFilter _companyFilter;
    private readonly IMemoryCache _cache;

    public AttendanceService(IAttendanceRepository repo, ICurrentUser user, ICompanyFilter companyFilter, IMemoryCache cache)
    {
        _repo = repo;
        _user = user;
        _companyFilter = companyFilter;
        _cache = cache;
    }

    public AttScope Scope => new(_user.ActiveCompanyId, _companyFilter.Csv);

    private sealed record Session(string FileName, List<string[]> Rows);

    private string Key(string token) => $"hrms:att-import:{_user.UserId}:{token}";

    public Task<AttPreview> PreviewAsync(string fileName, List<string[]> rows, CancellationToken ct = default)
    {
        var token = Guid.NewGuid().ToString("N");
        _cache.Set(Key(token), new Session(fileName, rows), Keep);
        var layout = AttendanceFileParser.Detect(rows);
        return BuildAsync(token, fileName, rows, layout, ct);
    }

    public Task<AttPreview?> RepreviewAsync(string token, IReadOnlyDictionary<int, AttColumn> roles, CancellationToken ct = default)
    {
        if (!_cache.TryGetValue(Key(token), out Session? s) || s is null) return Task.FromResult<AttPreview?>(null);
        var layout = AttendanceFileParser.Detect(s.Rows);
        AttendanceFileParser.Apply(layout, roles);
        return BuildAsync(token, s.FileName, s.Rows, layout, ct)!;
    }

    private async Task<AttPreview?> BuildAsync(string token, string fileName, List<string[]> rows, AttLayout layout, CancellationToken ct)
    {
        var problem = layout.Problem;
        var parsed = problem is null ? AttendanceFileParser.Parse(rows, layout) : new AttParseResult();
        var people = problem is null ? await MatchAsync(parsed, ct) : [];
        return new AttPreview
        {
            Token = token,
            FileName = fileName,
            Format = layout.Format,
            HeaderRow = layout.HeaderRow,
            DayFirst = layout.DayFirst,
            Columns = layout.Columns.Select(c => new AttPreviewColumn(c.Index, c.Header, c.Role.ToString(), c.Basis, c.Sample, c.DataKind)).ToList(),
            Problem = problem,
            Warnings = layout.Warnings,
            DataRows = parsed.DataRows,
            Days = parsed.Days.Count,
            Skipped = parsed.Skipped,
            SkipReasons = parsed.SkipReasons,
            From = parsed.From?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            To = parsed.To?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            People = people,
            Sample = parsed.Days.Take(8).Select(d => (object)new
            {
                id = d.DeviceId, name = d.Name, date = d.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                clockIn = d.ClockIn?.ToString("HH:mm", CultureInfo.InvariantCulture),
                clockOut = d.ClockOut is { } o ? o.ToString(d.Date.ToDateTime(TimeOnly.MinValue).Date == o.Date ? "HH:mm" : "HH:mm (+1)", CultureInfo.InvariantCulture) : null
            }).ToList()
        };
    }

    /// <summary>
    /// The employee of each ID in the file: the device ID saved for them, else their employee number /
    /// code, else their name (when only one employee has it). An ID several employees share (the same
    /// number in two companies) is settled by the name in the file, else left to choose.
    /// </summary>
    private async Task<List<AttPreviewPerson>> MatchAsync(AttParseResult parsed, CancellationToken ct)
    {
        var employees = await _repo.MatchListAsync(Scope, ct);
        ILookup<string, AttendanceEmployee> Index(Func<AttendanceEmployee, IEnumerable<string?>> keys) =>
            employees.SelectMany(e => keys(e).Where(k => !string.IsNullOrWhiteSpace(k)).Select(k => (Key: k!, E: e))).Distinct()
                     .ToLookup(x => x.Key, x => x.E);
        var byDevice = Index(e => [AttendanceFileParser.IdKey(e.DeviceUserId)]);
        var byNumber = Index(e => [AttendanceFileParser.IdKey(e.EmployeeNo), AttendanceFileParser.IdKey(e.EmployeeCode)]);
        var byName = Index(e => [NameKey(e.EmployeeName), NameKey(e.ArabicName)]);

        var people = new List<AttPreviewPerson>();
        foreach (var g in parsed.Days.GroupBy(d => d.DeviceId))
        {
            var fileName = g.Select(d => d.Name).FirstOrDefault(n => !string.IsNullOrWhiteSpace(n));
            var person = new AttPreviewPerson { DeviceId = g.Key, FileName = fileName, Days = g.Count() };
            var key = AttendanceFileParser.IdKey(g.Key);
            AttendanceEmployee? hit = null;
            var candidates = byDevice[key].ToList();
            if (candidates.Count > 0) { hit = Pick(candidates, fileName); person.MatchedBy = hit is null ? "ambiguous" : "device"; }
            if (hit is null)
            {
                candidates = byNumber[key].ToList();
                if (candidates.Count > 0) { hit = Pick(candidates, fileName); person.MatchedBy = hit is null ? "ambiguous" : "number"; }
            }
            if (hit is null && person.MatchedBy == "none" && NameKey(fileName) is { } nk)
            {
                var named = byName[nk].ToList();
                if (named.Count == 1) { hit = named[0]; person.MatchedBy = "name"; }
            }
            if (hit is not null)
            {
                person.EmployeeId = hit.EmployeeId;
                person.EmployeeName = hit.EmployeeName;
                person.EmployeeNo = hit.DisplayNo;
                person.CompanyName = hit.CompanyName;
            }
            people.Add(person);
        }
        return people.OrderBy(p => p.EmployeeId is null ? 0 : 1).ThenBy(p => p.DeviceId, StringComparer.Ordinal).ToList();
    }

    private static AttendanceEmployee? Pick(List<AttendanceEmployee> candidates, string? fileName)
    {
        if (candidates.Count == 1) return candidates[0];
        if (NameKey(fileName) is not { } nk) return null;
        var named = candidates.Where(c => NameKey(c.EmployeeName) == nk || NameKey(c.ArabicName) == nk).ToList();
        if (named.Count == 1) return named[0];
        // the file's name is the start of the employee's full name ("Ahmed Ali" / "Ahmed Ali Hassan")
        var partial = candidates.Where(c => (NameKey(c.EmployeeName) ?? "").StartsWith(nk, StringComparison.Ordinal)
                                            || nk.StartsWith(NameKey(c.EmployeeName) ?? "\u0001", StringComparison.Ordinal)).ToList();
        return partial.Count == 1 ? partial[0] : null;
    }

    private static string? NameKey(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var parts = name.Trim().ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length == 0 ? null : string.Join(' ', parts);
    }

    public async Task<SaveResult> ConfirmAsync(string token, IReadOnlyDictionary<int, AttColumn> roles, IReadOnlyDictionary<string, long> links, bool remember,
                                               CancellationToken ct = default)
    {
        if (!_cache.TryGetValue(Key(token), out Session? s) || s is null)
            return SaveResult.Fail("The file is no longer open - choose it again.", "EXPIRED");
        var layout = AttendanceFileParser.Detect(s.Rows);
        AttendanceFileParser.Apply(layout, roles);
        if (layout.Problem is { } problem) return SaveResult.Fail(problem, "VALIDATION");
        var parsed = AttendanceFileParser.Parse(s.Rows, layout);
        var people = await MatchAsync(parsed, ct);

        // the links chosen on the preview win over the match
        var employeeOf = new Dictionary<string, long>(StringComparer.Ordinal);
        foreach (var p in people)
        {
            if (links.TryGetValue(p.DeviceId, out var chosen)) { if (chosen > 0) employeeOf[p.DeviceId] = chosen; }
            else if (p.EmployeeId is { } id) employeeOf[p.DeviceId] = id;
        }
        if (employeeOf.Count == 0) return SaveResult.Fail("No ID of the file is linked to an employee.", "VALIDATION");

        if (remember)
        {
            var chosenLinks = links.Where(l => l.Value > 0 && people.Any(p => p.DeviceId == l.Key && p.EmployeeId != l.Value))
                                   .Select(l => (object)new { employeeId = l.Value, deviceUserId = l.Key, setDevice = true }).ToList();
            if (chosenLinks.Count > 0) await _repo.SetEmployeesAsync(Scope, chosenLinks, _user.UserId, ct);
        }

        var days = parsed.Days.Where(d => employeeOf.ContainsKey(d.DeviceId))
            .Select(d => (object)new
            {
                employeeId = employeeOf[d.DeviceId],
                workDate = d.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                clockIn = d.ClockIn?.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture),
                clockOut = d.ClockOut?.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture),
                punches = d.Punches
            }).ToList();
        var skipped = parsed.Skipped + parsed.Days.Count(d => !employeeOf.ContainsKey(d.DeviceId));
        var (result, months) = await _repo.ImportAsync(Scope, s.FileName, layout.Format, layout.Describe(), parsed.DataRows, skipped, days, _user.UserId, ct);
        if (!result.Success) return result;

        _cache.Remove(Key(token));
        await RecalculateAsync(months, null, ct);
        return result;
    }

    public async Task RecalculateAsync(IEnumerable<AttMonth> months, long? employeeId = null, CancellationToken ct = default)
    {
        var scope = Scope;
        var patterns = (await _repo.PatternsAsync(scope, ct: ct)).ToDictionary(p => p.PatternId);
        var assignments = await _repo.AssignmentsAsync(scope, employeeId, ct);
        foreach (var m in months.Distinct())
        {
            var month = new DateTime(m.RunMonth.Year, m.RunMonth.Month, 1);
            var days = (await _repo.MonthDaysAsync(scope, m.CompanyId, month, employeeId, ct)).Where(d => d.Source != "GENERATED").ToList();
            var employees = await _repo.MonthEmployeesAsync(scope, m.CompanyId, month, employeeId, ct);
            var leave = await _repo.MonthLeaveAsync(m.CompanyId, month, ct);
            var holidays = await _repo.MonthHolidaysAsync(m.CompanyId, month, ct);
            // the days the files cover (a day with no punch in that range is absent)
            var imported = (await _repo.MonthDaysAsync(scope, m.CompanyId, month, null, ct)).Where(d => d.Source == "IMPORT").ToList();
            DateOnly? coverFrom = imported.Count == 0 ? null : DateOnly.FromDateTime(imported.Min(d => d.WorkDate));
            DateOnly? coverTo = imported.Count == 0 ? null : DateOnly.FromDateTime(imported.Max(d => d.WorkDate));

            var results = new List<AttDayResult>();
            foreach (var e in employees)
            {
                results.AddRange(AttendanceCalculator.Month(DateOnly.FromDateTime(month), e, assignments, patterns, days, leave, holidays, coverFrom, coverTo));
            }
            await _repo.SaveMonthAsync(scope, m.CompanyId, month, employeeId, results, _user.UserId, ct);
        }
    }
}
