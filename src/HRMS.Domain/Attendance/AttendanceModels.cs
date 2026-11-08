namespace HRMS.Domain.Attendance;

/// <summary>Codes of Time &amp; Attendance (db/126).</summary>
public static class AttCodes
{
    public const string Fixed = "FIXED";
    public const string Flexible = "FLEXIBLE";

    public const string Late = "LATE";
    public const string Short = "SHORT";

    public const string Amount = "AMOUNT";
    public const string DayPercent = "DAY_PERCENT";
    public const string Prorata = "PRORATA";

    public static readonly string[] Statuses =
        ["PRESENT", "LATE", "SHORT", "LATE_SHORT", "ABSENT", "MISSING", "LEAVE", "EXCUSED", "NO_PATTERN", "OFF", "HOLIDAY"];

    public static readonly string[] WeekDays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

    public static string Day(DayOfWeek d) => WeekDays[(int)d];

    public static string StatusBadge(string? status) => status switch
    {
        "PRESENT" => "success",
        "LATE" or "SHORT" or "LATE_SHORT" => "warning",
        "ABSENT" => "danger",
        "MISSING" or "NO_PATTERN" => "purple",
        "LEAVE" or "EXCUSED" or "HOLIDAY" or "OFF" => "info",
        _ => "muted"
    };
}

/// <summary>An attendance pattern: working hours / shift and its deduction rules (Attendance.Patterns).</summary>
public sealed class AttendancePattern
{
    public int PatternId { get; set; }
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string PatternCode { get; set; } = string.Empty;
    public string PatternName { get; set; } = string.Empty;
    public string? ArabicName { get; set; }
    /// <summary>FIXED (a shift: start - end) or FLEXIBLE (minimum hours a day).</summary>
    public string PatternType { get; set; } = AttCodes.Fixed;
    public TimeSpan? ShiftStart { get; set; }
    public TimeSpan? ShiftEnd { get; set; }
    /// <summary>The working minutes a day (e.g. 690 = 11:30).</summary>
    public int RequiredMinutes { get; set; } = 480;
    public int BreakMinutes { get; set; }
    public int GraceMinutes { get; set; }
    /// <summary>"FRI,SAT".</summary>
    public string? WeeklyOffDays { get; set; }
    public bool LateEnabled { get; set; } = true;
    public bool ShortEnabled { get; set; } = true;
    /// <summary>HIGHER (the higher of the late and short-hours deductions of a day) or BOTH (added).</summary>
    public string CombineRule { get; set; } = "HIGHER";
    public int FreeLatesPerMonth { get; set; }
    public bool AbsentEnabled { get; set; } = true;
    public decimal AbsentDayValue { get; set; } = 1m;
    /// <summary>FLAG (to review), IGNORE, HALF_DAY, ABSENT.</summary>
    public string MissingPunch { get; set; } = "FLAG";
    public bool OvertimeEnabled { get; set; }
    public int OvertimeAfterMinutes { get; set; } = 30;
    public decimal OvertimeRate { get; set; } = 1.25m;
    /// <summary>BASIC or GROSS (basic + allowances): the salary a day's pay is worked out from.</summary>
    public string SalaryBasis { get; set; } = "BASIC";
    public int DayDivisor { get; set; } = 26;
    /// <summary>NONE, AMOUNT (KWD a month) or PERCENT (of the salary basis).</summary>
    public string MaxDeductionType { get; set; } = "NONE";
    public decimal? MaxDeductionValue { get; set; }
    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;
    public int EmployeeCount { get; set; }
    public List<AttendanceSlab> Slabs { get; set; } = [];

    public bool IsFixed => PatternType == AttCodes.Fixed;

    public bool IsOff(DateOnly date) =>
        !string.IsNullOrWhiteSpace(WeeklyOffDays) &&
        WeeklyOffDays.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                     .Contains(AttCodes.Day(date.DayOfWeek), StringComparer.OrdinalIgnoreCase);

    /// <summary>"10:00 – 22:00" / "11:30 h".</summary>
    public string HoursText => IsFixed && ShiftStart is { } s && ShiftEnd is { } e
        ? $"{s:hh\\:mm} – {e:hh\\:mm}"
        : $"{RequiredMinutes / 60}:{RequiredMinutes % 60:00} h";
}

/// <summary>A late / short-hours slab: from - to minutes and what is deducted.</summary>
public sealed class AttendanceSlab
{
    public int SlabId { get; set; }
    public int PatternId { get; set; }
    public string RuleKind { get; set; } = AttCodes.Late;
    public int FromMinutes { get; set; }
    public int? ToMinutes { get; set; }
    /// <summary>AMOUNT (KWD), DAY_PERCENT (% of a day's pay), PRORATA (the minutes at the minute rate x Value, 0 = x1).</summary>
    public string DeductionType { get; set; } = AttCodes.Amount;
    public decimal Value { get; set; }

    public bool Covers(int minutes) => minutes >= FromMinutes && (ToMinutes is null || minutes <= ToMinutes);
}

