/* =====================================================================
   63_Document_Types_Setup.sql  -  HRMS: Organization > Employee Documents
   ---------------------------------------------------------------------
   Run after 19 and 22. Safe to re-run.

   Administrators maintain the document types employees upload (name,
   Arabic name, section, mandatory or optional) on a new Organization tab,
   and add a Document Section on the spot (the "+" next to Section).

     1. Documents.DocumentTypes gets an IsActive column - ONLY when it has
        no active flag of its own (IsActive / Is_Active / IsDeleted /
        Active) - so a type can be deactivated instead of deleted - and a
        SortOrder column, only when it has no sort column of its own.
     2. [Documents].[vw_DocumentTypes] regenerated (same rules as db/22)
        so it sees that column.
     3. Documents.usp_DocumentType_Manage - LIST / GET / INSERT / UPDATE /
        DELETE / TOGGLE (the Organization Setup envelope).
        Documents.DocumentTypes pre-dates the numbered scripts and its
        column names differ between databases, so every write is built
        from the columns found in sys.columns (key, English / Arabic name,
        active flag, sort order, created / modified columns); any other
        NOT NULL column without a default gets a neutral value (the name
        for text, 0 for numbers, now for dates).
        DELETE only removes a type no employee file has ever used -
        otherwise deactivate it (files keep their history).
     4. Documents.usp_DocumentSection_Manage - LIST / INSERT (the "+").
     5. Labels (English + Arabic).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Documents].[DocumentTypes]', N'U') IS NULL
   OR OBJECT_ID(N'[Documents].[DocumentSections]', N'U') IS NULL
   OR OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]', N'U') IS NULL
    RAISERROR(N'Run db/19 and db/22 first.', 16, 1);
GO

/* ------------------------------------------------------------------
   1. An active flag on Documents.DocumentTypes (only when it has none)
   ------------------------------------------------------------------ */
IF COL_LENGTH(N'Documents.DocumentTypes', N'IsActive') IS NULL
   AND COL_LENGTH(N'Documents.DocumentTypes', N'Is_Active') IS NULL
   AND COL_LENGTH(N'Documents.DocumentTypes', N'IsDeleted') IS NULL
   AND COL_LENGTH(N'Documents.DocumentTypes', N'Active') IS NULL
BEGIN
    ALTER TABLE [Documents].[DocumentTypes] ADD [IsActive] BIT NOT NULL
        CONSTRAINT [DF_DocumentTypes_IsActive] DEFAULT (1) WITH VALUES;
    PRINT N'Added [Documents].[DocumentTypes].[IsActive].';
END
GO

/* a sort column too (only when it has none), so the drag order on the
   Organization tab can be saved (db/64) */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID(N'[Documents].[DocumentTypes]')
                 AND name IN (N'Seq_num', N'SeqNum', N'Seq_No', N'SeqNo', N'SortOrder', N'Sort_Order', N'DisplayOrder', N'Display_Order', N'OrderNo'))
BEGIN
    ALTER TABLE [Documents].[DocumentTypes] ADD [SortOrder] INT NULL;
    PRINT N'Added [Documents].[DocumentTypes].[SortOrder].';
END
GO

/* ------------------------------------------------------------------
   2. [Documents].[vw_DocumentTypes] (copy of db/22 section 1)
   ------------------------------------------------------------------ */
DECLARE @obj INT = OBJECT_ID(N'[Documents].[DocumentTypes]');

DECLARE @Cols TABLE (name SYSNAME, type_name SYSNAME, is_char BIT, is_identity BIT, column_id INT);
INSERT INTO @Cols
SELECT c.name, t.name,
       CASE WHEN t.name IN (N'nvarchar', N'varchar', N'nchar', N'char') THEN 1 ELSE 0 END,
       c.is_identity, c.column_id
FROM sys.columns c
JOIN sys.types   t ON t.user_type_id = c.user_type_id
WHERE c.object_id = @obj;

-- Primary key (single column), falling back to the identity column
DECLARE @IdCol SYSNAME =
    (SELECT TOP 1 c.name
     FROM sys.indexes i
     JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
     JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
     WHERE i.object_id = @obj AND i.is_primary_key = 1
     ORDER BY ic.key_ordinal);
IF @IdCol IS NULL SET @IdCol = (SELECT TOP 1 name FROM @Cols WHERE is_identity = 1);

-- Arabic name column: a text column whose name says Arabic
DECLARE @ArCol SYSNAME =
    (SELECT TOP 1 name FROM @Cols
     WHERE is_char = 1
       AND (name LIKE N'%Arabic%' OR name LIKE N'%Arb%' OR name LIKE N'%[_]Ar' OR name LIKE N'%NameAr%'
            OR name LIKE N'%Ar[_]Name%' OR name LIKE N'%[_]AR[_]%')
     ORDER BY CASE WHEN name LIKE N'%Name%' THEN 0 ELSE 1 END, column_id);

