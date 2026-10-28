using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Assets;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>What the profile asks for: the user's scope and the parts the user may see.</summary>
public sealed record EmployeeProfileLoadRequest(
    long EmployeeId,
    int? LookupCompanyId,
    int? UserCompanyId,
    long? UserId,
    bool IncludeInactive,
    bool WithDateAlerts,
    bool WithAssets,
    bool WithDependents,
    bool WithDocuments,
    bool WithComplianceDocuments);

/// <summary>
/// The parts of the profile read in one call. A part that is missing (it failed, or the
/// database predates it) answers <c>Has(part) == false</c> and is read on its own.
/// </summary>
public sealed class EmployeeProfileData
{
    public const string Employee = "employee";
    public const string Compliance = "compliance";
    public const string LookupPrefix = "lookup:";
    public const string PayrollCalendar = "payrollCalendar";
    public const string Calendars = "calendars";
    public const string DateAlerts = "dateAlerts";
    public const string LeaveTerms = "leaveTerms";
    public const string Assets = "assets";
    public const string Dependents = "dependents";
    public const string Documents = "documents";
    public const string ComplianceDocuments = "complianceDocuments";

    private readonly IReadOnlyDictionary<string, IReadOnlyList<object>> _parts;

    public EmployeeProfileData(IReadOnlyDictionary<string, IReadOnlyList<object>> parts) => _parts = parts;

    public bool Has(string part) => _parts.ContainsKey(part);

    public T? One<T>(string part) where T : class =>
        _parts.TryGetValue(part, out var rows) ? rows.OfType<T>().FirstOrDefault() : null;

    public IReadOnlyList<T> Many<T>(string part) =>
        _parts.TryGetValue(part, out var rows) ? rows.OfType<T>().ToList() : [];

    /// <summary>The row type of each part (null = a part this app does not read).</summary>
    public static Type? TypeOf(string part) => part switch
    {
        Employee => typeof(HRMS.Domain.Workforce.Employee),
        Compliance => typeof(EmployeeKuwaitCompliance),
        PayrollCalendar => typeof(EmployeePayrollCalendar),
        Calendars => typeof(HRMS.Domain.Payroll.PayrollCalendar),
        DateAlerts => typeof(DateAlertRule),
        LeaveTerms => typeof(EmployeeLeaveTerms),
        Assets => typeof(AssetRow),
        Dependents => typeof(EmployeeDependent),
        Documents => typeof(EmployeeDocumentRow),
        ComplianceDocuments => typeof(ComplianceDocumentRow),
        _ when part.StartsWith(LookupPrefix, StringComparison.Ordinal) => typeof(LookupItem),
        _ => null
    };
}

public interface IEmployeeProfileRepository
{
    /// <summary>Every part of the profile in one database call (db/97).</summary>
    Task<EmployeeProfileData> LoadAsync(EmployeeProfileLoadRequest request, CancellationToken cancellationToken = default);
}

public sealed class EmployeeProfileRepository : IEmployeeProfileRepository
{
    private readonly ISqlExecutor _sql;

    public EmployeeProfileRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<EmployeeProfileData> LoadAsync(EmployeeProfileLoadRequest request, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@EmployeeId", request.EmployeeId, DbType.Int64);
        p.Add("@LookupCompanyId", request.LookupCompanyId, DbType.Int32);
        p.Add("@UserCompanyId", request.UserCompanyId, DbType.Int32);
        p.Add("@UserId", request.UserId, DbType.Int64);
        p.Add("@IncludeInactive", request.IncludeInactive, DbType.Boolean);
        p.Add("@WithDateAlerts", request.WithDateAlerts, DbType.Boolean);
        p.Add("@WithAssets", request.WithAssets, DbType.Boolean);
        p.Add("@WithDependents", request.WithDependents, DbType.Boolean);
        p.Add("@WithDocuments", request.WithDocuments, DbType.Boolean);
        p.Add("@WithComplianceDocuments", request.WithComplianceDocuments, DbType.Boolean);

        var parts = await _sql.QuerySectionsAsync(StoredProcedure.EmployeeProfileLoad, p, EmployeeProfileData.TypeOf, cancellationToken)
            .ConfigureAwait(false);
        return new EmployeeProfileData(parts);
    }
}
