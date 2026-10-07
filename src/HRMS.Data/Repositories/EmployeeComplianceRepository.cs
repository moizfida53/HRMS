using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>
/// Kuwait Compliance tab of the Employee Profile screen. This is a 1:1 child
/// record keyed by EmployeeId, not a master list, so it doesn't fit
/// <see cref="MasterRepositoryBase{T}"/> - it gets its own small interface,
/// modeled on <see cref="AuthRepository"/>: an explicit envelope built per
/// call rather than the generic LIST/GET/paging machinery.
/// </summary>
public interface IEmployeeComplianceRepository
{
    /// <summary>
    /// Returns the compliance record for one employee, or null when none has
    /// been entered yet - a normal state for a newly created employee, not
    /// an error condition.
    /// </summary>
    Task<EmployeeKuwaitCompliance?> GetAsync(long employeeId, CancellationToken cancellationToken = default);

    /// <summary>Inserts on first save, updates on every save after that.</summary>
    Task<(string ResultCode, string ResultMessage)> UpsertAsync(
        EmployeeKuwaitCompliance entity, long? userId, CancellationToken cancellationToken = default);
}

public sealed class EmployeeComplianceRepository : IEmployeeComplianceRepository
{
    private readonly ISqlExecutor _sql;

    public EmployeeComplianceRepository(ISqlExecutor sql) => _sql = sql;

    public Task<EmployeeKuwaitCompliance?> GetAsync(
        long employeeId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("GET", employeeId);

        return _sql.QuerySingleOrDefaultAsync<EmployeeKuwaitCompliance>(
            StoredProcedure.EmployeeComplianceManage, parameters, cancellationToken);
    }

    public async Task<(string ResultCode, string ResultMessage)> UpsertAsync(
        EmployeeKuwaitCompliance entity, long? userId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("UPSERT", entity.EmployeeId);

        // NullIfEmpty on every string column, same reasoning as
        // EmployeeRepository.AddEntityParameters: a blank <select> or empty
        // text input reaches here as "" (ASP.NET Core's default model
        // binder does not turn "" into null for a string? property), and
        // BloodType's CHECK constraint (NULL or one of the 8 blood types)
        // would reject "" the same way Gender/MaritalStatus/EmploymentType
        // did on Employee.Employees - fixed there 2026-08-31, applied here
        // too before it could cause the same failure on this form.
        parameters.Add("@CivilIdNumber", NullIfEmpty(entity.CivilIdNumber), DbType.String, size: 20);
        parameters.Add("@CivilIdExpiryDate", entity.CivilIdExpiryDate, DbType.Date);

        parameters.Add("@PassportNumber", NullIfEmpty(entity.PassportNumber), DbType.String, size: 30);
        parameters.Add("@PassportCountryId", entity.PassportCountryId, DbType.Int32);
        parameters.Add("@PassportExpiryDate", entity.PassportExpiryDate, DbType.Date);

        parameters.Add("@ResidencyNumber", NullIfEmpty(entity.ResidencyNumber), DbType.String, size: 30);
        parameters.Add("@ResidencyType", NullIfEmpty(entity.ResidencyType), DbType.String, size: 50);
        parameters.Add("@ResidencyExpiryDate", entity.ResidencyExpiryDate, DbType.Date);

        parameters.Add("@SponsorName", NullIfEmpty(entity.SponsorName), DbType.String, size: 200);
        parameters.Add("@SponsorFileNumber", NullIfEmpty(entity.SponsorFileNumber), DbType.String, size: 50);
        parameters.Add("@SponsorStatus", NullIfEmpty(entity.SponsorStatus), DbType.String, size: 50);
        parameters.Add("@ResidencyStatus", NullIfEmpty(entity.ResidencyStatus), DbType.String, size: 30);

        parameters.Add("@MolFileNumber", NullIfEmpty(entity.MolFileNumber), DbType.String, size: 50);
        parameters.Add("@WorkPermitNumber", NullIfEmpty(entity.WorkPermitNumber), DbType.String, size: 50);
        parameters.Add("@WorkPermitExpiryDate", entity.WorkPermitExpiryDate, DbType.Date);

        parameters.Add("@PaciNumber", NullIfEmpty(entity.PaciNumber), DbType.String, size: 20);
        parameters.Add("@PaciAddress", NullIfEmpty(entity.PaciAddress), DbType.String, size: 300);

        parameters.Add("@DrivingLicenseNumber", NullIfEmpty(entity.DrivingLicenseNumber), DbType.String, size: 30);
        parameters.Add("@DrivingLicenseExpiryDate", entity.DrivingLicenseExpiryDate, DbType.Date);
        parameters.Add("@BloodType", NullIfEmpty(entity.BloodType), DbType.String, size: 5);
        parameters.Add("@HealthCertificateExpiry", entity.HealthCertificateExpiry, DbType.Date);

        parameters.Add("@UserId", userId, DbType.Int64);

        await _sql.ExecuteAsync(StoredProcedure.EmployeeComplianceManage, parameters, cancellationToken)
                  .ConfigureAwait(false);

        return (
            parameters.Get<string?>("@ResultCode") ?? ResultCode.Success,
            parameters.Get<string?>("@ResultMessage") ?? string.Empty);
    }

    private static DynamicParameters Envelope(string action, long employeeId)
    {
        var parameters = new DynamicParameters();

        parameters.Add("@Action", action, DbType.AnsiString, size: 10);
        parameters.Add("@EmployeeId", employeeId, DbType.Int64);
        parameters.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        parameters.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);

        return parameters;
    }

    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