/// <summary>An employee as Time &amp; Attendance shows them (device ID, pattern now).</summary>
public sealed class AttendanceEmployee
{
    public long EmployeeId { get; set; }
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeCode { get; set; }
    public string? EmployeeName { get; set; }
    public string? ArabicName { get; set; }
    public string? DepartmentName { get; set; }
    public string? EmploymentStatus { get; set; }
    public DateTime? HireDate { get; set; }
    public string? DeviceUserId { get; set; }
    public int? PatternId { get; set; }
    public DateTime? EffectiveFrom { get; set; }
    public string? PatternCode { get; set; }
    public string? PatternName { get; set; }
    public int? NextPatternId { get; set; }
    public DateTime? NextFrom { get; set; }
    public decimal? BasicSalary { get; set; }
    public decimal? Allowances { get; set; }
    public int Total { get; set; }

    public string DisplayNo => !string.IsNullOrWhiteSpace(EmployeeCode) ? EmployeeCode! : EmployeeNo ?? string.Empty;
}

public sealed class AttendanceAssignment
{
    public long AssignmentId { get; set; }
    public long EmployeeId { get; set; }
    public int PatternId { get; set; }
    public DateTime EffectiveFrom { get; set; }
}

/// <summary>One employee's day (Attendance.Records).</summary>
public sealed class AttendanceRecord
{
    public long RecordId { get; set; }
    public long? ImportId { get; set; }
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? ArabicName { get; set; }
    public string? DepartmentName { get; set; }
    public DateTime WorkDate { get; set; }
    public DateTime? ClockIn { get; set; }
    public DateTime? ClockOut { get; set; }
    public int PunchCount { get; set; }
    public string Source { get; set; } = "IMPORT";
    public int? PatternId { get; set; }
    public string? PatternName { get; set; }
    public string Status { get; set; } = "PRESENT";
    public int WorkedMinutes { get; set; }
    public int LateMinutes { get; set; }
    public int ShortMinutes { get; set; }
    public int OvertimeMinutes { get; set; }
    public decimal DeductionAmount { get; set; }
    public decimal OvertimeAmount { get; set; }
    public string? DeductionNote { get; set; }
    public bool IsExcused { get; set; }
    public string? Note { get; set; }
    public DateTime? OriginalClockIn { get; set; }
    public DateTime? OriginalClockOut { get; set; }
    public DateTime? EditedDate { get; set; }
    public string? EditedByName { get; set; }
    public bool IsPosted { get; set; }
    public int Total { get; set; }
}

/// <summary>The month's figures (KPIS).</summary>
public sealed class AttendanceKpis
{
    public int EmployeeCount { get; set; }
    public int PresentDays { get; set; }
    public int LateDays { get; set; }
    public int ShortDays { get; set; }
    public int AbsentDays { get; set; }
    public int ReviewDays { get; set; }
    public int LateMinutes { get; set; }
    public int ShortMinutes { get; set; }
    public int OvertimeMinutes { get; set; }
    public decimal DeductionAmount { get; set; }
    public decimal OvertimeAmount { get; set; }
    public DateTime? FirstDate { get; set; }
    public DateTime? LastDate { get; set; }
}

/// <summary>A file imported.</summary>
public sealed class AttendanceImport
{
    public long ImportId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FileFormat { get; set; } = "PAIRED";
    public string? MappingText { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public int FileRowCount { get; set; }
    public int RecordCount { get; set; }
    public int EmployeeCount { get; set; }
    public int SkippedCount { get; set; }
    public DateTime CreatedDate { get; set; }
    public string? CreatedByName { get; set; }
    public int LiveCount { get; set; }
    public int Total { get; set; }
}

/// <summary>One employee's month (Monthly Summary).</summary>
public sealed class AttendanceSummaryRow
{
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? ArabicName { get; set; }
    public string? DepartmentName { get; set; }
    public string? PatternName { get; set; }
    public int DayCount { get; set; }
    public int PresentDays { get; set; }
    public int LateDays { get; set; }
    public int ShortDays { get; set; }
    public int AbsentDays { get; set; }
    public int LeaveDays { get; set; }
    public int ReviewDays { get; set; }
    public int WorkedMinutes { get; set; }
    public int LateMinutes { get; set; }
    public int ShortMinutes { get; set; }
    public int OvertimeMinutes { get; set; }
    public decimal DeductionAmount { get; set; }
    public decimal OvertimeAmount { get; set; }
    public decimal? PostedDeduction { get; set; }
    public decimal? PostedOvertime { get; set; }
    public DateTime? PostedDate { get; set; }
    public string? PostedByName { get; set; }

    public bool IsPosted => PostedDate is not null;
    /// <summary>Posted, but the days changed since.</summary>
    public bool ChangedSincePosted => IsPosted && (PostedDeduction != DeductionAmount || PostedOvertime != OvertimeAmount);
}

/// <summary>An employee row of the Attendance Sheet.</summary>
public sealed class AttSheetEmployee
{
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? ArabicName { get; set; }
    public string? DepartmentName { get; set; }
    public DateTime? HireDate { get; set; }
    public DateTime? TerminationDate { get; set; }
}

/// <summary>A payroll period (the Attendance Sheet's range for a payroll month).</summary>
public sealed class AttPeriod
{
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
}

/// <summary>Minutes as "h:mm".</summary>
public static class AttFormat
{
    public static string Hm(int minutes) => minutes <= 0 ? "—" : $"{minutes / 60}:{minutes % 60:00}";
    public static string HmOrZero(int minutes) => minutes <= 0 ? "0:00" : $"{minutes / 60}:{minutes % 60:00}";
}
