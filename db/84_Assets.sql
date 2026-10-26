/* =====================================================================
   84_Assets.sql  -  HRMS: Assets (company cars, motor bikes, phones ...)
   ---------------------------------------------------------------------
   Run after 83. Safe to re-run. Then run 85 (labels).

   Company property handed to employees - each asset has a type, brand,
   model, colour, serial / plate number, purchase date and an expiry
   date (registration, insurance, warranty ...) with ALERTS before it,
   and the employee who uses it. Handing it to someone else or taking it
   back is kept as history.

     1. Assets.AssetTypes        what kind of asset (Setup > Organization >
                                 Asset Types): name, icon, whether it has an
                                 expiry date, what that date is called, and
                                 the alerts ('M3,M1,W1' = 3 months, 1 month
                                 and 1 week before; D0 = on the day)
     2. Assets.Assets            one asset of one company
     3. Assets.AssetAssignments  who used it, from / to
     4. Assets.usp_AssetType_Manage  the Setup tab (master envelope)
     5. Assets.usp_Asset_Manage
          LIST     the assets (company scope, type, status, search, paging)
          SUMMARY  counts for the page: per type and per status
          GET      one asset
          SAVE     add / change; a new holder closes the previous assignment
          RETURN   take it back from its holder (available again)
          DELETE   soft delete
          HISTORY  its assignments
          DUE      assets whose expiry date reached an alert (Dashboard);
                   an expired asset stays due until its date is renewed
          EMPLOYEE the assets an employee holds (profile)
     6. Permissions ASSET_VIEW / ASSET_EDIT / ASSET_DELETE (System
        Administrator; give them to other roles on Security > Create Roles)
     7. Starter types (only when there are none)

   Nothing is ever physically deleted (db/28).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Assets')
    EXEC (N'CREATE SCHEMA [Assets]');
GO

/* ------------------------------------------------------------------
   1. Assets.AssetTypes
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Assets].[AssetTypes]', N'U') IS NULL
BEGIN
    CREATE TABLE [Assets].[AssetTypes](
        AssetTypeId        INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_AssetTypes PRIMARY KEY,
        TypeName           NVARCHAR(100)  NOT NULL,
        ArabicName         NVARCHAR(100)  NULL,
        /* CAR, BIKE, PHONE, LAPTOP, TABLET, KEY, TOOL, OTHER - the icon and colour on screen */
        Icon               VARCHAR(12)    NOT NULL CONSTRAINT DF_AssetTypes_Icon DEFAULT ('OTHER'),
        HasExpiryDate      BIT            NOT NULL CONSTRAINT DF_AssetTypes_HasExpiry DEFAULT (1),
        /* what the expiry date is: "Registration (Daftar) expiry", "Warranty expiry" ... */
        ExpiryLabel        NVARCHAR(80)   NULL,
        ExpiryLabelAr      NVARCHAR(80)   NULL,
        /* alerts before the expiry date: M = months, W = weeks, D = days; 'M1,W2,D0' */
        AlertRules         VARCHAR(60)    NULL,
        SortOrder          INT            NULL,
        IsActive           BIT            NOT NULL CONSTRAINT DF_AssetTypes_IsActive DEFAULT (1),
        CreatedBy          BIGINT         NULL,
        CreatedDate        DATETIME2(0)   NOT NULL CONSTRAINT DF_AssetTypes_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy         BIGINT         NULL,
        ModifiedDate       DATETIME2(0)   NULL,
        Deleted            BIT            NOT NULL CONSTRAINT DF_AssetTypes_Deleted DEFAULT (0),
        DeletedBy          BIGINT         NULL,
        DeletedDate        DATETIME2(0)   NULL,
        CONSTRAINT CK_AssetTypes_Icon CHECK (Icon IN ('CAR', 'BIKE', 'PHONE', 'LAPTOP', 'TABLET', 'KEY', 'TOOL', 'OTHER'))
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_AssetTypes_Name ON [Assets].[AssetTypes] (TypeName) WHERE Deleted = 0;');
    PRINT N'Created [Assets].[AssetTypes].';
END
GO

