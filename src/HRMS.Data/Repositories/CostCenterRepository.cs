using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface ICostCenterRepository : IMasterRepository<CostCenter>
{
}

public sealed class CostCenterRepository : MasterRepositoryBase<CostCenter>, ICostCenterRepository
{
    public CostCenterRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.CostCenterManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "CostCenterCode", "CostCenterName", "CompanyName", "ParentCostCenterName", "IsActive"
        };

    protected override string DefaultSortColumn => "CostCenterName";

    protected override long GetKey(CostCenter entity) => entity.CostCenterId;

    protected override void AddEntityParameters(DynamicParameters parameters, CostCenter entity)
    {
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@ParentCostCenterId", entity.ParentCostCenterId, DbType.Int32);
        parameters.Add("@CostCenterCode", entity.CostCenterCode, DbType.String, size: 50);
        parameters.Add("@CostCenterName", entity.CostCenterName, DbType.String, size: 150);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
