/* ================================================================
   HRMS Kuwait - shared stored procedures
   ----------------------------------------------------------------
   These two procedures are deliberately application-wide. Every
   dropdown in the entire system is served by usp_Lookup_Get, and
   every master form's uniqueness check goes through
   usp_Master_CheckDuplicate. Adding a new dropdown or a new master
   means adding a branch here - not a new procedure.

   Both are static SQL with a validated @LookupType / @EntityName.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   [Core].[usp_Lookup_Get]
   ----------------------------------------------------------------
   Returns a uniform shape for every dropdown in the application:
       Id INT, Code NVARCHAR, Text NVARCHAR, ParentId INT NULL

   @CompanyId scopes company-owned lists.
   @ParentId  drives cascading lists (Sections by Department,
              Locations by Branch, and so on).
   @IncludeInactive returns deactivated rows as well - used when
              editing a record that already points at an inactive row,
              so the current value does not vanish from the dropdown.
================================================================ */
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

    /* Unknown type: return an empty result set of the expected shape
       rather than raising, so a mis-wired dropdown degrades to empty. */
    SELECT CAST(NULL AS INT)           AS Id,
           CAST(NULL AS NVARCHAR(50))  AS Code,
           CAST(NULL AS NVARCHAR(200)) AS [Text],
           CAST(NULL AS INT)           AS ParentId
    WHERE  1 = 0;
END;
GO

/* ================================================================
   [Core].[usp_Master_CheckDuplicate]
   ----------------------------------------------------------------
   Single uniqueness check shared by all eight master forms. Called
   from the browser as the user leaves the Code field, so the clash is
   shown inline instead of after a failed save.

   @ScopeId is the owning key for scoped codes: CompanyId for most
   masters, DepartmentId for Sections. Ignored for Companies, whose
   code is globally unique.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_Master_CheckDuplicate]
    @EntityName  VARCHAR(30),
    @Code        NVARCHAR(50),
    @ExcludeId   BIGINT = NULL,
    @ScopeId     INT    = NULL,
    @IsDuplicate BIT    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @IsDuplicate = 0;
    SET @EntityName  = UPPER(LTRIM(RTRIM(ISNULL(@EntityName, ''))));
    SET @Code        = LTRIM(RTRIM(ISNULL(@Code, N'')));
    SET @ExcludeId   = ISNULL(@ExcludeId, 0);

    IF @Code = N''
        RETURN;

    IF @EntityName = 'COMPANY'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[Companies]
            WHERE CompanyCode = @Code AND CompanyId <> @ExcludeId) THEN 1 ELSE 0 END;

    ELSE IF @EntityName = 'BRANCH'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[Branches]
            WHERE BranchCode = @Code AND CompanyId = @ScopeId AND BranchId <> @ExcludeId) THEN 1 ELSE 0 END;

    ELSE IF @EntityName = 'DEPARTMENT'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[Departments]
            WHERE DepartmentCode = @Code AND CompanyId = @ScopeId AND DepartmentId <> @ExcludeId) THEN 1 ELSE 0 END;

    ELSE IF @EntityName = 'SECTION'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[Sections]
            WHERE SectionCode = @Code AND DepartmentId = @ScopeId AND SectionId <> @ExcludeId) THEN 1 ELSE 0 END;

    ELSE IF @EntityName = 'DESIGNATION'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[Designations]
            WHERE DesignationCode = @Code AND CompanyId = @ScopeId AND DesignationId <> @ExcludeId) THEN 1 ELSE 0 END;

    ELSE IF @EntityName = 'JOBPOSITION'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[Positions]
            WHERE PositionCode = @Code AND CompanyId = @ScopeId AND PositionId <> @ExcludeId) THEN 1 ELSE 0 END;

    ELSE IF @EntityName = 'LOCATION'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[Locations]
            WHERE LocationCode = @Code AND CompanyId = @ScopeId AND LocationId <> @ExcludeId) THEN 1 ELSE 0 END;

    ELSE IF @EntityName = 'COSTCENTER'
        SELECT @IsDuplicate = CASE WHEN EXISTS (
            SELECT 1 FROM [Core].[CostCenters]
            WHERE CostCenterCode = @Code AND CompanyId = @ScopeId AND CostCenterId <> @ExcludeId) THEN 1 ELSE 0 END;
END;
GO

PRINT 'Shared stored procedures created: Core.usp_Lookup_Get, Core.usp_Master_CheckDuplicate.';
GO
