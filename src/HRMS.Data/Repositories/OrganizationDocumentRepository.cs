using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

/// <summary>Setup > Organization > Organization Documents: the types of company document (db/73).</summary>
public interface IOrgDocumentTypeRepository : IMasterRepository<OrgDocumentType> { }

public sealed class OrgDocumentTypeRepository : MasterRepositoryBase<OrgDocumentType>, IOrgDocumentTypeRepository
{
    public OrgDocumentTypeRepository(ISqlExecutor sql) : base(sql) { }

    protected override string ProcedureName => StoredProcedure.OrgDocumentTypeManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "TypeName", "Category", "IsMandatory", "IsActive", "UsageCount" };

    protected override string DefaultSortColumn => "Category";

    protected override long GetKey(OrgDocumentType entity) => entity.OrgDocumentTypeId;

    protected override void AddEntityParameters(DynamicParameters parameters, OrgDocumentType entity)
    {
        parameters.Add("@TypeName", entity.TypeName, DbType.String, size: 150);
        parameters.Add("@ArabicName", entity.ArabicName, DbType.String, size: 150);
        parameters.Add("@Category", entity.Category, DbType.AnsiString, size: 20);
        parameters.Add("@IsMandatory", entity.IsMandatory, DbType.Boolean);
        parameters.Add("@HasNumber", entity.HasNumber, DbType.Boolean);
        parameters.Add("@HasIssueDate", entity.HasIssueDate, DbType.Boolean);
        parameters.Add("@HasExpiryDate", entity.HasExpiryDate, DbType.Boolean);
        // the form posts its ticked alerts; anything else (the stored value) is kept as it is
        var rules = entity.AlertChoices is { } picked
            ? string.Join(",", ExpiryAlert.Parse(string.Join(",", picked)).Select(r => r.Code))
            : entity.AlertRules;
        parameters.Add("@AlertRules", string.IsNullOrEmpty(rules) ? null : rules, DbType.AnsiString, size: 60);
        parameters.Add("@SortOrder", entity.SortOrder, DbType.Int32);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}

/// <summary>Who is asking: a user pinned to one company, and the top-bar company filter.</summary>
public sealed record OrgDocumentScope(int? UserCompanyId, string? CompanyIds, long? UserId);

/// <summary>Workforce > Organizations: each active company's legal and compliance documents (db/73).</summary>
public interface IOrganizationDocumentRepository
{
    Task<IReadOnlyList<OrgCompanySummary>> CompaniesAsync(OrgDocumentScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<OrgDocumentRow>> ListAsync(int companyId, OrgDocumentScope scope, CancellationToken ct = default);
    Task<OrgDocument?> GetAsync(long id, OrgDocumentScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<OrgDocumentVersion>> HistoryAsync(int companyId, int typeId, OrgDocumentScope scope, CancellationToken ct = default);
    Task<SaveResult> SaveAsync(OrgDocumentInput input, OrgDocumentFile? file, OrgDocumentScope scope, CancellationToken ct = default);
    Task<SaveResult> DeleteAsync(long id, OrgDocumentScope scope, CancellationToken ct = default);
    Task<IReadOnlyList<OrgDocumentDue>> DueAsync(OrgDocumentScope scope, CancellationToken ct = default);
}

public sealed class OrganizationDocumentRepository : IOrganizationDocumentRepository
{
    private readonly ISqlExecutor _sql;

    public OrganizationDocumentRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<OrgCompanySummary>> CompaniesAsync(OrgDocumentScope scope, CancellationToken ct = default) =>
        _sql.QueryAsync<OrgCompanySummary>(StoredProcedure.OrgDocumentManage, Envelope("COMPANIES", scope), ct);

    public Task<IReadOnlyList<OrgDocumentRow>> ListAsync(int companyId, OrgDocumentScope scope, CancellationToken ct = default)
    {
        var p = Envelope("LIST", scope);
        p.Add("@CompanyId", companyId, DbType.Int32);
        return _sql.QueryAsync<OrgDocumentRow>(StoredProcedure.OrgDocumentManage, p, ct);
    }

    public Task<OrgDocument?> GetAsync(long id, OrgDocumentScope scope, CancellationToken ct = default)
    {
        var p = Envelope("GET", scope);
        p.Add("@Id", id, DbType.Int64);
        return _sql.QuerySingleOrDefaultAsync<OrgDocument>(StoredProcedure.OrgDocumentManage, p, ct);
    }

    public Task<IReadOnlyList<OrgDocumentVersion>> HistoryAsync(int companyId, int typeId, OrgDocumentScope scope, CancellationToken ct = default)
    {
        var p = Envelope("HISTORY", scope);
        p.Add("@CompanyId", companyId, DbType.Int32);
        p.Add("@OrgDocumentTypeId", typeId, DbType.Int32);
        return _sql.QueryAsync<OrgDocumentVersion>(StoredProcedure.OrgDocumentManage, p, ct);
    }

    public async Task<SaveResult> SaveAsync(OrgDocumentInput input, OrgDocumentFile? file, OrgDocumentScope scope, CancellationToken ct = default)
    {
        var p = Envelope("SAVE", scope);
        p.Add("@Id", input.OrgDocumentId, DbType.Int64);
        p.Add("@CompanyId", input.CompanyId, DbType.Int32);
        p.Add("@OrgDocumentTypeId", input.OrgDocumentTypeId, DbType.Int32);
        p.Add("@DocumentNumber", Trim(input.DocumentNumber, 100), DbType.String, size: 100);
        p.Add("@IssuingAuthority", Trim(input.IssuingAuthority, 150), DbType.String, size: 150);
        p.Add("@IssueDate", input.IssueDate, DbType.Date);
        p.Add("@ExpiryDate", input.ExpiryDate, DbType.Date);
        p.Add("@Notes", Trim(input.Notes, 500), DbType.String, size: 500);
        p.Add("@OriginalFileName", file?.OriginalFileName, DbType.String, size: 260);
        p.Add("@StoredFileName", file?.StoredFileName, DbType.String, size: 400);
        p.Add("@ContentType", file?.ContentType, DbType.String, size: 100);
        p.Add("@FileSizeBytes", file?.SizeBytes, DbType.Int64);
        p.Add("@RemoveFile", input.RemoveFile, DbType.Boolean);
        p.Add("@Renew", input.Renew, DbType.Boolean);
        await _sql.ExecuteAsync(StoredProcedure.OrgDocumentManage, p, ct).ConfigureAwait(false);
        return Read(p, input.OrgDocumentId);
    }

    public async Task<SaveResult> DeleteAsync(long id, OrgDocumentScope scope, CancellationToken ct = default)
    {
        var p = Envelope("DELETE", scope);
        p.Add("@Id", id, DbType.Int64);
        await _sql.ExecuteAsync(StoredProcedure.OrgDocumentManage, p, ct).ConfigureAwait(false);
        return Read(p, id);
    }

    public Task<IReadOnlyList<OrgDocumentDue>> DueAsync(OrgDocumentScope scope, CancellationToken ct = default) =>
        _sql.QueryAsync<OrgDocumentDue>(StoredProcedure.OrgDocumentManage, Envelope("DUE", scope), ct);

    private static DynamicParameters Envelope(string action, OrgDocumentScope scope)
    {
        var p = new DynamicParameters();
        p.Add("@Action", action, DbType.AnsiString, size: 10);
        p.Add("@UserCompanyId", scope.UserCompanyId, DbType.Int32);
        p.Add("@CompanyIds", Trim(scope.CompanyIds, 2000), DbType.String, size: 2000);
        p.Add("@UserId", scope.UserId, DbType.Int64);
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
