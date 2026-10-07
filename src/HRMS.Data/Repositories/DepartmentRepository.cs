using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface IDepartmentRepository : IMasterRepository<Department>
{
}

public sealed class DepartmentRepository : MasterRepositoryBase<Department>, IDepartmentRepository
{
    public DepartmentRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.DepartmentManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "DepartmentCode", "DepartmentName", "CompanyName", "ParentDepartmentName", "CostCenterName", "IsActive"
        };

    protected override string DefaultSortColumn => "DepartmentName";

    protected override long GetKey(Department entity) => entity.DepartmentId;

    protected override void AddEntityParameters(DynamicParameters parameters, Department entity)
    {
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@ParentDepartmentId", entity.ParentDepartmentId, DbType.Int32);
        parameters.Add("@DepartmentCode", entity.DepartmentCode, DbType.String, size: 50);
        parameters.Add("@DepartmentName", entity.DepartmentName, DbType.String, size: 150);
        parameters.Add("@CostCenterId", entity.CostCenterId, DbType.Int32);
        parameters.Add("@ManagerEmployeeId", entity.ManagerEmployeeId, DbType.Int64);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