/* ------------------------------------------------------------------
   2. Assets.Assets
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Assets].[Assets]', N'U') IS NULL
BEGIN
    CREATE TABLE [Assets].[Assets](
        AssetId            BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Assets PRIMARY KEY,
        CompanyId          INT            NOT NULL,
        AssetTypeId        INT            NOT NULL,
        AssetCode          NVARCHAR(30)   NOT NULL,       -- AST-00001 when left blank
        Brand              NVARCHAR(100)  NULL,
        Model              NVARCHAR(100)  NULL,
        Color              NVARCHAR(50)   NULL,
        SerialNumber       NVARCHAR(100)  NULL,           -- plate / IMEI / serial
        PurchaseDate       DATE           NULL,
        PurchaseCost       DECIMAL(12, 3) NULL,
        ExpiryDate         DATE           NULL,
        AssignedEmployeeId BIGINT         NULL,
        AssignedDate       DATE           NULL,
        Notes              NVARCHAR(500)  NULL,
        IsActive           BIT            NOT NULL CONSTRAINT DF_Assets_IsActive DEFAULT (1),   -- 0 = retired (sold, scrapped)
        CreatedBy          BIGINT         NULL,
        CreatedDate        DATETIME2(0)   NOT NULL CONSTRAINT DF_Assets_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy         BIGINT         NULL,
        ModifiedDate       DATETIME2(0)   NULL,
        Deleted            BIT            NOT NULL CONSTRAINT DF_Assets_Deleted DEFAULT (0),
        DeletedBy          BIGINT         NULL,
        DeletedDate        DATETIME2(0)   NULL,
        CONSTRAINT FK_Assets_Company  FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_Assets_Type     FOREIGN KEY (AssetTypeId) REFERENCES [Assets].[AssetTypes](AssetTypeId),
        CONSTRAINT FK_Assets_Employee FOREIGN KEY (AssignedEmployeeId) REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT CK_Assets_Dates    CHECK (ExpiryDate IS NULL OR PurchaseDate IS NULL OR ExpiryDate >= PurchaseDate),
        CONSTRAINT CK_Assets_Cost     CHECK (PurchaseCost IS NULL OR PurchaseCost >= 0)
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_Assets_Code ON [Assets].[Assets] (CompanyId, AssetCode) WHERE Deleted = 0;');
    EXEC (N'CREATE NONCLUSTERED INDEX IX_Assets_Expiry ON [Assets].[Assets] (ExpiryDate) INCLUDE (CompanyId, AssetTypeId) WHERE Deleted = 0 AND IsActive = 1;');
    EXEC (N'CREATE NONCLUSTERED INDEX IX_Assets_Employee ON [Assets].[Assets] (AssignedEmployeeId) WHERE Deleted = 0;');
    PRINT N'Created [Assets].[Assets].';
END
GO

/* ------------------------------------------------------------------
   3. Assets.AssetAssignments
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Assets].[AssetAssignments]', N'U') IS NULL
BEGIN
    CREATE TABLE [Assets].[AssetAssignments](
        AssignmentId       BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_AssetAssignments PRIMARY KEY,
        AssetId            BIGINT         NOT NULL,
        EmployeeId         BIGINT         NOT NULL,
        FromDate           DATE           NOT NULL,
        ToDate             DATE           NULL,              -- NULL = still holds it
        Remarks            NVARCHAR(300)  NULL,
        CreatedBy          BIGINT         NULL,
        CreatedDate        DATETIME2(0)   NOT NULL CONSTRAINT DF_AssetAssignments_Created DEFAULT (SYSUTCDATETIME()),
        ClosedBy           BIGINT         NULL,
        Deleted            BIT            NOT NULL CONSTRAINT DF_AssetAssignments_Deleted DEFAULT (0),
        DeletedBy          BIGINT         NULL,
        DeletedDate        DATETIME2(0)   NULL,
        CONSTRAINT FK_AssetAssignments_Asset    FOREIGN KEY (AssetId) REFERENCES [Assets].[Assets](AssetId),
        CONSTRAINT FK_AssetAssignments_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees](EmployeeId)
    );
    EXEC (N'CREATE NONCLUSTERED INDEX IX_AssetAssignments_Asset ON [Assets].[AssetAssignments] (AssetId, FromDate) WHERE Deleted = 0;');
    PRINT N'Created [Assets].[AssetAssignments].';
END
GO

/* ------------------------------------------------------------------
   4. Assets.usp_AssetType_Manage - Setup > Organization > Asset Types
      (the master envelope every Organization Setup tab uses)
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Assets].[usp_AssetType_Manage]
    @Action            VARCHAR(10),
    @Id                BIGINT          = NULL,
    @UserId            BIGINT          = NULL,
    /* LIST */
    @Search            NVARCHAR(200)   = NULL,
    @IsActiveFilter    BIT             = NULL,
    @CompanyId         INT             = NULL,     -- envelope only: the types are group-wide
    @CompanyIds        NVARCHAR(2000)  = NULL,
    @ParentId          INT             = NULL,
    @PageNumber        INT             = 1,
    @PageSize          INT             = 25,
    @SortColumn        VARCHAR(50)     = NULL,
    @SortDirection     VARCHAR(4)      = NULL,
    /* INSERT / UPDATE */
    @TypeName          NVARCHAR(100)   = NULL,
    @ArabicName        NVARCHAR(100)   = NULL,
    @Icon              VARCHAR(12)     = NULL,
    @HasExpiryDate     BIT             = NULL,
    @ExpiryLabel       NVARCHAR(80)    = NULL,
    @ExpiryLabelAr     NVARCHAR(80)    = NULL,
    @AlertRules        VARCHAR(60)     = NULL,
    @SortOrder         INT             = NULL,
    @IsActive          BIT             = NULL,

    @TotalCount        INT             = NULL OUTPUT,
    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @Search        = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @TypeName      = NULLIF(LTRIM(RTRIM(@TypeName)), N'');
    SET @ArabicName    = NULLIF(LTRIM(RTRIM(@ArabicName)), N'');
    SET @ExpiryLabel   = NULLIF(LTRIM(RTRIM(@ExpiryLabel)), N'');
    SET @ExpiryLabelAr = NULLIF(LTRIM(RTRIM(@ExpiryLabelAr)), N'');
    SET @AlertRules    = NULLIF(REPLACE(LTRIM(RTRIM(@AlertRules)), ' ', ''), '');
    SET @PageNumber    = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 500 THEN 500 ELSE @PageSize END;
    SET @SortColumn    = CASE WHEN @SortColumn IN ('TypeName', 'IsActive', 'UsageCount', 'SortOrder') THEN @SortColumn ELSE 'SortOrder' END;
    SET @SortDirection = CASE WHEN UPPER(@SortDirection) = 'DESC' THEN 'DESC' ELSE 'ASC' END;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= LIST / GET =========================== */
    IF @Action IN ('LIST', 'GET')
    BEGIN
        ;WITH x AS (
            SELECT  t.AssetTypeId, t.TypeName, t.ArabicName, t.Icon, t.HasExpiryDate, t.ExpiryLabel, t.ExpiryLabelAr,
                    t.AlertRules, t.SortOrder, t.IsActive,
                    (SELECT COUNT(1) FROM [Assets].[Assets] a WHERE a.AssetTypeId = t.AssetTypeId AND a.Deleted = 0) AS UsageCount
            FROM    [Assets].[AssetTypes] AS t
            WHERE   t.Deleted = 0
              AND   (@Action = 'LIST' OR t.AssetTypeId = @Id)
              AND   (@IsActiveFilter IS NULL OR t.IsActive = @IsActiveFilter)
              AND   (@Search IS NULL OR t.TypeName LIKE N'%' + @Search + N'%' OR t.ArabicName LIKE N'%' + @Search + N'%')
        ),
        sorted AS (
            SELECT  x.*,
                    ROW_NUMBER() OVER (ORDER BY
                        CASE WHEN @SortColumn = 'TypeName'   AND @SortDirection = 'ASC'  THEN x.TypeName END ASC,
                        CASE WHEN @SortColumn = 'TypeName'   AND @SortDirection = 'DESC' THEN x.TypeName END DESC,
                        CASE WHEN @SortColumn = 'IsActive'   AND @SortDirection = 'ASC'  THEN x.IsActive END ASC,
                        CASE WHEN @SortColumn = 'IsActive'   AND @SortDirection = 'DESC' THEN x.IsActive END DESC,
                        CASE WHEN @SortColumn = 'UsageCount' AND @SortDirection = 'ASC'  THEN x.UsageCount END ASC,
                        CASE WHEN @SortColumn = 'UsageCount' AND @SortDirection = 'DESC' THEN x.UsageCount END DESC,
                        CASE WHEN @SortColumn = 'SortOrder'  AND @SortDirection = 'DESC' THEN ISNULL(x.SortOrder, 2147483647) END DESC,
                        ISNULL(x.SortOrder, 2147483647), x.TypeName) AS RowNo,
                    COUNT(1) OVER () AS TotalRows
            FROM    x
        )
        SELECT  *
        INTO    #Page
        FROM    sorted
        WHERE   @Action = 'GET' OR (RowNo > (@PageNumber - 1) * @PageSize AND RowNo <= @PageNumber * @PageSize);

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #Page;
        SELECT AssetTypeId, TypeName, ArabicName, Icon, HasExpiryDate, ExpiryLabel, ExpiryLabelAr, AlertRules, SortOrder, IsActive, UsageCount
        FROM   #Page
        ORDER BY RowNo;
        RETURN;
    END;

    /* ======================= INSERT / UPDATE ====================== */
    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        IF @TypeName IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the asset type name.'; RETURN; END;
        IF ISNULL(@Icon, '') NOT IN ('CAR', 'BIKE', 'PHONE', 'LAPTOP', 'TABLET', 'KEY', 'TOOL', 'OTHER') SET @Icon = 'OTHER';
        IF ISNULL(@HasExpiryDate, 1) = 0 SELECT @AlertRules = NULL, @ExpiryLabel = NULL, @ExpiryLabelAr = NULL;
        /* every alert is M|W|D + 0..99 */
        IF @AlertRules IS NOT NULL AND EXISTS (
            SELECT 1 FROM STRING_SPLIT(@AlertRules, ',') s
            WHERE  LEN(s.value) < 2 OR LEFT(s.value, 1) NOT IN ('M', 'W', 'D')
               OR  TRY_CAST(SUBSTRING(s.value, 2, 3) AS INT) IS NULL
               OR  TRY_CAST(SUBSTRING(s.value, 2, 3) AS INT) NOT BETWEEN 0 AND 99)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The alerts could not be read.'; RETURN; END;
        IF EXISTS (SELECT 1 FROM [Assets].[AssetTypes] WHERE Deleted = 0 AND TypeName = @TypeName AND AssetTypeId <> ISNULL(@Id, 0))
        BEGIN SELECT @ResultCode = 'DUPLICATE_NAME', @ResultMessage = N'An asset type with this name already exists.'; RETURN; END;

        IF @Action = 'INSERT'
        BEGIN
            INSERT INTO [Assets].[AssetTypes]
                (TypeName, ArabicName, Icon, HasExpiryDate, ExpiryLabel, ExpiryLabelAr, AlertRules, SortOrder, IsActive, CreatedBy)
            VALUES (@TypeName, @ArabicName, @Icon, ISNULL(@HasExpiryDate, 1), @ExpiryLabel, @ExpiryLabelAr, @AlertRules,
                    ISNULL(@SortOrder, (SELECT ISNULL(MAX(SortOrder), 0) + 1 FROM [Assets].[AssetTypes] WHERE Deleted = 0)),
                    ISNULL(@IsActive, 1), @UserId);
            SELECT @NewId = SCOPE_IDENTITY(), @ResultMessage = N'Asset type added.';
            RETURN;
        END;

        UPDATE [Assets].[AssetTypes]
           SET TypeName = @TypeName, ArabicName = @ArabicName, Icon = @Icon, HasExpiryDate = ISNULL(@HasExpiryDate, 1),
               ExpiryLabel = @ExpiryLabel, ExpiryLabelAr = @ExpiryLabelAr, AlertRules = @AlertRules,
               SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, IsActive),
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE AssetTypeId = @Id AND Deleted = 0;
        IF @@ROWCOUNT = 0
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        SELECT @NewId = @Id, @ResultMessage = N'Asset type saved.';
        RETURN;
    END;

    /* ======================= TOGGLE / DELETE ====================== */
    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Assets].[AssetTypes]
           SET IsActive = 1 - IsActive, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE AssetTypeId = @Id AND Deleted = 0;
        SELECT @NewId = @Id, @ResultMessage = N'Status changed.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Assets].[Assets] WHERE AssetTypeId = @Id AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Assets of this type exist. Deactivate it instead.'; RETURN; END;
        UPDATE [Assets].[AssetTypes]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE AssetTypeId = @Id AND Deleted = 0;
        SELECT @NewId = @Id, @ResultMessage = N'Asset type deleted.';
        RETURN;
    END;
