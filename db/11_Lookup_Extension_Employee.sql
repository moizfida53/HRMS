/* ================================================================
   HRMS Kuwait - extends Core.usp_Lookup_Get with one more lookup type
   ----------------------------------------------------------------
   Adds EMPLOYEE, needed for the "Reporting Manager" dropdown on the
   Employee Profile screen. CREATE OR ALTER replaces the whole
   procedure body, so this file carries the complete text of the
   version in db/04_Shared_StoredProcedures.sql plus the one new
   branch - every existing branch (COMPANY, BRANCH, DEPARTMENT,
   SECTION, DESIGNATION, JOBPOSITION, LOCATION, COSTCENTER, GRADE,
   COUNTRY, CURRENCY, GOVERNORATE) is reproduced unchanged so no
   existing dropdown in the application regresses.

   Run AFTER 04 (and after 08, since EMPLOYEE needs Employee.Employees'
   new EmployeeCode column).
================================================================ */
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
        WHERE   (@IncludeInactive = 1 OR c.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR b.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR d.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR s.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR dg.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR jp.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR l.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR cc.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR g.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR co.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR cu.IsActive = 1)
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
        WHERE   (@IncludeInactive = 1 OR gv.IsActive = 1)
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
            AND (@IncludeInactive = 1 OR e.EmploymentStatus NOT IN ('Terminated', 'Resigned'))
            AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
        ORDER BY e.FirstName, e.LastName;
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

PRINT 'Core.usp_Lookup_Get extended with EMPLOYEE lookup type.';
GO
