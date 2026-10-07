using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Security;

namespace HRMS.Data.Repositories;

public interface IAuthRepository
{
    /// <summary>
    /// Resolves a username or email to its credential row. Returns null when no
    /// account matches. The comparison of the password happens in the
    /// application, never in SQL - a password is never sent to the database.
    /// </summary>
    Task<AuthUser?> FindForLoginAsync(string username, CancellationToken cancellationToken = default);

    Task RecordSuccessAsync(
        long userId, string username, string? ipAddress, string? userAgent,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Records a failed attempt and applies the lockout policy.
    /// Returns the lockout expiry when this attempt tripped the threshold.
    /// </summary>
    Task<DateTime?> RecordFailureAsync(
        long? userId, string username, string outcome,
        string? ipAddress, string? userAgent,
        int maxFailedAttempts, int lockoutMinutes,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<string>> GetPermissionsAsync(long userId, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RoleInfo>> GetRolesAsync(long userId, CancellationToken cancellationToken = default);

    /// <param name="plainPassword">
    /// SimplePassword mode only: stored as-is in Security.Users.[Password].
    /// Null in normal mode, which clears any plain copy.
    /// </param>
    Task ChangePasswordAsync(long userId, string passwordHash, string? plainPassword = null, CancellationToken cancellationToken = default);

    /// <summary>SimplePassword mode: fills [Password] after a first sign-in with the hashed password.</summary>
    Task SetPlainPasswordAsync(long userId, string plainPassword, CancellationToken cancellationToken = default);
}

public sealed class AuthRepository : IAuthRepository
{
    private readonly ISqlExecutor _sql;

    public AuthRepository(ISqlExecutor sql) => _sql = sql;

    public Task<AuthUser?> FindForLoginAsync(string username, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("LOGIN_LOOKUP");
        parameters.Add("@Username", username, DbType.String, size: 100);

        return _sql.QuerySingleOrDefaultAsync<AuthUser>(
            StoredProcedure.AuthManage, parameters, cancellationToken);
    }

    public async Task RecordSuccessAsync(
        long userId, string username, string? ipAddress, string? userAgent,
        CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("LOGIN_SUCCESS");
        parameters.Add("@UserId", userId, DbType.Int64);
        parameters.Add("@Username", username, DbType.String, size: 100);
        parameters.Add("@IpAddress", Truncate(ipAddress, 64), DbType.String, size: 64);
        parameters.Add("@UserAgent", Truncate(userAgent, 400), DbType.String, size: 400);

        await _sql.ExecuteAsync(StoredProcedure.AuthManage, parameters, cancellationToken)
                  .ConfigureAwait(false);
    }

    public async Task<DateTime?> RecordFailureAsync(
        long? userId, string username, string outcome,
        string? ipAddress, string? userAgent,
        int maxFailedAttempts, int lockoutMinutes,
        CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("LOGIN_FAILURE");
        parameters.Add("@UserId", userId, DbType.Int64);
        parameters.Add("@Username", username, DbType.String, size: 100);
        parameters.Add("@Outcome", outcome, DbType.AnsiString, size: 30);
        parameters.Add("@IpAddress", Truncate(ipAddress, 64), DbType.String, size: 64);
        parameters.Add("@UserAgent", Truncate(userAgent, 400), DbType.String, size: 400);
        parameters.Add("@MaxFailedAttempts", maxFailedAttempts, DbType.Int32);
        parameters.Add("@LockoutMinutes", lockoutMinutes, DbType.Int32);
        parameters.Add("@LockoutEndUtc", dbType: DbType.DateTime2, direction: ParameterDirection.Output);

        await _sql.ExecuteAsync(StoredProcedure.AuthManage, parameters, cancellationToken)
                  .ConfigureAwait(false);

        return parameters.Get<DateTime?>("@LockoutEndUtc");
    }

    public Task<IReadOnlyList<string>> GetPermissionsAsync(
        long userId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("GET_PERMISSIONS");
        parameters.Add("@UserId", userId, DbType.Int64);

        return _sql.QueryAsync<string>(StoredProcedure.AuthManage, parameters, cancellationToken);
    }

    public Task<IReadOnlyList<RoleInfo>> GetRolesAsync(
        long userId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("GET_ROLES");
        parameters.Add("@UserId", userId, DbType.Int64);

        return _sql.QueryAsync<RoleInfo>(StoredProcedure.AuthManage, parameters, cancellationToken);
    }

    public async Task ChangePasswordAsync(
        long userId, string passwordHash, string? plainPassword = null, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("CHANGE_PASSWORD");
        parameters.Add("@UserId", userId, DbType.Int64);
        parameters.Add("@PasswordHash", passwordHash, DbType.String, size: 500);
        parameters.Add("@PlainPassword", plainPassword, DbType.String, size: 50);   // db/27

        await _sql.ExecuteAsync(StoredProcedure.AuthManage, parameters, cancellationToken)
                  .ConfigureAwait(false);
    }

    public async Task SetPlainPasswordAsync(
        long userId, string plainPassword, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("SET_PLAIN");
        parameters.Add("@UserId", userId, DbType.Int64);
        parameters.Add("@PlainPassword", plainPassword, DbType.String, size: 50);

        await _sql.ExecuteAsync(StoredProcedure.AuthManage, parameters, cancellationToken)
                  .ConfigureAwait(false);
    }

    private static DynamicParameters Envelope(string action)
    {
        var parameters = new DynamicParameters();

        parameters.Add("@Action", action, DbType.AnsiString, size: 20);
        parameters.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        parameters.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);

        return parameters;
    }

    private static string? Truncate(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return value.Length <= maxLength ? value : value[..maxLength];
    }
}
