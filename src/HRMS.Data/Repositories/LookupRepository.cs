using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;

namespace HRMS.Data.Repositories;

public interface ILookupRepository
{
    /// <summary>
    /// Fetches any dropdown in the application. One procedure, one C# method -
    /// adding a new dropdown means adding a branch to the procedure, not a new
    /// procedure and a new repository method.
    /// </summary>
    Task<IReadOnlyList<LookupItem>> GetAsync(
        string lookupType,
        int? companyId = null,
        int? parentId = null,
        bool includeInactive = false,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Shared uniqueness check used by every master form. Returns true when the
    /// code is already taken by a different row.
    /// </summary>
    Task<bool> IsDuplicateCodeAsync(
        string entityName,
        string code,
        long? excludeId = null,
        int? scopeId = null,
        CancellationToken cancellationToken = default);
}

public sealed class LookupRepository : ILookupRepository
{
    private readonly ISqlExecutor _sql;

    /// <summary>
    /// Allowlist mirroring the CHECK inside Core.usp_Lookup_Get. Validated here as
    /// well so an invalid type fails fast without a database round trip.
    /// </summary>
    private static readonly IReadOnlySet<string> AllowedLookupTypes =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            LookupType.Company,
            LookupType.Branch,
            LookupType.Department,
            LookupType.Section,
            LookupType.Designation,
            LookupType.JobPosition,
            LookupType.Location,
            LookupType.CostCenter,
            LookupType.Grade,
            LookupType.Country,
            LookupType.Currency,
            LookupType.Governorate,
            LookupType.Employee
        };

    private static readonly IReadOnlySet<string> AllowedDuplicateEntities =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "COMPANY", "BRANCH", "DEPARTMENT", "SECTION",
            "DESIGNATION", "JOBPOSITION", "LOCATION", "COSTCENTER"
        };

    public LookupRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<IReadOnlyList<LookupItem>> GetAsync(
        string lookupType,
        int? companyId = null,
        int? parentId = null,
        bool includeInactive = false,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(lookupType) || !AllowedLookupTypes.Contains(lookupType))
        {
            throw new ArgumentException($"'{lookupType}' is not a recognised lookup type.", nameof(lookupType));
        }

        var parameters = new DynamicParameters();
        parameters.Add("@LookupType", lookupType.ToUpperInvariant(), DbType.AnsiString, size: 30);
        parameters.Add("@CompanyId", companyId, DbType.Int32);
        parameters.Add("@ParentId", parentId, DbType.Int32);
        parameters.Add("@IncludeInactive", includeInactive, DbType.Boolean);

        return await _sql.QueryAsync<LookupItem>(StoredProcedure.LookupGet, parameters, cancellationToken)
                         .ConfigureAwait(false);
    }

    public async Task<bool> IsDuplicateCodeAsync(
        string entityName,
        string code,
        long? excludeId = null,
        int? scopeId = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(entityName) || !AllowedDuplicateEntities.Contains(entityName))
        {
            throw new ArgumentException($"'{entityName}' is not a recognised master entity.", nameof(entityName));
        }

        if (string.IsNullOrWhiteSpace(code))
        {
            return false;
        }

        var parameters = new DynamicParameters();
        parameters.Add("@EntityName", entityName.ToUpperInvariant(), DbType.AnsiString, size: 30);
        parameters.Add("@Code", code.Trim(), DbType.String, size: 50);
        parameters.Add("@ExcludeId", excludeId, DbType.Int64);
        parameters.Add("@ScopeId", scopeId, DbType.Int32);
        parameters.Add("@IsDuplicate", dbType: DbType.Boolean, direction: ParameterDirection.Output);

        await _sql.ExecuteAsync(StoredProcedure.MasterCheckDuplicate, parameters, cancellationToken)
                  .ConfigureAwait(false);

        return parameters.Get<bool?>("@IsDuplicate") ?? false;
    }
}
