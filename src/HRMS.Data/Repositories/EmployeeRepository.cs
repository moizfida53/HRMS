using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Workforce;

namespace HRMS.Data.Repositories;

public interface IEmployeeRepository : IMasterRepository<Employee>
{
}

/// <summary>
/// LIST / GET / DELETE / TOGGLE come free from <see cref="MasterRepositoryBase{T}"/> -
/// Employee.usp_Employee_Manage shares the identical envelope every other master
/// procedure uses. Only the entity's own editable columns need binding here.
/// </summary>
public sealed class EmployeeRepository : MasterRepositoryBase<Employee>, IEmployeeRepository
{
    public EmployeeRepository(ISqlExecutor sql) : base(sql)
    {
    }

    protected override string ProcedureName => StoredProcedure.EmployeeManage;

    protected override IReadOnlySet<string> SortableColumns { get; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "EmployeeCode", "FullName", "DepartmentName", "HireDate", "EmploymentStatus"
        };

    protected override string DefaultSortColumn => "FullName";

    protected override long GetKey(Employee entity) => entity.EmployeeId;

    protected override void AddEntityParameters(DynamicParameters parameters, Employee entity)
    {
        // ---- personal info ----
        // EmployeeCode / FirstName intentionally NOT run through NullIfEmpty:
        // FirstName is [Required] and already ModelState-validated non-empty
        // by the time this runs, and EmployeeCode's own blank-vs-null distinction
        // is handled below (it still goes through NullIfEmpty like everything
        // else - the note is just that skipping it here would be the actual bug).
        parameters.Add("@EmployeeCode", NullIfEmpty(entity.EmployeeCode), DbType.String, size: 20);
        // EmployeeNo is [Required] (a pre-existing NOT NULL base-schema column -
        // see the Employee.EmployeeNo doc comment and db/16), so like FirstName
        // it is bound directly rather than through NullIfEmpty: ModelState
        // validation has already rejected a blank submission by the time this runs.
        parameters.Add("@EmployeeNo", entity.EmployeeNo, DbType.String, size: 20);
        parameters.Add("@FirstName", entity.FirstName, DbType.String, size: 100);
        parameters.Add("@MiddleName", NullIfEmpty(entity.MiddleName), DbType.String, size: 100);
        parameters.Add("@LastName", NullIfEmpty(entity.LastName), DbType.String, size: 100);
        parameters.Add("@ArabicName", NullIfEmpty(entity.ArabicName), DbType.String, size: 300);
        parameters.Add("@Gender", NullIfEmpty(entity.Gender), DbType.AnsiString, size: 1);
        parameters.Add("@DateOfBirth", entity.DateOfBirth, DbType.Date);
        parameters.Add("@MaritalStatus", NullIfEmpty(entity.MaritalStatus), DbType.String, size: 20);
        parameters.Add("@NationalityCountryId", entity.NationalityCountryId, DbType.Int32);
        parameters.Add("@Religion", NullIfEmpty(entity.Religion), DbType.String, size: 50);
        // BloodGroup has the same CHECK (NULL or one of 8 fixed values) shape
        // as Gender/MaritalStatus/EmploymentType below - NullIfEmpty is not
        // optional here, it is exactly the bug class fixed 2026-08-31.
        parameters.Add("@BloodGroup", NullIfEmpty(entity.BloodGroup), DbType.AnsiString, size: 5);
        parameters.Add("@MobileNumber", NullIfEmpty(entity.MobileNumber), DbType.String, size: 20);
        parameters.Add("@Extension", NullIfEmpty(entity.Extension), DbType.String, size: 10);
        parameters.Add("@PersonalEmail", NullIfEmpty(entity.PersonalEmail), DbType.String, size: 150);
        parameters.Add("@WorkEmail", NullIfEmpty(entity.WorkEmail), DbType.String, size: 150);
        // Address itself is no longer bound from the form (replaced by the
        // structured fields below) but is still sent through - see the
        // Employee.Address property doc comment. Sending null here simply
        // leaves the column as it was the last time this employee had a
        // free-text address saved; it is never overwritten with "".
        parameters.Add("@Address", NullIfEmpty(entity.Address), DbType.String, size: 500);
        parameters.Add("@Neighborhood", NullIfEmpty(entity.Neighborhood), DbType.String, size: 100);
        parameters.Add("@Block", NullIfEmpty(entity.Block), DbType.String, size: 20);
        parameters.Add("@StreetName", NullIfEmpty(entity.StreetName), DbType.String, size: 150);
        parameters.Add("@BuildingNumber", NullIfEmpty(entity.BuildingNumber), DbType.String, size: 30);
        parameters.Add("@FloorNumber", NullIfEmpty(entity.FloorNumber), DbType.String, size: 20);
        parameters.Add("@FlatNumber", NullIfEmpty(entity.FlatNumber), DbType.String, size: 20);
        parameters.Add("@PaciNumber", NullIfEmpty(entity.PaciNumber), DbType.String, size: 20);
        parameters.Add("@Landmark", NullIfEmpty(entity.Landmark), DbType.String, size: 200);
        parameters.Add("@PhotoPath", NullIfEmpty(entity.PhotoPath), DbType.String, size: 300);
        parameters.Add("@EmergencyContactName", NullIfEmpty(entity.EmergencyContactName), DbType.String, size: 150);
        parameters.Add("@EmergencyContactPhone", NullIfEmpty(entity.EmergencyContactPhone), DbType.String, size: 20);
        parameters.Add("@EmergencyContactRelation", NullIfEmpty(entity.EmergencyContactRelation), DbType.String, size: 50);

        // ---- father's details ----
        parameters.Add("@FatherName", NullIfEmpty(entity.FatherName), DbType.String, size: 150);
        parameters.Add("@FatherOccupation", NullIfEmpty(entity.FatherOccupation), DbType.String, size: 100);
        parameters.Add("@FatherMobileNumber", NullIfEmpty(entity.FatherMobileNumber), DbType.String, size: 20);
        parameters.Add("@FatherIsDeceased", entity.FatherIsDeceased, DbType.Boolean);
        parameters.Add("@CurrentResidenceCountryId", entity.CurrentResidenceCountryId, DbType.Int32);

        // Passport and Civil ID are deliberately NOT bound here - Personal
        // Info no longer edits them (removed as redundant with the Kuwait
        // Compliance tab, which already owns these fields - see Employee.cs's
        // doc comment for the full history). @PassportNumber, @CivilIdNumber
        // etc. are still declared (with `= NULL` defaults) on
        // usp_Employee_Manage from db/18, and its UPDATE still unconditionally
        // sets each column from its parameter (same shape as the pre-existing
        // Address column above) - so not supplying them here means SQL Server
        // uses the NULL default, and any future save through this procedure
        // leaves those columns NULL. That's fine: nothing writes real data to
        // them any more from anywhere in the app (Personal Info never did in
        // practice - this was reverted before shipping - and Kuwait
        // Compliance uses its own separate columns/table entirely).

        // ---- employment ----
        parameters.Add("@CompanyId", entity.CompanyId, DbType.Int32);
        parameters.Add("@BranchId", entity.BranchId, DbType.Int32);
        parameters.Add("@DepartmentId", entity.DepartmentId, DbType.Int32);
        parameters.Add("@SectionId", entity.SectionId, DbType.Int32);
        parameters.Add("@PositionId", entity.PositionId, DbType.Int32);
        parameters.Add("@DesignationId", entity.DesignationId, DbType.Int32);
        parameters.Add("@GradeId", entity.GradeId, DbType.Int32);
        parameters.Add("@CostCenterId", entity.CostCenterId, DbType.Int32);
        parameters.Add("@WorkLocationId", entity.WorkLocationId, DbType.Int32);
        parameters.Add("@ReportingManagerId", entity.ReportingManagerId, DbType.Int64);
        parameters.Add("@HireDate", entity.HireDate, DbType.Date);
        parameters.Add("@ProbationEndDate", entity.ProbationEndDate, DbType.Date);
        parameters.Add("@TerminationDate", entity.TerminationDate, DbType.Date);
        parameters.Add("@EmploymentType", NullIfEmpty(entity.EmploymentType), DbType.String, size: 20);
        parameters.Add("@EmploymentStatus", entity.EmploymentStatus, DbType.String, size: 20);
        parameters.Add("@NoticePeriodDays", entity.NoticePeriodDays, DbType.Int32);

        // ---- company contact & assets, payroll & bank (db/20) ----
        parameters.Add("@CompanyPhone", NullIfEmpty(entity.CompanyPhone), DbType.String, size: 20);
        parameters.Add("@CompanyAssets", NullIfEmpty(entity.CompanyAssets), DbType.String, size: 300);
        parameters.Add("@BasicSalary", entity.BasicSalary, DbType.Decimal, precision: 12, scale: 3);
        parameters.Add("@Allowances", entity.Allowances, DbType.Decimal, precision: 12, scale: 3);
        parameters.Add("@BankName", NullIfEmpty(entity.BankName), DbType.String, size: 100);
        parameters.Add("@Iban", NullIfEmpty(entity.Iban)?.Replace(" ", string.Empty).ToUpperInvariant(), DbType.String, size: 34);
    }

    /// <summary>
    /// ASP.NET Core's default model binder leaves an unselected/blank
    /// &lt;select&gt; or empty text input as <c>""</c> on a <c>string?</c>
    /// property - it does NOT convert it to <c>null</c> the way it does for
    /// nullable numeric/date properties. That "" then reaches the database
    /// as a real value rather than NULL, which breaks two things on this
    /// entity specifically: the CHECK constraints on Gender, MaritalStatus
    /// and EmploymentType only allow NULL or one of their fixed values (not
    /// ""), and the filtered unique index on EmployeeCode
    /// (WHERE EmployeeCode IS NOT NULL) would treat every blank-code
    /// employee in the same company as a duplicate of every other one,
    /// since "" IS NOT NULL. Root cause of the "Employee.usp_Employee_Manage
    /// / DataAccessException" error reported 2026-08-31 when creating a new
    /// employee without picking Gender/Marital Status/Employment Type.
    /// Applied to every nullable string column for consistency, not just
    /// the three that currently have a CHECK constraint - a blank text
    /// field should mean NULL in the database, never "".
    /// </summary>
    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
