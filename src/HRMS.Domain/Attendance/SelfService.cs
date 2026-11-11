namespace HRMS.Domain.Attendance;

// ===========================================================================
// Employee Self Service (/ess, db/146): what the signed-in employee sees of
// their own attendance and profile. Rows of Attendance.usp_EssSelfService.
// ===========================================================================

/// <summary>TODAY: the employee, today's day and a shift still open (punched in, not out).</summary>
public sealed class EssToday
{
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? ArabicName { get; set; }
    public string? CompanyName { get; set; }
    public string? BranchName { get; set; }
    public DateTime Today { get; set; }
    public long? TodayRecordId { get; set; }
    public DateTime? TodayClockIn { get; set; }
    public DateTime? TodayClockOut { get; set; }
    public string? TodayStatus { get; set; }
    public long? OpenRecordId { get; set; }
    public DateTime? OpenWorkDate { get; set; }
    public DateTime? OpenClockIn { get; set; }
    /// <summary>A location with coordinates is set up for the employee (work location or branch).</summary>
    public bool HasLocation { get; set; }

    /// <summary>What the punch button does next: IN, OUT, or DONE (in and out today).</summary>
    public string NextPunch =>
        OpenRecordId is not null ? "OUT"
        : TodayClockOut is not null ? "DONE"
        : "IN";

    /// <summary>The clock in shown on the card: the open shift's, else today's.</summary>
    public DateTime? ShownClockIn => OpenClockIn ?? TodayClockIn;
}

/// <summary>LOCATIONS: a place the employee may punch at.</summary>
public sealed class EssLocation
{
    public int LocationId { get; set; }
    public string LocationName { get; set; } = string.Empty;
    public decimal Latitude { get; set; }
    public decimal Longitude { get; set; }
    public int RadiusM { get; set; }
}

/// <summary>PUNCH: the day the punch set (or, when out of range, how far the employee is).</summary>
public sealed class EssPunchRow
{
    public long? RecordId { get; set; }
    public int CompanyId { get; set; }
    public long EmployeeId { get; set; }
    public DateTime WorkDate { get; set; }
    public DateTime? ClockIn { get; set; }
    public DateTime? ClockOut { get; set; }
    public string? LocationName { get; set; }
    public decimal? DistanceM { get; set; }
}

/// <summary>MONTH: a day of the employee's attendance.</summary>
public sealed class EssDay
{
    public long RecordId { get; set; }
    public DateTime WorkDate { get; set; }
    public DateTime? ClockIn { get; set; }
    public DateTime? ClockOut { get; set; }
    public string Source { get; set; } = "IMPORT";
    public string Status { get; set; } = "PRESENT";
    public int WorkedMinutes { get; set; }
    public int LateMinutes { get; set; }
    public int ShortMinutes { get; set; }
    public bool IsExcused { get; set; }

    public bool CountsPresent => Status is "PRESENT" or "LATE" or "SHORT" or "LATE_SHORT" or "EXCUSED";
    public bool CountsShort => Status is "SHORT" or "LATE_SHORT";
    public bool CountsLate => Status is "LATE" or "LATE_SHORT";
    public bool CountsAbsent => Status == "ABSENT";
    public bool CountsLeave => Status == "LEAVE";
}

/// <summary>PROFILE: the employee's own details, read-only.</summary>
public sealed class EssProfile
{
    public long EmployeeId { get; set; }
    public string? EmployeeNo { get; set; }
    public string? EmployeeName { get; set; }
    public string? ArabicName { get; set; }
    public string? Gender { get; set; }
    public DateTime? DateOfBirth { get; set; }
    public string? MaritalStatus { get; set; }
    public string? NationalityName { get; set; }
    public string? MobileNumber { get; set; }
    public string? WorkEmail { get; set; }
    public string? CivilIdNumber { get; set; }
    public DateTime? CivilIdExpiryDate { get; set; }
    public string? CompanyName { get; set; }
    public string? BranchName { get; set; }
    public string? DepartmentName { get; set; }
    public string? SectionName { get; set; }
    public string? PositionName { get; set; }
    public string? DesignationName { get; set; }
    public string? LocationName { get; set; }
    public string? ReportingManagerName { get; set; }
    public DateTime? HireDate { get; set; }
    public DateTime? ProbationEndDate { get; set; }
    public string? EmploymentType { get; set; }
    public string? EmploymentStatus { get; set; }
}
