namespace HRMS.Domain.Attendance;

/// <summary>A day as the calculation reads it (an existing Attendance.Records row).</summary>
public sealed class AttDayInput
{
    public long RecordId { get; init; }
    public long EmployeeId { get; init; }
    public DateTime WorkDate { get; init; }
    public DateTime? ClockIn { get; init; }
    public DateTime? ClockOut { get; init; }
    public int PunchCount { get; init; }
    public string Source { get; init; } = "IMPORT";
    public bool IsExcused { get; init; }
    public string? Note { get; init; }
    /// <summary>Marked by hand on the Attendance Sheet (db/129): wins over the clock times.</summary>
    public string? ManualStatus { get; init; }
    /// <summary>The minutes of a day marked late / short by hand.</summary>
    public int? ManualMinutes { get; init; }
}

/// <summary>An employee's salary and employment dates (the day's pay is worked out from them).</summary>
public sealed class AttEmployeeInput
{
    public long EmployeeId { get; init; }
    public int CompanyId { get; init; }
    public decimal BasicSalary { get; init; }
    public decimal Allowances { get; init; }
    public DateTime? HireDate { get; init; }
    public DateTime? TerminationDate { get; init; }
}

public sealed class AttLeaveInput
{
    public long EmployeeId { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public bool HalfDay { get; init; }
}

public sealed class AttHolidayInput
{
    public DateTime FromDate { get; init; }
    public DateTime ToDate { get; init; }
    public string? HolidayName { get; init; }
}

/// <summary>A day worked out (SAVE_CALC): an existing day (RecordId) or one added (absent, leave).</summary>
public sealed class AttDayResult
{
    public long RecordId { get; set; }
    public long EmployeeId { get; set; }
    public DateOnly WorkDate { get; set; }
    public int? PatternId { get; set; }
    public string Status { get; set; } = "PRESENT";
    public int WorkedMinutes { get; set; }
    public int LateMinutes { get; set; }
    public int ShortMinutes { get; set; }
    public int OvertimeMinutes { get; set; }
    public decimal DeductionAmount { get; set; }
    public decimal OvertimeAmount { get; set; }
    public string? DeductionNote { get; set; }

