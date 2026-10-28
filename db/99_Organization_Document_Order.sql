/* =====================================================================
   99_Organization_Document_Order.sql  -  HRMS: drag organization
                                          document types into order
   ---------------------------------------------------------------------
   Run after 75 (and 98). Safe to re-run. Replaces
   Documents.usp_OrgDocumentType_Manage of db/75 - do not run db/75 again
   after this script.

     1. Documents.usp_OrgDocumentType_Manage: the list's default order is
        now its own sequence (SortOrder) - SortColumn 'SortOrder'; the
        other columns still sort it.
     2. Documents.usp_OrgDocumentType_Reorder: the ids in their new order
        (Organization > Organization Documents, dragged) numbered 1..n;
        a type not in the list keeps its place after them. The company
        documents page (Workforce > Organizations) shows each category's
        documents in this sequence.
     3. Labels (English + Arabic).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Documents].[OrganizationDocumentTypes]', N'U') IS NULL
   OR COL_LENGTH(N'Documents.OrganizationDocumentTypes', N'IssuingAuthorityId') IS NULL
    RAISERROR (N'Run db/73 and db/75 first.', 16, 1);
GO

/* ---- 1. the list in its own sequence ---- */
CREATE OR ALTER PROCEDURE [Documents].[usp_OrgDocumentType_Manage]
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
    @TypeName          NVARCHAR(150)   = NULL,
    @ArabicName        NVARCHAR(150)   = NULL,
    @Category          VARCHAR(20)     = NULL,
    @IsMandatory       BIT             = NULL,
    @HasNumber         BIT             = NULL,
    @HasIssueDate      BIT             = NULL,
    @HasExpiryDate     BIT             = NULL,
    @AlertRules        VARCHAR(60)     = NULL,
    @IssuingAuthorityId INT            = NULL,
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
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @TypeName   = NULLIF(LTRIM(RTRIM(@TypeName)), N'');
    SET @ArabicName = NULLIF(LTRIM(RTRIM(@ArabicName)), N'');
    SET @AlertRules = NULLIF(REPLACE(LTRIM(RTRIM(@AlertRules)), ' ', ''), '');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 500 THEN 500 ELSE @PageSize END;
    /* db/99: the list's own sequence (SortOrder, dragged on Organization > Organization Documents) is the default */
    SET @SortColumn = CASE WHEN @SortColumn IN ('SortOrder', 'TypeName', 'Category', 'IsMandatory', 'IsActive', 'UsageCount') THEN @SortColumn ELSE 'SortOrder' END;
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
            SELECT  t.OrgDocumentTypeId, t.TypeName, t.ArabicName, t.Category, t.IsMandatory, t.HasNumber, t.HasIssueDate,
                    t.HasExpiryDate, t.AlertRules, t.SortOrder, t.IsActive,
                    t.IssuingAuthorityId, ia.AuthorityName, ia.ArabicName AS AuthorityNameAr, ia.ShortName AS AuthorityShortName,
                    (SELECT COUNT(1) FROM [Documents].[OrganizationDocuments] d
                      WHERE d.OrgDocumentTypeId = t.OrgDocumentTypeId AND d.Deleted = 0 AND d.State = 'C') AS UsageCount,
                    CASE t.Category WHEN 'LICENSE' THEN 1 WHEN 'REGISTRATION' THEN 2 WHEN 'AUTHORIZATION' THEN 3
                                    WHEN 'CONTRACT' THEN 4 WHEN 'INSURANCE' THEN 5 ELSE 6 END AS CategorySeq
            FROM    [Documents].[OrganizationDocumentTypes] AS t
            LEFT JOIN [Documents].[IssuingAuthorities] AS ia ON ia.IssuingAuthorityId = t.IssuingAuthorityId
            WHERE   t.Deleted = 0
              AND   (@Action = 'LIST' OR t.OrgDocumentTypeId = @Id)
              AND   (@IsActiveFilter IS NULL OR t.IsActive = @IsActiveFilter)
              AND   (@Search IS NULL OR t.TypeName LIKE N'%' + @Search + N'%' OR t.ArabicName LIKE N'%' + @Search + N'%'
                     OR ia.AuthorityName LIKE N'%' + @Search + N'%' OR ia.ShortName LIKE N'%' + @Search + N'%')
        ),
        sorted AS (
            SELECT  x.*,
                    ROW_NUMBER() OVER (ORDER BY
                        CASE WHEN @SortColumn = 'SortOrder'   AND @SortDirection = 'ASC'  THEN ISNULL(x.SortOrder, 2147483647) END ASC,
                        CASE WHEN @SortColumn = 'SortOrder'   AND @SortDirection = 'DESC' THEN ISNULL(x.SortOrder, 2147483647) END DESC,
                        CASE WHEN @SortColumn = 'TypeName'    AND @SortDirection = 'ASC'  THEN x.TypeName END ASC,
                        CASE WHEN @SortColumn = 'TypeName'    AND @SortDirection = 'DESC' THEN x.TypeName END DESC,
                        CASE WHEN @SortColumn = 'IsMandatory' AND @SortDirection = 'ASC'  THEN x.IsMandatory END ASC,
                        CASE WHEN @SortColumn = 'IsMandatory' AND @SortDirection = 'DESC' THEN x.IsMandatory END DESC,
                        CASE WHEN @SortColumn = 'IsActive'    AND @SortDirection = 'ASC'  THEN x.IsActive END ASC,
                        CASE WHEN @SortColumn = 'IsActive'    AND @SortDirection = 'DESC' THEN x.IsActive END DESC,
                        CASE WHEN @SortColumn = 'UsageCount'  AND @SortDirection = 'ASC'  THEN x.UsageCount END ASC,
                        CASE WHEN @SortColumn = 'UsageCount'  AND @SortDirection = 'DESC' THEN x.UsageCount END DESC,
                        CASE WHEN @SortColumn = 'Category'    AND @SortDirection = 'DESC' THEN x.CategorySeq END DESC,
                        x.CategorySeq, ISNULL(x.SortOrder, 2147483647), x.TypeName) AS RowNo,
                    COUNT(1) OVER () AS TotalRows
            FROM    x
        )
        SELECT  *
        INTO    #Page
        FROM    sorted
        WHERE   @Action = 'GET' OR (RowNo > (@PageNumber - 1) * @PageSize AND RowNo <= @PageNumber * @PageSize);

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #Page;
        SELECT OrgDocumentTypeId, TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate,
               AlertRules, SortOrder, IsActive, UsageCount, IssuingAuthorityId, AuthorityName, AuthorityNameAr, AuthorityShortName
        FROM   #Page
        ORDER BY RowNo;
        RETURN;
    END;

    /* ======================= INSERT / UPDATE ====================== */
    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        IF @TypeName IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the document type name.'; RETURN; END;
        IF ISNULL(@Category, '') NOT IN ('LICENSE', 'REGISTRATION', 'AUTHORIZATION', 'CONTRACT', 'INSURANCE', 'OTHER') SET @Category = 'OTHER';
        IF ISNULL(@HasExpiryDate, 0) = 0 SET @AlertRules = NULL;   -- alerts are on the expiry date
        /* every alert is M|W|D + 0..99 */
        IF @AlertRules IS NOT NULL AND EXISTS (
            SELECT 1 FROM STRING_SPLIT(@AlertRules, ',') s
            WHERE  LEN(s.value) < 2 OR LEFT(s.value, 1) NOT IN ('M', 'W', 'D')
               OR  TRY_CAST(SUBSTRING(s.value, 2, 3) AS INT) IS NULL
               OR  TRY_CAST(SUBSTRING(s.value, 2, 3) AS INT) NOT BETWEEN 0 AND 99)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The alerts could not be read.'; RETURN; END;
        IF @IssuingAuthorityId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [Documents].[IssuingAuthorities] WHERE IssuingAuthorityId = @IssuingAuthorityId AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the issuing authority from the list.'; RETURN; END;
        IF EXISTS (SELECT 1 FROM [Documents].[OrganizationDocumentTypes]
                   WHERE Deleted = 0 AND TypeName = @TypeName AND OrgDocumentTypeId <> ISNULL(@Id, 0))
        BEGIN SELECT @ResultCode = 'DUPLICATE_NAME', @ResultMessage = N'An organization document type with this name already exists.'; RETURN; END;

        IF @Action = 'INSERT'
        BEGIN
            INSERT INTO [Documents].[OrganizationDocumentTypes]
                (TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate, AlertRules, IssuingAuthorityId, SortOrder, IsActive, CreatedBy)
            VALUES (@TypeName, @ArabicName, @Category, ISNULL(@IsMandatory, 0), ISNULL(@HasNumber, 1), ISNULL(@HasIssueDate, 1),
                    ISNULL(@HasExpiryDate, 1), @AlertRules, @IssuingAuthorityId,
                    ISNULL(@SortOrder, (SELECT ISNULL(MAX(SortOrder), 0) + 1 FROM [Documents].[OrganizationDocumentTypes] WHERE Deleted = 0)),
                    ISNULL(@IsActive, 1), @UserId);
            SELECT @NewId = SCOPE_IDENTITY(), @ResultMessage = N'Organization document type added.';
            RETURN;
        END;

        UPDATE [Documents].[OrganizationDocumentTypes]
           SET TypeName = @TypeName, ArabicName = @ArabicName, Category = @Category, IsMandatory = ISNULL(@IsMandatory, 0),
               HasNumber = ISNULL(@HasNumber, 1), HasIssueDate = ISNULL(@HasIssueDate, 1), HasExpiryDate = ISNULL(@HasExpiryDate, 1),
               AlertRules = @AlertRules, IssuingAuthorityId = @IssuingAuthorityId, SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, IsActive),
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE OrgDocumentTypeId = @Id AND Deleted = 0;
        IF @@ROWCOUNT = 0
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        SELECT @NewId = @Id, @ResultMessage = N'Organization document type saved.';
        RETURN;
    END;

    /* ======================= TOGGLE / DELETE ====================== */
    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Documents].[OrganizationDocumentTypes]
           SET IsActive = 1 - IsActive, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE OrgDocumentTypeId = @Id AND Deleted = 0;
        SELECT @NewId = @Id, @ResultMessage = N'Status changed.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Documents].[OrganizationDocuments] WHERE OrgDocumentTypeId = @Id AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Companies keep documents of this type. Deactivate it instead.'; RETURN; END;
        UPDATE [Documents].[OrganizationDocumentTypes]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE OrgDocumentTypeId = @Id AND Deleted = 0;
        SELECT @NewId = @Id, @ResultMessage = N'Organization document type deleted.';
        RETURN;
    END;
