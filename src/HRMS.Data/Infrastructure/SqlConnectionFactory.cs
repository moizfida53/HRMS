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
    private readonly IOptionsMonitor<SqlServerOptions> _options;
    private readonly object _gate = new();
    private SqlServerOptions? _builtFrom;
    private string _connectionString = string.Empty;

    // IOptionsMonitor: a connection string changed in dbsettings.json is used from the next call on
    public SqlConnectionFactory(IOptionsMonitor<SqlServerOptions> options)
    {
        ArgumentNullException.ThrowIfNull(options);
        _options = options;
    }

    /// <summary>The connection string with the app's security rules applied (rebuilt when the settings change).</summary>
    private string ConnectionString
    {
        get
        {
            var settings = _options.CurrentValue;
            lock (_gate)
            {
                if (ReferenceEquals(settings, _builtFrom)) return _connectionString;
                _connectionString = Build(settings);
                _builtFrom = settings;
                return _connectionString;
            }
        }
    }

    private static string Build(SqlServerOptions settings)
    {
        if (!settings.IsConfigured)
        {
            throw new InvalidOperationException(
                "The database connection is not set up. Set ConnectionStrings:SqlServerConnectionString " +
                "in appsettings.json (next to the application).");
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

        return builder.ConnectionString;
    }

    public async Task<IDbConnection> CreateOpenConnectionAsync(CancellationToken cancellationToken = default)
    {
        var connection = new SqlConnection(ConnectionString);
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
