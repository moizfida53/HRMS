/* =====================================================================
   31_Lookup_Payroll.sql  -  HRMS Kuwait: Payroll Phase 1 dropdowns
   ---------------------------------------------------------------------
   Run AFTER 30_Payroll_Master_StoredProcedures.sql.

   Reissues Core.usp_Lookup_Get. The body is the CURRENT version from
   28_Soft_Delete.sql, copied verbatim, with payroll branches added just
   before the "unknown type" fallback - no existing branch is changed.

   New @LookupType values
     PAYCOMPONENT, PAYCOMPONENT_EARNING, PAYCOMPONENT_DEDUCTION  (@CompanyId)
     PAYCALENDAR, SALARYSTRUCTURE, COMPANYBANKACCOUNT            (@CompanyId)
     PAYROLLPERIOD                                 (@ParentId = calendar)
     BANK
     Fixed option lists (bind the VALUE to Code):
       PAYFREQUENCY, PERIODSTATUS, COMPONENTTYPE, VALUETYPE, CALCMETHOD,
       CALCBASE, WORKINGDAYSBASIS, PIFSSAPPLICABLETO, PIFSSBASIS,
       OVERTIMETYPE, SEPARATIONTYPE, ENTITLEMENTUNIT

   NOTE for the future: any later script that reissues usp_Lookup_Get
   must start from THIS file's body, not from 28's.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE [Core].[usp_Lookup_Get]
    @LookupType      VARCHAR(30),
    @CompanyId       INT  = NULL,
    @ParentId        INT  = NULL,
    @IncludeInactive BIT  = 0
AS
BEGIN
    SET NOCOUNT ON;

    SET @LookupType = UPPER(LTRIM(RTRIM(ISNULL(@LookupType, ''))));
    SET @IncludeInactive = ISNULL(@IncludeInactive, 0);

    IF @LookupType = 'COMPANY'
    BEGIN
        SELECT  c.CompanyId   AS Id,
                c.CompanyCode AS Code,
                c.CompanyName AS [Text],
                NULL          AS ParentId
        FROM    [Core].[Companies] AS c
        WHERE   c.Deleted = 0
            AND (@IncludeInactive = 1 OR c.IsActive = 1)
        ORDER BY c.CompanyName;
        RETURN;
    END;

    IF @LookupType = 'BRANCH'
    BEGIN
        SELECT  b.BranchId   AS Id,
                b.BranchCode AS Code,
                b.BranchName AS [Text],
                b.CompanyId  AS ParentId
        FROM    [Core].[Branches] AS b
        WHERE   b.Deleted = 0
            AND (@IncludeInactive = 1 OR b.IsActive = 1)
            AND (@CompanyId IS NULL OR b.CompanyId = @CompanyId)
        ORDER BY b.BranchName;
        RETURN;
    END;

    IF @LookupType = 'DEPARTMENT'
    BEGIN
        SELECT  d.DepartmentId   AS Id,
                d.DepartmentCode AS Code,
                d.DepartmentName AS [Text],
                d.CompanyId      AS ParentId
        FROM    [Core].[Departments] AS d
        WHERE   d.Deleted = 0
            AND (@IncludeInactive = 1 OR d.IsActive = 1)
            AND (@CompanyId IS NULL OR d.CompanyId = @CompanyId)
        ORDER BY d.DepartmentName;
        RETURN;
    END;

    IF @LookupType = 'SECTION'
    BEGIN
        SELECT  s.SectionId    AS Id,
                s.SectionCode  AS Code,
                s.SectionName  AS [Text],
                s.DepartmentId AS ParentId
        FROM    [Core].[Sections]    AS s
        INNER JOIN [Core].[Departments] AS d ON d.DepartmentId = s.DepartmentId
        WHERE   s.Deleted = 0
            AND (@IncludeInactive = 1 OR s.IsActive = 1)
            AND (@CompanyId IS NULL OR d.CompanyId    = @CompanyId)
            AND (@ParentId  IS NULL OR s.DepartmentId = @ParentId)
        ORDER BY s.SectionName;
        RETURN;
    END;

    IF @LookupType = 'DESIGNATION'
    BEGIN
        SELECT  dg.DesignationId   AS Id,
                dg.DesignationCode AS Code,
                dg.DesignationName AS [Text],
                dg.CompanyId       AS ParentId
        FROM    [Core].[Designations] AS dg
        WHERE   dg.Deleted = 0
            AND (@IncludeInactive = 1 OR dg.IsActive = 1)
            AND (@CompanyId IS NULL OR dg.CompanyId = @CompanyId)
        ORDER BY dg.DesignationName;
        RETURN;
    END;

    IF @LookupType = 'JOBPOSITION'
    BEGIN
        SELECT  jp.PositionId   AS Id,
                jp.PositionCode AS Code,
                jp.PositionName AS [Text],
                jp.CompanyId    AS ParentId
        FROM    [Core].[Positions] AS jp
        WHERE   jp.Deleted = 0
            AND (@IncludeInactive = 1 OR jp.IsActive = 1)
            AND (@CompanyId IS NULL OR jp.CompanyId = @CompanyId)
        ORDER BY jp.PositionName;
        RETURN;
    END;

    IF @LookupType = 'LOCATION'
    BEGIN
        SELECT  l.LocationId   AS Id,
                l.LocationCode AS Code,
                l.LocationName AS [Text],
                l.BranchId     AS ParentId
        FROM    [Core].[Locations] AS l
        WHERE   l.Deleted = 0
            AND (@IncludeInactive = 1 OR l.IsActive = 1)
            AND (@CompanyId IS NULL OR l.CompanyId = @CompanyId)
            AND (@ParentId  IS NULL OR l.BranchId  = @ParentId)
        ORDER BY l.LocationName;
        RETURN;
    END;

    IF @LookupType = 'COSTCENTER'
    BEGIN
        SELECT  cc.CostCenterId   AS Id,
                cc.CostCenterCode AS Code,
                cc.CostCenterName AS [Text],
                cc.CompanyId      AS ParentId
        FROM    [Core].[CostCenters] AS cc
        WHERE   cc.Deleted = 0
            AND (@IncludeInactive = 1 OR cc.IsActive = 1)
            AND (@CompanyId IS NULL OR cc.CompanyId = @CompanyId)
        ORDER BY cc.CostCenterName;
        RETURN;
    END;

    IF @LookupType = 'GRADE'
    BEGIN
        SELECT  g.GradeId   AS Id,
                g.GradeCode AS Code,
                g.GradeName AS [Text],
                g.CompanyId AS ParentId
        FROM    [Core].[Grades] AS g
        WHERE   g.Deleted = 0
            AND (@IncludeInactive = 1 OR g.IsActive = 1)
            AND (@CompanyId IS NULL OR g.CompanyId = @CompanyId)
        ORDER BY g.GradeName;
        RETURN;
    END;

    IF @LookupType = 'COUNTRY'
    BEGIN
        SELECT  co.CountryId   AS Id,
                co.CountryCode AS Code,
                co.CountryName AS [Text],
                NULL           AS ParentId
        FROM    [Core].[Countries] AS co
        WHERE   co.Deleted = 0
            AND (@IncludeInactive = 1 OR co.IsActive = 1)
        ORDER BY CASE WHEN co.CountryCode = 'KW' THEN 0 ELSE 1 END, co.CountryName;
        RETURN;
    END;

    IF @LookupType = 'CURRENCY'
    BEGIN
        SELECT  cu.CurrencyId   AS Id,
                cu.CurrencyCode AS Code,
                cu.CurrencyName AS [Text],
                NULL            AS ParentId
        FROM    [Core].[Currencies] AS cu
        WHERE   cu.Deleted = 0
            AND (@IncludeInactive = 1 OR cu.IsActive = 1)
        ORDER BY CASE WHEN cu.CurrencyCode = 'KWD' THEN 0 ELSE 1 END, cu.CurrencyName;
        RETURN;
    END;

    IF @LookupType = 'GOVERNORATE'
    BEGIN
        SELECT  gv.GovernorateId AS Id,
                gv.Code          AS Code,
                gv.Name          AS [Text],
                gv.CountryId     AS ParentId
        FROM    [Core].[Governorates] AS gv
        WHERE   gv.Deleted = 0
            AND (@IncludeInactive = 1 OR gv.IsActive = 1)
        ORDER BY gv.Name;
        RETURN;
    END;

    /* Reporting-manager dropdown on the Employee Profile screen.
       Excludes deleted rows outright regardless of @IncludeInactive -
       you should never be able to pick a deleted employee as someone's
       manager, even when editing a record that already points at one. */
    IF @LookupType = 'EMPLOYEE'
    BEGIN
        -- LookupItem.Id is a shared int contract used by every dropdown in the
        -- app (every other lookup's key is an INT master PK). EmployeeId is
        -- BIGINT, so it is narrowed here for that one shared contract; the
        -- actual save path (Employee.usp_Employee_Manage) still binds
        -- @ReportingManagerId as a full BIGINT, so this cast only affects the
        -- display list, and only matters once a company passes ~2 billion
        -- employee rows on an IDENTITY column starting at 1.
        SELECT  CAST(e.EmployeeId AS INT)                                 AS Id,
                ISNULL(e.EmployeeCode, N'')                               AS Code,
                CONCAT(e.FirstName, N' ', ISNULL(e.LastName, N''))        AS [Text],
                e.CompanyId                                               AS ParentId
        FROM    [Employee].[Employees] AS e
        WHERE   e.IsDeleted = 0
            AND e.Deleted = 0
            AND (@IncludeInactive = 1 OR e.EmploymentStatus NOT IN ('Terminated', 'Resigned'))
            AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
        ORDER BY e.FirstName, e.LastName;
        RETURN;
    END;

    /* =============== db/31: Payroll dropdowns =============== */

    /* Earnings + deductions. Code = ComponentCode, ParentId = CompanyId.
       Use PAYCOMPONENT_EARNING / PAYCOMPONENT_DEDUCTION for one type only. */
    IF @LookupType IN ('PAYCOMPONENT', 'PAYCOMPONENT_EARNING', 'PAYCOMPONENT_DEDUCTION')
    BEGIN
        SELECT  pc.PayComponentId AS Id,
                pc.ComponentCode  AS Code,
                pc.ComponentName  AS [Text],
                pc.CompanyId      AS ParentId
        FROM    [Payroll].[PayComponents] AS pc
        WHERE   pc.Deleted = 0
            AND (@IncludeInactive = 1 OR pc.IsActive = 1)
            AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
            AND (   @LookupType = 'PAYCOMPONENT'
                 OR (@LookupType = 'PAYCOMPONENT_EARNING'   AND pc.ComponentType = 'EARNING')
                 OR (@LookupType = 'PAYCOMPONENT_DEDUCTION' AND pc.ComponentType = 'DEDUCTION'))
        ORDER BY CASE pc.ComponentType WHEN 'EARNING' THEN 0 ELSE 1 END, pc.DisplayOrder, pc.ComponentName;
        RETURN;
    END;

    IF @LookupType = 'PAYCALENDAR'
    BEGIN
        SELECT  pc.PayrollCalendarId AS Id,
                pc.CalendarCode      AS Code,
                pc.CalendarName      AS [Text],
                pc.CompanyId         AS ParentId
        FROM    [Payroll].[PayrollCalendars] AS pc
        WHERE   pc.Deleted = 0
            AND (@IncludeInactive = 1 OR pc.IsActive = 1)
            AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
        ORDER BY pc.IsDefault DESC, pc.CalendarName;
        RETURN;
    END;

    /* Periods of one calendar (@ParentId). @IncludeInactive = 0 hides CLOSED periods. */
    IF @LookupType = 'PAYROLLPERIOD'
    BEGIN
        SELECT  p.PayrollPeriodId   AS Id,
                p.PeriodCode        AS Code,
                p.PeriodName        AS [Text],
                p.PayrollCalendarId AS ParentId
        FROM    [Payroll].[PayrollPeriods]   AS p
        INNER JOIN [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = p.PayrollCalendarId
        WHERE   p.Deleted = 0
            AND (@IncludeInactive = 1 OR p.Status <> 'CLOSED')
            AND (@ParentId  IS NULL OR p.PayrollCalendarId = @ParentId)
            AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
        ORDER BY p.StartDate;
        RETURN;
    END;

    IF @LookupType = 'SALARYSTRUCTURE'
    BEGIN
        SELECT  s.SalaryStructureId AS Id,
                s.StructureCode     AS Code,
                s.StructureName     AS [Text],
                s.CompanyId         AS ParentId
        FROM    [Payroll].[SalaryStructures] AS s
        WHERE   s.Deleted = 0
            AND (@IncludeInactive = 1 OR s.IsActive = 1)
            AND (@CompanyId IS NULL OR s.CompanyId = @CompanyId)
        ORDER BY s.StructureName;
        RETURN;
    END;

    IF @LookupType = 'BANK'
    BEGIN
        SELECT  b.BankId    AS Id,
                b.BankCode  AS Code,
                b.BankName  AS [Text],
                b.CountryId AS ParentId
        FROM    [Payroll].[Banks] AS b
        WHERE   b.Deleted = 0
            AND (@IncludeInactive = 1 OR b.IsActive = 1)
        ORDER BY b.BankName;
        RETURN;
    END;

    IF @LookupType = 'COMPANYBANKACCOUNT'
    BEGIN
        SELECT  a.CompanyBankAccountId AS Id,
                a.AccountCode          AS Code,
                CONCAT(a.AccountTitle, N' - ', b.BankName) AS [Text],
                a.CompanyId            AS ParentId
        FROM    [Payroll].[CompanyBankAccounts] AS a
        INNER JOIN [Payroll].[Banks]            AS b ON b.BankId = a.BankId
        WHERE   a.Deleted = 0
            AND (@IncludeInactive = 1 OR a.IsActive = 1)
            AND (@CompanyId IS NULL OR a.CompanyId = @CompanyId)
        ORDER BY a.IsDefault DESC, a.AccountTitle;
        RETURN;
    END;

    /* Fixed option lists used by the payroll forms. Bind the dropdown
       VALUE to Code (the column stores the code); Id is only a row number. */
    IF @LookupType IN ('PAYFREQUENCY', 'PERIODSTATUS', 'COMPONENTTYPE', 'VALUETYPE', 'CALCMETHOD', 'CALCBASE',
                       'WORKINGDAYSBASIS', 'PIFSSAPPLICABLETO', 'PIFSSBASIS', 'OVERTIMETYPE', 'SEPARATIONTYPE', 'ENTITLEMENTUNIT')
    BEGIN
        SELECT  CAST(ROW_NUMBER() OVER (ORDER BY v.SortOrder) AS INT) AS Id,
                CAST(v.Code AS NVARCHAR(50))  AS Code,
                CAST(v.Txt  AS NVARCHAR(200)) AS [Text],
                CAST(NULL AS INT)             AS ParentId
        FROM (VALUES
            ('PAYFREQUENCY',      1, 'MONTHLY',        N'Monthly'),
            ('PAYFREQUENCY',      2, 'BIWEEKLY',       N'Bi-weekly'),
            ('PAYFREQUENCY',      3, 'WEEKLY',         N'Weekly'),
            ('PERIODSTATUS',      1, 'OPEN',           N'Open'),
            ('PERIODSTATUS',      2, 'PROCESSING',     N'Processing'),
            ('PERIODSTATUS',      3, 'APPROVED',       N'Approved'),
            ('PERIODSTATUS',      4, 'POSTED',         N'Posted'),
            ('PERIODSTATUS',      5, 'CLOSED',         N'Closed'),
            ('COMPONENTTYPE',     1, 'EARNING',        N'Earning'),
            ('COMPONENTTYPE',     2, 'DEDUCTION',      N'Deduction'),
            ('VALUETYPE',         1, 'FIXED',          N'Fixed'),
            ('VALUETYPE',         2, 'VARIABLE',       N'Variable'),
            ('CALCMETHOD',        1, 'AMOUNT',         N'Fixed amount'),
            ('CALCMETHOD',        2, 'PERCENTAGE',     N'Percentage of base'),
            ('CALCMETHOD',        3, 'DAYS',           N'Days x daily rate'),
            ('CALCMETHOD',        4, 'HOURS',          N'Hours x hourly rate'),
            ('CALCMETHOD',        5, 'FORMULA',        N'Formula'),
            ('CALCBASE',          1, 'BASIC',          N'Basic salary'),
            ('CALCBASE',          2, 'FIXED_GROSS',    N'Fixed gross (all fixed earnings)'),
            ('CALCBASE',          3, 'OVERTIME_BASE',  N'Overtime base (components marked for overtime)'),
            ('CALCBASE',          4, 'INDEMNITY_BASE', N'Indemnity base (components marked for end-of-service)'),
            ('WORKINGDAYSBASIS',  1, 'FIXED',          N'Fixed days per month (26 / 30)'),
            ('WORKINGDAYSBASIS',  2, 'CALENDAR',       N'Calendar days in the period'),
            ('WORKINGDAYSBASIS',  3, 'WORKING',        N'Working days in the period'),
            ('PIFSSAPPLICABLETO', 1, 'KUWAITI',        N'Kuwaiti nationals'),
            ('PIFSSAPPLICABLETO', 2, 'GCC',            N'GCC nationals'),
            ('PIFSSAPPLICABLETO', 3, 'EXPAT',          N'Expatriates'),
            ('PIFSSAPPLICABLETO', 4, 'ALL',            N'All employees'),
            ('PIFSSBASIS',        1, 'CAPPED',         N'Salary up to the ceiling'),
            ('PIFSSBASIS',        2, 'BAND',           N'Salary between floor and ceiling'),
            ('OVERTIMETYPE',      1, 'NORMAL_DAY',     N'Normal working day'),
            ('OVERTIMETYPE',      2, 'REST_DAY',       N'Weekly rest day'),
            ('OVERTIMETYPE',      3, 'PUBLIC_HOLIDAY', N'Public holiday'),
            ('OVERTIMETYPE',      4, 'NIGHT',          N'Night shift'),
            ('OVERTIMETYPE',      5, 'OTHER',          N'Other'),
            ('SEPARATIONTYPE',    1, 'RESIGNATION',    N'Resignation'),
            ('SEPARATIONTYPE',    2, 'TERMINATION',    N'Termination by employer'),
            ('SEPARATIONTYPE',    3, 'CONTRACT_END',   N'End of contract'),
            ('SEPARATIONTYPE',    4, 'RETIREMENT',     N'Retirement'),
            ('SEPARATIONTYPE',    5, 'DEATH',          N'Death'),
            ('SEPARATIONTYPE',    6, 'DISABILITY',     N'Disability'),
            ('SEPARATIONTYPE',    7, 'OTHER',          N'Other'),
            ('ENTITLEMENTUNIT',   1, 'DAYS',           N'Days'' wage per year'),
            ('ENTITLEMENTUNIT',   2, 'MONTHS',         N'Months'' wage per year')
        ) v(LookupType, SortOrder, Code, Txt)
        WHERE v.LookupType = @LookupType
        ORDER BY v.SortOrder;
        RETURN;
    END;

    /* Unknown type: return an empty result set of the expected shape
       rather than raising, so a mis-wired dropdown degrades to empty. */
    SELECT CAST(NULL AS INT)           AS Id,
           CAST(NULL AS NVARCHAR(50))  AS Code,
           CAST(NULL AS NVARCHAR(200)) AS [Text],
           CAST(NULL AS INT)           AS ParentId
    WHERE  1 = 0;
END;
GO

PRINT N'31_Lookup_Payroll.sql applied.';
GO