END;
GO

/* ------------------------------------------------------------------
   2. Documents.usp_OrgDocumentType_Reorder
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Documents].[usp_OrgDocumentType_Reorder]
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
                 (SELECT 1 FROM [Documents].[OrganizationDocumentTypes] t WHERE t.OrgDocumentTypeId = s.TypeId AND t.Deleted = 0))
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
        RETURN;
    END;

    /* the sent ids 1..n, then every other type in its current order */
    DECLARE @SentCount INT = (SELECT COUNT(1) FROM #Sent);
    CREATE TABLE #Final (TypeId INT NOT NULL PRIMARY KEY, Seq INT NOT NULL);
    INSERT INTO #Final (TypeId, Seq) SELECT TypeId, Pos FROM #Sent;
    INSERT INTO #Final (TypeId, Seq)
    SELECT t.OrgDocumentTypeId,
           @SentCount + ROW_NUMBER() OVER (ORDER BY ISNULL(t.SortOrder, 2147483647), t.TypeName, t.OrgDocumentTypeId)
    FROM   [Documents].[OrganizationDocumentTypes] t
    WHERE  t.Deleted = 0 AND NOT EXISTS (SELECT 1 FROM #Sent s WHERE s.TypeId = t.OrgDocumentTypeId);

    UPDATE t
    SET    t.SortOrder = f.Seq
    FROM   [Documents].[OrganizationDocumentTypes] t
    JOIN   #Final f ON f.TypeId = t.OrgDocumentTypeId
    WHERE  ISNULL(t.SortOrder, -1) <> f.Seq;

    SELECT @NewId = @SentCount, @ResultMessage = N'Order saved.';
END;
GO

/* ---- 3. labels ----------------------------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('org.od_order', 'org', N'Order', N'الترتيب', NULL),
        ('org.od_drag_hint', 'org', N'Drag a row by its grip (or use the arrow keys on it) to change the sequence - it is saved at once.', N'اسحب الصف من المقبض (أو استخدم مفاتيح الأسهم عليه) لتغيير الترتيب - يُحفظ فوراً.', NULL),
        ('org.od_drag_off_hint', 'org', N'Sorted by a column or filtered: click Order to go back to the sequence and drag rows again.', N'مرتب حسب عمود أو مُصفّى: انقر على الترتيب للعودة إلى التسلسل وسحب الصفوف مجدداً.', NULL),
        ('org.od_drag_handle', 'org', N'Move {0}', N'نقل {0}', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Organization document order labels inserted: ', @LabelsInserted);
GO
