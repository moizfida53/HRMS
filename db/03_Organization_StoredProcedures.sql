/* ================================================================
   HRMS Kuwait - Organization Setup stored procedures
   ----------------------------------------------------------------
   Eight procedures cover all eight masters. Each one handles six
   actions through a single @Action parameter, so the module needs
   8 procedures instead of the ~40 a one-procedure-per-operation
   design would require.

   Security notes for review:
     * Every statement is static SQL. There is no EXEC, no
       sp_executesql, and no string concatenation anywhere.
     * Sorting is applied by CASE expressions over a fixed list of
       logical column names. An unrecognised @SortColumn simply
       falls through to the default order.
     * @Search has its LIKE metacharacters escaped before use.
     * Failure messages returned to the caller are fixed strings and
       never echo user input back to the UI.
     * Business failures (duplicate code, row in use) are reported in
       @ResultCode / @ResultMessage rather than raised as errors.

   Run order: 01 base schema -> 02 additions -> 03 (this file)
              -> 04 shared procedures -> 05 security.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   [Core].[usp_Company_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_Company_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @CompanyCode               NVARCHAR(30)    = NULL,
    @CompanyName               NVARCHAR(200)   = NULL,
    @LegalName                 NVARCHAR(250)   = NULL,
    @CommercialRegistrationNo  NVARCHAR(100)   = NULL,
    @TaxNo                     NVARCHAR(100)   = NULL,
    @CountryId                 INT             = NULL,
    @DefaultCurrencyId         INT             = NULL,
    @Address                   NVARCHAR(500)   = NULL,
    @Telephone                 NVARCHAR(50)    = NULL,
    @Email                     NVARCHAR(150)   = NULL,
    @Website                   NVARCHAR(200)   = NULL,
    @LogoPath                  NVARCHAR(500)   = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[Companies]  AS c
        LEFT JOIN   [Core].[Countries]  AS co ON co.CountryId  = c.CountryId
        LEFT JOIN   [Core].[Currencies] AS cu ON cu.CurrencyId = c.DefaultCurrencyId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR c.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR c.CompanyId = @CompanyId)
              AND (@Pattern IS NULL OR (c.CompanyCode LIKE @Pattern ESCAPE '\'
                   OR c.CompanyName LIKE @Pattern ESCAPE '\'
                   OR c.LegalName LIKE @Pattern ESCAPE '\'
                   OR c.CommercialRegistrationNo LIKE @Pattern ESCAPE '\'));

        SELECT  c.CompanyId,
                c.CompanyCode,
                c.CompanyName,
                c.LegalName,
                c.CommercialRegistrationNo,
                c.TaxNo,
                c.CountryId,
                c.DefaultCurrencyId,
                c.Address,
                c.Telephone,
                c.Email,
                c.Website,
                c.LogoPath,
                c.IsActive,
                co.CountryName,
                cu.CurrencyCode,
                (SELECT COUNT(1) FROM [Core].[Branches]      b WHERE b.CompanyId = c.CompanyId)                        AS BranchCount,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.CompanyId = c.CompanyId AND e.IsDeleted = 0)    AS EmployeeCount
        FROM        [Core].[Companies]  AS c
        LEFT JOIN   [Core].[Countries]  AS co ON co.CountryId  = c.CountryId
        LEFT JOIN   [Core].[Currencies] AS cu ON cu.CurrencyId = c.DefaultCurrencyId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR c.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR c.CompanyId = @CompanyId)
              AND (@Pattern IS NULL OR (c.CompanyCode LIKE @Pattern ESCAPE '\'
                   OR c.CompanyName LIKE @Pattern ESCAPE '\'
                   OR c.LegalName LIKE @Pattern ESCAPE '\'
                   OR c.CommercialRegistrationNo LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyCode' THEN c.CompanyCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyCode' THEN c.CompanyCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'LegalName' THEN c.LegalName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'LegalName' THEN c.LegalName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CountryName' THEN co.CountryName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CountryName' THEN co.CountryName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN c.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN c.IsActive END DESC,
                c.CompanyName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  c.CompanyId,
                c.CompanyCode,
                c.CompanyName,
                c.LegalName,
                c.CommercialRegistrationNo,
                c.TaxNo,
                c.CountryId,
                c.DefaultCurrencyId,
                c.Address,
                c.Telephone,
                c.Email,
                c.Website,
                c.LogoPath,
                c.IsActive,
                co.CountryName,
                cu.CurrencyCode,
                (SELECT COUNT(1) FROM [Core].[Branches]      b WHERE b.CompanyId = c.CompanyId)                        AS BranchCount,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.CompanyId = c.CompanyId AND e.IsDeleted = 0)    AS EmployeeCount
        FROM        [Core].[Companies]  AS c
        LEFT JOIN   [Core].[Countries]  AS co ON co.CountryId  = c.CountryId
        LEFT JOIN   [Core].[Currencies] AS cu ON cu.CurrencyId = c.DefaultCurrencyId
        WHERE c.CompanyId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[Companies] AS c WHERE c.CompanyCode = @CompanyCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[Companies]
            (CompanyCode, CompanyName, LegalName, CommercialRegistrationNo, TaxNo, CountryId, DefaultCurrencyId, Address, Telephone, Email, Website, LogoPath, IsActive)
        VALUES
            (@CompanyCode, @CompanyName, @LegalName, @CommercialRegistrationNo, @TaxNo, @CountryId, @DefaultCurrencyId, @Address, @Telephone, @Email, @Website, @LogoPath, ISNULL(@IsActive, 1));

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Company created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Companies] WHERE CompanyId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Companies] AS c WHERE c.CompanyCode = @CompanyCode AND c.CompanyId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        UPDATE [Core].[Companies]
           SET CompanyCode                = @CompanyCode,
               CompanyName                = @CompanyName,
               LegalName                  = @LegalName,
               CommercialRegistrationNo   = @CommercialRegistrationNo,
               TaxNo                      = @TaxNo,
               CountryId                  = @CountryId,
               DefaultCurrencyId          = @DefaultCurrencyId,
               Address                    = @Address,
               Telephone                  = @Telephone,
               Email                      = @Email,
               Website                    = @Website,
               LogoPath                   = @LogoPath,
               IsActive                   = @IsActive,
               ModifiedDate               = SYSUTCDATETIME()
         WHERE CompanyId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Company updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Companies] WHERE CompanyId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Branches] WHERE CompanyId = @Id)
           OR EXISTS (SELECT 1 FROM [Core].[Departments] WHERE CompanyId = @Id)
           OR EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE CompanyId = @Id)
           OR EXISTS (SELECT 1 FROM [Core].[Grades] WHERE CompanyId = @Id)
           OR EXISTS (SELECT 1 FROM [Core].[Positions] WHERE CompanyId = @Id)
           OR EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE CompanyId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This company is referenced by other records and cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        DELETE FROM [Core].[Companies] WHERE CompanyId = @Id;

        SET @ResultMessage = N'Company deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Companies] WHERE CompanyId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[Companies]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE CompanyId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Company activated.'
                                     ELSE N'Company deactivated.' END
        FROM [Core].[Companies]
        WHERE CompanyId = @Id;

        RETURN;
    END;
END;
GO

/* ================================================================
   [Core].[usp_Branch_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_Branch_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @BranchCode                NVARCHAR(30)    = NULL,
    @BranchName                NVARCHAR(150)   = NULL,
    @Address                   NVARCHAR(500)   = NULL,
    @Area                      NVARCHAR(100)   = NULL,
    @Governorate               NVARCHAR(100)   = NULL,
    @Telephone                 NVARCHAR(50)    = NULL,
    @Email                     NVARCHAR(150)   = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[Branches]  AS b
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = b.CompanyId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR b.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR b.CompanyId = @CompanyId)
              AND (@Pattern IS NULL OR (b.BranchCode LIKE @Pattern ESCAPE '\'
                   OR b.BranchName LIKE @Pattern ESCAPE '\'
                   OR b.Area LIKE @Pattern ESCAPE '\'
                   OR b.Governorate LIKE @Pattern ESCAPE '\'));

        SELECT  b.BranchId,
                b.CompanyId,
                b.BranchCode,
                b.BranchName,
                b.Address,
                b.Area,
                b.Governorate,
                b.Telephone,
                b.Email,
                b.IsActive,
                c.CompanyName,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.BranchId = b.BranchId AND e.IsDeleted = 0) AS EmployeeCount
        FROM        [Core].[Branches]  AS b
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = b.CompanyId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR b.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR b.CompanyId = @CompanyId)
              AND (@Pattern IS NULL OR (b.BranchCode LIKE @Pattern ESCAPE '\'
                   OR b.BranchName LIKE @Pattern ESCAPE '\'
                   OR b.Area LIKE @Pattern ESCAPE '\'
                   OR b.Governorate LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'BranchCode' THEN b.BranchCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'BranchCode' THEN b.BranchCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'BranchName' THEN b.BranchName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'BranchName' THEN b.BranchName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'Governorate' THEN b.Governorate END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'Governorate' THEN b.Governorate END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'Area' THEN b.Area END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'Area' THEN b.Area END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN b.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN b.IsActive END DESC,
                b.BranchName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  b.BranchId,
                b.CompanyId,
                b.BranchCode,
                b.BranchName,
                b.Address,
                b.Area,
                b.Governorate,
                b.Telephone,
                b.Email,
                b.IsActive,
                c.CompanyName,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.BranchId = b.BranchId AND e.IsDeleted = 0) AS EmployeeCount
        FROM        [Core].[Branches]  AS b
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = b.CompanyId
        WHERE b.BranchId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[Branches] AS b WHERE b.CompanyId = @CompanyId AND b.BranchCode = @BranchCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[Branches]
            (CompanyId, BranchCode, BranchName, Address, Area, Governorate, Telephone, Email, IsActive)
        VALUES
            (@CompanyId, @BranchCode, @BranchName, @Address, @Area, @Governorate, @Telephone, @Email, ISNULL(@IsActive, 1));

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Branch created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Branches] WHERE BranchId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Branches] AS b WHERE b.CompanyId = @CompanyId AND b.BranchCode = @BranchCode AND b.BranchId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        UPDATE [Core].[Branches]
           SET CompanyId                  = @CompanyId,
               BranchCode                 = @BranchCode,
               BranchName                 = @BranchName,
               Address                    = @Address,
               Area                       = @Area,
               Governorate                = @Governorate,
               Telephone                  = @Telephone,
               Email                      = @Email,
               IsActive                   = @IsActive
         WHERE BranchId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Branch updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Branches] WHERE BranchId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE BranchId = @Id)
           OR EXISTS (SELECT 1 FROM [Attendance].[AttendanceDevices] WHERE BranchId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This branch is referenced by other records and cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        DELETE FROM [Core].[Branches] WHERE BranchId = @Id;

        SET @ResultMessage = N'Branch deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Branches] WHERE BranchId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[Branches]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE BranchId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Branch activated.'
                                     ELSE N'Branch deactivated.' END
        FROM [Core].[Branches]
        WHERE BranchId = @Id;

        RETURN;
    END;
END;
GO

/* ================================================================
   [Core].[usp_Department_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_Department_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @ParentDepartmentId        INT             = NULL,
    @DepartmentCode            NVARCHAR(50)    = NULL,
    @DepartmentName            NVARCHAR(150)   = NULL,
    @CostCenterId              INT             = NULL,
    @ManagerEmployeeId         BIGINT          = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[Departments]     AS d
        INNER JOIN  [Core].[Companies]       AS c  ON c.CompanyId       = d.CompanyId
        LEFT JOIN   [Core].[Departments]     AS p  ON p.DepartmentId    = d.ParentDepartmentId
        LEFT JOIN   [Core].[CostCenters]     AS cc ON cc.CostCenterId   = d.CostCenterId
        LEFT JOIN   [Employee].[Employees]   AS m  ON m.EmployeeId      = d.ManagerEmployeeId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR d.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR d.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR d.ParentDepartmentId = @ParentId)
              AND (@Pattern IS NULL OR (d.DepartmentCode LIKE @Pattern ESCAPE '\'
                   OR d.DepartmentName LIKE @Pattern ESCAPE '\'));

        SELECT  d.DepartmentId,
                d.CompanyId,
                d.ParentDepartmentId,
                d.DepartmentCode,
                d.DepartmentName,
                d.CostCenterId,
                d.ManagerEmployeeId,
                d.IsActive,
                c.CompanyName,
                p.DepartmentName                                        AS ParentDepartmentName,
                cc.CostCenterName,
                CONCAT(m.FirstName, N' ', ISNULL(m.LastName, N''))      AS ManagerName,
                (SELECT COUNT(1) FROM [Core].[Sections]     s WHERE s.DepartmentId = d.DepartmentId)                        AS SectionCount,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.DepartmentId = d.DepartmentId AND e.IsDeleted = 0)   AS EmployeeCount
        FROM        [Core].[Departments]     AS d
        INNER JOIN  [Core].[Companies]       AS c  ON c.CompanyId       = d.CompanyId
        LEFT JOIN   [Core].[Departments]     AS p  ON p.DepartmentId    = d.ParentDepartmentId
        LEFT JOIN   [Core].[CostCenters]     AS cc ON cc.CostCenterId   = d.CostCenterId
        LEFT JOIN   [Employee].[Employees]   AS m  ON m.EmployeeId      = d.ManagerEmployeeId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR d.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR d.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR d.ParentDepartmentId = @ParentId)
              AND (@Pattern IS NULL OR (d.DepartmentCode LIKE @Pattern ESCAPE '\'
                   OR d.DepartmentName LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DepartmentCode' THEN d.DepartmentCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DepartmentCode' THEN d.DepartmentCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ParentDepartmentName' THEN p.DepartmentName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ParentDepartmentName' THEN p.DepartmentName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CostCenterName' THEN cc.CostCenterName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CostCenterName' THEN cc.CostCenterName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN d.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN d.IsActive END DESC,
                d.DepartmentName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  d.DepartmentId,
                d.CompanyId,
                d.ParentDepartmentId,
                d.DepartmentCode,
                d.DepartmentName,
                d.CostCenterId,
                d.ManagerEmployeeId,
                d.IsActive,
                c.CompanyName,
                p.DepartmentName                                        AS ParentDepartmentName,
                cc.CostCenterName,
                CONCAT(m.FirstName, N' ', ISNULL(m.LastName, N''))      AS ManagerName,
                (SELECT COUNT(1) FROM [Core].[Sections]     s WHERE s.DepartmentId = d.DepartmentId)                        AS SectionCount,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.DepartmentId = d.DepartmentId AND e.IsDeleted = 0)   AS EmployeeCount
        FROM        [Core].[Departments]     AS d
        INNER JOIN  [Core].[Companies]       AS c  ON c.CompanyId       = d.CompanyId
        LEFT JOIN   [Core].[Departments]     AS p  ON p.DepartmentId    = d.ParentDepartmentId
        LEFT JOIN   [Core].[CostCenters]     AS cc ON cc.CostCenterId   = d.CostCenterId
        LEFT JOIN   [Employee].[Employees]   AS m  ON m.EmployeeId      = d.ManagerEmployeeId
        WHERE d.DepartmentId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[Departments] AS d WHERE d.CompanyId = @CompanyId AND d.DepartmentCode = @DepartmentCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[Departments]
            (CompanyId, ParentDepartmentId, DepartmentCode, DepartmentName, CostCenterId, ManagerEmployeeId, IsActive)
        VALUES
            (@CompanyId, @ParentDepartmentId, @DepartmentCode, @DepartmentName, @CostCenterId, @ManagerEmployeeId, ISNULL(@IsActive, 1));

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Department created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Departments] WHERE DepartmentId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Departments] AS d WHERE d.CompanyId = @CompanyId AND d.DepartmentCode = @DepartmentCode AND d.DepartmentId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        /* A department cannot be its own parent. */
        IF @ParentDepartmentId IS NOT NULL AND @ParentDepartmentId = @Id
        BEGIN
            SELECT @ResultCode    = 'CIRCULAR_REFERENCE',
                   @ResultMessage = N'A department cannot report to itself.';
            RETURN;
        END;

        UPDATE [Core].[Departments]
           SET CompanyId                  = @CompanyId,
               ParentDepartmentId         = @ParentDepartmentId,
               DepartmentCode             = @DepartmentCode,
               DepartmentName             = @DepartmentName,
               CostCenterId               = @CostCenterId,
               ManagerEmployeeId          = @ManagerEmployeeId,
               IsActive                   = @IsActive
         WHERE DepartmentId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Department updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Departments] WHERE DepartmentId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Sections] WHERE DepartmentId = @Id)
           OR EXISTS (SELECT 1 FROM [Core].[Departments] WHERE ParentDepartmentId = @Id)
           OR EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE DepartmentId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This department is referenced by other records and cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        DELETE FROM [Core].[Departments] WHERE DepartmentId = @Id;

        SET @ResultMessage = N'Department deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Departments] WHERE DepartmentId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[Departments]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE DepartmentId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Department activated.'
                                     ELSE N'Department deactivated.' END
        FROM [Core].[Departments]
        WHERE DepartmentId = @Id;

        RETURN;
    END;
