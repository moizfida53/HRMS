using System.Globalization;
using HRMS.Domain.Attendance;
using HRMS.Domain.Leave;

namespace HRMS.Web.Areas.Ess.Models;

/// <summary>The self-service sign-in page (/ess/login).</summary>
public sealed class EssLoginModel
{
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public bool RememberMe { get; set; } = true;
    public string? ReturnUrl { get; set; }
    public string? ErrorMessage { get; set; }
    public string? InfoMessage { get; set; }
}

/// <summary>The Punch tab: today's card and the month's figures.</summary>
public sealed class EssHomeModel
{
    public required EssToday Today { get; init; }
    public required EssMonthModel Month { get; init; }
    public required EssLeaveModel Leave { get; init; }
    public int RadiusM { get; init; }
}

/// <summary>The Attendance tab: one calendar month.</summary>
public sealed class EssMonthModel
{
    public DateTime Month { get; init; }
    public DateTime Today { get; init; }
    public IReadOnlyList<EssDay> Days { get; init; } = [];
    /// <summary>The months offered in the picker (this one and the 11 before).</summary>
    public IReadOnlyList<DateTime> Months { get; init; } = [];

    public int Present => Days.Count(d => d.CountsPresent);
    public int Absent => Days.Count(d => d.CountsAbsent);
    public int Short => Days.Count(d => d.CountsShort);
    public int Late => Days.Count(d => d.CountsLate);
    public int Leave => Days.Count(d => d.CountsLeave);

    public EssDay? DayOf(DateTime date) => Days.FirstOrDefault(d => d.WorkDate.Date == date.Date);
}

/// <summary>The Leave tab: annual leave only (no sick or other types).</summary>
public sealed class EssLeaveModel
{
    /// <summary>The employee's annual leave balance; null when annual leave is not set up.</summary>
    public LeaveBalance? Annual { get; init; }
    public IReadOnlyList<LeaveRequest> Requests { get; init; } = [];

    public decimal DaysLeft => Annual is null ? 0 : (Annual.Available ?? 0) - Annual.Pending;

    /// <summary>The share of the entitlement still free, for the ring (0-100).</summary>
    public int Percent =>
        Annual?.Entitled is { } e && e > 0 ? (int)Math.Clamp(Math.Round(DaysLeft / e * 100), 0, 100) : 0;
}

public sealed class EssPageModel
{
    public required EssHomeModel Home { get; init; }
    public EssProfile? Profile { get; init; }
    public string Initials { get; init; } = "?";
    /// <summary>The user can also open the full system (has any permission besides self-service).</summary>
    public bool CanOpenDesktop { get; init; }
}

public static class EssFormat
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string Time(DateTime? t) => t is { } v ? v.ToString("HH:mm", Inv) : "--:--";

    public static string Hours(int minutes) =>
        minutes <= 0 ? "—" : $"{(minutes / 60).ToString(Inv)}h {(minutes % 60).ToString("00", Inv)}m";

    /// <summary>The CSS modifier of a day's status (calendar cell, pill).</summary>
    public static string Tone(string? status) => status switch
    {
        "PRESENT" or "EXCUSED" => "present",
        "LATE" => "late",
        "SHORT" or "LATE_SHORT" => "short",
        "ABSENT" => "absent",
        "LEAVE" => "leave",
        "HOLIDAY" or "OFF" => "off",
        "MISSING" => "missing",
        _ => "none"
    };

    /// <summary>The English label of a day's status (translated with L.Tr).</summary>
    public static string StatusText(string? status) => status switch
    {
        "PRESENT" => "Present",
        "EXCUSED" => "Excused",
        "LATE" => "Late",
        "SHORT" => "Short",
        "LATE_SHORT" => "Late",
        "ABSENT" => "Absent",
        "LEAVE" => "Leave",
        "HOLIDAY" => "Holiday",
        "OFF" => "Day off",
        "MISSING" => "One punch",
        "NO_PATTERN" => "Present",
        _ => status ?? string.Empty
    };

    /// <summary>"2900•••••123": the first 4 and last 3 characters of an id.</summary>
    public static string Mask(string? value, int head = 4, int tail = 3)
    {
        if (string.IsNullOrWhiteSpace(value)) return "—";
        var v = value.Trim();
        if (v.Length <= head + tail) return v;
        return string.Concat(v.AsSpan(0, head), new string('•', v.Length - head - tail), v.AsSpan(v.Length - tail));
    }
}
