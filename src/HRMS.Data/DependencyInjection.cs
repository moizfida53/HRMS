using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Data.Repositories;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace HRMS.Data;

public static class DependencyInjection
{
    /// <summary>
    /// Registers the stored-procedure data layer. Nothing outside this assembly
    /// receives a connection or a connection string.
    /// </summary>
    public static IServiceCollection AddHrmsDataAccess(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services
            .AddOptions<SqlServerOptions>()
            // Everything except the connection string itself - timeout, encryption
            // flags, the DMV application name - lives under "Database" in
            // appsettings.json, since none of that is a secret.
            .Bind(configuration.GetSection(SqlServerOptions.SectionName))
            // The connection string is read the standard ASP.NET Core way, from
            // ConnectionStrings:SqlServerConnectionString, via GetConnectionString
            // so it works with the same "ConnectionStrings" section every other
            // .NET project uses. This runs after Bind() above, so it is the one
            // that wins if both happen to be set.
            .Configure(options =>
                options.ConnectionString =
                    configuration.GetConnectionString(SqlServerOptions.ConnectionStringName)
                    ?? options.ConnectionString)
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();
        services.AddScoped<ISqlExecutor, DapperStoredProcedureExecutor>();

        services.AddScoped<ILookupRepository, LookupRepository>();
        services.AddScoped<IAuthRepository, AuthRepository>();

        services.AddScoped<ICompanyRepository, CompanyRepository>();
        services.AddScoped<IBranchRepository, BranchRepository>();
        services.AddScoped<IDepartmentRepository, DepartmentRepository>();
        services.AddScoped<ISectionRepository, SectionRepository>();
        services.AddScoped<IDesignationRepository, DesignationRepository>();
        services.AddScoped<IJobPositionRepository, JobPositionRepository>();
        services.AddScoped<ILocationRepository, LocationRepository>();
        services.AddScoped<ICostCenterRepository, CostCenterRepository>();

        // ---- Module 4: Workforce - Employees & Kuwait Compliance ----
        services.AddScoped<IEmployeeRepository, EmployeeRepository>();
        services.AddScoped<IEmployeeComplianceRepository, EmployeeComplianceRepository>();
        services.AddScoped<IEmployeeDependentRepository, EmployeeDependentRepository>();
        services.AddScoped<IEmployeeDocumentRepository, EmployeeDocumentRepository>();

        // ---- Dashboard ----
        services.AddScoped<IDashboardRepository, DashboardRepository>();

        // ---- Localization (labels in Core.UiLabels, user language in Security.Users) ----
        services.AddScoped<ILocalizationRepository, LocalizationRepository>();

        // ---- Payroll: calendars / periods (db/29-30) and payroll runs (db/34-35) ----
        services.AddScoped<IPayrollCalendarRepository, PayrollCalendarRepository>();
        services.AddScoped<IPayrollRunRepository, PayrollRunRepository>();
        services.AddScoped<IPayItemRepository, PayItemRepository>();

        // ---- Payroll: final settlement and leave encashment (db/39-40) ----
        services.AddScoped<IFinalSettlementRepository, FinalSettlementRepository>();

        // ---- Payroll Settings (db/29-30 masters, db/46+) ----
        services.AddScoped<IPayItemTypeRepository, PayItemTypeRepository>();
        services.AddScoped<IStatutoryRepository, StatutoryRepository>();
        services.AddScoped<IBankRepository, BankRepository>();
        services.AddScoped<IPayrollRulesRepository, PayrollRulesRepository>();
        services.AddScoped<IPayrollFinanceRepository, PayrollFinanceRepository>();

        // ---- Payroll: payslips (db/42-43) ----
        services.AddScoped<IPayslipRepository, PayslipRepository>();

        return services;
    }
}
