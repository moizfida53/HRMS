using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Workforce;
using HRMS.Web.Security;

namespace HRMS.Web.Services;

/// <summary>
/// Writes the employee Audit Report (Employee.EmployeeAuditLog, db/60). Every
/// write is best-effort: a failure is logged and never undoes or blocks the
/// action being audited. Calendar changes are logged by the database itself,
/// in the same transaction as the change (usp_EmployeePayrollCalendar_Manage).
/// </summary>
public interface IEmployeeAuditor
{
    Task CreatedAsync(Employee employee);
    /// <summary>One row per changed field: employment fields, salary and bank (values from two reads of the record).</summary>
    Task UpdatedAsync(Employee before, Employee after);
    Task ActiveChangedAsync(long employeeId, bool active);
    Task DeletedAsync(Employee employee);
    Task PayrollInclusionAsync(long employeeId, bool excluded, string? runCode, string? reason);
}

public sealed class EmployeeAuditor : IEmployeeAuditor
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    private readonly IEmployeeAuditRepository _audit;
    private readonly ICurrentUser _user;
    private readonly ILogger<EmployeeAuditor> _logger;

    public EmployeeAuditor(IEmployeeAuditRepository audit, ICurrentUser user, ILogger<EmployeeAuditor> logger)
    {
        _audit = audit;
        _user = user;
        _logger = logger;
    }

    /// <summary>
    /// The employment fields an "Employee updated" row is written for (English names;
    /// the report translates them). Salary and bank have transaction types of their own.
    /// </summary>
    private static readonly (string Field, Func<Employee, string?> Value)[] EmploymentFields =
    [
        ("First name", e => e.FirstName), ("Middle name", e => e.MiddleName), ("Last name", e => e.LastName),
        ("Arabic name", e => e.ArabicName), ("Company", e => e.CompanyName), ("Branch", e => e.BranchName),
        ("Department", e => e.DepartmentName), ("Section", e => e.SectionName), ("Job position", e => e.PositionName),
        ("Designation", e => e.DesignationName), ("Grade", e => e.GradeName), ("Cost center", e => e.CostCenterName),
        ("Work location", e => e.LocationName), ("Reporting manager", e => e.ReportingManagerName),
        ("Hire date", e => Date(e.HireDate)), ("Probation end date", e => Date(e.ProbationEndDate)),
        ("Termination date", e => Date(e.TerminationDate)), ("Employment type", e => e.EmploymentType),
        ("Employment status", e => e.EmploymentStatus), ("Notice period (days)", e => e.NoticePeriodDays?.ToString(Inv)),
        ("Nationality", e => e.NationalityName), ("Date of birth", e => Date(e.DateOfBirth)),
        ("Mobile number", e => e.MobileNumber), ("Work email", e => e.WorkEmail)
    ];

    private static readonly (string Field, Func<Employee, string?> Value)[] SalaryFields =
    [
        ("Basic salary (KWD)", e => Money(e.BasicSalary)), ("Allowances (KWD)", e => Money(e.Allowances))
    ];

    private static readonly (string Field, Func<Employee, string?> Value)[] BankFields =
    [
        ("Bank name", e => e.BankName), ("IBAN / account no.", e => MaskIban(e.Iban))
    ];

    public Task CreatedAsync(Employee employee) =>
        WriteAsync(new EmployeeAuditInput
        {
            EmployeeId = employee.EmployeeId,
            TransactionType = AuditType.EmployeeCreated,
            NewValue = Who(employee),
            Remarks = employee.BasicSalary is null && employee.Allowances is null
                ? null
                : $"Basic salary {Money(employee.BasicSalary) ?? "—"} KWD, allowances {Money(employee.Allowances) ?? "—"} KWD"
        });

    public async Task UpdatedAsync(Employee before, Employee after)
    {
        await WriteChangesAsync(before, after, EmploymentFields, AuditType.EmployeeUpdated);
        await WriteChangesAsync(before, after, SalaryFields, AuditType.SalaryChanged);
        await WriteChangesAsync(before, after, BankFields, AuditType.BankChanged);
    }

    public Task ActiveChangedAsync(long employeeId, bool active) =>
        WriteAsync(new EmployeeAuditInput
        {
            EmployeeId = employeeId,
            TransactionType = active ? AuditType.EmployeeActivated : AuditType.EmployeeDeactivated,
            FieldName = "Active",
            OldValue = active ? "No" : "Yes",
            NewValue = active ? "Yes" : "No"
        });

    public Task DeletedAsync(Employee employee) =>
        WriteAsync(new EmployeeAuditInput
        {
            EmployeeId = employee.EmployeeId,
            TransactionType = AuditType.EmployeeDeleted,
            OldValue = Who(employee)
        });

    public Task PayrollInclusionAsync(long employeeId, bool excluded, string? runCode, string? reason) =>
        WriteAsync(new EmployeeAuditInput
        {
            EmployeeId = employeeId,
            TransactionType = excluded ? AuditType.PayrollExcluded : AuditType.PayrollIncluded,
            FieldName = "Payroll",
            OldValue = excluded ? "Included" : "Excluded",
            NewValue = excluded ? "Excluded" : "Included",
            Reference = runCode,
            Remarks = reason
        });

    // ------------------------------------------------------------ helpers

    private async Task WriteChangesAsync(Employee before, Employee after,
                                         (string Field, Func<Employee, string?> Value)[] fields, string type)
    {
        foreach (var (field, value) in fields)
        {
            var oldValue = Normalize(value(before));
            var newValue = Normalize(value(after));
            if (string.Equals(oldValue, newValue, StringComparison.Ordinal)) continue;

            await WriteAsync(new EmployeeAuditInput
            {
                EmployeeId = after.EmployeeId,
                TransactionType = type,
                FieldName = field,
                OldValue = oldValue,
                NewValue = newValue
            });
        }
    }

    private async Task WriteAsync(EmployeeAuditInput input)
    {
        try
        {
            var result = await _audit.AddAsync(input, _user.UserId);
            if (!result.Success)
            {
                _logger.LogWarning("Audit row {Type} for employee {EmployeeId} was not written: {Code}.",
                    input.TransactionType, input.EmployeeId, result.ErrorCode);
            }
        }
        catch (Exception ex)
        {
            // auditing never breaks the action it records (e.g. db/60 not run yet)
            _logger.LogWarning(ex, "Audit row {Type} for employee {EmployeeId} could not be written.",
                input.TransactionType, input.EmployeeId);
        }
    }

    private static string? Normalize(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string? Date(DateTime? value) => value?.ToString("yyyy-MM-dd", Inv);

    private static string? Money(decimal? value) => value?.ToString("N3", Inv);

    private static string Who(Employee e) =>
        $"{(string.IsNullOrWhiteSpace(e.EmployeeCode) ? e.EmployeeNo : e.EmployeeCode)} · {e.FirstName} {e.LastName}".Trim();

    /// <summary>"KW81CBKU0000000000001234567890" -> "KW81 •••• 7890": enough to tell accounts apart, not to copy one.</summary>
    internal static string? MaskIban(string? iban)
    {
        if (string.IsNullOrWhiteSpace(iban)) return null;
        var clean = iban.Replace(" ", string.Empty);
        return clean.Length <= 8 ? new string('•', clean.Length - Math.Min(clean.Length, 2)) + clean[^Math.Min(clean.Length, 2)..]
                                 : $"{clean[..4]} •••• {clean[^4..]}";
    }
}