    internal decimal LateDeduction { get; set; }
    internal decimal ShortDeduction { get; set; }
}

/// <summary>
/// Works out an employee's month from their attendance pattern:
/// <list type="bullet">
/// <item>Fixed shift: late = clock in after the shift start (beyond the grace minutes); short hours =
///       the required minutes not worked (the break is taken off the time between clock in and out).</item>
/// <item>Flexible: only the minimum hours a day count (short hours).</item>
/// <item>Each is priced by its slabs (minutes from - to: an amount, a % of a day's pay, or the minutes
///       pro rata); with no slab defined the minutes are deducted pro rata. A day takes the higher of the
///       two, or both (the pattern says). The first late days of the month may be free.</item>
/// <item>A day with one punch: flagged for review, ignored, half a day or absent (the pattern says).</item>
/// <item>Days the device file covers with no punch are absent (a day's pay x the absence value), unless a
///       weekly day off, a public holiday or approved leave.</item>
/// <item>Overtime: the minutes past the required ones (from the threshold on) at the overtime rate;
///       on a day off or a holiday every minute worked.</item>
/// <item>The month's deduction stops at the cap (an amount, or a % of the salary).</item>
/// </list>
/// A day's pay = the salary (basic, or basic + allowances) / the day divisor (e.g. 26).
/// </summary>
public static class AttendanceCalculator
{
    public static List<AttDayResult> Month(
        DateOnly month,
        AttEmployeeInput employee,
        IReadOnlyList<AttendanceAssignment> assignments,
        IReadOnlyDictionary<int, AttendancePattern> patterns,
        IReadOnlyList<AttDayInput> days,
        IReadOnlyList<AttLeaveInput> leave,
        IReadOnlyList<AttHolidayInput> holidays,
        DateOnly? coverFrom,
        DateOnly? coverTo,
        DateOnly? monthFrom = null,
        DateOnly? monthTo = null)
    {
        // the payroll month: its days follow the payroll calendar's start day (25 -> 25 Sep - 24 Oct), else the calendar month
        var first = monthFrom ?? new DateOnly(month.Year, month.Month, 1);
        var last = monthTo ?? new DateOnly(month.Year, month.Month, 1).AddMonths(1).AddDays(-1);
        var results = new List<AttDayResult>();

        AttendancePattern? PatternOn(DateOnly d)
        {
            var a = assignments.Where(x => x.EmployeeId == employee.EmployeeId && DateOnly.FromDateTime(x.EffectiveFrom) <= d)
                               .OrderByDescending(x => x.EffectiveFrom).FirstOrDefault();
            return a is not null && patterns.TryGetValue(a.PatternId, out var p) ? p : null;
        }
        bool IsHoliday(DateOnly d) => holidays.Any(h => DateOnly.FromDateTime(h.FromDate) <= d && d <= DateOnly.FromDateTime(h.ToDate));
        AttLeaveInput? LeaveOn(DateOnly d) => leave.FirstOrDefault(l => l.EmployeeId == employee.EmployeeId
                                                                       && DateOnly.FromDateTime(l.StartDate) <= d && d <= DateOnly.FromDateTime(l.EndDate));

        // the days in the file
        var byDate = days.Where(x => x.EmployeeId == employee.EmployeeId)
                         .GroupBy(x => DateOnly.FromDateTime(x.WorkDate))
                         .ToDictionary(g => g.Key, g => g.First());
        foreach (var (date, day) in byDate.OrderBy(k => k.Key))
        {
            if (date < first || date > last) continue;
            var pattern = PatternOn(date);
            var result = new AttDayResult { RecordId = day.RecordId, EmployeeId = employee.EmployeeId, WorkDate = date, PatternId = pattern?.PatternId };
            Evaluate(result, day, pattern, employee, IsHoliday(date), LeaveOn(date));
            results.Add(result);
        }

        // the days the file covers with no punch: absent (or leave), for the employees in the file
        if (coverFrom is { } cf && coverTo is { } ct && byDate.Count > 0)
        {
            var hire = employee.HireDate is { } h ? DateOnly.FromDateTime(h) : DateOnly.MinValue;
            var leaving = employee.TerminationDate is { } t ? DateOnly.FromDateTime(t) : DateOnly.MaxValue;
            for (var d = cf < first ? first : cf; d <= (ct > last ? last : ct); d = d.AddDays(1))
            {
                if (byDate.ContainsKey(d) || d < hire || d > leaving) continue;
                var pattern = PatternOn(d);
                if (pattern is null || pattern.IsOff(d) || IsHoliday(d)) continue;
                var rate = DayRate(pattern, employee);
                var r = new AttDayResult { RecordId = 0, EmployeeId = employee.EmployeeId, WorkDate = d, PatternId = pattern.PatternId };
                if (LeaveOn(d) is { } lv)
                {
                    r.Status = "LEAVE";
                    if (lv.HalfDay) r.DeductionNote = "Half-day leave";
                }
                else
                {
                    r.Status = "ABSENT";
                    if (pattern.AbsentEnabled)
                    {
                        r.DeductionAmount = Round(rate * pattern.AbsentDayValue);
                        r.DeductionNote = pattern.AbsentDayValue == 1 ? "Absent - a day's pay" : $"Absent - {pattern.AbsentDayValue:0.##} days' pay";
                    }
                }
                results.Add(r);
            }
        }

        results.Sort((a, b) => a.WorkDate.CompareTo(b.WorkDate));
        ApplyFreeLates(results, patterns);
        ApplyCap(results, patterns, employee);
        return results;
    }

    /// <summary>A day's pay: the salary basis / the day divisor.</summary>
    public static decimal DayRate(AttendancePattern p, AttEmployeeInput e)
    {
        var monthly = p.SalaryBasis == "GROSS" ? e.BasicSalary + e.Allowances : e.BasicSalary;
        return p.DayDivisor <= 0 ? 0 : monthly / p.DayDivisor;
    }

