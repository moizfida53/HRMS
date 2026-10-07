namespace HRMS.Domain.Dashboard;

// Rows returned by Employee.usp_Dashboard_Get - one class per @Action.

public sealed class DashboardKpis
{
    public int TotalEmployees { get; set; }
    public int PrevTotalEmployees { get; set; }
    public int ActiveEmployees { get; set; }
    public int OnLeave { get; set; }
    public int NewJoiners { get; set; }
    public int PrevNewJoiners { get; set; }
    public int Separations { get; set; }
    public int PrevSeparations { get; set; }
}

public sealed class DashboardTrendPoint
{
    public DateTime MonthStart { get; set; }
    public int Headcount { get; set; }
    public int Joiners { get; set; }
    public int Leavers { get; set; }

    /// <summary>Null when Employee.EmployeePayroll (db/20) does not exist.</summary>
    public decimal? GrossPayroll { get; set; }
}

/// <summary>One company's headcount - the "Employees by company" chart (db/26).</summary>
public sealed class DashboardCompany
{
    public int CompanyId { get; set; }
    public string CompanyName { get; set; } = string.Empty;
    public int Headcount { get; set; }
}

public sealed class DashboardDepartment
{
    public string DepartmentName { get; set; } = string.Empty;
    public int Headcount { get; set; }
}

public sealed class DashboardPayroll
{
    public int EmployeesWithSalary { get; set; }
    public decimal? TotalBasic { get; set; }
    public decimal? TotalAllowances { get; set; }
    public decimal? Gross { get; set; }
}

public sealed class DashboardActions
{
    public int DocumentsExpiring { get; set; }
    public int DocumentsExpired { get; set; }
    public int ProbationEnding { get; set; }

    /// <summary>Null when the Documents tables (db/22) do not exist.</summary>
    public int? MandatoryDocumentsMissing { get; set; }
}

public sealed class DashboardEvent
{
    /// <summary>BIRTHDAY, ANNIVERSARY, EXPIRY or PROBATION.</summary>
    public string EventType { get; set; } = string.Empty;
    public long EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public DateTime EventDate { get; set; }
    public string Detail { get; set; } = string.Empty;
}

public sealed class DashboardActivity
{
    public long EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string Activity { get; set; } = string.Empty;
    public DateTime ActivityDate { get; set; }
    public string Status { get; set; } = string.Empty;
}

/// <summary>Everything the dashboard page shows, for one company and month.</summary>
public sealed class DashboardData
{
    public required DateTime MonthStart { get; init; }
    public required DashboardKpis Kpis { get; init; }
    public required IReadOnlyList<DashboardTrendPoint> Trend { get; init; }
    public required IReadOnlyList<DashboardCompany> Companies { get; init; }
    public required IReadOnlyList<DashboardDepartment> Departments { get; init; }
    public required DashboardPayroll Payroll { get; init; }
    public required DashboardActions Actions { get; init; }
    public required IReadOnlyList<DashboardEvent> Events { get; init; }
    public required IReadOnlyList<DashboardActivity> Activity { get; init; }
}