-- English name column: a text column with Name in it that is not the Arabic one
DECLARE @NameCol SYSNAME =
    (SELECT TOP 1 name FROM @Cols
     WHERE is_char = 1 AND name <> ISNULL(@ArCol, N'')
       AND (name LIKE N'%Name%' OR name IN (N'DocumentType', N'Doc_Type', N'Title', N'Description'))
     ORDER BY CASE WHEN name LIKE N'%Eng%'  THEN 0
                   WHEN name LIKE N'%Type%Name%' OR name LIKE N'%Name%Type%' THEN 1
                   WHEN name LIKE N'%Name%' THEN 2
                   ELSE 3 END,
              column_id);

DECLARE @ActiveExpr NVARCHAR(200) =
    CASE WHEN EXISTS (SELECT 1 FROM @Cols WHERE name = N'IsActive')  THEN N'CAST(ISNULL(dt.[IsActive], 1) AS BIT)'
         WHEN EXISTS (SELECT 1 FROM @Cols WHERE name = N'Is_Active') THEN N'CAST(ISNULL(dt.[Is_Active], 1) AS BIT)'
         WHEN EXISTS (SELECT 1 FROM @Cols WHERE name = N'IsDeleted') THEN N'CAST(CASE WHEN ISNULL(dt.[IsDeleted], 0) = 0 THEN 1 ELSE 0 END AS BIT)'
         WHEN EXISTS (SELECT 1 FROM @Cols WHERE name = N'Active')    THEN N'CAST(ISNULL(dt.[Active], 1) AS BIT)'
         ELSE N'CAST(1 AS BIT)' END;

DECLARE @SortCol SYSNAME =
    (SELECT TOP 1 name FROM @Cols
     WHERE name IN (N'Seq_num', N'SeqNum', N'Seq_No', N'SeqNo', N'SortOrder', N'Sort_Order', N'DisplayOrder', N'Display_Order', N'OrderNo')
     ORDER BY column_id);

IF @IdCol IS NULL OR @NameCol IS NULL
BEGIN
    RAISERROR(N'Could not detect the key / name columns of [Documents].[DocumentTypes]. Edit section 1 of this script to set @IdCol and @NameCol by hand.', 16, 1);
    RETURN;
END;

IF (SELECT type_name FROM @Cols WHERE name = @IdCol) NOT IN (N'int', N'smallint', N'tinyint', N'bigint')
BEGIN
    RAISERROR(N'[Documents].[DocumentTypes] key column is not an integer type; the attachments table expects an INT DocumentTypeId.', 16, 1);
    RETURN;
END;

PRINT N'vw_DocumentTypes mapping -> DocumentTypeId = ' + QUOTENAME(@IdCol)
    + N', DocumentTypeName = ' + QUOTENAME(@NameCol)
    + N', DocumentTypeNameAr = ' + ISNULL(QUOTENAME(@ArCol), N'(none found)')
    + N', IsActive = ' + @ActiveExpr
    + N', SortOrder = ' + ISNULL(QUOTENAME(@SortCol), N'(none)');

DECLARE @View NVARCHAR(MAX) = N'
CREATE OR ALTER VIEW [Documents].[vw_DocumentTypes]
AS
/* Generated by db/22 / db/63 from the real columns of
   [Documents].[DocumentTypes]. Re-run 22 or 63 to regenerate. */
SELECT  CAST(dt.' + QUOTENAME(@IdCol) + N' AS INT)                       AS DocumentTypeId,
        CAST(dt.' + QUOTENAME(@NameCol) + N' AS NVARCHAR(200))           AS DocumentTypeName,
        ' + CASE WHEN @ArCol IS NULL THEN N'CAST(NULL AS NVARCHAR(200))'
                 ELSE N'CAST(dt.' + QUOTENAME(@ArCol) + N' AS NVARCHAR(200))' END + N' AS DocumentTypeNameAr,
        dt.[SectionID]                                                    AS SectionID,
        CAST(ISNULL(dt.[Attachment_Mandatory], 0) AS BIT)                 AS Attachment_Mandatory,
        dt.[Attachment_Mandatory]                                         AS AttachmentMandatoryRaw,  -- updatable through the view
        ' + @ActiveExpr + N'                                              AS IsActive,
        ' + CASE WHEN @SortCol IS NULL THEN N'CAST(NULL AS INT)'
                 ELSE N'CAST(dt.' + QUOTENAME(@SortCol) + N' AS INT)' END + N' AS SortOrder
