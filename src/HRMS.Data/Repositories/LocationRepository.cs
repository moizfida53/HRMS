using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface ILocationRepository : IMasterRepository<Location>
{
}

public sealed class LocationRepository : MasterRepositoryBase<Location>, ILocationRepository
{
    public LocationRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.LocationManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "LocationCode", "LocationName", "CompanyName", "BranchName", "Governorate", "LocationType", "IsActive"
        };

    protected override string DefaultSortColumn => "LocationName";

    protected override long GetKey(Location entity) => entity.LocationId;

    protected override void AddEntityParameters(DynamicParameters parameters, Location entity)
    {
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@BranchId", entity.BranchId, DbType.Int32);
        parameters.Add("@LocationCode", entity.LocationCode, DbType.String, size: 50);
        parameters.Add("@LocationName", entity.LocationName, DbType.String, size: 150);
        parameters.Add("@LocationType", entity.LocationType, DbType.String, size: 50);
        parameters.Add("@Governorate", entity.Governorate, DbType.String, size: 100);
        parameters.Add("@Area", entity.Area, DbType.String, size: 100);
        parameters.Add("@Block", entity.Block, DbType.String, size: 30);
        parameters.Add("@Street", entity.Street, DbType.String, size: 150);
        parameters.Add("@Building", entity.Building, DbType.String, size: 50);
        parameters.Add("@Latitude", entity.Latitude, DbType.Decimal, precision: 10, scale: 7);
        parameters.Add("@Longitude", entity.Longitude, DbType.Decimal, precision: 10, scale: 7);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
