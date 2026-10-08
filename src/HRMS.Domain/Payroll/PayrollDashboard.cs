namespace HRMS.Domain.Payroll;

// ===========================================================================
// The Payroll Dashboard (db/53, Payroll.usp_PayrollDashboard)
// ===========================================================================

/// <summary>The month's figures (payrolls past Draft and not Cancelled).</summary>
public sealed class DashboardSummary
{
    public DateTime RunMonth { get; set; }
    public long? MainRunId { get; set; }
    public string? MainRunCode { get; set; }
    public string? MainStage { get; set; }
    public string? MainRunType { get; set; }
    public string? CalendarName { get; set; }
    public DateTime? CutOffDate { get; set; }
    public DateTime? PaymentDate { get; set; }
    public int RunCount { get; set; }
    public int EmployeeCount { get; set; }
    public int PrevEmployeeCount { get; set; }
    public int Joiners { get; set; }
    public int Leavers { get; set; }
    public decimal NetPay { get; set; }
    public decimal PrevNetPay { get; set; }
    public decimal Gross { get; set; }
    public decimal EmployerPifss { get; set; }

    public decimal EmployerCost => Gross + EmployerPifss;

    /// <summary>Change against the month before in %, or null when there is nothing to compare with.</summary>
    public static decimal? Change(decimal now, decimal before) =>
        before == 0 ? null : Math.Round((now - before) * 100m / before, 1);
}

public sealed class DashboardTrendPoint
{
    public DateTime RunMonth { get; set; }
    public decimal NetPay { get; set; }
    public decimal Gross { get; set; }
    public int Employees { get; set; }
}

public sealed class DashboardDepartment
{
    public string DepartmentName { get; set; } = string.Empty;
    public int Employees { get; set; }
    public decimal Gross { get; set; }
    public decimal NetPay { get; set; }
}

public sealed class DashboardPeriod
{
    public int PayrollPeriodId { get; set; }
    public int CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string? CalendarName { get; set; }
    public DateTime PeriodMonth { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public DateTime? PaymentDate { get; set; }
    public string Status { get; set; } = "OPEN";
    public string? RunCode { get; set; }
    public string? RunStage { get; set; }
}

/// <summary>What needs doing (the "Needs attention" list).</summary>
public sealed class DashboardAttention
{
    public int ValidationErrors { get; set; }
    public int OpenWarnings { get; set; }
    public int PayItemsPending { get; set; }
    public int LoansPending { get; set; }
    public int PermitsExpiring { get; set; }
    public int UnverifiedRules { get; set; }
    public int BankFilesToMake { get; set; }
    public int PaymentsFailed { get; set; }
    public int JournalsToMake { get; set; }
    public int JournalsToPost { get; set; }
}