FROM    [Documents].[DocumentTypes] AS dt'
    -- db/28: a deleted document type (Deleted = 1) is gone for every reader of the view
    + CASE WHEN COL_LENGTH(N'Documents.DocumentTypes', N'Deleted') IS NOT NULL THEN N'
WHERE   dt.[Deleted] = 0' ELSE N'' END + N';';

EXEC sys.sp_executesql @View;
GO

/* ------------------------------------------------------------------
   3. Documents.usp_DocumentType_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Documents].[usp_DocumentType_Manage]
    @Action            VARCHAR(10),
    @Id                BIGINT          = NULL,
    @UserId            BIGINT          = NULL,
    /* LIST */
    @Search            NVARCHAR(200)   = NULL,
    @IsActiveFilter    BIT             = NULL,
    @CompanyId         INT             = NULL,     -- envelope only: document types are group-wide
    @CompanyIds        NVARCHAR(2000)  = NULL,
    @ParentId          INT             = NULL,     -- a section
    @PageNumber        INT             = 1,
    @PageSize          INT             = 25,
    @SortColumn        VARCHAR(50)     = NULL,
    @SortDirection     VARCHAR(4)      = NULL,
    /* INSERT / UPDATE */
    @DocumentTypeName  NVARCHAR(200)   = NULL,
    @ArabicName        NVARCHAR(200)   = NULL,
    @SectionId         INT             = NULL,
    @IsMandatory       BIT             = NULL,
    @IsActive          BIT             = NULL,
    @SortOrder         INT             = NULL,

    @TotalCount        INT             = NULL OUTPUT,
    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @Search           = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @DocumentTypeName = NULLIF(LTRIM(RTRIM(@DocumentTypeName)), N'');
    SET @ArabicName       = NULLIF(LTRIM(RTRIM(@ArabicName)), N'');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 500 THEN 500 ELSE @PageSize END;
    SET @SortColumn = CASE WHEN @SortColumn IN ('DocumentTypeName', 'SectionName', 'IsMandatory', 'IsActive', 'UsageCount') THEN @SortColumn ELSE 'SectionName' END;
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
            SELECT  v.DocumentTypeId, v.DocumentTypeName, v.DocumentTypeNameAr AS ArabicName,
                    v.SectionID AS SectionId, s.Section_Name_Eng AS SectionName, s.Section_Name_Arb AS SectionNameAr,
                    s.Seq_num AS SectionSeq, v.Attachment_Mandatory AS IsMandatory, v.IsActive, v.SortOrder,
                    (SELECT COUNT(1) FROM [Documents].[EmployeeDocumentAttachments] a
                      WHERE a.DocumentTypeId = v.DocumentTypeId AND a.IsDeleted = 0) AS UsageCount
            FROM    [Documents].[vw_DocumentTypes] AS v
            LEFT JOIN [Documents].[DocumentSections] AS s ON s.ID = v.SectionID
            WHERE   (@Action = 'LIST' OR v.DocumentTypeId = @Id)
              AND   (@IsActiveFilter IS NULL OR v.IsActive = @IsActiveFilter)
              AND   (@ParentId IS NULL OR v.SectionID = @ParentId)
              AND   (@Search IS NULL OR v.DocumentTypeName LIKE N'%' + @Search + N'%' OR v.DocumentTypeNameAr LIKE N'%' + @Search + N'%'
                     OR s.Section_Name_Eng LIKE N'%' + @Search + N'%' OR s.Section_Name_Arb LIKE N'%' + @Search + N'%')
        ),
        sorted AS (
            SELECT  x.*,
                    ROW_NUMBER() OVER (ORDER BY
                        CASE WHEN @SortColumn = 'DocumentTypeName' AND @SortDirection = 'ASC'  THEN x.DocumentTypeName END ASC,
                        CASE WHEN @SortColumn = 'DocumentTypeName' AND @SortDirection = 'DESC' THEN x.DocumentTypeName END DESC,
                        CASE WHEN @SortColumn = 'IsMandatory'      AND @SortDirection = 'ASC'  THEN x.IsMandatory END ASC,
                        CASE WHEN @SortColumn = 'IsMandatory'      AND @SortDirection = 'DESC' THEN x.IsMandatory END DESC,
                        CASE WHEN @SortColumn = 'IsActive'         AND @SortDirection = 'ASC'  THEN x.IsActive END ASC,
                        CASE WHEN @SortColumn = 'IsActive'         AND @SortDirection = 'DESC' THEN x.IsActive END DESC,
                        CASE WHEN @SortColumn = 'UsageCount'       AND @SortDirection = 'ASC'  THEN x.UsageCount END ASC,
                        CASE WHEN @SortColumn = 'UsageCount'       AND @SortDirection = 'DESC' THEN x.UsageCount END DESC,
                        -- section order (unsectioned last), then the type's own order and name
                        CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'SectionName' THEN ISNULL(x.SectionSeq, 2147483647) END DESC,
                        ISNULL(x.SectionSeq, 2147483647), ISNULL(x.SortOrder, 2147483647), x.DocumentTypeName) AS RowNo,
                    COUNT(1) OVER () AS TotalRows
            FROM    x
        )
        SELECT  *
        INTO    #Page
        FROM    sorted
        WHERE   @Action = 'GET' OR (RowNo > (@PageNumber - 1) * @PageSize AND RowNo <= @PageNumber * @PageSize);

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #Page;
        SELECT DocumentTypeId, DocumentTypeName, ArabicName, SectionId, SectionName, SectionNameAr, SectionSeq,
               IsMandatory, IsActive, SortOrder, UsageCount
        FROM   #Page
        ORDER BY RowNo;
        RETURN;
    END;

    /* ======================= writes =============================== */
    /* the real columns of Documents.DocumentTypes (same rules as db/22) */
    DECLARE @obj INT = OBJECT_ID(N'[Documents].[DocumentTypes]');
    DECLARE @Cols TABLE (name SYSNAME, type_name SYSNAME, is_char BIT, is_identity BIT, is_nullable BIT,
                         is_computed BIT, has_default BIT, max_length SMALLINT, column_id INT);
    INSERT INTO @Cols
    SELECT c.name, t.name, CASE WHEN t.name IN (N'nvarchar', N'varchar', N'nchar', N'char') THEN 1 ELSE 0 END,
           c.is_identity, c.is_nullable, c.is_computed, CASE WHEN c.default_object_id <> 0 THEN 1 ELSE 0 END,
           c.max_length, c.column_id
    FROM   sys.columns c
    JOIN   sys.types t ON t.user_type_id = c.user_type_id
    WHERE  c.object_id = @obj;

    DECLARE @IdCol SYSNAME =
        (SELECT TOP 1 c.name FROM sys.indexes i
         JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
         JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
         WHERE i.object_id = @obj AND i.is_primary_key = 1 ORDER BY ic.key_ordinal);
    IF @IdCol IS NULL SET @IdCol = (SELECT TOP 1 name FROM @Cols WHERE is_identity = 1);

    DECLARE @ArCol SYSNAME =
        (SELECT TOP 1 name FROM @Cols
         WHERE is_char = 1
           AND (name LIKE N'%Arabic%' OR name LIKE N'%Arb%' OR name LIKE N'%[_]Ar' OR name LIKE N'%NameAr%'
                OR name LIKE N'%Ar[_]Name%' OR name LIKE N'%[_]AR[_]%')
         ORDER BY CASE WHEN name LIKE N'%Name%' THEN 0 ELSE 1 END, column_id);
    DECLARE @NameCol SYSNAME =
        (SELECT TOP 1 name FROM @Cols
         WHERE is_char = 1 AND name <> ISNULL(@ArCol, N'')
           AND (name LIKE N'%Name%' OR name IN (N'DocumentType', N'Doc_Type', N'Title', N'Description'))
         ORDER BY CASE WHEN name LIKE N'%Eng%' THEN 0
                       WHEN name LIKE N'%Type%Name%' OR name LIKE N'%Name%Type%' THEN 1
                       WHEN name LIKE N'%Name%' THEN 2 ELSE 3 END, column_id);
    DECLARE @ActiveCol SYSNAME =
        (SELECT TOP 1 name FROM @Cols WHERE name IN (N'IsActive', N'Is_Active', N'IsDeleted', N'Active')
         ORDER BY CASE name WHEN N'IsActive' THEN 0 WHEN N'Is_Active' THEN 1 WHEN N'IsDeleted' THEN 2 ELSE 3 END);
    DECLARE @ActiveInverted BIT = CASE WHEN @ActiveCol = N'IsDeleted' THEN 1 ELSE 0 END;
    DECLARE @SortCol SYSNAME =
        (SELECT TOP 1 name FROM @Cols
         WHERE name IN (N'Seq_num', N'SeqNum', N'Seq_No', N'SeqNo', N'SortOrder', N'Sort_Order', N'DisplayOrder', N'Display_Order', N'OrderNo')
         ORDER BY column_id);
    DECLARE @IdIdentity BIT = ISNULL((SELECT is_identity FROM @Cols WHERE name = @IdCol), 0);

    IF @IdCol IS NULL OR @NameCol IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_SUPPORTED',
               @ResultMessage = N'The key / name columns of Documents.DocumentTypes could not be detected (see db/22).';
        RETURN;
    END;

    /* ---- TOGGLE / DELETE ---------------------------------------- */
    IF @Action IN ('TOGGLE', 'DELETE')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Documents].[vw_DocumentTypes] WHERE DocumentTypeId = @Id)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
            RETURN;
        END;

        IF @Action = 'TOGGLE'
        BEGIN
            IF @ActiveCol IS NULL
            BEGIN
                SELECT @ResultCode = 'NOT_SUPPORTED', @ResultMessage = N'Document types cannot be deactivated (no active column).';
                RETURN;
            END;
            DECLARE @tSql NVARCHAR(MAX) = N'UPDATE [Documents].[DocumentTypes] SET ' + QUOTENAME(@ActiveCol)
                + N' = CASE WHEN ISNULL(' + QUOTENAME(@ActiveCol) + N', ' + CASE WHEN @ActiveInverted = 1 THEN N'0' ELSE N'1' END
                + N') = 1 THEN 0 ELSE 1 END WHERE ' + QUOTENAME(@IdCol) + N' = @Id;';
            EXEC sys.sp_executesql @tSql, N'@Id BIGINT', @Id = @Id;
            SELECT @NewId = @Id,
                   @ResultMessage = CASE WHEN (SELECT IsActive FROM [Documents].[vw_DocumentTypes] WHERE DocumentTypeId = @Id) = 1
                                         THEN N'Document type activated.' ELSE N'Document type deactivated.' END;
            RETURN;
        END;

        /* DELETE: only a type no employee file ever used (files keep their history) */
        IF EXISTS (SELECT 1 FROM [Documents].[EmployeeDocumentAttachments] WHERE DocumentTypeId = @Id)
        BEGIN
            SELECT @ResultCode = 'IN_USE',
                   @ResultMessage = N'Employee files are attached to this document type. Deactivate it instead.';
            RETURN;
        END;
        BEGIN TRY
            -- db/28: never a physical delete - Deleted = 1 when the table has the column
            DECLARE @dSql NVARCHAR(MAX) =
                CASE WHEN COL_LENGTH(N'Documents.DocumentTypes', N'Deleted') IS NOT NULL
                     THEN N'UPDATE [Documents].[DocumentTypes] SET [Deleted] = 1'
                          + CASE WHEN COL_LENGTH(N'Documents.DocumentTypes', N'DeletedBy') IS NOT NULL THEN N', [DeletedBy] = @UserId' ELSE N'' END
                          + CASE WHEN COL_LENGTH(N'Documents.DocumentTypes', N'DeletedDate') IS NOT NULL THEN N', [DeletedDate] = SYSUTCDATETIME()' ELSE N'' END
                          + N' WHERE ' + QUOTENAME(@IdCol) + N' = @Id AND [Deleted] = 0;'
                     ELSE N'RAISERROR(N''Records are never physically deleted - run db/28_Soft_Delete.sql first.'', 16, 1);' END;
            EXEC sys.sp_executesql @dSql, N'@Id BIGINT, @UserId BIGINT', @Id = @Id, @UserId = @UserId;
            SELECT @NewId = @Id, @ResultMessage = N'Document type deleted.';
        END TRY
        BEGIN CATCH
            SELECT @ResultCode = 'IN_USE', @ResultMessage = LEFT(CONCAT(N'The document type could not be deleted: ', ERROR_MESSAGE()), 400);
        END CATCH;
        RETURN;
    END;

    /* ---- INSERT / UPDATE ---------------------------------------- */
    IF @DocumentTypeName IS NULL
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the document type name.';
        RETURN;
    END;
    IF @Action = 'UPDATE' AND NOT EXISTS (SELECT 1 FROM [Documents].[vw_DocumentTypes] WHERE DocumentTypeId = @Id)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM [Documents].[vw_DocumentTypes]
               WHERE DocumentTypeName = @DocumentTypeName AND (@Action = 'INSERT' OR DocumentTypeId <> @Id))
    BEGIN
        SELECT @ResultCode = 'DUPLICATE_NAME', @ResultMessage = N'A document type with this name already exists.';
        RETURN;
    END;
    IF @SectionId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [Documents].[DocumentSections] WHERE ID = @SectionId)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose a document section.';
        RETURN;
    END;

    DECLARE @Active BIT = ISNULL(@IsActive, 1);
    DECLARE @ActiveValue BIT = CASE WHEN @ActiveInverted = 1 THEN 1 - @Active ELSE @Active END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Params NVARCHAR(400) = N'@Id BIGINT, @Name NVARCHAR(200), @Ar NVARCHAR(200), @Sec INT, @Mand BIT, @Act BIT, @Sort INT, @UserId BIGINT, @Now DATETIME2(0), @NewKey BIGINT OUTPUT';
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @NewKey BIGINT;

    BEGIN TRY
        IF @Action = 'INSERT'
        BEGIN
            DECLARE @ColList NVARCHAR(MAX) = QUOTENAME(@NameCol) + N', [SectionID], [Attachment_Mandatory]';
            DECLARE @ValList NVARCHAR(MAX) = N'@Name, @Sec, ISNULL(@Mand, 0)';
            IF @ArCol IS NOT NULL     SELECT @ColList += N', ' + QUOTENAME(@ArCol),     @ValList += N', @Ar';
            IF @ActiveCol IS NOT NULL SELECT @ColList += N', ' + QUOTENAME(@ActiveCol), @ValList += N', @Act';
            -- no order given: last in its section
            IF @SortCol IS NOT NULL   SELECT @ColList += N', ' + QUOTENAME(@SortCol),
                                             @ValList += N', ISNULL(@Sort, (SELECT ISNULL(MAX(' + QUOTENAME(@SortCol) + N'), 0) + 1 FROM [Documents].[DocumentTypes]'
                                                       + N' WHERE ISNULL([SectionID], -1) = ISNULL(@Sec, -1)))';
            IF @IdIdentity = 0        SELECT @ColList += N', ' + QUOTENAME(@IdCol),
                                             @ValList += N', (SELECT ISNULL(MAX(' + QUOTENAME(@IdCol) + N'), 0) + 1 FROM [Documents].[DocumentTypes] WITH (UPDLOCK, HOLDLOCK))';

            /* who / when, under the usual names */
            SELECT @ColList += N', ' + QUOTENAME(name),
                   @ValList += CASE WHEN name LIKE N'%By' OR name LIKE N'%[_]By' THEN N', @UserId' ELSE N', @Now' END
            FROM   @Cols
            WHERE  name IN (N'CreatedBy', N'Created_By', N'CreatedDate', N'Created_Date', N'CreatedOn', N'Created_On')
              AND  name NOT IN (@NameCol, ISNULL(@ArCol, N''), ISNULL(@ActiveCol, N''), ISNULL(@SortCol, N''), @IdCol);

            /* any other required column without a default: a neutral value */
            SELECT @ColList += N', ' + QUOTENAME(c.name),
                   @ValList += N', ' + CASE
                        WHEN c.is_char = 1 THEN N'LEFT(@Name, ' + CAST(CASE WHEN c.max_length < 0 THEN 4000
                                                                            WHEN c.type_name LIKE N'n%' THEN c.max_length / 2
                                                                            ELSE c.max_length END AS NVARCHAR(10)) + N')'
                        WHEN c.type_name IN (N'date', N'datetime', N'datetime2', N'smalldatetime', N'datetimeoffset') THEN N'@Now'
                        WHEN c.type_name = N'uniqueidentifier' THEN N'NEWID()'
                        ELSE N'0' END
            FROM   @Cols AS c
            WHERE  c.is_nullable = 0 AND c.is_identity = 0 AND c.is_computed = 0 AND c.has_default = 0
              AND  c.type_name NOT IN (N'timestamp', N'rowversion')
              AND  c.name NOT IN (@NameCol, ISNULL(@ArCol, N''), ISNULL(@ActiveCol, N''), ISNULL(@SortCol, N''), @IdCol,
                                  N'SectionID', N'Attachment_Mandatory',
                                  N'CreatedBy', N'Created_By', N'CreatedDate', N'Created_Date', N'CreatedOn', N'Created_On');

            SET @Sql = N'INSERT INTO [Documents].[DocumentTypes] (' + @ColList + N') VALUES (' + @ValList + N'); '
                     + CASE WHEN @IdIdentity = 1 THEN N'SET @NewKey = SCOPE_IDENTITY();'
                            ELSE N'SET @NewKey = (SELECT MAX(' + QUOTENAME(@IdCol) + N') FROM [Documents].[DocumentTypes]);' END;
        END
        ELSE
        BEGIN
            DECLARE @SetList NVARCHAR(MAX) = QUOTENAME(@NameCol) + N' = @Name, [SectionID] = @Sec, [Attachment_Mandatory] = ISNULL(@Mand, 0)';
            IF @ArCol IS NOT NULL     SET @SetList += N', ' + QUOTENAME(@ArCol) + N' = @Ar';
            IF @ActiveCol IS NOT NULL SET @SetList += N', ' + QUOTENAME(@ActiveCol) + N' = @Act';
            -- the order is set by dragging (db/64), not on the form: keep it, unless the
            -- type moves to another section - then it goes last there
            IF @SortCol IS NOT NULL   SET @SetList += N', ' + QUOTENAME(@SortCol) + N' = CASE'
                                                    + N' WHEN @Sort IS NOT NULL THEN @Sort'
                                                    + N' WHEN ISNULL([SectionID], -1) = ISNULL(@Sec, -1) THEN ' + QUOTENAME(@SortCol)
                                                    + N' ELSE (SELECT ISNULL(MAX(o.' + QUOTENAME(@SortCol) + N'), 0) + 1 FROM [Documents].[DocumentTypes] AS o'
                                                    + N' WHERE ISNULL(o.[SectionID], -1) = ISNULL(@Sec, -1)) END';
            SELECT @SetList += N', ' + QUOTENAME(name) + N' = '
                             + CASE WHEN name LIKE N'%By' OR name LIKE N'%[_]By' THEN N'@UserId' ELSE N'@Now' END
            FROM   @Cols
            WHERE  name IN (N'ModifiedBy', N'Modified_By', N'ModifiedDate', N'Modified_Date', N'ModifiedOn', N'Modified_On',
                            N'UpdatedBy', N'Updated_By', N'UpdatedDate', N'Updated_Date', N'UpdatedOn', N'Updated_On');

            SET @Sql = N'UPDATE [Documents].[DocumentTypes] SET ' + @SetList + N' WHERE ' + QUOTENAME(@IdCol) + N' = @Id; SET @NewKey = @Id;';
        END;

        EXEC sys.sp_executesql @Sql, @Params,
             @Id = @Id, @Name = @DocumentTypeName, @Ar = @ArabicName, @Sec = @SectionId, @Mand = @IsMandatory,
             @Act = @ActiveValue, @Sort = @SortOrder, @UserId = @UserId, @Now = @Now, @NewKey = @NewKey OUTPUT;

        SELECT @NewId = @NewKey,
               @ResultMessage = CASE WHEN @Action = 'INSERT' THEN N'Document type created.' ELSE N'Document type saved.' END;
    END TRY
    BEGIN CATCH
        SELECT @ResultCode = 'DB_ERROR', @ResultMessage = LEFT(CONCAT(N'The document type could not be saved: ', ERROR_MESSAGE()), 400);
    END CATCH;