END;
GO

/* ================================================================
   [Core].[usp_Section_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_Section_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @DepartmentId              INT             = NULL,
    @SectionCode               NVARCHAR(50)    = NULL,
    @SectionName               NVARCHAR(150)   = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[Sections]    AS s
        INNER JOIN  [Core].[Departments] AS d ON d.DepartmentId = s.DepartmentId
        INNER JOIN  [Core].[Companies]   AS c ON c.CompanyId    = d.CompanyId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR s.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR d.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR s.DepartmentId = @ParentId)
              AND (@Pattern IS NULL OR (s.SectionCode LIKE @Pattern ESCAPE '\'
                   OR s.SectionName LIKE @Pattern ESCAPE '\'
                   OR d.DepartmentName LIKE @Pattern ESCAPE '\'));

        SELECT  s.SectionId,
                s.DepartmentId,
                s.SectionCode,
                s.SectionName,
                s.IsActive,
                d.CompanyId,
                d.DepartmentName,
                c.CompanyName,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.SectionId = s.SectionId AND e.IsDeleted = 0) AS EmployeeCount
        FROM        [Core].[Sections]    AS s
        INNER JOIN  [Core].[Departments] AS d ON d.DepartmentId = s.DepartmentId
        INNER JOIN  [Core].[Companies]   AS c ON c.CompanyId    = d.CompanyId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR s.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR d.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR s.DepartmentId = @ParentId)
              AND (@Pattern IS NULL OR (s.SectionCode LIKE @Pattern ESCAPE '\'
                   OR s.SectionName LIKE @Pattern ESCAPE '\'
                   OR d.DepartmentName LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'SectionCode' THEN s.SectionCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'SectionCode' THEN s.SectionCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'SectionName' THEN s.SectionName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'SectionName' THEN s.SectionName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN s.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN s.IsActive END DESC,
                s.SectionName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  s.SectionId,
                s.DepartmentId,
                s.SectionCode,
                s.SectionName,
                s.IsActive,
                d.CompanyId,
                d.DepartmentName,
                c.CompanyName,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.SectionId = s.SectionId AND e.IsDeleted = 0) AS EmployeeCount
        FROM        [Core].[Sections]    AS s
        INNER JOIN  [Core].[Departments] AS d ON d.DepartmentId = s.DepartmentId
        INNER JOIN  [Core].[Companies]   AS c ON c.CompanyId    = d.CompanyId
        WHERE s.SectionId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[Sections] AS s WHERE s.DepartmentId = @DepartmentId AND s.SectionCode = @SectionCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[Sections]
            (DepartmentId, SectionCode, SectionName, IsActive)
        VALUES
            (@DepartmentId, @SectionCode, @SectionName, ISNULL(@IsActive, 1));

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Section created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Sections] WHERE SectionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Sections] AS s WHERE s.DepartmentId = @DepartmentId AND s.SectionCode = @SectionCode AND s.SectionId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        UPDATE [Core].[Sections]
           SET DepartmentId               = @DepartmentId,
               SectionCode                = @SectionCode,
               SectionName                = @SectionName,
               IsActive                   = @IsActive
         WHERE SectionId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Section updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Sections] WHERE SectionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE SectionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This section is referenced by other records and cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        DELETE FROM [Core].[Sections] WHERE SectionId = @Id;

        SET @ResultMessage = N'Section deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Sections] WHERE SectionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[Sections]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE SectionId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Section activated.'
                                     ELSE N'Section deactivated.' END
        FROM [Core].[Sections]
        WHERE SectionId = @Id;

        RETURN;
    END;
END;
GO

/* ================================================================
   [Core].[usp_Designation_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_Designation_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @DesignationCode           NVARCHAR(50)    = NULL,
    @DesignationName           NVARCHAR(150)   = NULL,
    @ArabicName                NVARCHAR(150)   = NULL,
    @GradeId                   INT             = NULL,
    @Description               NVARCHAR(500)   = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[Designations] AS dg
        INNER JOIN  [Core].[Companies]    AS c ON c.CompanyId = dg.CompanyId
        LEFT JOIN   [Core].[Grades]       AS g ON g.GradeId   = dg.GradeId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR dg.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR dg.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR dg.GradeId = @ParentId)
              AND (@Pattern IS NULL OR (dg.DesignationCode LIKE @Pattern ESCAPE '\'
                   OR dg.DesignationName LIKE @Pattern ESCAPE '\'
                   OR dg.ArabicName LIKE @Pattern ESCAPE '\'));

        SELECT  dg.DesignationId,
                dg.CompanyId,
                dg.DesignationCode,
                dg.DesignationName,
                dg.ArabicName,
                dg.GradeId,
                dg.Description,
                dg.IsActive,
                c.CompanyName,
                g.GradeName,
                0 AS EmployeeCount
        FROM        [Core].[Designations] AS dg
        INNER JOIN  [Core].[Companies]    AS c ON c.CompanyId = dg.CompanyId
        LEFT JOIN   [Core].[Grades]       AS g ON g.GradeId   = dg.GradeId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR dg.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR dg.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR dg.GradeId = @ParentId)
              AND (@Pattern IS NULL OR (dg.DesignationCode LIKE @Pattern ESCAPE '\'
                   OR dg.DesignationName LIKE @Pattern ESCAPE '\'
                   OR dg.ArabicName LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DesignationCode' THEN dg.DesignationCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DesignationCode' THEN dg.DesignationCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DesignationName' THEN dg.DesignationName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DesignationName' THEN dg.DesignationName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'GradeName' THEN g.GradeName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'GradeName' THEN g.GradeName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN dg.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN dg.IsActive END DESC,
                dg.DesignationName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  dg.DesignationId,
                dg.CompanyId,
                dg.DesignationCode,
                dg.DesignationName,
                dg.ArabicName,
                dg.GradeId,
                dg.Description,
                dg.IsActive,
                c.CompanyName,
                g.GradeName,
                0 AS EmployeeCount
        FROM        [Core].[Designations] AS dg
        INNER JOIN  [Core].[Companies]    AS c ON c.CompanyId = dg.CompanyId
        LEFT JOIN   [Core].[Grades]       AS g ON g.GradeId   = dg.GradeId
        WHERE dg.DesignationId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[Designations] AS dg WHERE dg.CompanyId = @CompanyId AND dg.DesignationCode = @DesignationCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[Designations]
            (CompanyId, DesignationCode, DesignationName, ArabicName, GradeId, Description, IsActive, CreatedBy)
        VALUES
            (@CompanyId, @DesignationCode, @DesignationName, @ArabicName, @GradeId, @Description, ISNULL(@IsActive, 1), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Designation created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Designations] WHERE DesignationId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Designations] AS dg WHERE dg.CompanyId = @CompanyId AND dg.DesignationCode = @DesignationCode AND dg.DesignationId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        UPDATE [Core].[Designations]
           SET CompanyId                  = @CompanyId,
               DesignationCode            = @DesignationCode,
               DesignationName            = @DesignationName,
               ArabicName                 = @ArabicName,
               GradeId                    = @GradeId,
               Description                = @Description,
               IsActive                   = @IsActive,
               ModifiedBy                 = @UserId,
               ModifiedDate               = SYSUTCDATETIME()
         WHERE DesignationId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Designation updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Designations] WHERE DesignationId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        DELETE FROM [Core].[Designations] WHERE DesignationId = @Id;

        SET @ResultMessage = N'Designation deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Designations] WHERE DesignationId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[Designations]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE DesignationId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Designation activated.'
                                     ELSE N'Designation deactivated.' END
        FROM [Core].[Designations]
        WHERE DesignationId = @Id;

        RETURN;
    END;
END;
GO

/* ================================================================
   [Core].[usp_JobPosition_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_JobPosition_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @PositionCode              NVARCHAR(50)    = NULL,
    @PositionName              NVARCHAR(150)   = NULL,
    @JobDescription            NVARCHAR(MAX)   = NULL,
    @GradeId                   INT             = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[Positions] AS jp
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = jp.CompanyId
        LEFT JOIN   [Core].[Grades]    AS g ON g.GradeId   = jp.GradeId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR jp.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR jp.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR jp.GradeId = @ParentId)
              AND (@Pattern IS NULL OR (jp.PositionCode LIKE @Pattern ESCAPE '\'
                   OR jp.PositionName LIKE @Pattern ESCAPE '\'));

        SELECT  jp.PositionId,
                jp.CompanyId,
                jp.PositionCode,
                jp.PositionName,
                jp.JobDescription,
                jp.GradeId,
                jp.IsActive,
                c.CompanyName,
                g.GradeName,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.PositionId = jp.PositionId AND e.IsDeleted = 0) AS EmployeeCount
        FROM        [Core].[Positions] AS jp
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = jp.CompanyId
        LEFT JOIN   [Core].[Grades]    AS g ON g.GradeId   = jp.GradeId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR jp.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR jp.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR jp.GradeId = @ParentId)
              AND (@Pattern IS NULL OR (jp.PositionCode LIKE @Pattern ESCAPE '\'
                   OR jp.PositionName LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'PositionCode' THEN jp.PositionCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'PositionCode' THEN jp.PositionCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'PositionName' THEN jp.PositionName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'PositionName' THEN jp.PositionName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'GradeName' THEN g.GradeName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'GradeName' THEN g.GradeName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN jp.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN jp.IsActive END DESC,
                jp.PositionName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  jp.PositionId,
                jp.CompanyId,
                jp.PositionCode,
                jp.PositionName,
                jp.JobDescription,
                jp.GradeId,
                jp.IsActive,
                c.CompanyName,
                g.GradeName,
                (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.PositionId = jp.PositionId AND e.IsDeleted = 0) AS EmployeeCount
        FROM        [Core].[Positions] AS jp
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = jp.CompanyId
        LEFT JOIN   [Core].[Grades]    AS g ON g.GradeId   = jp.GradeId
        WHERE jp.PositionId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[Positions] AS jp WHERE jp.CompanyId = @CompanyId AND jp.PositionCode = @PositionCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[Positions]
            (CompanyId, PositionCode, PositionName, JobDescription, GradeId, IsActive)
        VALUES
            (@CompanyId, @PositionCode, @PositionName, @JobDescription, @GradeId, ISNULL(@IsActive, 1));

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Job position created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Positions] WHERE PositionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Positions] AS jp WHERE jp.CompanyId = @CompanyId AND jp.PositionCode = @PositionCode AND jp.PositionId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        UPDATE [Core].[Positions]
           SET CompanyId                  = @CompanyId,
               PositionCode               = @PositionCode,
               PositionName               = @PositionName,
               JobDescription             = @JobDescription,
               GradeId                    = @GradeId,
               IsActive                   = @IsActive
         WHERE PositionId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Job position updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Positions] WHERE PositionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE PositionId = @Id)
           OR EXISTS (SELECT 1 FROM [Recruitment].[JobRequisitions] WHERE PositionId = @Id)
           OR EXISTS (SELECT 1 FROM [Recruitment].[JobOffers] WHERE PositionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This job position is referenced by other records and cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        DELETE FROM [Core].[Positions] WHERE PositionId = @Id;

        SET @ResultMessage = N'Job position deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Positions] WHERE PositionId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[Positions]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE PositionId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Job position activated.'
                                     ELSE N'Job position deactivated.' END
        FROM [Core].[Positions]
        WHERE PositionId = @Id;

        RETURN;
    END;
END;
GO

/* ================================================================
   [Core].[usp_Location_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_Location_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @BranchId                  INT             = NULL,
    @LocationCode              NVARCHAR(50)    = NULL,
    @LocationName              NVARCHAR(150)   = NULL,
    @LocationType              NVARCHAR(50)    = NULL,
    @Governorate               NVARCHAR(100)   = NULL,
    @Area                      NVARCHAR(100)   = NULL,
    @Block                     NVARCHAR(30)    = NULL,
    @Street                    NVARCHAR(150)   = NULL,
    @Building                  NVARCHAR(50)    = NULL,
    @Latitude                  DECIMAL(10,7)   = NULL,
    @Longitude                 DECIMAL(10,7)   = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[Locations] AS l
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = l.CompanyId
        LEFT JOIN   [Core].[Branches]  AS b ON b.BranchId  = l.BranchId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR l.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR l.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR l.BranchId = @ParentId)
              AND (@Pattern IS NULL OR (l.LocationCode LIKE @Pattern ESCAPE '\'
                   OR l.LocationName LIKE @Pattern ESCAPE '\'
                   OR l.Area LIKE @Pattern ESCAPE '\'
                   OR l.Governorate LIKE @Pattern ESCAPE '\'
                   OR l.Building LIKE @Pattern ESCAPE '\'));

        SELECT  l.LocationId,
                l.CompanyId,
                l.BranchId,
                l.LocationCode,
                l.LocationName,
                l.LocationType,
                l.Governorate,
                l.Area,
                l.Block,
                l.Street,
                l.Building,
                l.Latitude,
                l.Longitude,
                l.IsActive,
                c.CompanyName,
                b.BranchName
        FROM        [Core].[Locations] AS l
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = l.CompanyId
        LEFT JOIN   [Core].[Branches]  AS b ON b.BranchId  = l.BranchId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR l.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR l.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR l.BranchId = @ParentId)
              AND (@Pattern IS NULL OR (l.LocationCode LIKE @Pattern ESCAPE '\'
                   OR l.LocationName LIKE @Pattern ESCAPE '\'
                   OR l.Area LIKE @Pattern ESCAPE '\'
                   OR l.Governorate LIKE @Pattern ESCAPE '\'
                   OR l.Building LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'LocationCode' THEN l.LocationCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'LocationCode' THEN l.LocationCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'LocationName' THEN l.LocationName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'LocationName' THEN l.LocationName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'BranchName' THEN b.BranchName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'BranchName' THEN b.BranchName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'Governorate' THEN l.Governorate END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'Governorate' THEN l.Governorate END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'LocationType' THEN l.LocationType END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'LocationType' THEN l.LocationType END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN l.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN l.IsActive END DESC,
                l.LocationName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  l.LocationId,
                l.CompanyId,
                l.BranchId,
                l.LocationCode,
                l.LocationName,
                l.LocationType,
                l.Governorate,
                l.Area,
                l.Block,
                l.Street,
                l.Building,
                l.Latitude,
                l.Longitude,
                l.IsActive,
                c.CompanyName,
                b.BranchName
        FROM        [Core].[Locations] AS l
        INNER JOIN  [Core].[Companies] AS c ON c.CompanyId = l.CompanyId
        LEFT JOIN   [Core].[Branches]  AS b ON b.BranchId  = l.BranchId
        WHERE l.LocationId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[Locations] AS l WHERE l.CompanyId = @CompanyId AND l.LocationCode = @LocationCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[Locations]
            (CompanyId, BranchId, LocationCode, LocationName, LocationType, Governorate, Area, Block, Street, Building, Latitude, Longitude, IsActive, CreatedBy)
        VALUES
            (@CompanyId, @BranchId, @LocationCode, @LocationName, @LocationType, @Governorate, @Area, @Block, @Street, @Building, @Latitude, @Longitude, ISNULL(@IsActive, 1), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Location created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Locations] WHERE LocationId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Locations] AS l WHERE l.CompanyId = @CompanyId AND l.LocationCode = @LocationCode AND l.LocationId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        UPDATE [Core].[Locations]
           SET CompanyId                  = @CompanyId,
               BranchId                   = @BranchId,
               LocationCode               = @LocationCode,
               LocationName               = @LocationName,
               LocationType               = @LocationType,
               Governorate                = @Governorate,
               Area                       = @Area,
               Block                      = @Block,
               Street                     = @Street,
               Building                   = @Building,
               Latitude                   = @Latitude,
               Longitude                  = @Longitude,
               IsActive                   = @IsActive,
               ModifiedBy                 = @UserId,
               ModifiedDate               = SYSUTCDATETIME()
         WHERE LocationId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Location updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Locations] WHERE LocationId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        DELETE FROM [Core].[Locations] WHERE LocationId = @Id;

        SET @ResultMessage = N'Location deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[Locations] WHERE LocationId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[Locations]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE LocationId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Location activated.'
                                     ELSE N'Location deactivated.' END
        FROM [Core].[Locations]
        WHERE LocationId = @Id;

        RETURN;
    END;
END;
GO

/* ================================================================
   [Core].[usp_CostCenter_Manage]
   ----------------------------------------------------------------
   One procedure, six actions: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE.
   All SQL is static - the sort order is resolved by CASE expressions
   against an allowlist of logical column names, never by dynamic SQL.
================================================================ */
CREATE OR ALTER PROCEDURE [Core].[usp_CostCenter_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @ParentCostCenterId        INT             = NULL,
    @CostCenterCode            NVARCHAR(50)    = NULL,
    @CostCenterName            NVARCHAR(150)   = NULL,
    @IsActive                  BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* Normalise paging and sorting so caller input can never reach the plan. */
    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* Escape LIKE metacharacters: a search term cannot become a wildcard pattern. */
    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Core].[CostCenters] AS cc
        INNER JOIN  [Core].[Companies]   AS c ON c.CompanyId    = cc.CompanyId
        LEFT JOIN   [Core].[CostCenters] AS p ON p.CostCenterId = cc.ParentCostCenterId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR cc.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR cc.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR cc.ParentCostCenterId = @ParentId)
              AND (@Pattern IS NULL OR (cc.CostCenterCode LIKE @Pattern ESCAPE '\'
                   OR cc.CostCenterName LIKE @Pattern ESCAPE '\'));

        SELECT  cc.CostCenterId,
                cc.CompanyId,
                cc.ParentCostCenterId,
                cc.CostCenterCode,
                cc.CostCenterName,
                cc.IsActive,
                c.CompanyName,
                p.CostCenterName AS ParentCostCenterName,
                (SELECT COUNT(1) FROM [Core].[Departments] d WHERE d.CostCenterId = cc.CostCenterId) AS DepartmentCount
        FROM        [Core].[CostCenters] AS cc
        INNER JOIN  [Core].[Companies]   AS c ON c.CompanyId    = cc.CompanyId
        LEFT JOIN   [Core].[CostCenters] AS p ON p.CostCenterId = cc.ParentCostCenterId
        WHERE 1 = 1
              AND (@IsActiveFilter IS NULL OR cc.IsActive = @IsActiveFilter)
              AND (@CompanyId IS NULL OR cc.CompanyId = @CompanyId)
              AND (@ParentId IS NULL OR cc.ParentCostCenterId = @ParentId)
              AND (@Pattern IS NULL OR (cc.CostCenterCode LIKE @Pattern ESCAPE '\'
                   OR cc.CostCenterName LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CostCenterCode' THEN cc.CostCenterCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CostCenterCode' THEN cc.CostCenterCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CostCenterName' THEN cc.CostCenterName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CostCenterName' THEN cc.CostCenterName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName' THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName' THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ParentCostCenterName' THEN p.CostCenterName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ParentCostCenterName' THEN p.CostCenterName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive' THEN cc.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive' THEN cc.IsActive END DESC,
                cc.CostCenterName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  cc.CostCenterId,
                cc.CompanyId,
                cc.ParentCostCenterId,
                cc.CostCenterCode,
                cc.CostCenterName,
                cc.IsActive,
                c.CompanyName,
                p.CostCenterName AS ParentCostCenterName,
                (SELECT COUNT(1) FROM [Core].[Departments] d WHERE d.CostCenterId = cc.CostCenterId) AS DepartmentCount
        FROM        [Core].[CostCenters] AS cc
        INNER JOIN  [Core].[Companies]   AS c ON c.CompanyId    = cc.CompanyId
        LEFT JOIN   [Core].[CostCenters] AS p ON p.CostCenterId = cc.ParentCostCenterId
        WHERE cc.CostCenterId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Core].[CostCenters] AS cc WHERE cc.CompanyId = @CompanyId AND cc.CostCenterCode = @CostCenterCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Core].[CostCenters]
            (CompanyId, ParentCostCenterId, CostCenterCode, CostCenterName, IsActive)
        VALUES
            (@CompanyId, @ParentCostCenterId, @CostCenterCode, @CostCenterName, ISNULL(@IsActive, 1));

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Cost center created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE CostCenterId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[CostCenters] AS cc WHERE cc.CompanyId = @CompanyId AND cc.CostCenterCode = @CostCenterCode AND cc.CostCenterId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;

        /* A cost center cannot be its own parent. */
        IF @ParentCostCenterId IS NOT NULL AND @ParentCostCenterId = @Id
        BEGIN
            SELECT @ResultCode    = 'CIRCULAR_REFERENCE',
                   @ResultMessage = N'A cost center cannot roll up to itself.';
            RETURN;
        END;

        UPDATE [Core].[CostCenters]
           SET CompanyId                  = @CompanyId,
               ParentCostCenterId         = @ParentCostCenterId,
               CostCenterCode             = @CostCenterCode,
               CostCenterName             = @CostCenterName,
               IsActive                   = @IsActive
         WHERE CostCenterId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Cost center updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE CostCenterId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[Departments] WHERE CostCenterId = @Id)
           OR EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE ParentCostCenterId = @Id)
           OR EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE CostCenterId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This cost center is referenced by other records and cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        DELETE FROM [Core].[CostCenters] WHERE CostCenterId = @Id;

        SET @ResultMessage = N'Cost center deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE CostCenterId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Core].[CostCenters]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END
         WHERE CostCenterId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1
                                     THEN N'Cost center activated.'
                                     ELSE N'Cost center deactivated.' END
        FROM [Core].[CostCenters]
        WHERE CostCenterId = @Id;

        RETURN;
    END;
END;
GO

PRINT 'Organization Setup stored procedures created (8 procedures, 6 actions each).';
GO
