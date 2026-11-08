using HRMS.Domain.Attendance;
using HRMS.Domain.Common;

namespace HRMS.Web.Models.Attendance;

public sealed class AttRights
{
    public bool CanView { get; init; }
    public bool CanImport { get; init; }
    public bool CanPost { get; init; }
    public bool CanSetupView { get; init; }
    public bool CanSetupEdit { get; init; }
}

/// <summary>Attendance: the days of a month.</summary>
public sealed class AttRegisterModel
{
    public required AttRights Rights { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = [];
    public int? CompanyId { get; init; }
    public IReadOnlyList<DateTime> Months { get; init; } = [];
    public DateTime Month { get; init; }
    public string? Status { get; init; }
    public long? EmployeeId { get; init; }
    public string? Search { get; init; }
    public AttendanceKpis Kpis { get; init; } = new();
}

public sealed class AttRecordsModel
{
    public required PagedResult<AttendanceRecord> Page { get; init; }
    public required AttRights Rights { get; init; }
    public bool ManyCompanies { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class AttDayFormModel
{
    public AttendanceRecord? Record { get; init; }
    /// <summary>A day to add from the Attendance Sheet: the employee and the date clicked.</summary>
    public long? EmployeeId { get; init; }
    public DateTime? Date { get; init; }
    public IReadOnlyList<AttendanceEmployee> Employees { get; init; } = [];
}

public sealed class AttImportPageModel
{
    public required AttRights Rights { get; init; }
}

public sealed class AttImportsModel
{
    public required PagedResult<AttendanceImport> Page { get; init; }
    public required AttRights Rights { get; init; }
}

/// <summary>Monthly Summary: each employee's month, posted to the payroll.</summary>
public sealed class AttSummaryModel
{
    public required AttRights Rights { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = [];
    public int? CompanyId { get; init; }
    public IReadOnlyList<DateTime> Months { get; init; } = [];
    public DateTime Month { get; init; }
    public IReadOnlyList<AttendanceSummaryRow> Rows { get; init; } = [];
    public AttendanceKpis Kpis { get; init; } = new();
    /// <summary>The days of the payroll month (db/137: the payroll calendar's start day).</summary>
    public DateTime? From { get; init; }
    public DateTime? To { get; init; }
    /// <summary>A payroll is created for the month (or it is posted): it cannot be worked out again.</summary>
    public bool Locked { get; init; }

    public bool AnyPosted => Rows.Any(r => r.IsPosted);
    public bool AnyChanged => Rows.Any(r => r.ChangedSincePosted) || (AnyPosted && Rows.Any(r => !r.IsPosted && (r.DeductionAmount > 0 || r.OvertimeAmount > 0)));
    public decimal TotalDeduction => Rows.Sum(r => r.DeductionAmount);
    public decimal TotalOvertime => Rows.Sum(r => r.OvertimeAmount);
}

public sealed class AttEmployeesPageModel
{
    public required AttRights Rights { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = [];
    public int? CompanyId { get; init; }
    public int? PatternId { get; init; }
    public string? Search { get; init; }
    public IReadOnlyList<AttendancePattern> Patterns { get; init; } = [];
}

public sealed class AttEmployeesModel
{
    public required PagedResult<AttendanceEmployee> Page { get; init; }
    public IReadOnlyList<AttendancePattern> Patterns { get; init; } = [];
    public required AttRights Rights { get; init; }
    public bool ManyCompanies { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class AttSettingsModel
{
    public required AttRights Rights { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = [];
}

public sealed class AttPatternsModel
{
    public IReadOnlyList<AttendancePattern> Patterns { get; init; } = [];
    public required AttRights Rights { get; init; }
    public bool ManyCompanies { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class AttPatternFormModel
{
    public required AttendancePattern Pattern { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = [];
}

/// <summary>A day of the Attendance Sheet: what is shown (✓, ✗, L 12 ...) and what a click does.</summary>
/// <param name="AlsoShort">Late and short hours the same day (shown L, counted in both).</param>
public sealed record AttSheetCell(string Text, string Kind, string? Title, long RecordId, string? Sub = null, bool Manual = false, int Minutes = 0, bool AlsoShort = false,
                                  int LateMin = 0, int ShortMin = 0);

public sealed class AttSheetRow
{
    public required AttSheetEmployee Employee { get; init; }
    public required IReadOnlyList<AttSheetCell> Cells { get; init; }
    public int Present { get; init; }
    public int Late { get; init; }
    public int Short { get; init; }
    /// <summary>The late / short time the deduction is worked out on (minutes).</summary>
    public int LateMinutes { get; init; }
    public int ShortMinutes { get; init; }
    public int Absent { get; init; }
    public int Leave { get; init; }
    public decimal Deduction { get; init; }
}

/// <summary>
/// Time &amp; Attendance > Attendance Sheet: employees down the left, the days of the range across.
/// The range is the payroll period of the payroll month, or a From / To chosen (62 days at most).
/// </summary>
public sealed class AttSheetModel
{
    public const int MaxDays = 62;

    public required AttRights Rights { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = [];
    public int? CompanyId { get; init; }
    public IReadOnlyList<DateTime> Months { get; init; } = [];
    public DateTime Month { get; init; }
    public DateTime From { get; init; }
    public DateTime To { get; init; }
    /// <summary>The range is the payroll period of the month (not a From / To of its own).</summary>
    public bool IsPeriod { get; init; }
    public bool Clipped { get; init; }
    public string? Search { get; init; }
    public IReadOnlyList<DateTime> Days { get; init; } = [];
    public IReadOnlyList<AttSheetRow> Rows { get; init; } = [];
    public IReadOnlyList<int> PresentPerDay { get; init; } = [];
    /// <summary>Per day: the payroll is generated (or the month posted) - it cannot be marked.</summary>
    public IReadOnlyList<bool> LockedDays { get; init; } = [];
    /// <summary>A payroll is created for (part of) the range: it cannot be worked out again.</summary>
    public bool PayrollCreated { get; init; }

    private static readonly HashSet<string> PresentCodes = ["PRESENT", "LATE", "SHORT", "LATE_SHORT", "EXCUSED", "NO_PATTERN"];

    /// <summary>Builds the rows: each employee's day from their record, else leave, holiday, day off or nothing.</summary>
    public static (IReadOnlyList<AttSheetRow> Rows, IReadOnlyList<int> PerDay) Build(
        IReadOnlyList<DateTime> days, IReadOnlyList<AttSheetEmployee> employees, IReadOnlyList<AttendanceRecord> records,
        IReadOnlyList<AttHolidayInput> holidays, IReadOnlyList<AttLeaveInput> leave,
        IReadOnlyList<AttendanceAssignment> assignments, IReadOnlyDictionary<int, AttendancePattern> patterns)
    {
        var byKey = records.GroupBy(r => (r.EmployeeId, r.WorkDate.Date)).ToDictionary(g => g.Key, g => g.First());
        var today = DateTime.Today;
        var perDay = new int[days.Count];
        string T(DateTime? d) => d?.ToString("HH:mm", System.Globalization.CultureInfo.InvariantCulture) ?? "—";
        bool Holiday(DateTime d, out string? name)
        {
            var h = holidays.FirstOrDefault(x => x.FromDate.Date <= d && d <= x.ToDate.Date);
            name = h?.HolidayName;
            return h is not null;
        }

        var rows = new List<AttSheetRow>();
        foreach (var e in employees)
        {
            var cells = new List<AttSheetCell>();
            int present = 0, late = 0, shortDays = 0, absent = 0, onLeave = 0, lateMin = 0, shortMin = 0;
            decimal ded = 0;
            var empAssign = assignments.Where(a => a.EmployeeId == e.EmployeeId).OrderBy(a => a.EffectiveFrom).ToList();
            for (var i = 0; i < days.Count; i++)
            {
                var d = days[i];
                if (byKey.TryGetValue((e.EmployeeId, d), out var r))
                {
                    var times = $"{T(r.ClockIn)} – {T(r.ClockOut)}";
                    // the tooltip: the times, the late / short time (also under the first slab), the deduction, then any other note
                    var tip = new List<string> { times };
                    if (r.LateMinutes > 0) tip.Add($"Late {AttFormat.Hm(r.LateMinutes)}");
                    if (r.ShortMinutes > 0) tip.Add($"Short {AttFormat.Hm(r.ShortMinutes)}");
                    if (r.LateMinutes > 0 || r.ShortMinutes > 0 || r.DeductionAmount > 0)
                        tip.Add($"Deduction {r.DeductionAmount.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture)}");
                    if (!string.IsNullOrWhiteSpace(r.DeductionNote) && (r.LateMinutes == 0 && r.ShortMinutes == 0 || !string.IsNullOrEmpty(r.ManualStatus)))
                        tip.Add(r.DeductionNote!);
                    var title = string.Join(" · ", tip);
                    var manual = !string.IsNullOrEmpty(r.ManualStatus);
                    AttSheetCell cell = r.Status switch
                    {
                        "PRESENT" => new("✓", "ok", title, r.RecordId),
                        "LATE" or "LATE_SHORT" => new("L", "late", title, r.RecordId, r.LateMinutes > 0 ? r.LateMinutes.ToString(System.Globalization.CultureInfo.InvariantCulture) : null, Minutes: r.LateMinutes),
                        "SHORT" => new("S", "short", title, r.RecordId, Minutes: r.ShortMinutes),
                        "ABSENT" => new("✗", "absent", title, r.RecordId),
                        "MISSING" => new("?", "missing", title, r.RecordId),
                        "LEAVE" => new("LV", "leave", title, r.RecordId),
                        "EXCUSED" => new("E", "excused", title, r.RecordId),
                        "HOLIDAY" => new("H", "holiday", title, r.RecordId),
                        "OFF" => new("·", "off", title, r.RecordId),
                        _ => new("✓", "nopattern", title, r.RecordId)
                    };
                    if (manual) cell = cell with { Manual = true };
                    if (r.Status == "LATE_SHORT") cell = cell with { AlsoShort = true };
                    cell = cell with { LateMin = r.LateMinutes, ShortMin = r.ShortMinutes };
                    lateMin += r.LateMinutes;
                    shortMin += r.ShortMinutes;
                    cells.Add(cell);
                    if (PresentCodes.Contains(r.Status)) { present++; perDay[i]++; }
                    if (r.Status is "LATE" or "LATE_SHORT") late++;
                    if (r.Status is "SHORT" or "LATE_SHORT") shortDays++;
                    if (r.Status == "ABSENT") absent++;
                    if (r.Status == "LEAVE") onLeave++;
                    ded += r.DeductionAmount;
                    continue;
                }
                if ((e.HireDate is { } h && d < h.Date) || (e.TerminationDate is { } t && d > t.Date)) { cells.Add(new("", "out", null, 0)); continue; }
                if (leave.Any(l => l.EmployeeId == e.EmployeeId && l.StartDate.Date <= d && d <= l.EndDate.Date))
                {
                    cells.Add(new("LV", "leave", null, 0)); onLeave++; continue;
                }
                if (Holiday(d, out var hn)) { cells.Add(new("H", "holiday", hn, 0)); continue; }
                var a = empAssign.LastOrDefault(x => x.EffectiveFrom.Date <= d);
                if (a is not null && patterns.TryGetValue(a.PatternId, out var p) && p.IsOff(DateOnly.FromDateTime(d)))
                {
                    cells.Add(new("·", "off", null, 0)); continue;
                }
                cells.Add(new(d > today ? "" : "–", d > today ? "future" : "none", null, 0));
            }
            rows.Add(new AttSheetRow { Employee = e, Cells = cells, Present = present, Late = late, Short = shortDays, LateMinutes = lateMin, ShortMinutes = shortMin, Absent = absent, Leave = onLeave, Deduction = ded });
        }
        return (rows, perDay);
    }
}
