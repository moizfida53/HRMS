using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Organization;

namespace HRMS.Data.Repositories;

public interface ICompanyRepository : IMasterRepository<Company>
{
}

public sealed class CompanyRepository : MasterRepositoryBase<Company>, ICompanyRepository
{
    public CompanyRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.CompanyManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "CompanyCode", "CompanyName", "LegalName", "CountryName", "IsActive"
        };

    protected override string DefaultSortColumn => "CompanyName";

    protected override long GetKey(Company entity) => entity.CompanyId;

    protected override void AddEntityParameters(DynamicParameters parameters, Company entity)
    {
        parameters.Add("@CompanyCode", entity.CompanyCode, DbType.String, size: 30);
        parameters.Add("@CompanyName", entity.CompanyName, DbType.String, size: 200);
        parameters.Add("@LegalName", entity.LegalName, DbType.String, size: 250);
        parameters.Add("@CommercialRegistrationNo", entity.CommercialRegistrationNo, DbType.String, size: 100);
        parameters.Add("@TaxNo", entity.TaxNo, DbType.String, size: 100);
        parameters.Add("@CountryId", entity.CountryId, DbType.Int32);
        parameters.Add("@DefaultCurrencyId", entity.DefaultCurrencyId, DbType.Int32);
        parameters.Add("@Address", entity.Address, DbType.String, size: 500);
        parameters.Add("@Telephone", entity.Telephone, DbType.String, size: 50);
        parameters.Add("@Email", entity.Email, DbType.String, size: 150);
        parameters.Add("@Website", entity.Website, DbType.String, size: 200);
        parameters.Add("@LogoPath", entity.LogoPath, DbType.String, size: 500);
        parameters.Add("@IsActive", entity.IsActive, DbType.Boolean);
    }
}
