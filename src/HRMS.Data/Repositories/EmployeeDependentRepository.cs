using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>
/// Dependents tab of the Employee Profile screen. A one-to-many child list
/// scoped entirely by EmployeeId - not a company-wide master (no
/// <see cref="IMasterRepository{T}"/>, no paging/search/sort), and not a 1:1
/// record either (not modeled like <see cref="IEmployeeComplianceRepository"/>'s
/// GET/UPSERT pair) - it gets its own small LIST/GET/INSERT/UPDATE/DELETE
/// interface instead, the same explicit-envelope style as
/// <c>AuthRepository</c>, sized for "however many dependents one employee
/// has" rather than "however many rows a whole company has".
/// </summary>
public interface IEmployeeDependentRepository
{
    /// <summary>Every dependent for one employee, oldest-added first.</summary>
    Task<IReadOnlyList<EmployeeDependent>> ListAsync(long employeeId, CancellationToken cancellationToken = default);

    /// <summary>Inserts when <see cref="EmployeeDependent.DependentId"/> is 0/unset, updates otherwise.</summary>
    Task<SaveResult> SaveAsync(EmployeeDependent entity, long? currentUserId, CancellationToken cancellationToken = default);

    Task<SaveResult> DeleteAsync(long dependentId, long employeeId, long? currentUserId, CancellationToken cancellationToken = default);
}

public sealed class EmployeeDependentRepository : IEmployeeDependentRepository
{
    private readonly ISqlExecutor _sql;

    public EmployeeDependentRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<EmployeeDependent>> ListAsync(
        long employeeId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope(DbAction.List);
        parameters.Add("@EmployeeId", employeeId, DbType.Int64);

        return _sql.QueryAsync<EmployeeDependent>(
            StoredProcedure.EmployeeDependentManage, parameters, cancellationToken);
    }

    public async Task<SaveResult> SaveAsync(
        EmployeeDependent entity, long? currentUserId, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entity);

        var isInsert = entity.DependentId <= 0;
        var parameters = Envelope(isInsert ? DbAction.Insert : DbAction.Update);

        parameters.Add("@DependentId", isInsert ? null : entity.DependentId, DbType.Int64);
        parameters.Add("@EmployeeId", entity.EmployeeId, DbType.Int64);

        // FullName / Relationship are [Required] and already ModelState-
        // validated non-empty by the time this runs (same reasoning as
        // Employee.FirstName in EmployeeRepository) - not run through
        // NullIfEmpty. Gender is optional and has the same "blank <select>
        // binds as \"\", not null" CHECK-constraint hazard fixed on Employee
        // 2026-08-31, so it is wrapped exactly the same way here.
        parameters.Add("@FullName", entity.FullName, DbType.String, size: 150);
        parameters.Add("@Relationship", entity.Relationship, DbType.String, size: 30);
        parameters.Add("@DateOfBirth", entity.DateOfBirth, DbType.Date);
        parameters.Add("@Gender", NullIfEmpty(entity.Gender), DbType.AnsiString, size: 1);
        parameters.Add("@HasHealthInsurance", entity.HasHealthInsurance, DbType.Boolean);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        await _sql.ExecuteAsync(StoredProcedure.EmployeeDependentManage, parameters, cancellationToken)
                  .ConfigureAwait(false);

        return ReadResult(parameters, fallbackId: entity.DependentId);
    }

    public async Task<SaveResult> DeleteAsync(
        long dependentId, long employeeId, long? currentUserId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope(DbAction.Delete);
        parameters.Add("@DependentId", dependentId, DbType.Int64);
        parameters.Add("@EmployeeId", employeeId, DbType.Int64);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        await _sql.ExecuteAsync(StoredProcedure.EmployeeDependentManage, parameters, cancellationToken)
                  .ConfigureAwait(false);

        return ReadResult(parameters, fallbackId: dependentId);
    }

    private static DynamicParameters Envelope(string action)
    {
        var parameters = new DynamicParameters();

        parameters.Add("@Action", action, DbType.AnsiString, size: 10);
        parameters.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        parameters.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        parameters.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);

        return parameters;
    }

    private static SaveResult ReadResult(DynamicParameters parameters, long fallbackId)
    {
        var code = parameters.Get<string?>("@ResultCode") ?? ResultCode.Success;
        var message = parameters.Get<string?>("@ResultMessage") ?? string.Empty;
        var newId = parameters.Get<long?>("@NewId") ?? fallbackId;

        return string.Equals(code, ResultCode.Success, StringComparison.Ordinal)
            ? SaveResult.Ok(newId, string.IsNullOrWhiteSpace(message) ? "Saved successfully." : message)
            : SaveResult.Fail(
                string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code);
    }

    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
