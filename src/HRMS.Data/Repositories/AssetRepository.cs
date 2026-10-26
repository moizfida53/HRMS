using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Assets;
using HRMS.Domain.Common;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

/// <summary>Setup > Organization > Asset Types: the kinds of company asset (db/84).</summary>
public interface IAssetTypeRepository : IMasterRepository<AssetType> { }

public sealed class AssetTypeRepository : MasterRepositoryBase<AssetType>, IAssetTypeRepository
{
    public AssetTypeRepository(ISqlExecutor sql) : base(sql) { }

    protected override string ProcedureName => StoredProcedure.AssetTypeManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "TypeName", "IsActive", "UsageCount", "SortOrder" };

    protected override string DefaultSortColumn => "SortOrder";

    protected override long GetKey(AssetType entity) => entity.AssetTypeId;

    protected override void AddEntityParameters(DynamicParameters parameters, AssetType entity)
    {
        parameters.Add("@TypeName", entity.TypeName, DbType.String, size: 100);
        parameters.Add("@ArabicName", entity.ArabicName, DbType.String, size: 100);
        parameters.Add("@Icon", AssetIcon.All.Contains(entity.Icon) ? entity.Icon : AssetIcon.Other, DbType.AnsiString, size: 12);
        parameters.Add("@HasExpiryDate", entity.HasExpiryDate, DbType.Boolean);
        parameters.Add("@ExpiryLabel", entity.ExpiryLabel, DbType.String, size: 80);
        parameters.Add("@ExpiryLabelAr", entity.ExpiryLabelAr, DbType.String, size: 80);
        // the form posts its ticked alerts; anything else (the stored value) is kept as it is
        var rules = entity.AlertChoices is { } picked
            ? string.Join(",", ExpiryAlert.Parse(string.Join(",", picked)).Select(r => r.Code))
            : entity.AlertRules;
        parameters.Add("@AlertRules", string.IsNullOrEmpty(rules) ? null : rules, DbType.AnsiString, size: 60);
        parameters.Add("@SortOrder", entity.SortOrder, DbType.Int32);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}

/// <summary>Who is asking: a user pinned to one company, the top-bar company filter, and the user.</summary>
public sealed record AssetScope(int? UserCompanyId, string? CompanyIds, long? UserId);

/// <summary>The Assets list's filters.</summary>
public sealed record AssetFilter(int? AssetTypeId, string? Status, string? Search, int PageNumber = 1, int PageSize = 25);

