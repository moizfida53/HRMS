namespace HRMS.Domain.Payroll;

/// <summary>Payslip languages (Payroll.Payslips.Template).</summary>
public static class PayslipTemplate
{
    /// <summary>English and Arabic on one page (the default).</summary>
    public const string Bilingual = "BILINGUAL";
    public const string English = "ENGLISH";
    public const string Arabic = "ARABIC";

    public static readonly IReadOnlyList<string> All = [Bilingual, English, Arabic];

    public static string Normalize(string? template) =>
        template is not null && All.Contains(template.ToUpperInvariant()) ? template.ToUpperInvariant() : Bilingual;
}

/// <summary>Email delivery of a payslip (Payroll.Payslips.EmailStatus).</summary>
public static class PayslipEmailStatus
{
    public const string NotSent = "NOT_SENT";
    public const string Queued = "QUEUED";
    public const string Sending = "SENDING";
    public const string Sent = "SENT";
    public const string Failed = "FAILED";
}

/// <summary>The status filters of the payslip lists (usp_Payslip_Manage LIST @StatusFilter).</summary>
public static class PayslipFilter
{
    public const string All = "ALL";
    public const string Generated = "GENERATED";
    public const string NotGenerated = "NOT_GENERATED";
    public const string Outdated = "OUTDATED";
    public const string NotSent = "NOT_SENT";
    public const string Queued = "QUEUED";
    public const string Sent = "SENT";
    public const string Failed = "FAILED";
    public const string NoEmail = "NO_EMAIL";

    public static readonly IReadOnlyList<string> Values = [All, Generated, NotGenerated, Outdated, NotSent, Queued, Sent, Failed, NoEmail];

    public static string Normalize(string? filter) =>
        filter is not null && Values.Contains(filter.ToUpperInvariant()) ? filter.ToUpperInvariant() : All;
}