END;
GO

/* ------------------------------------------------------------------
   5. Assets.usp_Asset_Manage - Workforce > Assets
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Assets].[usp_Asset_Manage]
    @Action             VARCHAR(10),
    @Id                 BIGINT          = NULL,
    @UserCompanyId      INT             = NULL,     -- a user pinned to one company
    @CompanyIds         NVARCHAR(2000)  = NULL,     -- top-bar company filter
    /* LIST */
    @AssetTypeId        INT             = NULL,
    @Status             VARCHAR(10)     = NULL,     -- ASSIGNED, AVAILABLE, EXPIRING, EXPIRED, RETIRED
    @Search             NVARCHAR(200)   = NULL,
    @PageNumber         INT             = 1,
    @PageSize           INT             = 25,
    /* SAVE */
    @CompanyId          INT             = NULL,
    @AssetCode          NVARCHAR(30)    = NULL,
    @Brand              NVARCHAR(100)   = NULL,
    @Model              NVARCHAR(100)   = NULL,
    @Color              NVARCHAR(50)    = NULL,
    @SerialNumber       NVARCHAR(100)   = NULL,
    @PurchaseDate       DATE            = NULL,
    @PurchaseCost       DECIMAL(12, 3)  = NULL,
    @ExpiryDate         DATE            = NULL,
    @EmployeeId         BIGINT          = NULL,     -- SAVE: the holder (NULL = nobody); EMPLOYEE: whose assets
    @AssignedDate       DATE            = NULL,
    @Notes              NVARCHAR(500)   = NULL,
    @IsActive           BIT             = NULL,
    @Remarks            NVARCHAR(300)   = NULL,     -- RETURN / a change of holder
    @UserId             BIGINT          = NULL,

    @TotalCount         INT             = NULL OUTPUT,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(ISNULL(@CompanyIds, N''), N' ', N'') + N',';
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Status = NULLIF(UPPER(LTRIM(RTRIM(@Status))), '');
    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    /* the companies the user may see */
    DECLARE @Co TABLE (CompanyId INT PRIMARY KEY, CompanyName NVARCHAR(400));
    INSERT INTO @Co
    SELECT c.CompanyId, c.CompanyName
    FROM   [Core].[Companies] c
    WHERE  c.Deleted = 0
      AND  (@UserCompanyId IS NULL OR c.CompanyId = @UserCompanyId)
      AND  (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(c.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0);

    /* every asset the user may see, with its state on the expiry date:
       EXPIRED (past), EXPIRING (an alert of its type has fired), OK */
    DECLARE @A TABLE (AssetId BIGINT PRIMARY KEY, ExpiryState VARCHAR(10), DaysLeft INT NULL);
    INSERT INTO @A (AssetId, ExpiryState, DaysLeft)
    SELECT  a.AssetId,
            CASE WHEN a.ExpiryDate IS NULL OR t.HasExpiryDate = 0 THEN 'NONE'
                 WHEN a.ExpiryDate < @Today THEN 'EXPIRED'
                 WHEN EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(t.AlertRules, ''), ',') r
                              WHERE LEN(r.value) >= 2 AND TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT) IS NOT NULL
                                AND CASE LEFT(r.value, 1) WHEN 'M' THEN DATEADD(MONTH, -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), a.ExpiryDate)
                                                          WHEN 'W' THEN DATEADD(WEEK,  -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), a.ExpiryDate)
                                                          ELSE          DATEADD(DAY,   -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), a.ExpiryDate) END <= @Today)
                      THEN 'EXPIRING'
                 ELSE 'OK' END,
            CASE WHEN a.ExpiryDate IS NULL THEN NULL ELSE DATEDIFF(DAY, @Today, a.ExpiryDate) END
    FROM    [Assets].[Assets] a
    JOIN    @Co co ON co.CompanyId = a.CompanyId
    JOIN    [Assets].[AssetTypes] t ON t.AssetTypeId = a.AssetTypeId
    WHERE   a.Deleted = 0;

    /* ======================= LIST ================================= */
    IF @Action = 'LIST'
    BEGIN
        ;WITH x AS (
            SELECT  a.AssetId, a.CompanyId, co.CompanyName, a.AssetTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Icon,
                    t.HasExpiryDate, t.ExpiryLabel, t.ExpiryLabelAr,
                    a.AssetCode, a.Brand, a.Model, a.Color, a.SerialNumber, a.PurchaseDate, a.PurchaseCost, a.ExpiryDate,
                    a.AssignedEmployeeId, a.AssignedDate, a.Notes, a.IsActive,
                    ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                    LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                    s.ExpiryState, s.DaysLeft
            FROM    @A s
            JOIN    [Assets].[Assets] a ON a.AssetId = s.AssetId
            JOIN    @Co co ON co.CompanyId = a.CompanyId
            JOIN    [Assets].[AssetTypes] t ON t.AssetTypeId = a.AssetTypeId
            LEFT JOIN [Employee].[Employees] e ON e.EmployeeId = a.AssignedEmployeeId
            WHERE   (@AssetTypeId IS NULL OR a.AssetTypeId = @AssetTypeId)
              AND   (@Status IS NULL
                     OR (@Status = 'RETIRED'   AND a.IsActive = 0)
                     OR (@Status = 'ASSIGNED'  AND a.IsActive = 1 AND a.AssignedEmployeeId IS NOT NULL)
                     OR (@Status = 'AVAILABLE' AND a.IsActive = 1 AND a.AssignedEmployeeId IS NULL)
                     OR (@Status = 'EXPIRING'  AND a.IsActive = 1 AND s.ExpiryState = 'EXPIRING')
                     OR (@Status = 'EXPIRED'   AND a.IsActive = 1 AND s.ExpiryState = 'EXPIRED'))
              AND   (@Search IS NULL OR a.AssetCode LIKE N'%' + @Search + N'%' OR a.Brand LIKE N'%' + @Search + N'%'
                     OR a.Model LIKE N'%' + @Search + N'%' OR a.SerialNumber LIKE N'%' + @Search + N'%'
                     OR a.Color LIKE N'%' + @Search + N'%' OR e.FirstName LIKE N'%' + @Search + N'%'
                     OR e.LastName LIKE N'%' + @Search + N'%' OR e.EmployeeNo LIKE N'%' + @Search + N'%'
                     OR e.EmployeeCode LIKE N'%' + @Search + N'%')
        )
        SELECT *, COUNT(1) OVER () AS TotalRows
        INTO   #L
        FROM   x;

        SELECT @TotalCount = COUNT(1) FROM #L;
        SELECT  *
        FROM    #L
        ORDER BY IsActive DESC,
                 CASE ExpiryState WHEN 'EXPIRED' THEN 0 WHEN 'EXPIRING' THEN 1 ELSE 2 END,
                 TypeName, AssetCode
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= SUMMARY ============================== */
    IF @Action = 'SUMMARY'
    BEGIN
        /* one row per active type (with its count), and the status totals on every row */
        SELECT  t.AssetTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Icon,
                (SELECT COUNT(1) FROM @A s JOIN [Assets].[Assets] a ON a.AssetId = s.AssetId
                  WHERE a.AssetTypeId = t.AssetTypeId AND a.IsActive = 1) AS TypeCount,
                (SELECT COUNT(1) FROM @A s JOIN [Assets].[Assets] a ON a.AssetId = s.AssetId WHERE a.IsActive = 1) AS TotalCount,
                (SELECT COUNT(1) FROM @A s JOIN [Assets].[Assets] a ON a.AssetId = s.AssetId
                  WHERE a.IsActive = 1 AND a.AssignedEmployeeId IS NOT NULL) AS AssignedCount,
                (SELECT COUNT(1) FROM @A s JOIN [Assets].[Assets] a ON a.AssetId = s.AssetId
                  WHERE a.IsActive = 1 AND a.AssignedEmployeeId IS NULL) AS AvailableCount,
                (SELECT COUNT(1) FROM @A s JOIN [Assets].[Assets] a ON a.AssetId = s.AssetId
                  WHERE a.IsActive = 1 AND s.ExpiryState = 'EXPIRING') AS ExpiringCount,
                (SELECT COUNT(1) FROM @A s JOIN [Assets].[Assets] a ON a.AssetId = s.AssetId
                  WHERE a.IsActive = 1 AND s.ExpiryState = 'EXPIRED') AS ExpiredCount,
                (SELECT COUNT(1) FROM @A s JOIN [Assets].[Assets] a ON a.AssetId = s.AssetId WHERE a.IsActive = 0) AS RetiredCount
        FROM    [Assets].[AssetTypes] t
        WHERE   t.Deleted = 0 AND t.IsActive = 1
        ORDER BY ISNULL(t.SortOrder, 2147483647), t.TypeName;
        RETURN;
    END;

    /* ======================= GET ================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  a.AssetId, a.CompanyId, co.CompanyName, a.AssetTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Icon,
                t.HasExpiryDate, t.ExpiryLabel, t.ExpiryLabelAr,
                a.AssetCode, a.Brand, a.Model, a.Color, a.SerialNumber, a.PurchaseDate, a.PurchaseCost, a.ExpiryDate,
                a.AssignedEmployeeId, a.AssignedDate, a.Notes, a.IsActive,
                ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                s.ExpiryState, s.DaysLeft
        FROM    @A s
        JOIN    [Assets].[Assets] a ON a.AssetId = s.AssetId
        JOIN    @Co co ON co.CompanyId = a.CompanyId
        JOIN    [Assets].[AssetTypes] t ON t.AssetTypeId = a.AssetTypeId
        LEFT JOIN [Employee].[Employees] e ON e.EmployeeId = a.AssignedEmployeeId
        WHERE   a.AssetId = @Id;
        RETURN;
    END;

    /* ======================= HISTORY ============================== */
    IF @Action = 'HISTORY'
    BEGIN
        SELECT  h.AssignmentId, h.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                h.FromDate, h.ToDate, h.Remarks
        FROM    [Assets].[AssetAssignments] h
        JOIN    [Assets].[Assets] a ON a.AssetId = h.AssetId AND a.Deleted = 0
        JOIN    @Co co ON co.CompanyId = a.CompanyId
        JOIN    [Employee].[Employees] e ON e.EmployeeId = h.EmployeeId
        WHERE   h.AssetId = @Id AND h.Deleted = 0
        ORDER BY h.FromDate DESC, h.AssignmentId DESC;
        RETURN;
    END;

    /* ======================= EMPLOYEE ============================= */
    IF @Action = 'EMPLOYEE'
    BEGIN
        SELECT  a.AssetId, a.AssetCode, a.Brand, a.Model, a.Color, a.SerialNumber, a.ExpiryDate, a.AssignedDate,
                t.TypeName, t.ArabicName AS TypeArabicName, t.Icon, s.ExpiryState, s.DaysLeft
        FROM    @A s
        JOIN    [Assets].[Assets] a ON a.AssetId = s.AssetId
        JOIN    [Assets].[AssetTypes] t ON t.AssetTypeId = a.AssetTypeId
        WHERE   a.AssignedEmployeeId = @EmployeeId AND a.IsActive = 1
        ORDER BY t.TypeName, a.AssetCode;
        RETURN;
    END;

    /* ======================= DUE ================================== */
    IF @Action = 'DUE'
    BEGIN
        SELECT TOP (200)
                a.AssetId, a.CompanyId, co.CompanyName, a.AssetCode, a.Brand, a.Model, a.SerialNumber, a.ExpiryDate,
                t.TypeName, t.ArabicName AS TypeArabicName, t.Icon, t.ExpiryLabel, t.ExpiryLabelAr,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, s.DaysLeft
        FROM    @A s
        JOIN    [Assets].[Assets] a ON a.AssetId = s.AssetId
        JOIN    @Co co ON co.CompanyId = a.CompanyId
        JOIN    [Assets].[AssetTypes] t ON t.AssetTypeId = a.AssetTypeId AND t.IsActive = 1
        LEFT JOIN [Employee].[Employees] e ON e.EmployeeId = a.AssignedEmployeeId
        WHERE   a.IsActive = 1 AND s.ExpiryState IN ('EXPIRING', 'EXPIRED')
        ORDER BY a.ExpiryDate, t.TypeName, a.AssetCode;
        RETURN;
    END;

    /* ======================= SAVE ================================= */
    IF @Action = 'SAVE'
    BEGIN
        SET @AssetCode    = NULLIF(LTRIM(RTRIM(@AssetCode)), N'');
        SET @Brand        = NULLIF(LTRIM(RTRIM(@Brand)), N'');
        SET @Model        = NULLIF(LTRIM(RTRIM(@Model)), N'');
        SET @Color        = NULLIF(LTRIM(RTRIM(@Color)), N'');
        SET @SerialNumber = NULLIF(LTRIM(RTRIM(@SerialNumber)), N'');
        SET @Notes        = NULLIF(LTRIM(RTRIM(@Notes)), N'');
        SET @Remarks      = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

        DECLARE @Old TABLE (CompanyId INT, AssignedEmployeeId BIGINT NULL);
        IF @Id IS NOT NULL AND @Id > 0
        BEGIN
            INSERT INTO @Old SELECT a.CompanyId, a.AssignedEmployeeId
            FROM [Assets].[Assets] a JOIN @Co co ON co.CompanyId = a.CompanyId WHERE a.AssetId = @Id AND a.Deleted = 0;
            IF NOT EXISTS (SELECT 1 FROM @Old)
            BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That asset no longer exists. Refresh and try again.'; RETURN; END;
            SELECT @CompanyId = CompanyId FROM @Old;    -- an asset stays in its company
        END;

        IF @CompanyId IS NULL OR NOT EXISTS (SELECT 1 FROM @Co WHERE CompanyId = @CompanyId)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the company the asset belongs to.'; RETURN; END;
        IF NOT EXISTS (SELECT 1 FROM [Assets].[AssetTypes] WHERE AssetTypeId = @AssetTypeId AND Deleted = 0
                       AND (IsActive = 1 OR @AssetTypeId = (SELECT AssetTypeId FROM [Assets].[Assets] WHERE AssetId = ISNULL(@Id, 0))))
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the asset type.'; RETURN; END;
        IF @Brand IS NULL AND @Model IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the brand or the model.'; RETURN; END;
        IF @ExpiryDate IS NOT NULL AND @PurchaseDate IS NOT NULL AND @ExpiryDate < @PurchaseDate
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The expiry date cannot be before the purchase date.'; RETURN; END;
        IF @PurchaseCost < 0
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The purchase cost cannot be negative.'; RETURN; END;
        IF @EmployeeId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [Employee].[Employees]
                                                   WHERE EmployeeId = @EmployeeId AND CompanyId = @CompanyId AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose an employee of the asset''s company.'; RETURN; END;
        IF @AssetCode IS NOT NULL AND EXISTS (SELECT 1 FROM [Assets].[Assets]
                                              WHERE CompanyId = @CompanyId AND AssetCode = @AssetCode AND Deleted = 0 AND AssetId <> ISNULL(@Id, 0))
        BEGIN SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'Another asset of this company already has this code.'; RETURN; END;
        /* a retired asset is held by nobody */
        IF ISNULL(@IsActive, 1) = 0 SET @EmployeeId = NULL;
        SET @AssignedDate = CASE WHEN @EmployeeId IS NULL THEN NULL ELSE ISNULL(@AssignedDate, @Today) END;

        BEGIN TRANSACTION;
            IF @Id IS NULL OR @Id = 0
            BEGIN
                IF @AssetCode IS NULL
                BEGIN
                    DECLARE @Next INT = (SELECT ISNULL(MAX(TRY_CAST(SUBSTRING(AssetCode, 5, 20) AS INT)), 0) + 1
                                         FROM [Assets].[Assets] WITH (UPDLOCK, HOLDLOCK)
                                         WHERE CompanyId = @CompanyId AND AssetCode LIKE N'AST-%');
                    SET @AssetCode = CONCAT(N'AST-', RIGHT(CONCAT(N'0000', @Next), CASE WHEN @Next > 99999 THEN LEN(@Next) ELSE 5 END));
                END;
                INSERT INTO [Assets].[Assets]
                    (CompanyId, AssetTypeId, AssetCode, Brand, Model, Color, SerialNumber, PurchaseDate, PurchaseCost, ExpiryDate,
                     AssignedEmployeeId, AssignedDate, Notes, IsActive, CreatedBy)
                VALUES (@CompanyId, @AssetTypeId, @AssetCode, @Brand, @Model, @Color, @SerialNumber, @PurchaseDate, @PurchaseCost, @ExpiryDate,
                        @EmployeeId, @AssignedDate, @Notes, ISNULL(@IsActive, 1), @UserId);
                SET @NewId = SCOPE_IDENTITY();
                SET @ResultMessage = CONCAT(N'Asset ', @AssetCode, N' added.');
            END
            ELSE
            BEGIN
                /* a new holder: close the previous assignment */
                IF EXISTS (SELECT 1 FROM @Old WHERE ISNULL(AssignedEmployeeId, 0) <> ISNULL(@EmployeeId, 0))
                    UPDATE [Assets].[AssetAssignments]
                       SET ToDate = CASE WHEN @AssignedDate IS NOT NULL AND @AssignedDate > FromDate THEN DATEADD(DAY, -1, @AssignedDate)
                                         WHEN @Today > FromDate THEN @Today ELSE FromDate END,
                           ClosedBy = @UserId, Remarks = ISNULL(Remarks, @Remarks)
                     WHERE AssetId = @Id AND ToDate IS NULL AND Deleted = 0;
                ELSE
                    SET @AssignedDate = ISNULL(@AssignedDate, (SELECT AssignedDate FROM [Assets].[Assets] WHERE AssetId = @Id));

                UPDATE [Assets].[Assets]
                   SET AssetTypeId = @AssetTypeId, AssetCode = ISNULL(@AssetCode, AssetCode), Brand = @Brand, Model = @Model,
                       Color = @Color, SerialNumber = @SerialNumber, PurchaseDate = @PurchaseDate, PurchaseCost = @PurchaseCost,
                       ExpiryDate = @ExpiryDate, AssignedEmployeeId = @EmployeeId, AssignedDate = @AssignedDate, Notes = @Notes,
                       IsActive = ISNULL(@IsActive, IsActive), ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE AssetId = @Id;
                SET @NewId = @Id;
                SET @ResultMessage = N'Asset saved.';
            END;

            /* the holder's assignment row (a new or changed holder) */
            IF @EmployeeId IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [Assets].[AssetAssignments]
                               WHERE AssetId = @NewId AND EmployeeId = @EmployeeId AND ToDate IS NULL AND Deleted = 0)
                INSERT INTO [Assets].[AssetAssignments] (AssetId, EmployeeId, FromDate, Remarks, CreatedBy)
                VALUES (@NewId, @EmployeeId, @AssignedDate, @Remarks, @UserId);
        COMMIT;
        RETURN;
    END;

    /* ======================= RETURN =============================== */
    IF @Action = 'RETURN'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Assets].[Assets] a JOIN @Co co ON co.CompanyId = a.CompanyId
                       WHERE a.AssetId = @Id AND a.Deleted = 0 AND a.AssignedEmployeeId IS NOT NULL)
        BEGIN SELECT @ResultCode = 'NOT_ASSIGNED', @ResultMessage = N'This asset is not held by anyone.'; RETURN; END;
        BEGIN TRANSACTION;
            UPDATE [Assets].[AssetAssignments]
               SET ToDate = CASE WHEN @Today > FromDate THEN @Today ELSE FromDate END, ClosedBy = @UserId,
                   Remarks = CASE WHEN @Remarks IS NULL THEN Remarks ELSE LEFT(CONCAT(Remarks + N' · ', @Remarks), 300) END
             WHERE AssetId = @Id AND ToDate IS NULL AND Deleted = 0;
            UPDATE [Assets].[Assets]
               SET AssignedEmployeeId = NULL, AssignedDate = NULL, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE AssetId = @Id;
        COMMIT;
        SET @ResultMessage = N'Asset returned - it is available again.';
        RETURN;
    END;

    /* ======================= DELETE =============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Assets].[Assets] a JOIN @Co co ON co.CompanyId = a.CompanyId WHERE a.AssetId = @Id AND a.Deleted = 0)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That asset no longer exists.'; RETURN; END;
        BEGIN TRANSACTION;
            UPDATE [Assets].[AssetAssignments]
               SET ToDate = CASE WHEN @Today > FromDate THEN @Today ELSE FromDate END, ClosedBy = @UserId
             WHERE AssetId = @Id AND ToDate IS NULL AND Deleted = 0;
            UPDATE [Assets].[Assets]
               SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
             WHERE AssetId = @Id AND Deleted = 0;
        COMMIT;
        SET @ResultMessage = N'Asset deleted.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ------------------------------------------------------------------
   6. Permissions (System Administrator, the first time)
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action) VALUES
    ('ASSET_VIEW',   'Assets', 'View'),
    ('ASSET_EDIT',   'Assets', 'Edit'),
    ('ASSET_DELETE', 'Assets', 'Delete');

UPDATE c SET IsNew = 1 FROM #Codes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #Codes c WHERE c.IsNew = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] r
JOIN   [Security].[Permissions] p ON p.Deleted = 0
JOIN   #Codes c ON c.PermissionCode = p.PermissionCode AND c.IsNew = 1
WHERE  r.RoleCode = N'SYSADMIN' AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId AND rp.Deleted = 0);

DECLARE @CodesCreated INT = (SELECT COUNT(1) FROM #Codes WHERE IsNew = 1);
PRINT CONCAT(N'Asset permission codes created: ', @CodesCreated, N' (users see them after signing in again).');
DROP TABLE #Codes;
GO

/* ------------------------------------------------------------------
   7. Starter types (only when there are none) - change freely
   ------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM [Assets].[AssetTypes] WHERE Deleted = 0)
BEGIN
    INSERT INTO [Assets].[AssetTypes] (TypeName, ArabicName, Icon, HasExpiryDate, ExpiryLabel, ExpiryLabelAr, AlertRules, SortOrder)
    VALUES
        (N'Cars',          N'سيارات',           'CAR',    1, N'Registration (Daftar) expiry', N'انتهاء الدفتر (الترخيص)', 'M1,W2,W1,D0', 1),
        (N'Motor Bikes',   N'دراجات نارية',     'BIKE',   1, N'Registration expiry',          N'انتهاء الترخيص',          'M1,W2,D0',    2),
        (N'Mobile Phones', N'هواتف محمولة',     'PHONE',  1, N'Warranty expiry',              N'انتهاء الضمان',           'M1,D0',       3),
        (N'Laptops',       N'أجهزة لابتوب',     'LAPTOP', 1, N'Warranty expiry',              N'انتهاء الضمان',           'M1,D0',       4),
        (N'Tablets',       N'أجهزة لوحية',      'TABLET', 1, N'Warranty expiry',              N'انتهاء الضمان',           'M1,D0',       5),
        (N'Access Cards & Keys', N'بطاقات ومفاتيح', 'KEY', 0, NULL, NULL, NULL, 6),
        (N'Tools & Equipment', N'أدوات ومعدات', 'TOOL',   1, N'Calibration / service due',    N'موعد المعايرة / الصيانة', 'M1,W1',       7);
    PRINT N'Asset starter types added.';
END
GO
