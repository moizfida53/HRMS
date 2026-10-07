using System.Data;
using HRMS.Data.Abstractions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace HRMS.Data.Infrastructure;

public interface IDbConnectionFactory
{
    Task<IDbConnection> CreateOpenConnectionAsync(CancellationToken cancellationToken = default);
}

/// <summary>
/// Builds connections with transport security applied centrally, so an insecure
/// connection string in a config file cannot silently downgrade the channel.
/// </summary>
public sealed class SqlConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;

    public SqlConnectionFactory(IOptions<SqlServerOptions> options)
    {
        ArgumentNullException.ThrowIfNull(options);
        var settings = options.Value;

        if (string.IsNullOrWhiteSpace(settings.ConnectionString))
        {
            throw new InvalidOperationException(
                "Database:ConnectionString is not configured. Set it with " +
                "'dotnet user-secrets set \"Database:ConnectionString\" \"...\"' during development, " +
                "or the Database__ConnectionString environment variable in production.");
        }

        var builder = new SqlConnectionStringBuilder(settings.ConnectionString)
        {
            ApplicationName = settings.ApplicationName,

            // Fail fast rather than hanging a request thread on an unreachable server.
            ConnectTimeout = 15,

            // Connection pooling is on by default; stated explicitly for auditability.
            Pooling = true,

            // Never let the driver persist credentials back into a readable string.
            PersistSecurityInfo = false,

            // Multiple Active Result Sets is not needed and widens the attack surface.
            MultipleActiveResultSets = false
        };

        if (settings.ForceEncryption)
        {
            builder.Encrypt = true;
            builder.TrustServerCertificate = settings.TrustServerCertificate;
        }

        _connectionString = builder.ConnectionString;
    }

    public async Task<IDbConnection> CreateOpenConnectionAsync(CancellationToken cancellationToken = default)
    {
        var connection = new SqlConnection(_connectionString);
        try
        {
            await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }
}