/// <summary>RUNS - a payroll that has payslips to show.</summary>
public sealed class PayslipRun
{
    public long PayrollRunId { get; init; }
    public int CompanyId { get; init; }
    public string? CompanyCode { get; init; }
    public string? CompanyName { get; init; }
    public string? RunCode { get; init; }
    public string RunType { get; init; } = Payroll.RunType.Regular;
    public DateTime RunMonth { get; init; }
    public string Stage { get; init; } = RunStage.Closed;
    public DateTime? ClosedDate { get; init; }
    public string? CalendarName { get; init; }
    public string? CalendarArabicName { get; init; }
    public string PayFrequency { get; init; } = "MONTHLY";
    public int? PeriodNumber { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public DateTime? PaymentDate { get; init; }
    public int EmployeeCount { get; init; }
    public decimal TotalNet { get; init; }
    public int GeneratedCount { get; init; }
    public int SentCount { get; init; }

    public bool IsClosed => Stage == RunStage.Closed;
}

/// <summary>SUMMARY - key figures of one payroll's payslips.</summary>
public sealed class PayslipSummary
{
    public int EmployeeCount { get; init; }
    public int GeneratedCount { get; init; }
    public int NotGeneratedCount { get; init; }
    public int OutdatedCount { get; init; }
    public int NoEmailCount { get; init; }
    public int NotSentCount { get; init; }
    public int QueuedCount { get; init; }
    public int SentCount { get; init; }
    public int FailedCount { get; init; }
    public int ViewedCount { get; init; }
    public decimal TotalNet { get; init; }
    public DateTime? LastGeneratedDate { get; init; }
}

/// <summary>NAV_COUNTS - the figures next to the Payslips sub-sections in the sidebar.</summary>
public sealed class PayslipNavCounts
{
    public int ToGenerateCount { get; init; }
    public int GeneratedCount { get; init; }
    public int ToEmailCount { get; init; }
}

/// <summary>LIST - one employee of a payroll with their payslip and email status.</summary>
public sealed class PayslipRow
{
    public long PayrollRunId { get; init; }
    public string? RunCode { get; init; }
    public DateTime RunMonth { get; init; }
    public string Stage { get; init; } = RunStage.Closed;
    public int CompanyId { get; init; }
    public string? CompanyName { get; init; }
    public string PayFrequency { get; init; } = "MONTHLY";
    public int? PeriodNumber { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public DateTime? PaymentDate { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public int? DepartmentId { get; init; }
    public string? DepartmentName { get; init; }
    public decimal NetPay { get; init; }
    public long? PayslipId { get; init; }
    public string? PayslipNo { get; init; }
    public string? Template { get; init; }
    public decimal? SlipNetPay { get; init; }
    public DateTime? GeneratedDate { get; init; }
    public bool IsOutdated { get; init; }
    /// <summary>The employee's email address now (work email, else personal email).</summary>
    public string? Email { get; init; }
    /// <summary>The address the payslip email was last queued to.</summary>
    public string? EmailTo { get; init; }
    public string EmailStatus { get; init; } = PayslipEmailStatus.NotSent;
    public DateTime? EmailQueuedDate { get; init; }
    public DateTime? EmailSentDate { get; init; }
    public string? EmailError { get; init; }
    public int EmailAttempts { get; init; }
    public int ViewCount { get; init; }
    public DateTime? FirstViewedDate { get; init; }

    public bool IsGenerated => PayslipId is not null;
    public bool IsClosed => Stage == RunStage.Closed;
}

/// <summary>GET - the payslip header of one employee in one payroll.</summary>
public sealed class Payslip
{
    public long PayrollRunId { get; init; }
    public string? RunCode { get; init; }
    public string RunType { get; init; } = Payroll.RunType.Regular;
    public DateTime RunMonth { get; init; }
    public string Stage { get; init; } = RunStage.Closed;
    public DateTime? ClosedDate { get; init; }
    public int CompanyId { get; init; }
    public string? CompanyCode { get; init; }
    public string? CompanyName { get; init; }
    public string? CalendarName { get; init; }
    public string? CalendarArabicName { get; init; }
    public string PayFrequency { get; init; } = "MONTHLY";
    public int? PeriodNumber { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public DateTime? PaymentDate { get; init; }
    public long RunEmployeeId { get; init; }
    public long EmployeeId { get; init; }
    public string? EmployeeNo { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public string? DepartmentName { get; init; }
    public bool IsKuwaiti { get; init; }
    public DateTime? HireDate { get; init; }
    public DateTime? TerminationDate { get; init; }
    public int PeriodDays { get; init; }
    public int PaidDays { get; init; }
    public decimal SalaryTotal { get; init; }
    public decimal EarningsTotal { get; init; }
    public decimal DeductionsTotal { get; init; }
    public decimal NetPay { get; init; }
    public string? DesignationName { get; init; }
    public string? DesignationArabicName { get; init; }
    public string? CivilIdNumber { get; init; }
    public string? BankName { get; init; }
    public string? Iban { get; init; }
    public string? Email { get; init; }
    public long? PayslipId { get; init; }
    public string? PayslipNo { get; init; }
    public string? Template { get; init; }
    public decimal? SlipNetPay { get; init; }
    public DateTime? GeneratedDate { get; init; }
    public int? GenerationCount { get; init; }
    public string? EmailStatus { get; init; }
    public string? EmailTo { get; init; }
    public DateTime? EmailSentDate { get; init; }
    public int? ViewCount { get; init; }
    public string? GeneratedByName { get; init; }

    public bool IsClosed => Stage == RunStage.Closed;
    public bool IsGenerated => PayslipId is not null;

    /// <summary>The payroll was recalculated after the payslip was generated.</summary>
    public bool IsOutdated => IsGenerated && (SlipNetPay != NetPay || (ClosedDate is { } c && GeneratedDate < c));

    /// <summary>Not the final payslip: the payroll is not closed, or the payslip was not (re)generated since.</summary>
    public bool IsDraft => !IsClosed || !IsGenerated || IsOutdated;

    public decimal GrossPay => SalaryTotal + EarningsTotal;
}

/// <summary>EMAIL_CLAIM - a queued payslip email for the sender.</summary>
public sealed class PayslipEmailJob
{
    public long PayslipId { get; init; }
    public string? PayslipNo { get; init; }
    public string? EmailTo { get; init; }
    public string Template { get; init; } = PayslipTemplate.Bilingual;
    public long EmployeeId { get; init; }
    public string? EmployeeName { get; init; }
    public string? ArabicName { get; init; }
    public string? CompanyName { get; init; }
    public string? RunCode { get; init; }
    public DateTime RunMonth { get; init; }
    public string PayFrequency { get; init; } = "MONTHLY";
    public int? PeriodNumber { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime EndDate { get; init; }
    public DateTime? PaymentDate { get; init; }
}

/// <summary>The filter of a payslip list.</summary>
public sealed class PayslipListFilter
{
    public int? CompanyId { get; init; }
    public string? CompanyIds { get; init; }
    public long? RunId { get; init; }
    public long? EmployeeId { get; init; }
    /// <summary>My Payslips: only this employee's generated payslips of closed payrolls.</summary>
    public long? SelfEmployeeId { get; init; }
    public int? DepartmentId { get; init; }
    public string Status { get; init; } = PayslipFilter.All;
    public string? Search { get; init; }
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 25;
}
