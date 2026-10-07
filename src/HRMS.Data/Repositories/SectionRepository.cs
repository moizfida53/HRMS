using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface ISectionRepository : IMasterRepository<Section>
{
}

public sealed class SectionRepository : MasterRepositoryBase<Section>, ISectionRepository
{
    public SectionRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.SectionManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "SectionCode", "SectionName", "DepartmentName", "CompanyName", "IsActive"
        };

    protected override string DefaultSortColumn => "SectionName";

    protected override long GetKey(Section entity) => entity.SectionId;

    protected override void AddEntityParameters(DynamicParameters parameters, Section entity)
    {
        parameters.Add("@DepartmentId", entity.DepartmentId, DbType.Int32);
        parameters.Add("@SectionCode", entity.SectionCode, DbType.String, size: 50);
        parameters.Add("@SectionName", entity.SectionName, DbType.String, size: 150);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
