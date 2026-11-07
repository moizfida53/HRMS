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
