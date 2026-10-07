/* ================================================================
   HRMS Kuwait - Employee Documents tab (sections, mandatory flag,
   per-document-type upload)
   ----------------------------------------------------------------
   PURELY ADDITIVE and re-runnable. Run AFTER 19 (which creates
   Documents.DocumentSections and adds SectionID /
   Attachment_Mandatory to Documents.DocumentTypes).

   What this does
     1. Creates the view [Documents].[vw_DocumentTypes].
        [Documents].[DocumentTypes] pre-dates the numbered scripts
        in db/, so its exact column names are not known here. The
        view is built by reading sys.columns: it finds the primary
        key, the English / Arabic name columns and the active flag,
        and exposes them under fixed names:
            DocumentTypeId, DocumentTypeName, DocumentTypeNameAr,
            SectionID, Attachment_Mandatory, IsActive, SortOrder
        The procedure below only ever reads the view, so it works
        whatever the base table's columns are called. The detected
        mapping is PRINTed - check the Messages tab once.
     2. Seeds 5 starter Document Sections (only if the table is
        empty) and files every DocumentType that has no SectionID
        yet into one of them by keyword (Civil ID -> Identity, Visa
        -> Residency, ...). Types that match nothing stay unassigned
        and show under "Other Documents" on screen.
        If NO document type is mandatory yet, Civil ID, Passport,
        Residency, Work Permit and Employment Contract are marked
        mandatory as a starting point. Change them freely afterwards
        - re-running never overwrites your choices.
        If Documents.DocumentTypes is EMPTY, a starter list is added.
     3. Creates [Documents].[EmployeeDocumentAttachments] - one row
        per uploaded file. Replacing a file soft-deletes the old row
        (history kept); only one current file per employee + type.
        Files live on disk (see DocumentStorage:RootPath in
        appsettings.json, default App_Data/uploads, outside wwwroot
        so they are only reachable through the app's own
        authenticated download action). Only the relative path is
        stored here.
     4. Creates [Documents].[usp_EmployeeDocument_Manage]
        (LIST / GET / INSERT / DELETE).
     5. GRANT EXECUTE ON SCHEMA::[Documents] to hrms_app_role.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Stop the whole script (every batch) if the prerequisites are missing.
IF OBJECT_ID(N'[Documents].[DocumentTypes]', N'U') IS NULL
BEGIN
    RAISERROR(N'[Documents].[DocumentTypes] was not found. This script extends that existing table.', 16, 1);
    SET NOEXEC ON;
END;
IF OBJECT_ID(N'[Documents].[DocumentSections]', N'U') IS NULL
   OR COL_LENGTH(N'Documents.DocumentTypes', N'SectionID') IS NULL
   OR COL_LENGTH(N'Documents.DocumentTypes', N'Attachment_Mandatory') IS NULL
BEGIN
    RAISERROR(N'Run db/19_Document_Sections.sql first.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ================================================================
   1. [Documents].[vw_DocumentTypes] - built from the real columns
================================================================ */
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
/* Generated by db/22_Employee_Documents.sql from the real columns of
   [Documents].[DocumentTypes]. Re-run 22 to regenerate. */
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
FROM    [Documents].[DocumentTypes] AS dt;';

EXEC sys.sp_executesql @View;
GO

/* ================================================================
   2a. Starter Document Sections (only when none exist)
================================================================ */
IF NOT EXISTS (SELECT 1 FROM [Documents].[DocumentSections])
BEGIN
    INSERT INTO [Documents].[DocumentSections] (Section_Name_Eng, Section_Name_Arb, Seq_num, IsActive)
    VALUES (N'Identity Documents',         N'وثائق الهوية',         1, 1),
           (N'Residency & Work Permit',    N'الإقامة وإذن العمل',   2, 1),
           (N'Employment',                 N'التوظيف',              3, 1),
           (N'Education & Qualifications', N'المؤهلات العلمية',     4, 1),
           (N'Medical & Others',           N'طبية وأخرى',           5, 1);
    PRINT N'Seeded 5 starter Document Sections.';
END
GO