    private static void Evaluate(AttDayResult r, AttDayInput day, AttendancePattern? p, AttEmployeeInput e, bool holiday, AttLeaveInput? leave)
    {
        var worked = 0;
        if (day.ClockIn is { } ci && day.ClockOut is { } co && co > ci)
        {
            worked = (int)Math.Round((co - ci).TotalMinutes);
            if (p is not null && p.BreakMinutes > 0 && worked > p.BreakMinutes) worked -= p.BreakMinutes;
        }
        r.WorkedMinutes = worked;

        if (day.ManualStatus is { Length: > 0 } manual)
        {
            Manual(r, manual, day.ManualMinutes ?? 0, day.Note, p, e);
            return;
        }

        if (p is null)
        {
            r.Status = "NO_PATTERN";
            r.DeductionNote = "No attendance pattern assigned";
            return;
        }

        var rate = DayRate(p, e);
        var minuteRate = p.RequiredMinutes > 0 ? rate / p.RequiredMinutes : 0;
        var date = DateOnly.FromDateTime(day.WorkDate);
        var off = p.IsOff(date) || holiday;

        if (day.IsExcused)
        {
            r.Status = "EXCUSED";
            r.DeductionNote = string.IsNullOrWhiteSpace(day.Note) ? "Excused" : "Excused - " + day.Note;
            return;
        }
        if (leave is not null && !leave.HalfDay && (day.ClockIn is null || day.ClockOut is null))
        {
            r.Status = "LEAVE";
            return;
        }

        // a day off / holiday worked: overtime only
        if (off)
        {
            r.Status = "PRESENT";
            r.DeductionNote = holiday ? "Public holiday worked" : "Day off worked";
            if (p.OvertimeEnabled && worked > 0)
            {
                r.OvertimeMinutes = worked;
                r.OvertimeAmount = Round(worked / 60m * (minuteRate * 60) * p.OvertimeRate);
            }
            return;
        }

        // one punch only
        if (day.ClockIn is null || day.ClockOut is null)
        {
            switch (p.MissingPunch)
            {
                case "IGNORE":
                    r.Status = "PRESENT";
                    r.DeductionNote = "One punch - no deduction";
                    break;
                case "HALF_DAY":
                    r.Status = "MISSING";
                    r.DeductionAmount = Round(rate / 2);
                    r.DeductionNote = "One punch - half a day's pay";
                    break;
                case "ABSENT":
                    r.Status = "ABSENT";
                    r.DeductionAmount = p.AbsentEnabled ? Round(rate * p.AbsentDayValue) : 0;
                    r.DeductionNote = "One punch - counted absent";
                    break;
                default:
                    r.Status = "MISSING";
                    r.DeductionNote = day.ClockIn is null ? "No clock in - to review" : "No clock out - to review";
                    break;
            }
            return;
        }

        // late arrival (a fixed shift only), beyond the grace minutes
        var late = 0;
        if (p.IsFixed && p.ShiftStart is { } start)
        {
            var shiftStart = day.WorkDate.Date.Add(start);
            // a night shift: a clock in before midnight belongs to the shift starting that evening
            var diff = (int)Math.Round((day.ClockIn.Value - shiftStart).TotalMinutes);
            if (diff > p.GraceMinutes) late = diff;
        }
        // short hours: the required minutes not worked (within the grace minutes: none)
        var shortMin = Math.Max(0, p.RequiredMinutes - worked);
        if (shortMin <= p.GraceMinutes) shortMin = 0;
        r.LateMinutes = late;
        r.ShortMinutes = shortMin;
        r.Status = late > 0 && shortMin > 0 ? "LATE_SHORT" : late > 0 ? "LATE" : shortMin > 0 ? "SHORT" : "PRESENT";

        r.LateDeduction = p.LateEnabled && late > 0 ? Price(p, AttCodes.Late, late, rate, minuteRate) : 0;
        r.ShortDeduction = p.ShortEnabled && shortMin > 0 ? Price(p, AttCodes.Short, shortMin, rate, minuteRate) : 0;
        Combine(r, p);

        // overtime: past the required minutes, from the threshold on
        if (p.OvertimeEnabled)
        {
            var extra = worked - p.RequiredMinutes;
            if (extra >= Math.Max(1, p.OvertimeAfterMinutes))
            {
                r.OvertimeMinutes = extra;
                r.OvertimeAmount = Round(extra * minuteRate * p.OvertimeRate);
            }
        }
    }

    /// <summary>A day marked by hand: its status, and the deduction the pattern gives it (none without a pattern).</summary>
    private static void Manual(AttDayResult r, string status, int minutes, string? note, AttendancePattern? p, AttEmployeeInput e)
    {
        var rate = p is null ? 0 : DayRate(p, e);
        var minuteRate = p is not null && p.RequiredMinutes > 0 ? rate / p.RequiredMinutes : 0;
        var by = string.IsNullOrWhiteSpace(note) ? "Marked by hand" : "Marked by hand - " + note;
        r.Status = status;
        r.DeductionNote = by;
        switch (status)
        {
            case "ABSENT":
                if (p is { AbsentEnabled: true })
                {
                    r.DeductionAmount = Round(rate * p.AbsentDayValue);
                    r.DeductionNote = (p.AbsentDayValue == 1 ? "Absent - a day's pay" : $"Absent - {p.AbsentDayValue:0.##} days' pay") + " · " + by;
                }
                break;
            case "LATE":
                r.LateMinutes = Math.Max(0, minutes);
                if (p is not null)
                {
                    r.LateDeduction = p.LateEnabled && r.LateMinutes > 0 ? Price(p, AttCodes.Late, r.LateMinutes, rate, minuteRate) : 0;
                    Combine(r, p);
                    r.DeductionNote = r.DeductionNote is null ? by : r.DeductionNote + " · " + by;
                }
                break;
            case "SHORT":
                r.ShortMinutes = Math.Max(0, minutes);
                if (p is not null)
                {
                    r.ShortDeduction = p.ShortEnabled && r.ShortMinutes > 0 ? Price(p, AttCodes.Short, r.ShortMinutes, rate, minuteRate) : 0;
                    Combine(r, p);
                    r.DeductionNote = r.DeductionNote is null ? by : r.DeductionNote + " · " + by;
                }
                break;
        }
    }

