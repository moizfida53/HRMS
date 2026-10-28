/* =====================================================================
   100_Asset_Type_Order.sql  -  HRMS: drag asset types into order
   ---------------------------------------------------------------------
   Run after 84 (and 99). Safe to re-run. Replaces Assets.usp_Asset_Manage
   of db/84 - do not run db/84 again after this script.

     1. Assets.usp_AssetType_Reorder: the ids in their new order
        (Organization > Asset Types, dragged) numbered 1..n; a type not in
        the list keeps its place after them.
     2. Assets.usp_Asset_Manage: Workforce > Assets lists the assets in that
        sequence of their type (the type buttons were already in it), and
        so does the employee profile.
     3. Labels (English + Arabic).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Assets].[AssetTypes]', N'U') IS NULL
    RAISERROR (N'Run db/84 first.', 16, 1);
GO

/* ------------------------------------------------------------------
   1. Assets.usp_AssetType_Reorder
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Assets].[usp_AssetType_Reorder]
    @Ids               NVARCHAR(MAX),              -- type ids, comma separated, in their new order
    @UserId            BIGINT          = NULL,

    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0;

    /* the list, in order (no STRING_SPLIT: it does not promise the order) */
    CREATE TABLE #Sent (Pos INT IDENTITY(1, 1) PRIMARY KEY, TypeId INT NOT NULL UNIQUE);
    DECLARE @Rest NVARCHAR(MAX) = ISNULL(@Ids, N'') + N',', @At INT, @Token NVARCHAR(50);
    WHILE CHARINDEX(N',', @Rest) > 0
    BEGIN
        SET @At    = CHARINDEX(N',', @Rest);
        SET @Token = LTRIM(RTRIM(LEFT(@Rest, @At - 1)));
        SET @Rest  = STUFF(@Rest, 1, @At, N'');
        IF @Token = N'' CONTINUE;
        IF TRY_CAST(@Token AS INT) IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The new order could not be read.';
            RETURN;
        END;
        IF NOT EXISTS (SELECT 1 FROM #Sent WHERE TypeId = CAST(@Token AS INT))
            INSERT INTO #Sent (TypeId) VALUES (CAST(@Token AS INT));
    END;

    IF NOT EXISTS (SELECT 1 FROM #Sent)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The new order could not be read.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM #Sent s WHERE NOT EXISTS
                 (SELECT 1 FROM [Assets].[AssetTypes] t WHERE t.AssetTypeId = s.TypeId AND t.Deleted = 0))
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
        RETURN;
    END;

    /* the sent ids 1..n, then every other type in its current order */
    DECLARE @SentCount INT = (SELECT COUNT(1) FROM #Sent);
    CREATE TABLE #Final (TypeId INT NOT NULL PRIMARY KEY, Seq INT NOT NULL);
    INSERT INTO #Final (TypeId, Seq) SELECT TypeId, Pos FROM #Sent;
    INSERT INTO #Final (TypeId, Seq)
    SELECT t.AssetTypeId,
           @SentCount + ROW_NUMBER() OVER (ORDER BY ISNULL(t.SortOrder, 2147483647), t.TypeName, t.AssetTypeId)
    FROM   [Assets].[AssetTypes] t
    WHERE  t.Deleted = 0 AND NOT EXISTS (SELECT 1 FROM #Sent s WHERE s.TypeId = t.AssetTypeId);

    UPDATE t
    SET    t.SortOrder = f.Seq
    FROM   [Assets].[AssetTypes] t
    JOIN   #Final f ON f.TypeId = t.AssetTypeId
    WHERE  ISNULL(t.SortOrder, -1) <> f.Seq;

    SELECT @NewId = @SentCount, @ResultMessage = N'Order saved.';
END;
GO

/* ---- 2. assets listed in their type's sequence ---- */
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
                    ISNULL(t.SortOrder, 2147483647) AS TypeSeq,      -- db/100: the sequence set on Organization > Asset Types
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
                 TypeSeq, TypeName, AssetCode
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
        ORDER BY ISNULL(t.SortOrder, 2147483647), t.TypeName, a.AssetCode;
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
        ORDER BY a.ExpiryDate, ISNULL(t.SortOrder, 2147483647), t.TypeName, a.AssetCode;
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

/* ---- 3. labels ----------------------------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('as.type_drag_hint', 'as', N'Drag a row by its grip (or use the arrow keys on it) to change the sequence - Workforce > Assets shows the types in it.', N'اسحب الصف من المقبض (أو استخدم مفاتيح الأسهم عليه) لتغيير الترتيب - تعرض صفحة الأصول الأنواع بهذا الترتيب.', NULL),
        ('as.type_drag_off_hint', 'as', N'Sorted by a column or filtered: click Order to go back to the sequence and drag rows again.', N'مرتب حسب عمود أو مُصفّى: انقر على الترتيب للعودة إلى التسلسل وسحب الصفوف مجدداً.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Asset type order labels inserted: ', @LabelsInserted);
GO