/* ================================================================
   2b. Starter Document Types (only when the table is EMPTY).
       Written through the detected columns; skipped with a note if
       the table has other required columns this script can't fill.
================================================================ */
IF NOT EXISTS (SELECT 1 FROM [Documents].[DocumentTypes])
BEGIN
    DECLARE @NameCol SYSNAME, @ArCol SYSNAME;

    -- Same detection rules as section 1
    SELECT TOP 1 @ArCol = c.name FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'[Documents].[DocumentTypes]') AND t.name IN (N'nvarchar', N'varchar', N'nchar', N'char')
      AND (c.name LIKE N'%Arabic%' OR c.name LIKE N'%Arb%' OR c.name LIKE N'%[_]Ar' OR c.name LIKE N'%NameAr%' OR c.name LIKE N'%Ar[_]Name%' OR c.name LIKE N'%[_]AR[_]%')
    ORDER BY CASE WHEN c.name LIKE N'%Name%' THEN 0 ELSE 1 END, c.column_id;

    SELECT TOP 1 @NameCol = c.name FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'[Documents].[DocumentTypes]') AND t.name IN (N'nvarchar', N'varchar', N'nchar', N'char')
      AND c.name <> ISNULL(@ArCol, N'')
      AND (c.name LIKE N'%Name%' OR c.name IN (N'DocumentType', N'Doc_Type', N'Title', N'Description'))
    ORDER BY CASE WHEN c.name LIKE N'%Eng%' THEN 0 WHEN c.name LIKE N'%Type%Name%' OR c.name LIKE N'%Name%Type%' THEN 1 WHEN c.name LIKE N'%Name%' THEN 2 ELSE 3 END, c.column_id;

    DECLARE @Seed NVARCHAR(MAX) = N'
    INSERT INTO [Documents].[DocumentTypes] (' + QUOTENAME(@NameCol)
        + CASE WHEN @ArCol IS NULL THEN N'' ELSE N', ' + QUOTENAME(@ArCol) END + N', SectionID, Attachment_Mandatory)
    SELECT v.NameEn' + CASE WHEN @ArCol IS NULL THEN N'' ELSE N', v.NameAr' END + N', s.ID, v.Mandatory
    FROM (VALUES
        (N''Civil ID - Front'',          N''البطاقة المدنية - الوجه الأمامي'', 1, 1),
        (N''Civil ID - Back'',           N''البطاقة المدنية - الوجه الخلفي'',  1, 1),
        (N''Passport - First Page'',     N''جواز السفر - الصفحة الأولى'',      1, 1),
        (N''Passport - Last Page'',      N''جواز السفر - الصفحة الأخيرة'',     1, 0),
        (N''Residency (Iqama) Copy'',    N''نسخة الإقامة'',                    2, 1),
        (N''Work Permit (MOL)'',         N''إذن العمل'',                       2, 1),
        (N''Entry Visa'',                N''تأشيرة الدخول'',                   2, 0),
        (N''Signed Employment Contract'',N''عقد العمل الموقع'',                3, 1),
        (N''Offer Letter'',              N''خطاب العرض الوظيفي'',              3, 0),
        (N''Resume / CV'',               N''السيرة الذاتية'',                  3, 0),
        (N''Highest Degree Certificate'',N''شهادة أعلى مؤهل'',                 4, 1),
        (N''Experience Certificates'',   N''شهادات الخبرة'',                   4, 0),
        (N''Health Certificate'',        N''الشهادة الصحية'',                  5, 0),
        (N''Driving Licence'',           N''رخصة القيادة'',                    5, 0)
    ) v(NameEn, NameAr, SectionSeq, Mandatory)
    LEFT JOIN [Documents].[DocumentSections] s ON s.Seq_num = v.SectionSeq;';

    BEGIN TRY
        EXEC sys.sp_executesql @Seed;
        PRINT N'Documents.DocumentTypes was empty - seeded 14 starter document types.';
    END TRY
    BEGIN CATCH
        PRINT N'NOTE: Documents.DocumentTypes is empty and the starter list could not be added ('
            + ERROR_MESSAGE() + N'). Add document types through your own screen/script.';
    END CATCH;
END
GO

/* ================================================================
   2c. File unassigned document types into a section by keyword,
       and set starter mandatory flags if nothing is mandatory yet.
================================================================ */
DECLARE @Map TABLE (Pattern NVARCHAR(50), SectionSeq INT, Priority INT);
INSERT INTO @Map VALUES
    -- Medical first so "Health Certificate" doesn't land in Education
    (N'%Health%', 5, 1), (N'%Medical%', 5, 1), (N'%Driving%', 5, 1), (N'%Licen%', 5, 1), (N'%Insurance%', 5, 1), (N'%Blood%', 5, 1),
    (N'%Civil%', 1, 2), (N'%Passport%', 1, 2), (N'%National ID%', 1, 2), (N'%Identity%', 1, 2), (N'%Photo%', 1, 2),
    (N'%Residen%', 2, 3), (N'%Iqama%', 2, 3), (N'%Visa%', 2, 3), (N'%Permit%', 2, 3), (N'%MOL%', 2, 3), (N'%Sponsor%', 2, 3), (N'%PACI%', 2, 3),
    (N'%Contract%', 3, 4), (N'%Offer%', 3, 4), (N'%CV%', 3, 4), (N'%Resume%', 3, 4), (N'%Appointment%', 3, 4), (N'%Joining%', 3, 4),
    (N'%Degree%', 4, 5), (N'%Diploma%', 4, 5), (N'%Certificate%', 4, 5), (N'%Education%', 4, 5), (N'%Experience%', 4, 5), (N'%Qualification%', 4, 5);

;WITH pick AS (
    SELECT v.DocumentTypeId,
           (SELECT TOP 1 s.ID
            FROM @Map m
            JOIN [Documents].[DocumentSections] s ON s.Seq_num = m.SectionSeq AND s.IsActive = 1
            WHERE v.DocumentTypeName LIKE m.Pattern
            ORDER BY m.Priority) AS SectionId
    FROM [Documents].[vw_DocumentTypes] v
    WHERE v.SectionID IS NULL
)
UPDATE v
   SET SectionID = p.SectionId
FROM [Documents].[vw_DocumentTypes] v
JOIN pick p ON p.DocumentTypeId = v.DocumentTypeId
WHERE p.SectionId IS NOT NULL;

PRINT N'Document types filed into sections: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));

IF NOT EXISTS (SELECT 1 FROM [Documents].[vw_DocumentTypes] WHERE Attachment_Mandatory = 1)
BEGIN
    -- Through the view, so the base table's key column name is not needed
    UPDATE v
       SET AttachmentMandatoryRaw = 1
    FROM [Documents].[vw_DocumentTypes] v
    WHERE v.DocumentTypeName LIKE N'%Civil%'
       OR (v.DocumentTypeName LIKE N'%Passport%' AND v.DocumentTypeName NOT LIKE N'%Last%')
       OR v.DocumentTypeName LIKE N'%Residen%' OR v.DocumentTypeName LIKE N'%Iqama%'
       OR v.DocumentTypeName LIKE N'%Work Permit%'
       OR v.DocumentTypeName LIKE N'%Contract%';

    PRINT N'Starter mandatory flags set: ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + N' document type(s).';
END
GO

/* ================================================================
   3. [Documents].[EmployeeDocumentAttachments]
================================================================ */
IF OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]', N'U') IS NULL
BEGIN
    CREATE TABLE [Documents].[EmployeeDocumentAttachments](
        AttachmentId      BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_EmployeeDocumentAttachments PRIMARY KEY,
        EmployeeId        BIGINT         NOT NULL,
        DocumentTypeId    INT            NOT NULL,
        OriginalFileName  NVARCHAR(260)  NOT NULL,
        StoredFileName    NVARCHAR(400)  NOT NULL,   -- path relative to DocumentStorage:RootPath
        ContentType       NVARCHAR(100)  NOT NULL,
        FileSizeBytes     BIGINT         NOT NULL,
        IsDeleted         BIT            NOT NULL CONSTRAINT DF_EmpDocAtt_IsDeleted DEFAULT (0),
        UploadedBy        BIGINT         NULL,
        UploadedDate      DATETIME2(0)   NOT NULL CONSTRAINT DF_EmpDocAtt_UploadedDate DEFAULT (SYSUTCDATETIME()),
        DeletedBy         BIGINT         NULL,
        DeletedDate       DATETIME2(0)   NULL,

        CONSTRAINT FK_EmpDocAtt_Employee FOREIGN KEY(EmployeeId)
            REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT CK_EmpDocAtt_FileSize CHECK (FileSizeBytes > 0)
    );

    -- One current (non-deleted) file per employee + document type
    CREATE UNIQUE INDEX UX_EmpDocAtt_Current
        ON [Documents].[EmployeeDocumentAttachments](EmployeeId, DocumentTypeId)
        WHERE IsDeleted = 0;

    PRINT N'Created [Documents].[EmployeeDocumentAttachments].';