    private static void Combine(AttDayResult r, AttendancePattern p)
    {
        var both = p.CombineRule == "BOTH";
        r.DeductionAmount = Round(both ? r.LateDeduction + r.ShortDeduction : Math.Max(r.LateDeduction, r.ShortDeduction));
        var parts = new List<string>();
        // the minutes are always shown - also when they stay under the first slab (deduction 0.000)
        if (r.LateMinutes > 0) parts.Add($"Late {r.LateMinutes} min: {r.LateDeduction:0.000}");
        if (r.ShortMinutes > 0) parts.Add($"Short {r.ShortMinutes} min: {r.ShortDeduction:0.000}");
        r.DeductionNote = parts.Count == 0 ? null
            : parts.Count == 2 && !both && r.LateDeduction > 0 && r.ShortDeduction > 0 ? string.Join(" · ", parts) + " (the higher)" : string.Join(" · ", parts);
    }

    /// <summary>The deduction of the minutes by the slabs (none defined: the minutes pro rata).</summary>
    public static decimal Price(AttendancePattern p, string kind, int minutes, decimal dayRate, decimal minuteRate)
    {
        var slabs = p.Slabs.Where(s => s.RuleKind == kind).ToList();
        if (slabs.Count == 0) return Round(minutes * minuteRate);
        var slab = slabs.Where(s => s.Covers(minutes)).OrderByDescending(s => s.FromMinutes).FirstOrDefault();
        if (slab is null) return 0;
        return Round(slab.DeductionType switch
        {
            AttCodes.DayPercent => dayRate * slab.Value / 100m,
            AttCodes.Prorata => minutes * minuteRate * (slab.Value <= 0 ? 1 : slab.Value),
            _ => slab.Value
        });
    }

    /// <summary>The first N late days of the month carry no late deduction.</summary>
    private static void ApplyFreeLates(List<AttDayResult> results, IReadOnlyDictionary<int, AttendancePattern> patterns)
    {
        var used = 0;
        foreach (var r in results)
        {
            if (r.LateMinutes <= 0 || r.PatternId is not { } pid || !patterns.TryGetValue(pid, out var p) || p.FreeLatesPerMonth <= 0) continue;
            if (used >= p.FreeLatesPerMonth) continue;
            used++;
            r.LateDeduction = 0;
            Combine(r, p);
            r.DeductionNote = $"Free late {used} of {p.FreeLatesPerMonth}" + (r.DeductionNote is null ? "" : " · " + r.DeductionNote);
        }
    }

    /// <summary>The month's deductions stop at the cap of the pattern (the latest days give way first).</summary>
    private static void ApplyCap(List<AttDayResult> results, IReadOnlyDictionary<int, AttendancePattern> patterns, AttEmployeeInput e)
    {
        var lastPattern = results.LastOrDefault(r => r.PatternId is not null)?.PatternId;
        if (lastPattern is not { } pid || !patterns.TryGetValue(pid, out var p) || p.MaxDeductionType == "NONE" || p.MaxDeductionValue is not > 0) return;
        var monthly = p.SalaryBasis == "GROSS" ? e.BasicSalary + e.Allowances : e.BasicSalary;
        var cap = p.MaxDeductionType == "PERCENT" ? Round(monthly * p.MaxDeductionValue.Value / 100m) : p.MaxDeductionValue.Value;
        var total = results.Sum(r => r.DeductionAmount);
        if (total <= cap) return;
        var over = total - cap;
        for (var i = results.Count - 1; i >= 0 && over > 0; i--)
        {
            var r = results[i];
            if (r.DeductionAmount <= 0) continue;
            var cut = Math.Min(r.DeductionAmount, over);
            r.DeductionAmount = Round(r.DeductionAmount - cut);
            over -= cut;
            r.DeductionNote = (r.DeductionNote is null ? "" : r.DeductionNote + " · ") + $"monthly cap {cap:0.000} reached";
        }
    }

    private static decimal Round(decimal v) => Math.Round(v, 3, MidpointRounding.AwayFromZero);
}
