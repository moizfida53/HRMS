using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Payroll;

namespace HRMS.Data.Repositories;

/// <summary>
/// Payroll Components (db/111): a role limited to chosen item types of a page (e.g. only Overtime
/// in Earnings &amp; Allowances), and the item types a user may work with.
/// </summary>
public interface IComponentRightsRepository
{
    Task<IReadOnlyList<ComponentTypeOption>> TypesAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ComponentTypeGrant>> RoleTypesAsync(int roleId, CancellationToken cancellationToken = default);
    /// <param name="classCodes">"CLASS:CODE" values; none for a page = every item type of it.</param>
    Task SetRoleTypesAsync(int roleId, IEnumerable<string> classCodes, long? userId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ComponentTypeGrant>> UserTypesAsync(long userId, CancellationToken cancellationToken = default);
    /// <summary>An approved salary revision updates the employee profile (Basic Salary / Allowances).</summary>
    Task<bool> ApplySalaryRevisionAsync(long payItemId, long? userId, CancellationToken cancellationToken = default);
}

public sealed class ComponentRightsRepository : IComponentRightsRepository
{
    private readonly ISqlExecutor _sql;

    public ComponentRightsRepository(ISqlExecutor sql) => _sql = sql;

    private static DynamicParameters P(string action)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        return p;
    }

    public Task<IReadOnlyList<ComponentTypeOption>> TypesAsync(CancellationToken cancellationToken = default) =>
        _sql.QueryAsync<ComponentTypeOption>(StoredProcedure.RoleComponentTypes, P("TYPES"), cancellationToken);

    public Task<IReadOnlyList<ComponentTypeGrant>> RoleTypesAsync(int roleId, CancellationToken cancellationToken = default)
    {
        var p = P("ROLE_GET");
        p.Add("@RoleId", roleId, DbType.Int32);
        return _sql.QueryAsync<ComponentTypeGrant>(StoredProcedure.RoleComponentTypes, p, cancellationToken);
    }

    public async Task SetRoleTypesAsync(int roleId, IEnumerable<string> classCodes, long? userId, CancellationToken cancellationToken = default)
    {
        var p = P("ROLE_SET");
        p.Add("@RoleId", roleId, DbType.Int32);
        p.Add("@Codes", string.Join(",", classCodes.Where(c => !string.IsNullOrWhiteSpace(c) && !c.Contains(','))), DbType.String);
        p.Add("@ActionBy", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.RoleComponentTypes, p, cancellationToken).ConfigureAwait(false);
    }

    public Task<IReadOnlyList<ComponentTypeGrant>> UserTypesAsync(long userId, CancellationToken cancellationToken = default)
    {
        var p = P("USER");
        p.Add("@UserId", userId, DbType.Int64);
        return _sql.QueryAsync<ComponentTypeGrant>(StoredProcedure.RoleComponentTypes, p, cancellationToken);
    }

    public async Task<bool> ApplySalaryRevisionAsync(long payItemId, long? userId, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@PayItemId", payItemId, DbType.Int64);
        p.Add("@UserId", userId, DbType.Int64);
        p.Add("@Applied", dbType: DbType.Boolean, direction: ParameterDirection.Output);
        await _sql.ExecuteAsync(StoredProcedure.SalaryRevisionApply, p, cancellationToken).ConfigureAwait(false);
        return p.Get<bool?>("@Applied") ?? false;
    }
}
