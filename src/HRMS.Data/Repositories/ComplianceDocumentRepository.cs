using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>
/// Kuwait Compliance images (db/71): Civil ID, Passport, Residency and Work Permit
/// images tied to their expiry date, with renewals and archived images.
/// Uploads go through <see cref="IEmployeeDocumentRepository"/> like any document.
/// </summary>
public interface IComplianceDocumentRepository
{
    Task<IReadOnlyList<ComplianceDocumentRow>> ListAsync(long employeeId, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ComplianceImageEntry>> HistoryAsync(long employeeId, string complianceKey, CancellationToken cancellationToken = default);

    /// <summary>Applies the item's new images to the expiry date (and number); a renewal archives the images it replaces.</summary>
    Task<SaveResult> ConfirmAsync(long employeeId, string complianceKey, DateTime? expiryDate, string? documentNumber,
                                  long? currentUserId, CancellationToken cancellationToken = default);
}

public sealed class ComplianceDocumentRepository : IComplianceDocumentRepository
{
    private readonly ISqlExecutor _sql;

    public ComplianceDocumentRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<ComplianceDocumentRow>> ListAsync(long employeeId, CancellationToken cancellationToken = default) =>
        _sql.QueryAsync<ComplianceDocumentRow>(StoredProcedure.ComplianceDocumentManage, Envelope("LIST", employeeId), cancellationToken);

    public Task<IReadOnlyList<ComplianceImageEntry>> HistoryAsync(long employeeId, string complianceKey, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("HISTORY", employeeId);
        parameters.Add("@ComplianceKey", complianceKey, DbType.AnsiString, size: 20);
        return _sql.QueryAsync<ComplianceImageEntry>(StoredProcedure.ComplianceDocumentManage, parameters, cancellationToken);
    }

    public async Task<SaveResult> ConfirmAsync(long employeeId, string complianceKey, DateTime? expiryDate, string? documentNumber,
                                               long? currentUserId, CancellationToken cancellationToken = default)
    {
        var parameters = Envelope("CONFIRM", employeeId);
        parameters.Add("@ComplianceKey", complianceKey, DbType.AnsiString, size: 20);
        parameters.Add("@ExpiryDate", expiryDate, DbType.Date);
        parameters.Add("@DocumentNumber", string.IsNullOrWhiteSpace(documentNumber) ? null : documentNumber.Trim(), DbType.String, size: 50);
        parameters.Add("@UserId", currentUserId, DbType.Int64);

        await _sql.ExecuteAsync(StoredProcedure.ComplianceDocumentManage, parameters, cancellationToken).ConfigureAwait(false);

        var code = parameters.Get<string?>("@ResultCode") ?? ResultCode.Success;
        var message = parameters.Get<string?>("@ResultMessage") ?? string.Empty;
        return string.Equals(code, ResultCode.Success, StringComparison.Ordinal)
            ? SaveResult.Ok(employeeId, string.IsNullOrWhiteSpace(message) ? "Saved successfully." : message)
            : SaveResult.Fail(string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code);
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
}