END
GO

-- FK to DocumentTypes, added with the detected key column
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EmpDocAtt_DocumentType')
BEGIN
    DECLARE @IdCol SYSNAME =
        (SELECT TOP 1 c.name
         FROM sys.indexes i
         JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
         JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
         WHERE i.object_id = OBJECT_ID(N'[Documents].[DocumentTypes]') AND i.is_primary_key = 1
         ORDER BY ic.key_ordinal);

    IF @IdCol IS NOT NULL
    BEGIN
        DECLARE @Fk NVARCHAR(MAX) = N'ALTER TABLE [Documents].[EmployeeDocumentAttachments]
            ADD CONSTRAINT FK_EmpDocAtt_DocumentType FOREIGN KEY(DocumentTypeId)
            REFERENCES [Documents].[DocumentTypes](' + QUOTENAME(@IdCol) + N');';
        BEGIN TRY
            EXEC sys.sp_executesql @Fk;
        END TRY
        BEGIN CATCH
            PRINT N'NOTE: FK to DocumentTypes not added (' + ERROR_MESSAGE() + N'). Not required for the app to work.';
        END CATCH;
    END
END
GO

/* ================================================================
   4. [Documents].[usp_EmployeeDocument_Manage]
      LIST    @EmployeeId                    -> every active document type,
                                                grouped by section, with the
                                                employee's current file (if any)
      GET     @EmployeeId, @AttachmentId     -> one file row (for download)
      INSERT  @EmployeeId, @DocumentTypeId, file metadata
                                             -> replaces the current file for
                                                that type (old row soft-deleted)
      DELETE  @EmployeeId, @AttachmentId     -> soft delete
================================================================ */
CREATE OR ALTER PROCEDURE [Documents].[usp_EmployeeDocument_Manage]
    @Action             VARCHAR(10),
    @EmployeeId         BIGINT          = NULL,
    @AttachmentId       BIGINT          = NULL,
    @DocumentTypeId     INT             = NULL,
    @OriginalFileName   NVARCHAR(260)   = NULL,
    @StoredFileName     NVARCHAR(400)   = NULL,
    @ContentType        NVARCHAR(100)   = NULL,
    @FileSizeBytes      BIGINT          = NULL,
    @UserId             BIGINT          = NULL,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@AttachmentId, 0);

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'DELETE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    IF @EmployeeId IS NULL
    BEGIN
        SELECT @ResultCode = 'INVALID_REQUEST', @ResultMessage = N'An employee must be specified.';
        RETURN;
    END;

    /* ======================= LIST ================================= */
    IF @Action = 'LIST'
    BEGIN
        SELECT  s.ID                    AS SectionId,
                s.Section_Name_Eng      AS SectionNameEng,
                s.Section_Name_Arb      AS SectionNameArb,
                s.Seq_num               AS SectionSeq,
                v.DocumentTypeId,
                v.DocumentTypeName,
                v.DocumentTypeNameAr,
                v.Attachment_Mandatory  AS AttachmentMandatory,
                a.AttachmentId,
                a.OriginalFileName,
                a.ContentType,
                a.FileSizeBytes,
                a.UploadedDate
        FROM        [Documents].[vw_DocumentTypes]            AS v
        LEFT JOIN   [Documents].[DocumentSections]            AS s ON s.ID = v.SectionID AND s.IsActive = 1
        LEFT JOIN   [Documents].[EmployeeDocumentAttachments] AS a ON a.DocumentTypeId = v.DocumentTypeId
                                                                  AND a.EmployeeId     = @EmployeeId
                                                                  AND a.IsDeleted      = 0
        WHERE       v.IsActive = 1
        ORDER BY    CASE WHEN s.ID IS NULL THEN 1 ELSE 0 END,
                    s.Seq_num, s.Section_Name_Eng,
                    CASE WHEN v.SortOrder IS NULL THEN 1 ELSE 0 END, v.SortOrder,
                    v.DocumentTypeName;
        RETURN;
    END;

    /* ======================= GET ================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  a.AttachmentId, a.EmployeeId, a.DocumentTypeId, a.OriginalFileName,
                a.StoredFileName, a.ContentType, a.FileSizeBytes, a.UploadedDate
        FROM    [Documents].[EmployeeDocumentAttachments] AS a
        WHERE   a.AttachmentId = @AttachmentId
          AND   a.EmployeeId   = @EmployeeId
          AND   a.IsDeleted    = 0;
        RETURN;
    END;

    /* ======================= INSERT =============================== */
    IF @Action = 'INSERT'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That employee no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM [Documents].[vw_DocumentTypes] WHERE DocumentTypeId = @DocumentTypeId AND IsActive = 1)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That document type is not available any more. Refresh and try again.';
            RETURN;
        END;

        IF NULLIF(@StoredFileName, N'') IS NULL OR NULLIF(@OriginalFileName, N'') IS NULL OR ISNULL(@FileSizeBytes, 0) <= 0
        BEGIN
            SELECT @ResultCode = 'INVALID_REQUEST', @ResultMessage = N'The uploaded file is empty.';
            RETURN;
        END;

        BEGIN TRANSACTION;

        UPDATE [Documents].[EmployeeDocumentAttachments]
           SET IsDeleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE EmployeeId = @EmployeeId AND DocumentTypeId = @DocumentTypeId AND IsDeleted = 0;

        INSERT INTO [Documents].[EmployeeDocumentAttachments]
            (EmployeeId, DocumentTypeId, OriginalFileName, StoredFileName, ContentType, FileSizeBytes, UploadedBy)
        VALUES
            (@EmployeeId, @DocumentTypeId, @OriginalFileName, @StoredFileName, @ContentType, @FileSizeBytes, @UserId);

        SET @NewId = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        SET @ResultMessage = N'Document uploaded.';
        RETURN;
    END;

    /* ======================= DELETE =============================== */
    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Documents].[EmployeeDocumentAttachments]
           SET IsDeleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE AttachmentId = @AttachmentId AND EmployeeId = @EmployeeId AND IsDeleted = 0;

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That document was already removed. Refresh and try again.';
            RETURN;
        END;

        SET @ResultMessage = N'Document removed.';
        RETURN;
    END;
END;
GO

/* ================================================================
   5. Permissions - same schema-level grant as db/05
================================================================ */
IF DATABASE_PRINCIPAL_ID(N'hrms_app_role') IS NOT NULL
    GRANT EXECUTE ON SCHEMA::[Documents] TO [hrms_app_role];
GO

PRINT N'db/22 applied: vw_DocumentTypes, EmployeeDocumentAttachments, usp_EmployeeDocument_Manage.';
GO

SET NOEXEC OFF;
GO

/* Check what the Documents tab will show:
SELECT s.Seq_num, s.Section_Name_Eng, v.DocumentTypeId, v.DocumentTypeName, v.DocumentTypeNameAr, v.Attachment_Mandatory
FROM Documents.vw_DocumentTypes v
LEFT JOIN Documents.DocumentSections s ON s.ID = v.SectionID
WHERE v.IsActive = 1
ORDER BY CASE WHEN s.ID IS NULL THEN 1 ELSE 0 END, s.Seq_num, v.DocumentTypeName;
*/
