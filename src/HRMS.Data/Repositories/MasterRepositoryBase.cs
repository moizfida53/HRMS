using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;

namespace HRMS.Data.Repositories;

/// <summary>
/// Contract shared by all eight Organization Setup masters.
/// </summary>
public interface IMasterRepository<T> where T : class
{
    Task<PagedResult<T>> ListAsync(GridRequest request, CancellationToken cancellationToken = default);

    Task<T?> GetByIdAsync(long id, CancellationToken cancellationToken = default);

    Task<SaveResult> SaveAsync(T entity, long? currentUserId, CancellationToken cancellationToken = default);

    Task<SaveResult> DeleteAsync(long id, long? currentUserId, CancellationToken cancellationToken = default);

    Task<SaveResult> ToggleActiveAsync(long id, long? currentUserId, CancellationToken cancellationToken = default);
}

/// <summary>
/// Implements LIST / GET / DELETE / TOGGLE once for every master, because all eight
/// <c>usp_*_Manage</c> procedures share the same envelope of parameters. A derived
/// repository only has to declare its procedure name, its sortable columns, and how
/// to bind its own editable fields for INSERT and UPDATE.
/// <para>
/// This is what stops the "pile of stored procedures" problem from becoming a
/// matching pile of near-identical C# repositories.
/// </para>
/// </summary>
public abstract class MasterRepositoryBase<T> : IMasterRepository<T> where T : class
{
    private readonly ISqlExecutor _sql;

    protected MasterRepositoryBase(ISqlExecutor sql) => _sql = sql;

    /// <summary>The single multi-action procedure backing this master.</summary>
    protected abstract string ProcedureName { get; }

    /// <summary>
    /// Logical sort keys this master accepts. A value outside this set is discarded
    /// and replaced with <see cref="DefaultSortColumn"/>, so no caller-supplied text
    /// ever influences the ORDER BY.
    /// </summary>
    protected abstract IReadOnlySet<string> SortableColumns { get; }

    protected abstract string DefaultSortColumn { get; }

    /// <summary>Primary key of the entity. Zero means "not saved yet".</summary>
    protected abstract long GetKey(T entity);

    /// <summary>Binds the entity's own editable columns for INSERT / UPDATE.</summary>
    protected abstract void AddEntityParameters(DynamicParameters parameters, T entity);

    public async Task<PagedResult<T>> ListAsync(
        GridRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var parameters = CreateEnvelope(DbAction.List);

        parameters.Add("@Search", Trim(request.Search, 200), DbType.String, size: 200);
        parameters.Add("@IsActiveFilter", request.IsActive, DbType.Boolean);
        parameters.Add("@CompanyId", request.CompanyId, DbType.Int32);
        parameters.Add("@CompanyIds", Trim(request.CompanyIds, 2000), DbType.String, size: 2000);   // db/24
        parameters.Add("@ParentId", request.ParentId, DbType.Int32);
        parameters.Add("@PageNumber", request.PageNumber, DbType.Int32);
        parameters.Add("@PageSize", request.PageSize, DbType.Int32);
        parameters.Add("@SortColumn", ResolveSortColumn(request.SortColumn), DbType.AnsiString, size: 50);
        parameters.Add("@SortDirection", Domain.Common.SortDirection.Normalise(request.SortDirection), DbType.AnsiString, size: 4);
        parameters.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

        var rows = await _sql.QueryAsync<T>(ProcedureName, parameters, cancellationToken)
                             .ConfigureAwait(false);

        return new PagedResult<T>
        {
            Items = rows,
            TotalCount = parameters.Get<int?>("@TotalCount") ?? rows.Count,
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<T?> GetByIdAsync(long id, CancellationToken cancellationToken = default)
    {
        var parameters = CreateEnvelope(DbAction.Get);
        parameters.Add("@Id", id, DbType.Int64);

        return await _sql.QuerySingleOrDefaultAsync<T>(ProcedureName, parameters, cancellationToken)
                         .ConfigureAwait(false);
    }

    public async Task<SaveResult> SaveAsync(
        T entity,
        long? currentUserId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entity);

        var key = GetKey(entity);
        var isInsert = key <= 0;

        var parameters = CreateEnvelope(isInsert ? DbAction.Insert : DbAction.Update);
        parameters.Add("@Id", isInsert ? null : key, DbType.Int64);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        AddEntityParameters(parameters, entity);

        await _sql.ExecuteAsync(ProcedureName, parameters, cancellationToken).ConfigureAwait(false);

        return ReadResult(parameters, fallbackId: key);
    }

    public async Task<SaveResult> DeleteAsync(
        long id,
        long? currentUserId,
        CancellationToken cancellationToken = default)
    {
        var parameters = CreateEnvelope(DbAction.Delete);
        parameters.Add("@Id", id, DbType.Int64);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        await _sql.ExecuteAsync(ProcedureName, parameters, cancellationToken).ConfigureAwait(false);

        return ReadResult(parameters, fallbackId: id);
    }

    public async Task<SaveResult> ToggleActiveAsync(
        long id,
        long? currentUserId,
        CancellationToken cancellationToken = default)
    {
        var parameters = CreateEnvelope(DbAction.Toggle);
        parameters.Add("@Id", id, DbType.Int64);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        await _sql.ExecuteAsync(ProcedureName, parameters, cancellationToken).ConfigureAwait(false);

        return ReadResult(parameters, fallbackId: id);
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    /// <summary>The parameters every action shares, including the three output values.</summary>
    private static DynamicParameters CreateEnvelope(string action)
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
                string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message,
                code);
    }

    /// <summary>
    /// Allowlist check. Anything not explicitly declared sortable by the derived
    /// repository is replaced by the default - the caller's string is never trusted.
    /// </summary>
    private string ResolveSortColumn(string? requested) =>
        !string.IsNullOrWhiteSpace(requested) && SortableColumns.Contains(requested)
            ? requested
            : DefaultSortColumn;

    private static string? Trim(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        value = value.Trim();
        return value.Length <= maxLength ? value : value[..maxLength];
    }
}
