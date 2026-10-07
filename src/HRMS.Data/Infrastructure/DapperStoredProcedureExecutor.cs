using System.Data;
using System.Diagnostics;
using System.Text.RegularExpressions;
using Dapper;
using HRMS.Data.Abstractions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace HRMS.Data.Infrastructure;

/// <summary>
/// The single implementation of <see cref="ISqlExecutor"/>.
/// Every command it issues is <see cref="CommandType.StoredProcedure"/>; it has no
/// code path that concatenates or forwards a SQL string.
/// </summary>
public sealed partial class DapperStoredProcedureExecutor : ISqlExecutor
{
    private readonly IDbConnectionFactory _connectionFactory;
    private readonly ILogger<DapperStoredProcedureExecutor> _logger;
    private readonly int _commandTimeoutSeconds;

    // Defence in depth: a two-part name, schema + usp_ prefix, letters/digits/underscore only.
    // Anything containing whitespace, a semicolon, a comment marker or a bracket is rejected
    // before it can reach the driver.
    [GeneratedRegex(@"^[A-Za-z][A-Za-z0-9_]{0,127}\.usp_[A-Za-z0-9_]{1,120}$", RegexOptions.CultureInvariant)]
    private static partial Regex ProcedureNamePattern();

    public DapperStoredProcedureExecutor(
        IDbConnectionFactory connectionFactory,
        IOptions<SqlServerOptions> options,
        ILogger<DapperStoredProcedureExecutor> logger)
    {
        _connectionFactory = connectionFactory;
        _logger = logger;
        _commandTimeoutSeconds = options.Value.CommandTimeoutSeconds;
    }

    public Task<IReadOnlyList<T>> QueryAsync<T>(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default) =>
        RunAsync(procedureName, parameters, cancellationToken, async (connection, command) =>
        {
            var rows = await connection.QueryAsync<T>(command).ConfigureAwait(false);
            return (IReadOnlyList<T>)rows.AsList();
        });

    public Task<T?> QuerySingleOrDefaultAsync<T>(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default) =>
        RunAsync(procedureName, parameters, cancellationToken, (connection, command) =>
            connection.QuerySingleOrDefaultAsync<T?>(command));

    public Task<int> ExecuteAsync(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default) =>
        RunAsync(procedureName, parameters, cancellationToken, (connection, command) =>
            connection.ExecuteAsync(command));

    public Task<T?> ExecuteScalarAsync<T>(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default) =>
        RunAsync(procedureName, parameters, cancellationToken, (connection, command) =>
            connection.ExecuteScalarAsync<T?>(command));

    private async Task<TResult> RunAsync<TResult>(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken,
        Func<IDbConnection, CommandDefinition, Task<TResult>> operation)
    {
        GuardProcedureName(procedureName);
        ArgumentNullException.ThrowIfNull(parameters);

        var stopwatch = Stopwatch.StartNew();

        try
        {
            // Opening the connection is inside the try on purpose: a connection
            // failure is the most common SQL fault in production, and SqlClient's
            // message for it names the server and its configuration. That must be
            // wrapped like any other provider error rather than reaching a view.
            using var connection = await _connectionFactory
                .CreateOpenConnectionAsync(cancellationToken)
                .ConfigureAwait(false);

            var command = new CommandDefinition(
                commandText: procedureName,
                parameters: parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: _commandTimeoutSeconds,
                cancellationToken: cancellationToken);

            var result = await operation(connection, command).ConfigureAwait(false);

            stopwatch.Stop();
            if (stopwatch.ElapsedMilliseconds > 1000)
            {
                _logger.LogWarning(
                    "Slow stored procedure {Procedure} completed in {ElapsedMs} ms.",
                    procedureName, stopwatch.ElapsedMilliseconds);
            }
            else
            {
                _logger.LogDebug(
                    "Stored procedure {Procedure} completed in {ElapsedMs} ms.",
                    procedureName, stopwatch.ElapsedMilliseconds);
            }

            return result;
        }
        catch (SqlException ex)
        {
            // Parameter values are never logged - they routinely carry personal data.
            _logger.LogError(
                ex,
                "Stored procedure {Procedure} failed with SQL error {Number} (state {State}).",
                procedureName, ex.Number, ex.State);

            throw new DataAccessException(
                $"The database could not complete the requested operation ({procedureName}).", ex);
        }
    }

    private static void GuardProcedureName(string procedureName)
    {
        if (string.IsNullOrWhiteSpace(procedureName) || !ProcedureNamePattern().IsMatch(procedureName))
        {
            throw new ArgumentException(
                "Only two-part stored-procedure names of the form Schema.usp_Name may be executed.",
                nameof(procedureName));
        }
    }
}

/// <summary>
/// Wraps provider exceptions so that raw SQL Server messages - which can leak schema
/// details - never reach a controller or a view.
/// </summary>
public sealed class DataAccessException : Exception
{
    public DataAccessException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
