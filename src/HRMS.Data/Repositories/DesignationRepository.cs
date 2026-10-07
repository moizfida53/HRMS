using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface IDesignationRepository : IMasterRepository<Designation>
{
}

public sealed class DesignationRepository : MasterRepositoryBase<Designation>, IDesignationRepository
{
    public DesignationRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.DesignationManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "DesignationCode", "DesignationName", "CompanyName", "GradeName", "IsActive"
        };

    protected override string DefaultSortColumn => "DesignationName";

    protected override long GetKey(Designation entity) => entity.DesignationId;

    protected override void AddEntityParameters(DynamicParameters parameters, Designation entity)
    {
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@DesignationCode", entity.DesignationCode, DbType.String, size: 50);
        parameters.Add("@DesignationName", entity.DesignationName, DbType.String, size: 150);
        parameters.Add("@ArabicName", entity.ArabicName, DbType.String, size: 150);
        parameters.Add("@GradeId", entity.GradeId, DbType.Int32);
        parameters.Add("@Description", entity.Description, DbType.String, size: 500);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
