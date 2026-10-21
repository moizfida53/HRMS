namespace HRMS.Domain.Workforce;

/// <summary>
/// The date fields of the Employee profile that can carry alerts (db/65). An alert
/// rule belongs to the field, so it applies to that date of every employee.
/// <see cref="Key"/> is the field's name on the form (input name / id f-{Key}) and
/// the FieldKey stored in Employee.DateFieldAlerts.
/// </summary>
public sealed record DateAlertField(string Key, string LabelKey, string Tab, DateAlertKind Kind);

public enum DateAlertKind
{
    /// <summary>An expiry: alerts lead up to it, and it stays due (expired) until the date is renewed.</summary>
    Expiry,

    /// <summary>A one-off event (probation end, termination): alerts lead up to it, then it drops off.</summary>
    Event,

    /// <summary>Recurs every year on the same day (birthday, work anniversary).</summary>
    Annual
}

public static class DateAlertFields
{
    public static readonly IReadOnlyList<DateAlertField> All =
    [
        new("DateOfBirth", "emp.date_of_birth", "personal", DateAlertKind.Annual),
        new("HireDate", "emp.hire_date", "employment", DateAlertKind.Annual),
        new("ProbationEndDate", "emp.probation_end_date", "employment", DateAlertKind.Event),
        new("TerminationDate", "emp.termination_date", "employment", DateAlertKind.Event),
        new("CivilIdExpiryDate", "emp.civil_id_expiry", "compliance", DateAlertKind.Expiry),
        new("PassportExpiryDate", "emp.passport_expiry", "compliance", DateAlertKind.Expiry),
        new("ResidencyExpiryDate", "emp.residency_expiry", "compliance", DateAlertKind.Expiry),
        new("WorkPermitExpiryDate", "emp.work_permit_expiry", "compliance", DateAlertKind.Expiry),
        new("DrivingLicenseExpiryDate", "emp.driving_license_expiry", "compliance", DateAlertKind.Expiry),
        new("HealthCertificateExpiry", "emp.health_cert_expiry", "compliance", DateAlertKind.Expiry)
    ];

    public static DateAlertField? Find(string? key) =>
        All.FirstOrDefault(f => string.Equals(f.Key, key, StringComparison.OrdinalIgnoreCase));
}

/// <summary>One reminder on a date field: <see cref="Value"/> months / weeks / days before it; 0 = on the day.</summary>
public sealed class DateAlertRule
{
    public string FieldKey { get; set; } = string.Empty;

    /// <summary>M = months, W = weeks, D = days.</summary>
    public string UnitCode { get; set; } = "D";

    public int Value { get; set; }

    public const int MaxValue = 99;
    public const int MaxRulesPerField = 10;

    public static bool IsUnit(string? unit) => unit is "M" or "W" or "D";
}

/// <summary>An employee date that has reached one of its field's reminders (db/65, DUE).</summary>
public sealed class DateAlertDue
{
    public long EmployeeId { get; set; }
    public string? EmployeeCode { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? CompanyName { get; set; }
    public string FieldKey { get; set; } = string.Empty;

    /// <summary>The date on the employee record.</summary>
    public DateTime FieldDate { get; set; }

    /// <summary>The date the alert is about: the field date, or its next anniversary for a yearly field.</summary>
    public DateTime DueDate { get; set; }

    /// <summary>Days from today to <see cref="DueDate"/>; negative once it has passed (an expiry).</summary>
    public int DaysLeft { get; set; }

    /// <summary>The reminder that fired most recently.</summary>
    public string? RuleUnit { get; set; }
    public int? RuleValue { get; set; }
}
