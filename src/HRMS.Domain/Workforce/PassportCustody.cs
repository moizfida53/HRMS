namespace HRMS.Domain.Workforce;

/// <summary>Who holds an employee's passport (db/93): C = the company, E = the employee.</summary>
public static class PassportHolder
{
    public const string Company = "C";
    public const string Employee = "E";
}

/// <summary>The passport now: its number and who holds it since when (null = no hand-over recorded yet).</summary>
public sealed class PassportCustodyStatus
{
    public long EmployeeId { get; set; }
    public string? EmployeeCode { get; set; }
    public string? EmployeeName { get; set; }
    public string? EmployeeArabicName { get; set; }
    public string? PassportNumber { get; set; }
    public DateTime? PassportExpiryDate { get; set; }
    public string? HeldBy { get; set; }
    public DateTime? HeldSince { get; set; }
    public int Movements { get; set; }

    public bool WithCompany => HeldBy == PassportHolder.Company;
    public bool WithEmployee => HeldBy == PassportHolder.Employee;
}

/// <summary>One hand-over of the passport.</summary>
public sealed class PassportMovement
{
    public long MovementId { get; set; }
    public DateTime MovementDate { get; set; }
    public string HeldBy { get; set; } = PassportHolder.Company;
    public string? PassportNumber { get; set; }
    public string? Remarks { get; set; }
    public string? CreatedByName { get; set; }
    public DateTime CreatedDate { get; set; }
}
