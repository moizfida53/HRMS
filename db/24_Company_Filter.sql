/* ================================================================
   HRMS Kuwait - Company filter (top bar, all pages)
   ----------------------------------------------------------------
   Adds @CompanyIds NVARCHAR(2000) = NULL - a comma-separated list of
   CompanyIds, e.g. N'1,3' - to every list procedure, so a page can
   show one, several or all companies. NULL = all companies (default).

   The existing single @CompanyId filter is untouched and still works;
   the two are combined with AND.

   Re-created (CREATE OR ALTER, full body; only the new parameter and
   one extra filter line per LIST query are added):
     Core.usp_Branch_Manage, usp_Department_Manage, usp_Section_Manage,
     usp_Designation_Manage, usp_JobPosition_Manage,
     usp_Location_Manage, usp_CostCenter_Manage   (from db/03)
     Core.usp_Company_Manage    - accepts @CompanyIds but does NOT
                                  filter by it: Setup > Companies
                                  always lists every company
     Employee.usp_Employee_Manage   (from db/20)
     Employee.usp_Dashboard_Get     (from db/23)

   NOTE: built from the texts in db/03, db/20 and db/23. If any of these
   procedures was changed directly in the database after those scripts,
   re-apply that change after running this one.

   Run AFTER 23.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [Core].[usp_Company_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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

CREATE OR ALTER PROCEDURE [Core].[usp_Branch_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(b.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(b.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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

CREATE OR ALTER PROCEDURE [Core].[usp_Department_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(d.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(d.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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

CREATE OR ALTER PROCEDURE [Core].[usp_Section_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(d.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(d.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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

CREATE OR ALTER PROCEDURE [Core].[usp_Designation_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(dg.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(dg.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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

CREATE OR ALTER PROCEDURE [Core].[usp_JobPosition_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(jp.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(jp.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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

CREATE OR ALTER PROCEDURE [Core].[usp_Location_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(l.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(l.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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

CREATE OR ALTER PROCEDURE [Core].[usp_CostCenter_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(cc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(cc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
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

CREATE OR ALTER PROCEDURE [Employee].[usp_Employee_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                     VARCHAR(10),
    @Id                         BIGINT          = NULL,

    /* ---- LIST filters and paging -------------------------------- */
    @Search                     NVARCHAR(200)   = NULL,
    @IsActiveFilter             BIT             = NULL,   -- maps to IsDeleted = 0 (active) / 1 (deleted)
    @CompanyId                  INT             = NULL,   -- LIST scope filter AND editable column - declared once
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- db/24: company filter, comma-separated ids (NULL = all)
    @ParentId                   INT             = NULL,   -- LIST filter: DepartmentId
    @PageNumber                 INT             = 1,
    @PageSize                   INT             = 25,
    @SortColumn                 VARCHAR(50)     = NULL,
    @SortDirection              VARCHAR(4)      = 'ASC',

    /* ---- editable columns: personal info ------------------------ */
    @EmployeeCode               NVARCHAR(20)    = NULL,
    @EmployeeNo                 NVARCHAR(20)    = NULL,
    @FirstName                  NVARCHAR(100)   = NULL,
    @MiddleName                 NVARCHAR(100)   = NULL,
    @LastName                   NVARCHAR(100)   = NULL,
    @ArabicName                 NVARCHAR(300)   = NULL,
    @Gender                     CHAR(1)         = NULL,
    @DateOfBirth                DATE            = NULL,
    @MaritalStatus              NVARCHAR(20)    = NULL,
    @NationalityCountryId       INT             = NULL,
    @Religion                   NVARCHAR(50)    = NULL,
    @BloodGroup                 NVARCHAR(5)     = NULL,
    @MobileNumber                NVARCHAR(20)   = NULL,
    @Extension                   NVARCHAR(10)   = NULL,
    @PersonalEmail               NVARCHAR(150)  = NULL,
    @WorkEmail                   NVARCHAR(150)  = NULL,
    @Address                     NVARCHAR(500)  = NULL,
    @Neighborhood                 NVARCHAR(100) = NULL,
    @Block                        NVARCHAR(20)  = NULL,
    @StreetName                   NVARCHAR(150) = NULL,
    @BuildingNumber                NVARCHAR(30) = NULL,
    @FloorNumber                   NVARCHAR(20) = NULL,
    @FlatNumber                    NVARCHAR(20) = NULL,
    @PaciNumber                    NVARCHAR(20) = NULL,
    @Landmark                      NVARCHAR(200)= NULL,
    @PhotoPath                   NVARCHAR(300)  = NULL,
    @EmergencyContactName        NVARCHAR(150)  = NULL,
    @EmergencyContactPhone       NVARCHAR(20)   = NULL,
    @EmergencyContactRelation    NVARCHAR(50)   = NULL,

    /* ---- editable columns: father's details ---------------------- */
    @FatherName                  NVARCHAR(150)  = NULL,
    @FatherOccupation            NVARCHAR(100)  = NULL,
    @FatherMobileNumber          NVARCHAR(20)   = NULL,
    @FatherIsDeceased            BIT            = NULL,
    @CurrentResidenceCountryId   INT            = NULL,

    /* ---- editable columns: passport -------------------------------- */
    @PassportNumber              NVARCHAR(30)   = NULL,
    @PassportFullName            NVARCHAR(200)  = NULL,
    @PassportSurname             NVARCHAR(100)  = NULL,
    @PassportPlaceOfIssue        NVARCHAR(100)  = NULL,
    @PassportExpiryDate          DATE           = NULL,
    @PassportFirstPagePath       NVARCHAR(300)  = NULL,
    @PassportLastPagePath        NVARCHAR(300)  = NULL,

    /* ---- editable columns: civil id -------------------------------- */
    @CivilIdNumber               NVARCHAR(30)   = NULL,
    @CivilIdName                 NVARCHAR(200)  = NULL,
    @CivilIdExpiryDate           DATE           = NULL,
    @CivilIdFrontPath            NVARCHAR(300)  = NULL,
    @CivilIdBackPath             NVARCHAR(300)  = NULL,

    /* ---- editable columns: employment -----------------------------
       CompanyId is NOT repeated here - it is already declared above. */
    @BranchId                    INT            = NULL,
    @DepartmentId                INT            = NULL,
    @SectionId                   INT            = NULL,
    @PositionId                  INT            = NULL,   -- Job Position
    @DesignationId               INT            = NULL,
    @GradeId                     INT            = NULL,
    @CostCenterId                INT            = NULL,
    @WorkLocationId               INT           = NULL,
    @ReportingManagerId          BIGINT         = NULL,
    @HireDate                    DATE           = NULL,
    @ProbationEndDate            DATE           = NULL,
    @TerminationDate             DATE           = NULL,
    @EmploymentType               NVARCHAR(20)  = NULL,
    @EmploymentStatus             NVARCHAR(20)  = NULL,
    @NoticePeriodDays              INT          = NULL,

    /* ---- db/20: company contact & assets -------------------------- */
    @CompanyPhone                NVARCHAR(20)   = NULL,
    @CompanyAssets               NVARCHAR(300)  = NULL,

    /* ---- db/20: payroll & bank (stored in Employee.EmployeePayroll) - */
    @BasicSalary                 DECIMAL(12,3)  = NULL,
    @Allowances                  DECIMAL(12,3)  = NULL,
    @BankName                    NVARCHAR(100)  = NULL,
    @Iban                        NVARCHAR(34)   = NULL,

    /* ---- audit --------------------------------------------------- */
    @UserId                      BIGINT         = NULL,

    /* ---- outputs --------------------------------------------------*/
    @TotalCount                  INT            = NULL OUTPUT,
    @NewId                       BIGINT         = NULL OUTPUT,
    @ResultCode                  VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage               NVARCHAR(400)  = NULL OUTPUT
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

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================= */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Employee].[Employees] AS e
        WHERE       1 = 1
                AND (@IsActiveFilter IS NULL OR e.IsDeleted = CASE WHEN @IsActiveFilter = 1 THEN 0 ELSE 1 END)
                AND (@CompanyId      IS NULL OR e.CompanyId = @CompanyId)
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
                AND (@ParentId       IS NULL OR e.DepartmentId = @ParentId)
                AND (@Pattern IS NULL OR (
                        e.EmployeeCode LIKE @Pattern ESCAPE '\'
                     OR e.FirstName    LIKE @Pattern ESCAPE '\'
                     OR e.LastName     LIKE @Pattern ESCAPE '\'
                     OR e.ArabicName   LIKE @Pattern ESCAPE '\'
                     OR e.MobileNumber LIKE @Pattern ESCAPE '\'
                     OR e.WorkEmail    LIKE @Pattern ESCAPE '\'));

        SELECT  e.EmployeeId,
                e.EmployeeCode,
                e.FirstName,
                e.LastName,
                CONCAT(e.FirstName, N' ', ISNULL(e.LastName, N'')) AS FullName,
                e.MobileNumber,
                e.WorkEmail,
                e.HireDate,
                e.EmploymentStatus,
                CASE WHEN e.IsDeleted = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsActive,
                e.CompanyId,
                c.CompanyName,
                e.DepartmentId,
                d.DepartmentName,
                e.PositionId,
                p.PositionName,
                e.DesignationId,
                dg.DesignationName
        FROM        [Employee].[Employees] AS e
        INNER JOIN  [Core].[Companies]     AS c  ON c.CompanyId    = e.CompanyId
        LEFT JOIN   [Core].[Departments]   AS d  ON d.DepartmentId = e.DepartmentId
        LEFT JOIN   [Core].[Positions]     AS p  ON p.PositionId   = e.PositionId
        LEFT JOIN   [Core].[Designations]  AS dg ON dg.DesignationId = e.DesignationId
        WHERE       1 = 1
                AND (@IsActiveFilter IS NULL OR e.IsDeleted = CASE WHEN @IsActiveFilter = 1 THEN 0 ELSE 1 END)
                AND (@CompanyId      IS NULL OR e.CompanyId = @CompanyId)
              AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
                AND (@ParentId       IS NULL OR e.DepartmentId = @ParentId)
                AND (@Pattern IS NULL OR (
                        e.EmployeeCode LIKE @Pattern ESCAPE '\'
                     OR e.FirstName    LIKE @Pattern ESCAPE '\'
                     OR e.LastName     LIKE @Pattern ESCAPE '\'
                     OR e.ArabicName   LIKE @Pattern ESCAPE '\'
                     OR e.MobileNumber LIKE @Pattern ESCAPE '\'
                     OR e.WorkEmail    LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'EmployeeCode' THEN e.EmployeeCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'EmployeeCode' THEN e.EmployeeCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'FullName' THEN e.FirstName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'FullName' THEN e.FirstName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'HireDate' THEN e.HireDate END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'HireDate' THEN e.HireDate END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'EmploymentStatus' THEN e.EmploymentStatus END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'EmploymentStatus' THEN e.EmploymentStatus END DESC,
                e.FirstName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET =================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  e.EmployeeId,
                e.EmployeeCode,
                e.EmployeeNo,
                e.FirstName,
                e.MiddleName,
                e.LastName,
                e.ArabicName,
                e.Gender,
                e.DateOfBirth,
                e.MaritalStatus,
                e.NationalityCountryId,
                nc.CountryName                                         AS NationalityName,
                e.Religion,
                e.BloodGroup,
                e.MobileNumber,
                e.Extension,
                e.PersonalEmail,
                e.WorkEmail,
                e.Address,
                e.Neighborhood,
                e.Block,
                e.StreetName,
                e.BuildingNumber,
                e.FloorNumber,
                e.FlatNumber,
                e.PaciNumber,
                e.Landmark,
                e.PhotoPath,
                e.EmergencyContactName,
                e.EmergencyContactPhone,
                e.EmergencyContactRelation,
                e.FatherName,
                e.FatherOccupation,
                e.FatherMobileNumber,
                e.FatherIsDeceased,
                e.CurrentResidenceCountryId,
                crc.CountryName                                        AS CurrentResidenceCountryName,
                e.PassportNumber,
                e.PassportFullName,
                e.PassportSurname,
                e.PassportPlaceOfIssue,
                e.PassportExpiryDate,
                e.PassportFirstPagePath,
                e.PassportLastPagePath,
                e.CivilIdNumber,
                e.CivilIdName,
                e.CivilIdExpiryDate,
                e.CivilIdFrontPath,
                e.CivilIdBackPath,
                e.CompanyId,
                c.CompanyName,
                e.BranchId,
                br.BranchName,
                e.DepartmentId,
                d.DepartmentName,
                e.SectionId,
                s.SectionName,
                e.PositionId,
                p.PositionName,
                e.DesignationId,
                dg.DesignationName,
                e.GradeId,
                g.GradeName,
                e.CostCenterId,
                cc.CostCenterName,
                e.WorkLocationId,
                loc.LocationName,
                e.ReportingManagerId,
                CONCAT(mgr.FirstName, N' ', ISNULL(mgr.LastName, N'')) AS ReportingManagerName,
                e.HireDate,
                e.ProbationEndDate,
                e.TerminationDate,
                e.EmploymentType,
                e.EmploymentStatus,
                e.NoticePeriodDays,
                e.CompanyPhone,
                e.CompanyAssets,
                pay.BasicSalary,
                pay.Allowances,
                pay.BankName,
                pay.Iban,
                CASE WHEN e.IsDeleted = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsActive
        FROM        [Employee].[Employees] AS e
        INNER JOIN  [Core].[Companies]     AS c   ON c.CompanyId       = e.CompanyId
        LEFT JOIN   [Core].[Branches]      AS br  ON br.BranchId       = e.BranchId
        LEFT JOIN   [Core].[Departments]   AS d   ON d.DepartmentId    = e.DepartmentId
        LEFT JOIN   [Core].[Sections]      AS s   ON s.SectionId       = e.SectionId
        LEFT JOIN   [Core].[Positions]     AS p   ON p.PositionId      = e.PositionId
        LEFT JOIN   [Core].[Designations]  AS dg  ON dg.DesignationId  = e.DesignationId
        LEFT JOIN   [Core].[Grades]        AS g   ON g.GradeId         = e.GradeId
        LEFT JOIN   [Core].[CostCenters]   AS cc  ON cc.CostCenterId   = e.CostCenterId
        LEFT JOIN   [Core].[Locations]     AS loc ON loc.LocationId    = e.WorkLocationId
        LEFT JOIN   [Employee].[Employees] AS mgr ON mgr.EmployeeId    = e.ReportingManagerId
        LEFT JOIN   [Core].[Countries]     AS nc  ON nc.CountryId      = e.NationalityCountryId
        LEFT JOIN   [Core].[Countries]     AS crc ON crc.CountryId      = e.CurrentResidenceCountryId
        LEFT JOIN   [Employee].[EmployeePayroll] AS pay ON pay.EmployeeId = e.EmployeeId
        WHERE       e.EmployeeId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ================================ */
    IF @Action = 'INSERT'
    BEGIN
        IF NULLIF(LTRIM(RTRIM(@EmployeeNo)), N'') IS NULL
        BEGIN
            SELECT @ResultCode    = 'EMPLOYEE_NO_REQUIRED',
                   @ResultMessage = N'Employee No is required.';
            RETURN;
        END;

        IF @EmployeeCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeCode = @EmployeeCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That employee code is already in use. Enter a different code.';
            RETURN;
        END;

        IF EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeNo = @EmployeeNo)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_EMPLOYEE_NO',
                   @ResultMessage = N'That employee No is already in use. Enter a different one.';
            RETURN;
        END;

        INSERT INTO [Employee].[Employees]
            (EmployeeCode, EmployeeNo, FirstName, MiddleName, LastName, ArabicName, Gender, DateOfBirth,
             MaritalStatus, NationalityCountryId, Religion, BloodGroup, MobileNumber, Extension,
             PersonalEmail, WorkEmail, Address, Neighborhood, Block, StreetName, BuildingNumber,
             FloorNumber, FlatNumber, PaciNumber, Landmark, PhotoPath, EmergencyContactName,
             EmergencyContactPhone, EmergencyContactRelation,
             FatherName, FatherOccupation, FatherMobileNumber, FatherIsDeceased, CurrentResidenceCountryId,
             PassportNumber, PassportFullName, PassportSurname, PassportPlaceOfIssue, PassportExpiryDate,
             PassportFirstPagePath, PassportLastPagePath,
             CivilIdNumber, CivilIdName, CivilIdExpiryDate, CivilIdFrontPath, CivilIdBackPath,
             CompanyId, BranchId, DepartmentId, SectionId, PositionId, DesignationId, GradeId,
             CostCenterId, WorkLocationId, ReportingManagerId, HireDate, ProbationEndDate,
             TerminationDate, EmploymentType, EmploymentStatus, NoticePeriodDays,
             CompanyPhone, CompanyAssets, IsDeleted, CreatedBy)
        VALUES
            (@EmployeeCode, @EmployeeNo, @FirstName, @MiddleName, @LastName, @ArabicName, @Gender, @DateOfBirth,
             @MaritalStatus, @NationalityCountryId, @Religion, @BloodGroup, @MobileNumber, @Extension,
             @PersonalEmail, @WorkEmail, @Address, @Neighborhood, @Block, @StreetName, @BuildingNumber,
             @FloorNumber, @FlatNumber, @PaciNumber, @Landmark, @PhotoPath, @EmergencyContactName,
             @EmergencyContactPhone, @EmergencyContactRelation,
             @FatherName, @FatherOccupation, @FatherMobileNumber, ISNULL(@FatherIsDeceased, 0), @CurrentResidenceCountryId,
             @PassportNumber, @PassportFullName, @PassportSurname, @PassportPlaceOfIssue, @PassportExpiryDate,
             @PassportFirstPagePath, @PassportLastPagePath,
             @CivilIdNumber, @CivilIdName, @CivilIdExpiryDate, @CivilIdFrontPath, @CivilIdBackPath,
             @CompanyId, @BranchId, @DepartmentId, @SectionId, @PositionId, @DesignationId, @GradeId,
             @CostCenterId, @WorkLocationId, @ReportingManagerId, @HireDate, @ProbationEndDate,
             @TerminationDate, @EmploymentType, ISNULL(@EmploymentStatus, N'Active'), @NoticePeriodDays,
             @CompanyPhone, @CompanyAssets, 0, @UserId);

        SET @NewId = SCOPE_IDENTITY();

        /* db/20: payroll & bank - only create the 1:1 row when something was entered */
        IF COALESCE(CAST(@BasicSalary AS NVARCHAR(40)), CAST(@Allowances AS NVARCHAR(40)), @BankName, @Iban) IS NOT NULL
            INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, Allowances, BankName, Iban, CreatedBy)
            VALUES (@NewId, @BasicSalary, @Allowances, @BankName, @Iban, @UserId);
        SET @ResultMessage = N'Employee created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ================================= */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF NULLIF(LTRIM(RTRIM(@EmployeeNo)), N'') IS NULL
        BEGIN
            SELECT @ResultCode    = 'EMPLOYEE_NO_REQUIRED',
                   @ResultMessage = N'Employee No is required.';
            RETURN;
        END;

        IF @EmployeeCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeCode = @EmployeeCode AND EmployeeId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That employee code is already in use. Enter a different code.';
            RETURN;
        END;

        IF EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeNo = @EmployeeNo AND EmployeeId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_EMPLOYEE_NO',
                   @ResultMessage = N'That employee No is already in use. Enter a different one.';
            RETURN;
        END;

        -- An employee cannot be set as their own reporting manager.
        IF @ReportingManagerId = @Id
        BEGIN
            SELECT @ResultCode    = 'INVALID_MANAGER',
                   @ResultMessage = N'An employee cannot report to themselves.';
            RETURN;
        END;

        UPDATE [Employee].[Employees]
           SET EmployeeCode             = @EmployeeCode,
               EmployeeNo               = @EmployeeNo,
               FirstName                = @FirstName,
               MiddleName               = @MiddleName,
               LastName                 = @LastName,
               ArabicName               = @ArabicName,
               Gender                   = @Gender,
               DateOfBirth              = @DateOfBirth,
               MaritalStatus            = @MaritalStatus,
               NationalityCountryId     = @NationalityCountryId,
               Religion                 = @Religion,
               BloodGroup               = @BloodGroup,
               MobileNumber             = @MobileNumber,
               Extension                = @Extension,
               PersonalEmail            = @PersonalEmail,
               WorkEmail                = @WorkEmail,
               Address                  = @Address,
               Neighborhood             = @Neighborhood,
               Block                    = @Block,
               StreetName               = @StreetName,
               BuildingNumber           = @BuildingNumber,
               FloorNumber              = @FloorNumber,
               FlatNumber               = @FlatNumber,
               PaciNumber               = @PaciNumber,
               Landmark                 = @Landmark,
               PhotoPath                = @PhotoPath,
               EmergencyContactName     = @EmergencyContactName,
               EmergencyContactPhone    = @EmergencyContactPhone,
               EmergencyContactRelation = @EmergencyContactRelation,
               FatherName               = @FatherName,
               FatherOccupation         = @FatherOccupation,
               FatherMobileNumber       = @FatherMobileNumber,
               FatherIsDeceased         = ISNULL(@FatherIsDeceased, 0),
               CurrentResidenceCountryId = @CurrentResidenceCountryId,
               PassportNumber           = @PassportNumber,
               PassportFullName         = @PassportFullName,
               PassportSurname          = @PassportSurname,
               PassportPlaceOfIssue     = @PassportPlaceOfIssue,
               PassportExpiryDate       = @PassportExpiryDate,
               PassportFirstPagePath    = @PassportFirstPagePath,
               PassportLastPagePath     = @PassportLastPagePath,
               CivilIdNumber            = @CivilIdNumber,
               CivilIdName              = @CivilIdName,
               CivilIdExpiryDate        = @CivilIdExpiryDate,
               CivilIdFrontPath         = @CivilIdFrontPath,
               CivilIdBackPath          = @CivilIdBackPath,
               CompanyId                = @CompanyId,
               BranchId                 = @BranchId,
               DepartmentId             = @DepartmentId,
               SectionId                = @SectionId,
               PositionId               = @PositionId,
               DesignationId            = @DesignationId,
               GradeId                  = @GradeId,
               CostCenterId             = @CostCenterId,
               WorkLocationId           = @WorkLocationId,
               ReportingManagerId       = @ReportingManagerId,
               HireDate                 = @HireDate,
               ProbationEndDate         = @ProbationEndDate,
               TerminationDate          = @TerminationDate,
               EmploymentType           = @EmploymentType,
               EmploymentStatus         = ISNULL(@EmploymentStatus, N'Active'),
               NoticePeriodDays         = @NoticePeriodDays,
               CompanyPhone             = @CompanyPhone,
               CompanyAssets            = @CompanyAssets,
               ModifiedBy               = @UserId,
               ModifiedDate             = SYSUTCDATETIME()
         WHERE EmployeeId = @Id;

        /* db/20: payroll & bank upsert (1:1) */
        IF EXISTS (SELECT 1 FROM [Employee].[EmployeePayroll] WHERE EmployeeId = @Id)
        BEGIN
            UPDATE [Employee].[EmployeePayroll]
               SET BasicSalary  = @BasicSalary,
                   Allowances   = @Allowances,
                   BankName     = @BankName,
                   Iban         = @Iban,
                   ModifiedBy   = @UserId,
                   ModifiedDate = SYSUTCDATETIME()
             WHERE EmployeeId = @Id;
        END
        ELSE IF COALESCE(CAST(@BasicSalary AS NVARCHAR(40)), CAST(@Allowances AS NVARCHAR(40)), @BankName, @Iban) IS NOT NULL
        BEGIN
            INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, Allowances, BankName, Iban, CreatedBy)
            VALUES (@Id, @BasicSalary, @Allowances, @BankName, @Iban, @UserId);
        END;

        SET @NewId = @Id;
        SET @ResultMessage = N'Employee updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ================================= */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE ReportingManagerId = @Id)
        OR EXISTS (SELECT 1 FROM [Core].[Departments] WHERE ManagerEmployeeId = @Id)
        OR EXISTS (SELECT 1 FROM [Security].[Users] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This employee is referenced elsewhere (as a manager or a system login) and cannot be deleted. Deactivate instead.';
            RETURN;
        END;

        DELETE FROM [Employee].[Dependents]        WHERE EmployeeId = @Id;
        DELETE FROM [Kuwait].[EmployeeCompliance]  WHERE EmployeeId = @Id;
        DELETE FROM [Employee].[EmployeePayroll]   WHERE EmployeeId = @Id;
        DELETE FROM [Employee].[Employees]         WHERE EmployeeId = @Id;

        SET @ResultMessage = N'Employee deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ================================== */
    -- Employee uses IsDeleted, not IsActive, so TOGGLE flips that instead -
    -- semantics identical to every other master's TOGGLE from the caller's
    -- point of view (activate / deactivate one record).
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists.';
            RETURN;
        END;

        UPDATE [Employee].[Employees]
           SET IsDeleted    = CASE WHEN IsDeleted = 1 THEN 0 ELSE 1 END,
               ModifiedBy   = @UserId,
               ModifiedDate = SYSUTCDATETIME()
         WHERE EmployeeId = @Id;

        SELECT @ResultMessage = CASE WHEN IsDeleted = 0
                                     THEN N'Employee activated.'
                                     ELSE N'Employee deactivated.' END
        FROM [Employee].[Employees]
        WHERE EmployeeId = @Id;

        RETURN;
    END;
END;
GO

CREATE OR ALTER PROCEDURE [Employee].[usp_Dashboard_Get]
    @Action        VARCHAR(10),
    @CompanyId     INT   = NULL,   -- NULL = all companies
    @CompanyIds    NVARCHAR(2000) = NULL,   -- db/24: comma-separated ids, NULL = all
    @MonthStart    DATE  = NULL    -- first day of the selected month; NULL = this month
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today       DATE = CAST(SYSDATETIME() AS DATE);
    SET @MonthStart = DATEFROMPARTS(YEAR(ISNULL(@MonthStart, @Today)), MONTH(ISNULL(@MonthStart, @Today)), 1);

    DECLARE @MonthEnd    DATE = EOMONTH(@MonthStart);
    DECLARE @AsOf        DATE = CASE WHEN @MonthEnd > @Today THEN @Today ELSE @MonthEnd END;
    DECLARE @PrevStart   DATE = DATEADD(MONTH, -1, @MonthStart);
    DECLARE @PrevEnd     DATE = EOMONTH(@PrevStart);
    DECLARE @Horizon     DATE = DATEADD(DAY, 30, @Today);

    /* Employees in scope (company filter, not soft-deleted) */
    DECLARE @Emp TABLE (
        EmployeeId BIGINT PRIMARY KEY, FullName NVARCHAR(250), DepartmentId INT,
        HireDate DATE, TerminationDate DATE, EmploymentStatus NVARCHAR(20),
        DateOfBirth DATE, ProbationEndDate DATE,
        CreatedDate DATETIME2(0), ModifiedDate DATETIME2(0));

    INSERT INTO @Emp
    SELECT e.EmployeeId,
           LTRIM(RTRIM(CONCAT(e.FirstName, N' ', ISNULL(e.LastName, N'')))),
           e.DepartmentId, e.HireDate, e.TerminationDate, e.EmploymentStatus,
           e.DateOfBirth, e.ProbationEndDate, e.CreatedDate, e.ModifiedDate
    FROM [Employee].[Employees] e
    WHERE e.IsDeleted = 0
      AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
      AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0);

    /* ======================= KPI ================================== */
    IF @Action = 'KPI'
    BEGIN
        SELECT
            TotalEmployees      = SUM(CASE WHEN x.OnBooks = 1 THEN 1 ELSE 0 END),
            PrevTotalEmployees  = SUM(CASE WHEN x.OnBooksPrev = 1 THEN 1 ELSE 0 END),
            ActiveEmployees     = SUM(CASE WHEN x.OnBooks = 1 AND x.EmploymentStatus IN (N'Active', N'Probation') THEN 1 ELSE 0 END),
            OnLeave             = SUM(CASE WHEN x.OnBooks = 1 AND x.EmploymentStatus = N'OnLeave' THEN 1 ELSE 0 END),
            NewJoiners          = SUM(CASE WHEN x.HireDate BETWEEN @MonthStart AND @MonthEnd THEN 1 ELSE 0 END),
            PrevNewJoiners      = SUM(CASE WHEN x.HireDate BETWEEN @PrevStart  AND @PrevEnd  THEN 1 ELSE 0 END),
            Separations         = SUM(CASE WHEN x.TerminationDate BETWEEN @MonthStart AND @MonthEnd THEN 1 ELSE 0 END),
            PrevSeparations     = SUM(CASE WHEN x.TerminationDate BETWEEN @PrevStart  AND @PrevEnd  THEN 1 ELSE 0 END)
        FROM (
            SELECT e.*,
                   OnBooks = CASE WHEN (e.HireDate IS NULL OR e.HireDate <= @AsOf)
                                   AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned')
                                            AND (e.TerminationDate IS NULL OR e.TerminationDate <= @AsOf))
                                   AND (e.TerminationDate IS NULL OR e.TerminationDate > @AsOf)
                                  THEN 1 ELSE 0 END,
                   OnBooksPrev = CASE WHEN (e.HireDate IS NULL OR e.HireDate <= @PrevEnd)
                                       AND (e.TerminationDate IS NULL OR e.TerminationDate > @PrevEnd)
                                      THEN 1 ELSE 0 END
            FROM @Emp e
        ) x;
        RETURN;
    END;

    /* ======================= TREND ================================ */
    IF @Action = 'TREND'
    BEGIN
        DECLARE @Months TABLE (MonthStart DATE PRIMARY KEY, MonthEnd DATE, AsOf DATE);
        DECLARE @i INT = 11;
        DECLARE @m DATE;
        WHILE @i >= 0
        BEGIN
            SET @m = DATEADD(MONTH, -@i, @MonthStart);
            INSERT INTO @Months VALUES (@m, EOMONTH(@m), CASE WHEN EOMONTH(@m) > @Today THEN @Today ELSE EOMONTH(@m) END);
            SET @i -= 1;
        END;

        DECLARE @HasPayroll BIT = CASE WHEN OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL THEN 0 ELSE 1 END;
        DECLARE @Pay TABLE (EmployeeId BIGINT PRIMARY KEY, Gross DECIMAL(14,3));
        IF @HasPayroll = 1
            INSERT INTO @Pay
            EXEC (N'SELECT EmployeeId, ISNULL(BasicSalary, 0) + ISNULL(Allowances, 0) FROM [Employee].[EmployeePayroll]');

        SELECT  m.MonthStart,
                Headcount = (SELECT COUNT(1) FROM @Emp e
                             WHERE (e.HireDate IS NULL OR e.HireDate <= m.AsOf)
                               AND (e.TerminationDate IS NULL OR e.TerminationDate > m.AsOf)
                               AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)),
                Joiners   = (SELECT COUNT(1) FROM @Emp e WHERE e.HireDate BETWEEN m.MonthStart AND m.MonthEnd),
                Leavers   = (SELECT COUNT(1) FROM @Emp e WHERE e.TerminationDate BETWEEN m.MonthStart AND m.MonthEnd),
                GrossPayroll = CASE WHEN @HasPayroll = 0 THEN NULL ELSE
                               (SELECT ISNULL(SUM(p.Gross), 0) FROM @Emp e JOIN @Pay p ON p.EmployeeId = e.EmployeeId
                                WHERE (e.HireDate IS NULL OR e.HireDate <= m.AsOf)
                                  AND (e.TerminationDate IS NULL OR e.TerminationDate > m.AsOf)
                                  AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)) END
        FROM @Months m
        ORDER BY m.MonthStart;
        RETURN;
    END;

    /* ======================= DEPT ================================= */
    IF @Action = 'DEPT'
    BEGIN
        SELECT  DepartmentName = ISNULL(d.DepartmentName, N'Unassigned'),
                Headcount      = COUNT(1)
        FROM        @Emp e
        LEFT JOIN   [Core].[Departments] d ON d.DepartmentId = e.DepartmentId
        WHERE       (e.HireDate IS NULL OR e.HireDate <= @Today)
                AND (e.TerminationDate IS NULL OR e.TerminationDate > @Today)
                AND e.EmploymentStatus NOT IN (N'Terminated', N'Resigned')
        GROUP BY    ISNULL(d.DepartmentName, N'Unassigned')
        ORDER BY    COUNT(1) DESC, ISNULL(d.DepartmentName, N'Unassigned');
        RETURN;
    END;

    /* ======================= PAYROLL ============================== */
    IF @Action = 'PAYROLL'
    BEGIN
        IF OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL
        BEGIN
            SELECT EmployeesWithSalary = 0, TotalBasic = CAST(NULL AS DECIMAL(14,3)),
                   TotalAllowances = CAST(NULL AS DECIMAL(14,3)), Gross = CAST(NULL AS DECIMAL(14,3));
            RETURN;
        END;

        DECLARE @PayrollSql NVARCHAR(MAX) = N'
            SELECT  EmployeesWithSalary = COUNT(1),
                    TotalBasic          = SUM(ISNULL(p.BasicSalary, 0)),
                    TotalAllowances     = SUM(ISNULL(p.Allowances, 0)),
                    Gross               = SUM(ISNULL(p.BasicSalary, 0) + ISNULL(p.Allowances, 0))
            FROM    [Employee].[EmployeePayroll] p
            JOIN    [Employee].[Employees] e ON e.EmployeeId = p.EmployeeId
            WHERE   e.IsDeleted = 0
              AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
              AND   (@CompanyIds IS NULL OR CHARINDEX(N'','' + CAST(e.CompanyId AS VARCHAR(12)) + N'','', N'','' + REPLACE(@CompanyIds, N'' '', N'''') + N'','') > 0)
              AND   (e.HireDate IS NULL OR e.HireDate <= @AsOf)
              AND   (e.TerminationDate IS NULL OR e.TerminationDate > @AsOf)
              AND   e.EmploymentStatus NOT IN (N''Terminated'', N''Resigned'');';
        EXEC sys.sp_executesql @PayrollSql, N'@CompanyId INT, @CompanyIds NVARCHAR(2000), @AsOf DATE', @CompanyId, @CompanyIds, @AsOf;
        RETURN;
    END;

    /* ======================= ACTIONS ============================== */
    IF @Action = 'ACTIONS'
    BEGIN
        -- #temp (not a table variable) so the dynamic SQL below can see it
        CREATE TABLE #Live (EmployeeId BIGINT PRIMARY KEY);
        INSERT INTO #Live
        SELECT EmployeeId FROM @Emp e
        WHERE (e.TerminationDate IS NULL OR e.TerminationDate > @Today)
          AND e.EmploymentStatus NOT IN (N'Terminated', N'Resigned');

        DECLARE @MandatoryMissing INT = NULL;
        IF OBJECT_ID(N'[Documents].[vw_DocumentTypes]', N'V') IS NOT NULL
           AND OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]', N'U') IS NOT NULL
        BEGIN
            DECLARE @MissingSql NVARCHAR(MAX) = N'
                SELECT @n = COUNT(DISTINCT l.EmployeeId)
                FROM #Live l
                CROSS JOIN [Documents].[vw_DocumentTypes] v
                WHERE v.IsActive = 1 AND v.Attachment_Mandatory = 1
                  AND NOT EXISTS (SELECT 1 FROM [Documents].[EmployeeDocumentAttachments] a
                                  WHERE a.EmployeeId = l.EmployeeId
                                    AND a.DocumentTypeId = v.DocumentTypeId AND a.IsDeleted = 0);';
            EXEC sys.sp_executesql @MissingSql, N'@n INT OUTPUT', @MandatoryMissing OUTPUT;
        END;

        SELECT
            DocumentsExpiring = (SELECT COUNT(DISTINCT c.EmployeeId)
                                 FROM [Kuwait].[EmployeeCompliance] c JOIN #Live l ON l.EmployeeId = c.EmployeeId
                                 WHERE c.CivilIdExpiryDate    BETWEEN @Today AND @Horizon
                                    OR c.PassportExpiryDate   BETWEEN @Today AND @Horizon
                                    OR c.ResidencyExpiryDate  BETWEEN @Today AND @Horizon
                                    OR c.WorkPermitExpiryDate BETWEEN @Today AND @Horizon),
            DocumentsExpired  = (SELECT COUNT(DISTINCT c.EmployeeId)
                                 FROM [Kuwait].[EmployeeCompliance] c JOIN #Live l ON l.EmployeeId = c.EmployeeId
                                 WHERE c.CivilIdExpiryDate    < @Today
                                    OR c.PassportExpiryDate   < @Today
                                    OR c.ResidencyExpiryDate  < @Today
                                    OR c.WorkPermitExpiryDate < @Today),
            ProbationEnding   = (SELECT COUNT(1) FROM @Emp e JOIN #Live l ON l.EmployeeId = e.EmployeeId
                                 WHERE e.ProbationEndDate BETWEEN @Today AND @Horizon),
            MandatoryDocumentsMissing = @MandatoryMissing;
        RETURN;
    END;

    /* ======================= EVENTS =============================== */
    IF @Action = 'EVENTS'
    BEGIN
        ;WITH live AS (
            SELECT * FROM @Emp e
            WHERE (e.TerminationDate IS NULL OR e.TerminationDate > @Today)
              AND e.EmploymentStatus NOT IN (N'Terminated', N'Resigned')
        ),
        birthdays AS (
            SELECT l.EmployeeId, l.FullName,
                   NextDate = CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, l.DateOfBirth, @Today), l.DateOfBirth) < @Today
                                   THEN DATEADD(YEAR, DATEDIFF(YEAR, l.DateOfBirth, @Today) + 1, l.DateOfBirth)
                                   ELSE DATEADD(YEAR, DATEDIFF(YEAR, l.DateOfBirth, @Today), l.DateOfBirth) END
            FROM live l WHERE l.DateOfBirth IS NOT NULL
        ),
        anniversaries AS (
            SELECT l.EmployeeId, l.FullName, l.HireDate,
                   NextDate = CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, l.HireDate, @Today), l.HireDate) < @Today
                                   THEN DATEADD(YEAR, DATEDIFF(YEAR, l.HireDate, @Today) + 1, l.HireDate)
                                   ELSE DATEADD(YEAR, DATEDIFF(YEAR, l.HireDate, @Today), l.HireDate) END
            FROM live l WHERE l.HireDate IS NOT NULL
        ),
        expiries AS (
            SELECT l.EmployeeId, l.FullName, v.Doc, v.ExpiryDate
            FROM live l
            JOIN [Kuwait].[EmployeeCompliance] c ON c.EmployeeId = l.EmployeeId
            CROSS APPLY (VALUES (N'Civil ID',    c.CivilIdExpiryDate),
                                (N'Passport',    c.PassportExpiryDate),
                                (N'Residency',   c.ResidencyExpiryDate),
                                (N'Work permit', c.WorkPermitExpiryDate)) v(Doc, ExpiryDate)
            WHERE v.ExpiryDate BETWEEN @Today AND @Horizon
        ),
        allEvents AS (
            SELECT EventType = 'BIRTHDAY', EmployeeId, FullName, EventDate = NextDate, Detail = N'Birthday'
            FROM birthdays WHERE NextDate BETWEEN @Today AND @Horizon
            UNION ALL
            SELECT 'ANNIVERSARY', EmployeeId, FullName, NextDate,
                   CONCAT(DATEDIFF(YEAR, HireDate, NextDate), N' year', CASE WHEN DATEDIFF(YEAR, HireDate, NextDate) = 1 THEN N'' ELSE N's' END, N' with the company')
            FROM anniversaries WHERE NextDate BETWEEN @Today AND @Horizon AND DATEDIFF(YEAR, HireDate, NextDate) >= 1
            UNION ALL
            SELECT 'EXPIRY', EmployeeId, FullName, ExpiryDate, CONCAT(Doc, N' expires') FROM expiries
            UNION ALL
            SELECT 'PROBATION', EmployeeId, FullName, ProbationEndDate, N'Probation ends'
            FROM live WHERE ProbationEndDate BETWEEN @Today AND @Horizon
        )
        SELECT TOP (15) EventType, EmployeeId, EmployeeName = FullName, EventDate, Detail
        FROM allEvents
        ORDER BY EventDate, EventType, FullName;
        RETURN;
    END;

    /* ======================= ACTIVITY ============================= */
    IF @Action = 'ACTIVITY'
    BEGIN
        DECLARE @Activity TABLE (EmployeeId BIGINT, EmployeeName NVARCHAR(250), Activity NVARCHAR(200), ActivityDate DATETIME2(0), Status NVARCHAR(30));

        INSERT INTO @Activity
        SELECT TOP (10) EmployeeId, FullName, N'New employee added', CreatedDate, N'Completed'
        FROM @Emp WHERE CreatedDate IS NOT NULL ORDER BY CreatedDate DESC;

        INSERT INTO @Activity
        SELECT TOP (10) EmployeeId, FullName, N'Profile updated', ModifiedDate, N'Updated'
        FROM @Emp WHERE ModifiedDate IS NOT NULL AND ModifiedDate > DATEADD(MINUTE, 1, CreatedDate)
        ORDER BY ModifiedDate DESC;

        INSERT INTO @Activity
        SELECT TOP (10) e.EmployeeId, e.FullName, N'Kuwait compliance updated', ISNULL(c.ModifiedDate, c.CreatedDate), N'Updated'
        FROM [Kuwait].[EmployeeCompliance] c JOIN @Emp e ON e.EmployeeId = c.EmployeeId
        ORDER BY ISNULL(c.ModifiedDate, c.CreatedDate) DESC;

        IF OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]', N'U') IS NOT NULL
           AND OBJECT_ID(N'[Documents].[vw_DocumentTypes]', N'V') IS NOT NULL
        BEGIN
            DECLARE @DocActivity TABLE (EmployeeId BIGINT, Activity NVARCHAR(200), ActivityDate DATETIME2(0));
            INSERT INTO @DocActivity
            EXEC (N'SELECT TOP (10) a.EmployeeId, CONCAT(N''Uploaded '', v.DocumentTypeName), a.UploadedDate
                    FROM [Documents].[EmployeeDocumentAttachments] a
                    JOIN [Documents].[vw_DocumentTypes] v ON v.DocumentTypeId = a.DocumentTypeId
                    ORDER BY a.UploadedDate DESC');

            INSERT INTO @Activity
            SELECT d.EmployeeId, e.FullName, d.Activity, d.ActivityDate, N'Uploaded'
            FROM @DocActivity d JOIN @Emp e ON e.EmployeeId = d.EmployeeId;
        END;

        SELECT TOP (8) EmployeeId, EmployeeName, Activity, ActivityDate, Status
        FROM @Activity
        ORDER BY ActivityDate DESC;
        RETURN;
    END;
END;
GO

PRINT N'db/24 applied: @CompanyIds company filter added to list procedures and the dashboard.';
GO
