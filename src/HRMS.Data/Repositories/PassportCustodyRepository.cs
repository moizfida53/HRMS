using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

/// <summary>Passport In / Out (db/93): who holds an employee's passport, and the log of hand-overs.</summary>
public interface IPassportCustodyRepository
{
    Task<PassportCustodyStatus?> StatusAsync(long employeeId, AssetScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<PassportMovement>> LogAsync(long employeeId, AssetScope scope, CancellationToken ct = default);
    Task<SaveResult> SaveAsync(long employeeId, string? heldBy, DateTime? date, string? remarks, AssetScope scope, CancellationToken ct = default);
}

public sealed class PassportCustodyRepository : IPassportCustodyRepository
{
    private readonly ISqlExecutor _sql;

    public PassportCustodyRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<PassportCustodyStatus?> StatusAsync(long employeeId, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("STATUS", employeeId, scope);
        var row = await _sql.QuerySingleOrDefaultAsync<PassportCustodyStatus>(StoredProcedure.PassportCustodyManage, p, ct).ConfigureAwait(false);
        return Read(p, employeeId).Success ? row : null;
    }

    public async Task<IReadOnlyList<PassportMovement>> LogAsync(long employeeId, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("LOG", employeeId, scope);
        var rows = await _sql.QueryAsync<PassportMovement>(StoredProcedure.PassportCustodyManage, p, ct).ConfigureAwait(false);
        return Read(p, employeeId).Success ? rows : Array.Empty<PassportMovement>();
    }

    public async Task<SaveResult> SaveAsync(long employeeId, string? heldBy, DateTime? date, string? remarks, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("SAVE", employeeId, scope);
        p.Add("@HeldBy", string.IsNullOrWhiteSpace(heldBy) ? null : heldBy.Trim().ToUpperInvariant()[..1], DbType.AnsiStringFixedLength, size: 1);
        p.Add("@MovementDate", date, DbType.Date);
        p.Add("@Remarks", string.IsNullOrWhiteSpace(remarks) ? null : remarks.Trim()[..Math.Min(remarks.Trim().Length, 300)], DbType.String, size: 300);
        await _sql.ExecuteAsync(StoredProcedure.PassportCustodyManage, p, ct).ConfigureAwait(false);
        return Read(p, employeeId);
    }

    private static DynamicParameters Envelope(string action, long employeeId, AssetScope scope)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        p.Add("@CompanyId", scope.UserCompanyId, DbType.Int32);
        p.Add("@CompanyIds", scope.CompanyIds, DbType.String, size: 2000);
        p.Add("@UserId", scope.UserId, DbType.Int64);
        p.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        return p;
    }

    private static SaveResult Read(DynamicParameters p, long fallbackId)
    {
        var code = p.Get<string?>("@ResultCode") ?? ResultCode.Success;
        var message = p.Get<string?>("@ResultMessage") ?? string.Empty;
        var id = p.Get<long?>("@NewId") is { } n && n > 0 ? n : fallbackId;
        return string.Equals(code, ResultCode.Success, StringComparison.Ordinal)
            ? SaveResult.Ok(id, string.IsNullOrWhiteSpace(message) ? "Saved successfully." : message)
            : SaveResult.Fail(string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code);
    }
}