/// <summary>Workforce > Assets: company assets and who uses them (db/84).</summary>
public interface IAssetRepository
{
    Task<(IReadOnlyList<AssetRow> Rows, int Total)> ListAsync(AssetFilter filter, AssetScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<AssetSummaryRow>> SummaryAsync(AssetScope scope, CancellationToken ct = default);
    Task<AssetRow?> GetAsync(long id, AssetScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<AssetAssignment>> HistoryAsync(long id, AssetScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<AssetRow>> EmployeeAsync(long employeeId, AssetScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<AssetDue>> DueAsync(AssetScope scope, CancellationToken ct = default);
    Task<SaveResult> SaveAsync(AssetInput input, AssetScope scope, CancellationToken ct = default);
    Task<SaveResult> ReturnAsync(long id, string? remarks, AssetScope scope, CancellationToken ct = default);
    Task<SaveResult> DeleteAsync(long id, AssetScope scope, CancellationToken ct = default);
}

public sealed class AssetRepository : IAssetRepository
{
    private readonly ISqlExecutor _sql;

    public AssetRepository(ISqlExecutor sql) => _sql = sql;

    public async Task<(IReadOnlyList<AssetRow> Rows, int Total)> ListAsync(AssetFilter filter, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("LIST", scope);
        p.Add("@AssetTypeId", filter.AssetTypeId is > 0 ? filter.AssetTypeId : null, DbType.Int32);
        p.Add("@Status", Trim(filter.Status, 10), DbType.AnsiString, size: 10);
        p.Add("@Search", Trim(filter.Search, 200), DbType.String, size: 200);
        p.Add("@PageNumber", Math.Max(1, filter.PageNumber), DbType.Int32);
        p.Add("@PageSize", Math.Clamp(filter.PageSize, 1, 200), DbType.Int32);
        var rows = await _sql.QueryAsync<AssetRow>(StoredProcedure.AssetManage, p, ct).ConfigureAwait(false);
        return (rows, p.Get<int?>("@TotalCount") ?? rows.Count);
    }

    public Task<IReadOnlyList<AssetSummaryRow>> SummaryAsync(AssetScope scope, CancellationToken ct = default) =>
        _sql.QueryAsync<AssetSummaryRow>(StoredProcedure.AssetManage, Envelope("SUMMARY", scope), ct);

    public Task<AssetRow?> GetAsync(long id, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("GET", scope);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<AssetRow>(StoredProcedure.AssetManage, p, ct);
    }

    public Task<IReadOnlyList<AssetAssignment>> HistoryAsync(long id, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("HISTORY", scope);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QueryAsync<AssetAssignment>(StoredProcedure.AssetManage, p, ct);
    }

    public Task<IReadOnlyList<AssetRow>> EmployeeAsync(long employeeId, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("EMPLOYEE", scope);
        p.Add("@EmployeeId", employeeId, DbType.Int64);
        return _sql.QueryAsync<AssetRow>(StoredProcedure.AssetManage, p, ct);
    }

    public Task<IReadOnlyList<AssetDue>> DueAsync(AssetScope scope, CancellationToken ct = default) =>
        _sql.QueryAsync<AssetDue>(StoredProcedure.AssetManage, Envelope("DUE", scope), ct);

    public async Task<SaveResult> SaveAsync(AssetInput input, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("SAVE", scope);
        p.Add("@Id", input.AssetId > 0 ? input.AssetId : null, DbType.Int64);
        p.Add("@CompanyId", input.CompanyId > 0 ? input.CompanyId : null, DbType.Int32);
        p.Add("@AssetTypeId", input.AssetTypeId, DbType.Int32);
        p.Add("@AssetCode", Trim(input.AssetCode, 30), DbType.String, size: 30);
        p.Add("@Brand", Trim(input.Brand, 100), DbType.String, size: 100);
        p.Add("@Model", Trim(input.Model, 100), DbType.String, size: 100);
        p.Add("@Color", Trim(input.Color, 50), DbType.String, size: 50);
        p.Add("@SerialNumber", Trim(input.SerialNumber, 100), DbType.String, size: 100);
        p.Add("@PurchaseDate", input.PurchaseDate, DbType.Date);
        p.Add("@PurchaseCost", input.PurchaseCost, DbType.Decimal, precision: 12, scale: 3);
        p.Add("@ExpiryDate", input.ExpiryDate, DbType.Date);
        p.Add("@EmployeeId", input.EmployeeId is > 0 ? input.EmployeeId : null, DbType.Int64);
        p.Add("@AssignedDate", input.AssignedDate, DbType.Date);
        p.Add("@Notes", Trim(input.Notes, 500), DbType.String, size: 500);
        p.Add("@IsActive", input.IsActive, DbType.Boolean);
        p.Add("@Remarks", Trim(input.Remarks, 300), DbType.String, size: 300);
        await _sql.ExecuteAsync(StoredProcedure.AssetManage, p, ct).ConfigureAwait(false);
        return Read(p, input.AssetId);
    }

    public async Task<SaveResult> ReturnAsync(long id, string? remarks, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("RETURN", scope);
        p.Add("@Id", id, DbType.Int64);
        p.Add("@Remarks", Trim(remarks, 300), DbType.String, size: 300);
        await _sql.ExecuteAsync(StoredProcedure.AssetManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    public async Task<SaveResult> DeleteAsync(long id, AssetScope scope, CancellationToken ct = default)
    {
        var p = Envelope("DELETE", scope);
        p.Add("@Id", id, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.AssetManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    private static DynamicParameters Envelope(string action, AssetScope scope)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        p.Add("@UserCompanyId", scope.UserCompanyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(scope.CompanyIds, 2000), DbType.String, size: 2000);
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

    private static string? Trim(string? value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length > max ? value[..max] : value;
    }
}
