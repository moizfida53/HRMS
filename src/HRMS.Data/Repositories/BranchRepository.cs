using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface IBranchRepository : IMasterRepository<Branch>
{
}

public sealed class BranchRepository : MasterRepositoryBase<Branch>, IBranchRepository
{
    public BranchRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.BranchManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "BranchCode", "BranchName", "CompanyName", "Governorate", "Area", "IsActive"
        };

    protected override string DefaultSortColumn => "BranchName";

    protected override long GetKey(Branch entity) => entity.BranchId;

    protected override void AddEntityParameters(DynamicParameters parameters, Branch entity)
    {
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@BranchCode", entity.BranchCode, DbType.String, size: 30);
        parameters.Add("@BranchName", entity.BranchName, DbType.String, size: 150);
        parameters.Add("@Address", entity.Address, DbType.String, size: 500);
        parameters.Add("@Area", entity.Area, DbType.String, size: 100);
        parameters.Add("@Governorate", entity.Governorate, DbType.String, size: 100);
        parameters.Add("@Telephone", entity.Telephone, DbType.String, size: 50);
        parameters.Add("@Email", entity.Email, DbType.String, size: 150);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
