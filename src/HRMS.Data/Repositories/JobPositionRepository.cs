using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface IJobPositionRepository : IMasterRepository<JobPosition>
{
}

public sealed class JobPositionRepository : MasterRepositoryBase<JobPosition>, IJobPositionRepository
{
    public JobPositionRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.JobPositionManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "PositionCode", "PositionName", "CompanyName", "GradeName", "IsActive"
        };

    protected override string DefaultSortColumn => "PositionName";

    protected override long GetKey(JobPosition entity) => entity.PositionId;

    protected override void AddEntityParameters(DynamicParameters parameters, JobPosition entity)
    {
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@PositionCode", entity.PositionCode, DbType.String, size: 50);
        parameters.Add("@PositionName", entity.PositionName, DbType.String, size: 150);
        parameters.Add("@JobDescription", entity.JobDescription, DbType.String, size: -1);
        parameters.Add("@GradeId", entity.GradeId, DbType.Int32);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
