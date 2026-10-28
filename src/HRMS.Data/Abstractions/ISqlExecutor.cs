using Dapper;

namespace HRMS.Data.Abstractions;

/// <summary>
/// The only route from application code to SQL Server.
/// <para>
/// Deliberately there is <b>no overload that accepts a SQL string</b>. Every method
/// takes a stored-procedure name and a parameter bag, and every command is issued
/// with <see cref="System.Data.CommandType.StoredProcedure"/>. SQL injection is
/// therefore not "avoided by convention" - it is unrepresentable in this codebase,
/// because there is no API surface through which arbitrary SQL could be sent.
/// </para>
/// <para>
/// The procedure name itself is additionally validated against a strict pattern at
/// call time, so even a compromised call site cannot smuggle a batch through it.
/// </para>
/// </summary>
public interface ISqlExecutor
{
    /// <summary>Executes a procedure and materialises every returned row as <typeparamref name="T"/>.</summary>
    Task<IReadOnlyList<T>> QueryAsync<T>(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default);

    /// <summary>Executes a procedure expected to return zero or one row.</summary>
    Task<T?> QuerySingleOrDefaultAsync<T>(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default);

    /// <summary>Executes a procedure for its side effects and output parameters.</summary>
    Task<int> ExecuteAsync(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default);

    /// <summary>Executes a procedure returning a single scalar value.</summary>
    Task<T?> ExecuteScalarAsync<T>(
        string procedureName,
        DynamicParameters parameters,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Executes a procedure that returns several parts in one call: before each part a
    /// one-row result <c>SELECT N'name' AS [__Section]</c>, then the part's rows (the first
    /// result after the marker, read as <paramref name="typeOf"/>(name)). A part marked
    /// <c>N'!name'</c> failed and is left out of the answer; a part with no rows is empty.
    /// </summary>
    Task<IReadOnlyDictionary<string, IReadOnlyList<object>>> QuerySectionsAsync(
        string procedureName,
        DynamicParameters parameters,
        Func<string, Type?> typeOf,
        CancellationToken cancellationToken = default);
}
