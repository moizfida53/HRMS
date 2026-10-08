using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Security;

namespace HRMS.Data.Repositories;

// ===========================================================================
// Security > Create Roles / Assign Roles (db/57, Security.usp_SecurityAdmin_Manage)
// companyId = the signed-in user's company when pinned (the procedure scopes to it).
// ===========================================================================

public interface ISecurityAdminRepository
{
    Task<IReadOnlyList<RoleSummary>> RolesAsync(int? companyId, string? search, CancellationToken cancellationToken = default);
    Task<RoleSummary?> RoleAsync(int? companyId, int roleId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<string>> RoleCodesAsync(int? companyId, int roleId, CancellationToken cancellationToken = default);
    Task<SaveResult> SaveRoleAsync(int? companyId, RoleSaveRequest role, long? userId, CancellationToken cancellationToken = default);
    Task<SaveResult> DeleteRoleAsync(int? companyId, int roleId, long? userId, CancellationToken cancellationToken = default);
    Task<UserRoleRow?> UserAsync(int? companyId, long userId, CancellationToken cancellationToken = default);
    Task<PagedResult<UserRoleRow>> UsersAsync(int? companyId, string? search, int? roleFilter, int page, int pageSize, CancellationToken cancellationToken = default);
    Task<SaveResult> SetUserRolesAsync(int? companyId, long targetUserId, IReadOnlyCollection<int> roleIds, bool callerIsSysAdmin, long? userId,
                                       CancellationToken cancellationToken = default);
}

public sealed class SecurityAdminRepository : ISecurityAdminRepository
{
    private readonly ISqlExecutor _sql;

    public SecurityAdminRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<RoleSummary>> RolesAsync(int? companyId, string? search, CancellationToken cancellationToken = default)
    {
        var p = Env("ROLES", companyId);
        p.Add("@Search", Trim(search, 200), DbType.String, size: 200);
        return _sql.QueryAsync<RoleSummary>(StoredProcedure.SecurityAdminManage, p, cancellationToken);
    }

    public Task<RoleSummary?> RoleAsync(int? companyId, int roleId, CancellationToken cancellationToken = default)
    {
        var p = Env("ROLE_GET", companyId);
        p.Add("@RoleId", roleId, DbType.Int32);
        return _sql.QuerySingleOrDefaultAsync<RoleSummary>(StoredProcedure.SecurityAdminManage, p, cancellationToken);
    }

    public Task<IReadOnlyList<string>> RoleCodesAsync(int? companyId, int roleId, CancellationToken cancellationToken = default)
    {
        var p = Env("ROLE_CODES", companyId);
        p.Add("@RoleId", roleId, DbType.Int32);
        return _sql.QueryAsync<string>(StoredProcedure.SecurityAdminManage, p, cancellationToken);
    }

    public async Task<SaveResult> SaveRoleAsync(int? companyId, RoleSaveRequest role, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("ROLE_SAVE", companyId);
        p.Add("@RoleId", role.RoleId, DbType.Int32);
        p.Add("@RoleCode", Trim(role.RoleCode, 50), DbType.String, size: 50);
        p.Add("@RoleName", Trim(role.RoleName, 100), DbType.String, size: 100);
        p.Add("@Description", Trim(role.Description, 500), DbType.String, size: 500);
        p.Add("@RoleCompanyId", role.RoleCompanyId, DbType.Int32);
        p.Add("@IsActive", role.IsActive, DbType.Boolean);
        p.Add("@ManagedCodes", string.Join(',', role.ManagedCodes), DbType.String, size: -1);
        p.Add("@GrantedCodes", string.Join(',', role.GrantedCodes), DbType.String, size: -1);
        p.Add("@ActionBy", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.SecurityAdminManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, role.RoleId);
    }

    public async Task<SaveResult> DeleteRoleAsync(int? companyId, int roleId, long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("ROLE_DELETE", companyId);
        p.Add("@RoleId", roleId, DbType.Int32);
        p.Add("@ActionBy", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.SecurityAdminManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, roleId);
    }

    public async Task<PagedResult<UserRoleRow>> UsersAsync(int? companyId, string? search, int? roleFilter, int page, int pageSize,
                                                         CancellationToken cancellationToken = default)
    {
        var p = Env("USERS", companyId);
        p.Add("@Search", Trim(search, 200), DbType.String, size: 200);
        p.Add("@RoleFilter", roleFilter, DbType.Int32);
        p.Add("@PageNumber", Math.Max(1, page), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(pageSize, 1, 200), DbType.Int32);
        var rows = await _sql.QueryAsync<UserRoleRow>(StoredProcedure.SecurityAdminManage, p, cancellationToken).ConfigureAwait(false);
        return new PagedResult<UserRoleRow>
        {
            Items = rows,
            TotalCount = p.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = Math.Max(1, page),
            PageSize = Math.Clamp(pageSize, 1, 200)
        };
    }

    public Task<UserRoleRow?> UserAsync(int? companyId, long userId, CancellationToken cancellationToken = default)
    {
        var p = Env("USERS", companyId);
        p.Add("@UserId", userId, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<UserRoleRow>(StoredProcedure.SecurityAdminManage, p, cancellationToken);
    }

    public async Task<SaveResult> SetUserRolesAsync(int? companyId, long targetUserId, IReadOnlyCollection<int> roleIds, bool callerIsSysAdmin,
                                                    long? userId, CancellationToken cancellationToken = default)
    {
        var p = Env("USER_ROLES_SET", companyId);
        p.Add("@UserId", targetUserId, DbType.Int64);
        p.Add("@RoleIds", string.Join(',', roleIds), DbType.String, size: -1);
        p.Add("@CallerIsSysAdmin", callerIsSysAdmin, DbType.Boolean);
        p.Add("@ActionBy", userId, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.SecurityAdminManage, p, cancellationToken).ConfigureAwait(false);
        return PayrollRunRepository.ReadResult(p, targetUserId);
    }

    private static DynamicParameters Env(string action, int? companyId)
    {
        var p = PayrollRunRepository.Envelope(action);
        p.Add("@CompanyId", companyId, DbType.Int32);
        return p;
    }

    private static string? Trim(string? value, int max)
    {
        var v = value?.Trim();
        return string.IsNullOrEmpty(v) ? null : v.Length > max ? v[..max] : v;
    }
}
