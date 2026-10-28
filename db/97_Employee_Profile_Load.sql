/* =====================================================================
   97_Employee_Profile_Load.sql  -  HRMS: the employee profile in ONE call
   ---------------------------------------------------------------------
   Run after 96. Safe to re-run.

   Opening an employee's profile used to take ~26 separate calls to the
   database (the employee, Kuwait compliance, 11 dropdown lists, payroll
   calendar(s), date alerts, annual leave, assets, dependents, documents,
   compliance images). Employee.usp_EmployeeProfile_Load returns all of
   them from ONE call: it runs the same procedures the app already uses,
   one after the other, so their rules stay in one place.

   Before each part it returns a one-row marker, SELECT N'<part>' AS
   [__Section], and the part's rows follow. A part that fails is marked
   N'!<part>' and the app reads that part on its own, as before - so a
   database without db/60, 65, 71, 82 or 84 still opens the profile.
   Saving works exactly as before (one call per save).
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeProfile_Load]
    @EmployeeId                 BIGINT,
    @LookupCompanyId            INT     = NULL,     -- a company user's own company (dropdowns)
    @UserCompanyId              INT     = NULL,     -- the user's active company (payroll calendars, assets)
    @UserId                     BIGINT  = NULL,
    @IncludeInactive            BIT     = 1,        -- keep a since-deactivated value in its dropdown
    @WithDateAlerts             BIT     = 0,        -- the parts the user may see
    @WithAssets                 BIT     = 0,
    @WithDependents             BIT     = 0,
    @WithDocuments              BIT     = 0,
    @WithComplianceDocuments    BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        SELECT N'employee' AS [__Section];
        EXEC [Employee].[usp_Employee_Manage] @Action = 'GET', @Id = @EmployeeId;
    END TRY
    BEGIN CATCH
        SELECT N'!employee' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'compliance' AS [__Section];
        EXEC [Kuwait].[usp_EmployeeCompliance_Manage] @Action = 'GET', @EmployeeId = @EmployeeId;
    END TRY
    BEGIN CATCH
        SELECT N'!compliance' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:COMPANY' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'COMPANY', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:COMPANY' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:BRANCH' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'BRANCH', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:BRANCH' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:DEPARTMENT' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'DEPARTMENT', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:DEPARTMENT' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:SECTION' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'SECTION', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:SECTION' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:JOBPOSITION' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'JOBPOSITION', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:JOBPOSITION' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:DESIGNATION' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'DESIGNATION', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:DESIGNATION' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:GRADE' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'GRADE', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:GRADE' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:COSTCENTER' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'COSTCENTER', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:COSTCENTER' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:LOCATION' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'LOCATION', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:LOCATION' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:COUNTRY' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'COUNTRY', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:COUNTRY' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    BEGIN TRY
        SELECT N'lookup:EMPLOYEE' AS [__Section];
        EXEC [Core].[usp_Lookup_Get] @LookupType = 'EMPLOYEE', @CompanyId = @LookupCompanyId, @ParentId = NULL, @IncludeInactive = @IncludeInactive;
    END TRY
    BEGIN CATCH
        SELECT N'!lookup:EMPLOYEE' AS [__Section];   -- the app reads this part on its own
    END CATCH;
    IF OBJECT_ID(N'Employee.usp_EmployeePayrollCalendar_Manage', N'P') IS NOT NULL
    BEGIN
        BEGIN TRY
            SELECT N'payrollCalendar' AS [__Section];
            EXEC [Employee].[usp_EmployeePayrollCalendar_Manage] @Action = 'GET', @Id = @EmployeeId;
        END TRY
        BEGIN CATCH
            SELECT N'!payrollCalendar' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
    IF OBJECT_ID(N'Payroll.usp_PayrollCalendar_Manage', N'P') IS NOT NULL
    BEGIN
        BEGIN TRY
            SELECT N'calendars' AS [__Section];
            EXEC [Payroll].[usp_PayrollCalendar_Manage] @Action = 'LIST', @CompanyId = @UserCompanyId, @PageNumber = 1, @PageSize = 200, @SortColumn = 'CalendarName', @SortDirection = 'ASC';
        END TRY
        BEGIN CATCH
            SELECT N'!calendars' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
    IF OBJECT_ID(N'Employee.usp_DateAlert_Manage', N'P') IS NOT NULL AND @WithDateAlerts = 1
    BEGIN
        BEGIN TRY
            SELECT N'dateAlerts' AS [__Section];
            EXEC [Employee].[usp_DateAlert_Manage] @Action = 'LIST';
        END TRY
        BEGIN CATCH
            SELECT N'!dateAlerts' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
    IF OBJECT_ID(N'Employee.usp_EmployeeLeaveTerms_Manage', N'P') IS NOT NULL
    BEGIN
        BEGIN TRY
            SELECT N'leaveTerms' AS [__Section];
            EXEC [Employee].[usp_EmployeeLeaveTerms_Manage] @Action = 'GET', @Id = @EmployeeId;
        END TRY
        BEGIN CATCH
            SELECT N'!leaveTerms' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
    IF OBJECT_ID(N'Assets.usp_Asset_Manage', N'P') IS NOT NULL AND @WithAssets = 1
    BEGIN
        BEGIN TRY
            SELECT N'assets' AS [__Section];
            EXEC [Assets].[usp_Asset_Manage] @Action = 'EMPLOYEE', @UserCompanyId = @UserCompanyId, @CompanyIds = NULL, @UserId = @UserId, @EmployeeId = @EmployeeId;
        END TRY
        BEGIN CATCH
            SELECT N'!assets' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
    IF @WithDependents = 1
    BEGIN
        BEGIN TRY
            SELECT N'dependents' AS [__Section];
            EXEC [Employee].[usp_EmployeeDependent_Manage] @Action = 'LIST', @EmployeeId = @EmployeeId;
        END TRY
        BEGIN CATCH
            SELECT N'!dependents' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
    IF @WithDocuments = 1
    BEGIN
        BEGIN TRY
            SELECT N'documents' AS [__Section];
            EXEC [Documents].[usp_EmployeeDocument_Manage] @Action = 'LIST', @EmployeeId = @EmployeeId;
        END TRY
        BEGIN CATCH
            SELECT N'!documents' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
    IF OBJECT_ID(N'Kuwait.usp_ComplianceDocument_Manage', N'P') IS NOT NULL AND @WithComplianceDocuments = 1
    BEGIN
        BEGIN TRY
            SELECT N'complianceDocuments' AS [__Section];
            EXEC [Kuwait].[usp_ComplianceDocument_Manage] @Action = 'LIST', @EmployeeId = @EmployeeId;
        END TRY
        BEGIN CATCH
            SELECT N'!complianceDocuments' AS [__Section];   -- the app reads this part on its own
        END CATCH;
    END;
END;
GO

PRINT N'Employee.usp_EmployeeProfile_Load created.';
GO
