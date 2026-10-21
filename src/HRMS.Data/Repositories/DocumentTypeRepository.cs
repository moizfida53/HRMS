using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

/// <summary>Organization > Employee Documents: the document types (db/63).</summary>
public interface IDocumentTypeRepository : IMasterRepository<DocumentType>
{
}

public sealed class DocumentTypeRepository : MasterRepositoryBase<DocumentType>, IDocumentTypeRepository
{
    public DocumentTypeRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.DocumentTypeManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "DocumentTypeName", "SectionName", "IsMandatory", "IsActive", "UsageCount"
        };

    protected override string DefaultSortColumn => "SectionName";

    protected override long GetKey(DocumentType entity) => entity.DocumentTypeId;

    protected override void AddEntityParameters(DynamicParameters parameters, DocumentType entity)
    {
        parameters.Add("@DocumentTypeName", entity.DocumentTypeName, DbType.String, size: 200);
        parameters.Add("@ArabicName", entity.ArabicName, DbType.String, size: 200);
        parameters.Add("@SectionId", entity.SectionId, DbType.Int32);
        parameters.Add("@IsMandatory", entity.IsMandatory, DbType.Boolean);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
        parameters.Add("@SortOrder", entity.SortOrder, DbType.Int32);
    }
}

/// <summary>The sections document types are listed under; INSERT backs the "+" on the document type form.</summary>
public interface IDocumentSectionRepository
{
    Task<IReadOnlyList<DocumentSection>> ListAsync(CancellationToken cancellationToken = default);
    Task<SaveResult> AddAsync(string nameEng, string? nameArb, long? userId, CancellationToken cancellationToken = default);
}

public sealed class DocumentSectionRepository : IDocumentSectionRepository
{
    private readonly ISqlExecutor _sql;

    public DocumentSectionRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<DocumentSection>> ListAsync(CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@Action", "LIST", DbType.AnsiString, size: 10);
        return _sql.QueryAsync<DocumentSection>(StoredProcedure.DocumentSectionManage, p, cancellationToken);
    }

    public async Task<SaveResult> AddAsync(string nameEng, string? nameArb, long? userId, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@Action", "INSERT", DbType.AnsiString, size: 10);
        p.Add("@NameEng", nameEng, DbType.String, size: 150);
        p.Add("@NameArb", string.IsNullOrWhiteSpace(nameArb) ? null : nameArb, DbType.String, size: 150);
        p.Add("@UserId", userId, DbType.Int64);
        p.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        p.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        p.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        await _sql.ExecuteAsync(StoredProcedure.DocumentSectionManage, p, cancellationToken).ConfigureAwait(false);

        var code = p.Get<string?>("@ResultCode") ?? ResultCode.Success;
        var message = p.Get<string?>("@ResultMessage") ?? string.Empty;
        return code == ResultCode.Success
            ? SaveResult.Ok(p.Get<long?>("@NewId") ?? 0, message)
            : SaveResult.Fail(string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code);
    }
}
