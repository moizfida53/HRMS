namespace HRMS.Domain.Workforce;

/// <summary>
/// The mandatory details a saved employee is missing (Employee.usp_EmployeeCompleteness, db/95).
/// A new employee may be created without them; once saved, the profile cannot be saved until
/// they are filled, and the Employees list flags the employee.
/// </summary>
public sealed class EmployeeCompleteness
{
    public long EmployeeId { get; set; }

    public int MissingCount { get; set; }

    /// <summary>Comma-separated field keys, e.g. "HireDate,Iban,PassportNumber".</summary>
    public string? Missing { get; set; }

    public IReadOnlyList<string> MissingFields =>
        string.IsNullOrWhiteSpace(Missing) ? [] : Missing.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}
