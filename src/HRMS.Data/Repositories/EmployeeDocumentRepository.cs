using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>
/// Documents tab of the Employee Profile screen. Scoped entirely by
/// EmployeeId, same explicit-envelope style as
/// <see cref="EmployeeDependentRepository"/>. Only file metadata goes to the
/// database; the bytes live on disk (see HRMS.Web.Services.DocumentStorage).
/// </summary>
public interface IEmployeeDocumentRepository
{
    /// <summary>Every active document type, grouped by section, with the employee's current file.</summary>
    Task<IReadOnlyList<EmployeeDocumentRow>> ListAsync(long employeeId, CancellationToken cancellationToken = default);

    /// <summary>One current (non-deleted) file, or null - always checked against the employee.</summary>
    Task<EmployeeDocumentFile?> GetAsync(long employeeId, long attachmentId, CancellationToken cancellationToken = default);

    /// <summary>Records a new upload; any previous file for the same type is soft-deleted.</summary>
    Task<SaveResult> AddAsync(EmployeeDocumentFile file, long? currentUserId, CancellationToken cancellationToken = default);

    Task<SaveResult> DeleteAsync(long employeeId, long attachmentId, long? currentUserId, CancellationToken cancellationToken = default);
}

public sealed class EmployeeDocumentRepository : IEmployeeDocumentRepository
{
    private readonly ISqlExecutor _sql;

    public EmployeeDocumentRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<EmployeeDocumentRow>> ListAsync(
        long employeeId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope(DbAction.List, employeeId);

        return _sql.QueryAsync<EmployeeDocumentRow>(
            StoredProcedure.EmployeeDocumentManage, parameters, cancellationToken);
    }

    public Task<EmployeeDocumentFile?> GetAsync(
        long employeeId, long attachmentId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope(DbAction.Get, employeeId);
        parameters.Add("@AttachmentId", attachmentId, DbType.Int64);

        return _sql.QuerySingleOrDefaultAsync<EmployeeDocumentFile>(
            StoredProcedure.EmployeeDocumentManage, parameters, cancellationToken);
    }

    public async Task<SaveResult> AddAsync(
        EmployeeDocumentFile file, long? currentUserId, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(file);

        var parameters = Envelope(DbAction.Insert, file.EmployeeId);
        parameters.Add("@DocumentTypeId", file.DocumentTypeId, DbType.Int32);
        parameters.Add("@OriginalFileName", file.OriginalFileName, DbType.String, size: 260);
        parameters.Add("@StoredFileName", file.StoredFileName, DbType.String, size: 400);
        parameters.Add("@ContentType", file.ContentType, DbType.String, size: 100);
        parameters.Add("@FileSizeBytes", file.FileSizeBytes, DbType.Int64);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        await _sql.ExecuteAsync(StoredProcedure.EmployeeDocumentManage, parameters, cancellationToken)
                  .ConfigureAwait(false);

        return ReadResult(parameters, fallbackId: 0);
    }

    public async Task<SaveResult> DeleteAsync(
        long employeeId, long attachmentId, long? currentUserId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope(DbAction.Delete, employeeId);
        parameters.Add("@AttachmentId", attachmentId, DbType.Int64);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        await _sql.ExecuteAsync(StoredProcedure.EmployeeDocumentManage, parameters, cancellationToken)
                  .ConfigureAwait(false);

        return ReadResult(parameters, fallbackId: attachmentId);
    }

    private static DynamicParameters Envelope(string action, long employeeId)
    {
        var parameters = new DynamicParameters();

        parameters.Add("@Action", action, DbType.AnsiString, size: 10);
        parameters.Add("@EmployeeId", employeeId, DbType.Int64);
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
}