END;
GO

/* ------------------------------------------------------------------
   4. Documents.usp_DocumentSection_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Documents].[usp_DocumentSection_Manage]
    @Action            VARCHAR(10),
    @Id                INT             = NULL,
    @NameEng           NVARCHAR(150)   = NULL,
    @NameArb           NVARCHAR(150)   = NULL,
    @Seq               INT             = NULL,
    @UserId            BIGINT          = NULL,

    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0;
    SET @NameEng = NULLIF(LTRIM(RTRIM(@NameEng)), N'');
    SET @NameArb = NULLIF(LTRIM(RTRIM(@NameArb)), N'');

    IF @Action = 'LIST'
    BEGIN
        SELECT  s.ID AS SectionId, s.Section_Name_Eng AS NameEng, s.Section_Name_Arb AS NameArb, s.Seq_num AS Seq, s.IsActive,
                (SELECT COUNT(1) FROM [Documents].[vw_DocumentTypes] v WHERE v.SectionID = s.ID) AS TypeCount
        FROM    [Documents].[DocumentSections] AS s
        ORDER BY s.Seq_num, s.Section_Name_Eng;
        RETURN;
    END;

    IF @Action = 'INSERT'
    BEGIN
        IF @NameEng IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the section name.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Documents].[DocumentSections] WHERE Section_Name_Eng = @NameEng)
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_NAME', @ResultMessage = N'A document section with this name already exists.';
            RETURN;
        END;
        INSERT INTO [Documents].[DocumentSections] (Section_Name_Eng, Section_Name_Arb, Seq_num, IsActive)
        VALUES (@NameEng, @NameArb, ISNULL(@Seq, (SELECT ISNULL(MAX(Seq_num), 0) + 1 FROM [Documents].[DocumentSections])), 1);
        SELECT @NewId = SCOPE_IDENTITY(), @ResultMessage = N'Document section added.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ------------------------------------------------------------------
   5. Labels (English + Arabic) - new keys only
   ------------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('org.tab_employee_documents_desc', 'org', N'Documents employees upload, their section and whether they are mandatory', N'المستندات التي يرفعها الموظفون، وقسمها، وهل هي إلزامية', NULL),
        ('org.doc_type_singular', 'org', N'Document type', N'نوع المستند', NULL),
        ('org.doc_employee_files', 'org', N'Employee files', N'ملفات الموظفين', NULL),
        ('org.doc_no_section', 'org', N'No section (Other Documents)', N'بدون قسم (مستندات أخرى)', NULL),
        ('org.doc_type_name', 'org', N'Document type name', N'اسم نوع المستند', NULL),
        ('org.doc_type_name_placeholder', 'org', N'e.g. Civil ID - Front', N'مثال: البطاقة المدنية - الوجه الأمامي', NULL),
        ('org.doc_where_and_rules', 'org', N'Section & rules', N'القسم والقواعد', NULL),
        ('org.doc_section', 'org', N'Section', N'القسم', NULL),
        ('org.doc_section_hint', 'org', N'The band it is listed under on the employee''s Documents tab.', N'المجموعة التي يُعرض تحتها في تبويب مستندات الموظف.', NULL),
        ('org.doc_new_section', 'org', N'New section', N'قسم جديد', NULL),
        ('org.doc_section_name', 'org', N'Section name', N'اسم القسم', NULL),
        ('org.doc_add_section', 'org', N'Add section', N'إضافة القسم', NULL),
        ('org.doc_sort_order', 'org', N'Sort order', N'ترتيب العرض', NULL),
        ('org.doc_sort_order_hint', 'org', N'Order within its section (optional).', N'الترتيب داخل القسم (اختياري).', NULL),
        ('org.doc_mandatory', 'org', N'Mandatory - every employee must upload this document', N'إلزامي - يجب على كل موظف رفع هذا المستند', NULL),
        ('org.doc_mandatory_hint', 'org', N'Mandatory documents that are missing are flagged on the employee''s Documents tab and on the dashboard.', N'تُميَّز المستندات الإلزامية الناقصة في تبويب مستندات الموظف وفي لوحة المعلومات.', NULL),
        ('org.doc_inactive_hint', 'org', N'An inactive document type is no longer offered for upload; files already uploaded are kept.', N'لا يُعرض نوع المستند غير النشط للرفع؛ وتبقى الملفات المرفوعة محفوظة.', NULL),
        ('org.doc_in_use', 'org', N'{0} employee files are attached to this document type.', N'{0} من ملفات الموظفين مرفقة بنوع المستند هذا.', NULL),
        ('js.org_section_name_required', 'js', N'Enter the section name.', N'أدخل اسم القسم.', NULL),
        ('msg.doc_type_created', 'msg', N'Document type created.', N'تم إنشاء نوع المستند.', N'Document type created.'),
        ('msg.doc_type_saved', 'msg', N'Document type saved.', N'تم حفظ نوع المستند.', N'Document type saved.'),
        ('msg.doc_type_deleted', 'msg', N'Document type deleted.', N'تم حذف نوع المستند.', N'Document type deleted.'),
        ('msg.doc_type_activated', 'msg', N'Document type activated.', N'تم تفعيل نوع المستند.', N'Document type activated.'),
        ('msg.doc_type_deactivated', 'msg', N'Document type deactivated.', N'تم إيقاف نوع المستند.', N'Document type deactivated.'),
        ('msg.doc_type_duplicate', 'msg', N'A document type with this name already exists.', N'يوجد نوع مستند بهذا الاسم مسبقاً.', N'A document type with this name already exists.'),
        ('msg.doc_type_in_use', 'msg', N'Employee files are attached to this document type. Deactivate it instead.', N'توجد ملفات موظفين مرفقة بنوع المستند هذا. قم بإيقافه بدلاً من حذفه.', N'Employee files are attached to this document type. Deactivate it instead.'),
        ('msg.doc_type_name_required', 'msg', N'Enter the document type name.', N'أدخل اسم نوع المستند.', N'Enter the document type name.'),
        ('msg.doc_type_name_required2', 'msg', N'Document type name is required.', N'اسم نوع المستند مطلوب.', N'Document type name is required.'),
        ('msg.doc_choose_section', 'msg', N'Choose a document section.', N'اختر قسم المستند.', N'Choose a document section.'),
        ('msg.doc_section_added', 'msg', N'Document section added.', N'تمت إضافة قسم المستندات.', N'Document section added.'),
        ('msg.doc_section_duplicate', 'msg', N'A document section with this name already exists.', N'يوجد قسم مستندات بهذا الاسم مسبقاً.', N'A document section with this name already exists.'),
        ('msg.doc_section_name_required', 'msg', N'Enter the section name.', N'أدخل اسم القسم.', N'Enter the section name.'),
        ('msg.doc_max_150', 'msg', N'Use 150 characters or fewer.', N'استخدم 150 حرفاً أو أقل.', N'Use 150 characters or fewer.'),
        ('msg.doc_cannot_deactivate', 'msg', N'Document types cannot be deactivated (no active column).', N'لا يمكن إيقاف أنواع المستندات (لا يوجد عمود للحالة).', N'Document types cannot be deactivated (no active column).')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Employee Documents labels inserted: ', @LabelsInserted);
GO
