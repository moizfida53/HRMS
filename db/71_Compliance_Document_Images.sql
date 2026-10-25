/* =====================================================================
   71_Compliance_Document_Images.sql  -  HRMS: Kuwait Compliance images
   ---------------------------------------------------------------------
   Run after 22, 28 and 63. Safe to re-run. Then run 72 (labels).

   The Civil ID, Passport, Residency and Work Permit images (uploaded on
   the Documents tab or from Kuwait Compliance) are tied to their Kuwait
   Compliance item:

     Kuwait.ComplianceDocumentTypes  which document types belong to which
                                     item (Civil ID - Front / Back -> Civil
                                     ID ...). Filled once from the type
                                     names; change the rows to re-map.

   Each image of such a type now has a state
     (Documents.EmployeeDocumentAttachments.ImageState):
       C  current   - the image in use. Once CONFIRMED it is applied to
                      the item's expiry date (ConfirmedExpiryDate).
       R  renewal   - a new image uploaded while the current one is
                      confirmed; the current one stays in use until the
                      renewal is confirmed with the new expiry date.
       A  archived  - a previous image, replaced by a confirmed renewal.
                      Kept for "Previous images"; never deleted.
   Other document types keep working as before (C only; a new upload
   replaces the old file).

     Kuwait.usp_ComplianceDocument_Manage
       LIST     the items' document types with their current / renewal image
       HISTORY  every image of one item, archived ones included
       CONFIRM  applies the images to an expiry date (and number): a renewal
                archives the images it replaces; the expiry date (and
                number) is written to Kuwait.EmployeeCompliance
   Documents.usp_EmployeeDocument_Manage (db/28) is re-created: an upload
   for a confirmed item becomes a renewal (R) instead of replacing it.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]', N'U') IS NULL
   OR OBJECT_ID(N'[Documents].[vw_DocumentTypes]', N'V') IS NULL
   OR OBJECT_ID(N'[Kuwait].[EmployeeCompliance]', N'U') IS NULL
BEGIN
    RAISERROR(N'Run db/22, db/28 and db/63 first.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------
   1. Image state on the attachments
   ------------------------------------------------------------------ */
IF COL_LENGTH(N'Documents.EmployeeDocumentAttachments', N'ImageState') IS NULL
BEGIN
    ALTER TABLE [Documents].[EmployeeDocumentAttachments]
        ADD ImageState CHAR(1) NOT NULL CONSTRAINT DF_EmpDocAtt_ImageState DEFAULT ('C') WITH VALUES;
    PRINT N'Added [Documents].[EmployeeDocumentAttachments].[ImageState].';
END
GO
IF OBJECT_ID(N'[Documents].[CK_EmpDocAtt_ImageState]', N'C') IS NULL
    EXEC (N'ALTER TABLE [Documents].[EmployeeDocumentAttachments]
            ADD CONSTRAINT CK_EmpDocAtt_ImageState CHECK (ImageState IN (''C'', ''R'', ''A''));');
GO
IF COL_LENGTH(N'Documents.EmployeeDocumentAttachments', N'ConfirmedExpiryDate') IS NULL
    ALTER TABLE [Documents].[EmployeeDocumentAttachments]
        ADD ConfirmedExpiryDate DATE          NULL,
            ConfirmedNumber     NVARCHAR(50)  NULL,
            ConfirmedBy         BIGINT        NULL,
            ConfirmedDate       DATETIME2(0)  NULL,
            ArchivedBy          BIGINT        NULL,
            ArchivedDate        DATETIME2(0)  NULL;
GO

/* one current and at most one renewal image per employee + type (was: one non-deleted) */
DECLARE @obj INT = OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]');
DECLARE @ix SYSNAME, @isuc BIT, @sql NVARCHAR(MAX);
DECLARE ix_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT i.name, i.is_unique_constraint
    FROM   sys.indexes i
    WHERE  i.object_id = @obj AND i.is_unique = 1 AND i.is_primary_key = 0
      AND  i.name NOT IN (N'UX_EmpDocAtt_Current2', N'UX_EmpDocAtt_Renewal')
      AND  (SELECT COUNT(1) FROM sys.index_columns ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0) = 2
      AND  EXISTS (SELECT 1 FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND c.name = N'EmployeeId')
      AND  EXISTS (SELECT 1 FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND c.name = N'DocumentTypeId');
OPEN ix_cursor;
FETCH NEXT FROM ix_cursor INTO @ix, @isuc;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = CASE WHEN @isuc = 1 THEN N'ALTER TABLE [Documents].[EmployeeDocumentAttachments] DROP CONSTRAINT ' + QUOTENAME(@ix) + N';'
                    ELSE N'DROP INDEX ' + QUOTENAME(@ix) + N' ON [Documents].[EmployeeDocumentAttachments];' END;
    EXEC (@sql);
    PRINT N'Dropped the unique index ' + @ix + N' (one file per type) - replaced by one current + one renewal.';
    FETCH NEXT FROM ix_cursor INTO @ix, @isuc;
END;
CLOSE ix_cursor; DEALLOCATE ix_cursor;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = @obj AND name = N'UX_EmpDocAtt_Current2')
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UX_EmpDocAtt_Current2 ON [Documents].[EmployeeDocumentAttachments] (EmployeeId, DocumentTypeId)
            WHERE IsDeleted = 0 AND ImageState = ''C'';');
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = @obj AND name = N'UX_EmpDocAtt_Renewal')
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UX_EmpDocAtt_Renewal ON [Documents].[EmployeeDocumentAttachments] (EmployeeId, DocumentTypeId)
            WHERE IsDeleted = 0 AND ImageState = ''R'';');
GO

/* ------------------------------------------------------------------
   2. Kuwait.ComplianceDocumentTypes - document type -> compliance item
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Kuwait].[ComplianceDocumentTypes]', N'U') IS NULL
BEGIN
    CREATE TABLE [Kuwait].[ComplianceDocumentTypes](
        MapId           INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_ComplianceDocumentTypes PRIMARY KEY,
        ComplianceKey   VARCHAR(20)    NOT NULL,   -- CIVIL_ID, PASSPORT, RESIDENCY, WORK_PERMIT
        DocumentTypeId  INT            NOT NULL,
        CreatedBy       BIGINT         NULL,
        CreatedDate     DATETIME2(0)   NOT NULL CONSTRAINT DF_ComplianceDocumentTypes_Created DEFAULT (SYSUTCDATETIME()),
        Deleted         BIT            NOT NULL CONSTRAINT DF_ComplianceDocumentTypes_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(0)   NULL,
        CONSTRAINT CK_ComplianceDocumentTypes_Key CHECK (ComplianceKey IN ('CIVIL_ID', 'PASSPORT', 'RESIDENCY', 'WORK_PERMIT'))
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_ComplianceDocumentTypes_Type ON [Kuwait].[ComplianceDocumentTypes] (DocumentTypeId) WHERE Deleted = 0;');
    PRINT N'Created [Kuwait].[ComplianceDocumentTypes].';
END
GO

/* filled once, by name: a type named for both residency and work permit goes to Residency */
IF NOT EXISTS (SELECT 1 FROM [Kuwait].[ComplianceDocumentTypes] WHERE Deleted = 0)
BEGIN
    INSERT INTO [Kuwait].[ComplianceDocumentTypes] (ComplianceKey, DocumentTypeId)
    SELECT k.ComplianceKey, k.DocumentTypeId
    FROM (
        SELECT v.DocumentTypeId,
               CASE WHEN v.DocumentTypeName LIKE N'%Civil%'                                         THEN 'CIVIL_ID'
                    WHEN v.DocumentTypeName LIKE N'%Passport%'                                      THEN 'PASSPORT'
                    WHEN v.DocumentTypeName LIKE N'%Residen%' OR v.DocumentTypeName LIKE N'%Iqama%' THEN 'RESIDENCY'
                    WHEN v.DocumentTypeName LIKE N'%Work Permit%' OR v.DocumentTypeName LIKE N'%MOL%'
                         OR v.DocumentTypeName LIKE N'%Work-Permit%'                                THEN 'WORK_PERMIT'
               END AS ComplianceKey
        FROM [Documents].[vw_DocumentTypes] v
        WHERE v.DocumentTypeName NOT LIKE N'%Visa%'
    ) k
    WHERE k.ComplianceKey IS NOT NULL;

    DECLARE @Mapped INT = @@ROWCOUNT;
    PRINT CONCAT(N'Document types linked to Kuwait Compliance: ', @Mapped, N' - check them:');
END
GO
/* what is linked (Messages / Results) */
SELECT m.ComplianceKey, m.DocumentTypeId, v.DocumentTypeName
FROM   [Kuwait].[ComplianceDocumentTypes] m
JOIN   [Documents].[vw_DocumentTypes] v ON v.DocumentTypeId = m.DocumentTypeId
WHERE  m.Deleted = 0
ORDER BY m.ComplianceKey, v.DocumentTypeName;
GO

/* ------------------------------------------------------------------
   3. Documents.usp_EmployeeDocument_Manage (db/28 + image state)
   ------------------------------------------------------------------ */
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
                                                                  AND a.ImageState     = 'C'
        WHERE       v.IsActive = 1
        ORDER BY    CASE WHEN s.ID IS NULL THEN 1 ELSE 0 END,
                    s.Seq_num, s.Section_Name_Eng,
                    CASE WHEN v.SortOrder IS NULL THEN 1 ELSE 0 END, v.SortOrder,
                    v.DocumentTypeName;
        RETURN;
    END;

    /* ======================= GET ================================== */
    /* any image of the employee that is not deleted - archived ones too ("Previous images") */
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

        /* a Kuwait Compliance image whose current image is confirmed: the new one waits as a renewal */
        DECLARE @Renewal BIT =
            CASE WHEN EXISTS (SELECT 1 FROM [Kuwait].[ComplianceDocumentTypes] m WHERE m.DocumentTypeId = @DocumentTypeId AND m.Deleted = 0)
                  AND EXISTS (SELECT 1 FROM [Documents].[EmployeeDocumentAttachments] a
                              WHERE a.EmployeeId = @EmployeeId AND a.DocumentTypeId = @DocumentTypeId
                                AND a.IsDeleted = 0 AND a.ImageState = 'C' AND a.ConfirmedDate IS NOT NULL)
                 THEN 1 ELSE 0 END;

        BEGIN TRANSACTION;

        /* the file it replaces: the renewal waiting (for a renewal), else the current one
           (and any renewal left behind when its current image was removed) */
        UPDATE [Documents].[EmployeeDocumentAttachments]
           SET IsDeleted = 1, Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE EmployeeId = @EmployeeId AND DocumentTypeId = @DocumentTypeId AND IsDeleted = 0
           AND ImageState IN ('R', CASE WHEN @Renewal = 1 THEN 'R' ELSE 'C' END);

        INSERT INTO [Documents].[EmployeeDocumentAttachments]
            (EmployeeId, DocumentTypeId, OriginalFileName, StoredFileName, ContentType, FileSizeBytes, UploadedBy, ImageState)
        VALUES
            (@EmployeeId, @DocumentTypeId, @OriginalFileName, @StoredFileName, @ContentType, @FileSizeBytes, @UserId,
             CASE WHEN @Renewal = 1 THEN 'R' ELSE 'C' END);

        SET @NewId = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        SET @ResultMessage = CASE WHEN @Renewal = 1
                                  THEN N'Renewal image uploaded - confirm it on Kuwait Compliance to apply the new expiry date.'
                                  ELSE N'Document uploaded.' END;
        RETURN;
    END;

    /* ======================= DELETE =============================== */
    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Documents].[EmployeeDocumentAttachments]
           SET IsDeleted = 1, Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
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

/* ------------------------------------------------------------------
   4. Kuwait.usp_ComplianceDocument_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Kuwait].[usp_ComplianceDocument_Manage]
    @Action          VARCHAR(10),
    @EmployeeId      BIGINT          = NULL,
    @ComplianceKey   VARCHAR(20)     = NULL,
    @ExpiryDate      DATE            = NULL,
    @DocumentNumber  NVARCHAR(50)    = NULL,
    @UserId          BIGINT          = NULL,
    @NewId           BIGINT          = NULL OUTPUT,
    @ResultCode      VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage   NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0;

    IF @Action NOT IN ('LIST', 'HISTORY', 'CONFIRM')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;
    IF @EmployeeId IS NULL
    BEGIN
        SELECT @ResultCode = 'INVALID_REQUEST', @ResultMessage = N'An employee must be specified.';
        RETURN;
    END;
    IF @Action <> 'LIST' AND ISNULL(@ComplianceKey, '') NOT IN ('CIVIL_ID', 'PASSPORT', 'RESIDENCY', 'WORK_PERMIT')
    BEGIN
        SELECT @ResultCode = 'INVALID_REQUEST', @ResultMessage = N'Unknown compliance item.';
        RETURN;
    END;

    /* ======================= LIST ================================= */
    /* each linked document type, with its current and its renewal image (one row each) */
    IF @Action = 'LIST'
    BEGIN
        SELECT  m.ComplianceKey,
                v.DocumentTypeId,
                v.DocumentTypeName,
                v.DocumentTypeNameAr,
                a.AttachmentId,
                a.ImageState,
                a.OriginalFileName,
                a.ContentType,
                a.FileSizeBytes,
                a.UploadedDate,
                a.ConfirmedExpiryDate,
                a.ConfirmedNumber,
                a.ConfirmedDate,
                (SELECT COUNT(1) FROM [Documents].[EmployeeDocumentAttachments] x
                 WHERE x.EmployeeId = @EmployeeId AND x.DocumentTypeId = v.DocumentTypeId
                   AND x.IsDeleted = 0 AND x.ImageState = 'A') AS ArchivedCount
        FROM        [Kuwait].[ComplianceDocumentTypes]        AS m
        JOIN        [Documents].[vw_DocumentTypes]            AS v ON v.DocumentTypeId = m.DocumentTypeId AND v.IsActive = 1
        LEFT JOIN   [Documents].[EmployeeDocumentAttachments] AS a ON a.EmployeeId = @EmployeeId
                                                                  AND a.DocumentTypeId = v.DocumentTypeId
                                                                  AND a.IsDeleted = 0
                                                                  AND a.ImageState IN ('C', 'R')
        WHERE       m.Deleted = 0
        ORDER BY    m.ComplianceKey,
                    CASE WHEN v.SortOrder IS NULL THEN 1 ELSE 0 END, v.SortOrder, v.DocumentTypeName,
                    CASE a.ImageState WHEN 'C' THEN 0 ELSE 1 END;
        RETURN;
    END;

    /* ======================= HISTORY ============================== */
    IF @Action = 'HISTORY'
    BEGIN
        SELECT  a.AttachmentId,
                a.DocumentTypeId,
                v.DocumentTypeName,
                v.DocumentTypeNameAr,
                a.ImageState,
                a.OriginalFileName,
                a.ContentType,
                a.FileSizeBytes,
                a.UploadedDate,
                uu.Username  AS UploadedByName,
                a.ConfirmedExpiryDate,
                a.ConfirmedNumber,
                a.ConfirmedDate,
                a.ArchivedDate
        FROM        [Documents].[EmployeeDocumentAttachments] AS a
        JOIN        [Kuwait].[ComplianceDocumentTypes]        AS m ON m.DocumentTypeId = a.DocumentTypeId AND m.Deleted = 0
        JOIN        [Documents].[vw_DocumentTypes]            AS v ON v.DocumentTypeId = a.DocumentTypeId
        LEFT JOIN   [Security].[Users]                        AS uu ON uu.UserId = a.UploadedBy
        WHERE       a.EmployeeId = @EmployeeId
          AND       m.ComplianceKey = @ComplianceKey
          AND       a.IsDeleted = 0
        ORDER BY    CASE a.ImageState WHEN 'R' THEN 0 WHEN 'C' THEN 1 ELSE 2 END,
                    ISNULL(a.ConfirmedExpiryDate, '99991231') DESC, a.UploadedDate DESC;
        RETURN;
    END;

    /* ======================= CONFIRM ============================== */
    IF @Action = 'CONFIRM'
    BEGIN
        IF @ExpiryDate IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the expiry date the images apply to.';
            RETURN;
        END;
        SET @DocumentNumber = NULLIF(LTRIM(RTRIM(@DocumentNumber)), N'');

        DECLARE @Img TABLE (AttachmentId BIGINT, DocumentTypeId INT, ImageState CHAR(1), Confirmed BIT, ConfirmedExpiryDate DATE);
        INSERT INTO @Img
        SELECT a.AttachmentId, a.DocumentTypeId, a.ImageState, CASE WHEN a.ConfirmedDate IS NULL THEN 0 ELSE 1 END, a.ConfirmedExpiryDate
        FROM   [Documents].[EmployeeDocumentAttachments] a
        JOIN   [Kuwait].[ComplianceDocumentTypes] m ON m.DocumentTypeId = a.DocumentTypeId AND m.Deleted = 0
        WHERE  a.EmployeeId = @EmployeeId AND m.ComplianceKey = @ComplianceKey
          AND  a.IsDeleted = 0 AND a.ImageState IN ('C', 'R');

        DECLARE @IsRenewal BIT = CASE WHEN EXISTS (SELECT 1 FROM @Img WHERE ImageState = 'R') THEN 1 ELSE 0 END;
        IF @IsRenewal = 0 AND NOT EXISTS (SELECT 1 FROM @Img WHERE ImageState = 'C' AND Confirmed = 0)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'There are no new images to confirm.';
            RETURN;
        END;

        IF @IsRenewal = 1
        BEGIN
            /* the images it replaces (a type left on an older document may catch up later) */
            DECLARE @Previous DATE = (SELECT MAX(c.ConfirmedExpiryDate) FROM @Img c
                                      WHERE c.ImageState = 'C' AND c.Confirmed = 1
                                        AND EXISTS (SELECT 1 FROM @Img r WHERE r.ImageState = 'R' AND r.DocumentTypeId = c.DocumentTypeId));
            IF @Previous IS NOT NULL AND @ExpiryDate <= @Previous
            BEGIN
                SELECT @ResultCode = 'VALIDATION',
                       @ResultMessage = CONCAT(N'The new expiry date must be after the current one (', FORMAT(@Previous, 'dd MMM yyyy', 'en-US'), N').');
                RETURN;
            END;
        END;

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

        BEGIN TRANSACTION;

        /* a renewal: the image it replaces is archived first (one current per type) */
        UPDATE a
           SET ImageState = 'A', ArchivedBy = @UserId, ArchivedDate = @Now
          FROM [Documents].[EmployeeDocumentAttachments] a
          JOIN @Img i ON i.AttachmentId = a.AttachmentId AND i.ImageState = 'C'
         WHERE EXISTS (SELECT 1 FROM @Img r WHERE r.ImageState = 'R' AND r.DocumentTypeId = i.DocumentTypeId);

        /* the renewal images and any unconfirmed current image now apply to the date */
        UPDATE a
           SET ImageState = 'C', ConfirmedExpiryDate = @ExpiryDate, ConfirmedNumber = @DocumentNumber,
               ConfirmedBy = @UserId, ConfirmedDate = @Now
          FROM [Documents].[EmployeeDocumentAttachments] a
          JOIN @Img i ON i.AttachmentId = a.AttachmentId
         WHERE i.ImageState = 'R' OR (i.ImageState = 'C' AND i.Confirmed = 0);

        /* the expiry date (and number) on Kuwait Compliance */
        IF NOT EXISTS (SELECT 1 FROM [Kuwait].[EmployeeCompliance] WHERE EmployeeId = @EmployeeId)
            INSERT INTO [Kuwait].[EmployeeCompliance] (EmployeeId, CreatedBy) VALUES (@EmployeeId, @UserId);

        UPDATE [Kuwait].[EmployeeCompliance]
           SET CivilIdExpiryDate    = CASE WHEN @ComplianceKey = 'CIVIL_ID'    THEN @ExpiryDate ELSE CivilIdExpiryDate END,
               CivilIdNumber        = CASE WHEN @ComplianceKey = 'CIVIL_ID'    AND @DocumentNumber IS NOT NULL THEN LEFT(@DocumentNumber, 20) ELSE CivilIdNumber END,
               PassportExpiryDate   = CASE WHEN @ComplianceKey = 'PASSPORT'    THEN @ExpiryDate ELSE PassportExpiryDate END,
               PassportNumber       = CASE WHEN @ComplianceKey = 'PASSPORT'    AND @DocumentNumber IS NOT NULL THEN LEFT(@DocumentNumber, 30) ELSE PassportNumber END,
               ResidencyExpiryDate  = CASE WHEN @ComplianceKey = 'RESIDENCY'   THEN @ExpiryDate ELSE ResidencyExpiryDate END,
               ResidencyNumber      = CASE WHEN @ComplianceKey = 'RESIDENCY'   AND @DocumentNumber IS NOT NULL THEN LEFT(@DocumentNumber, 30) ELSE ResidencyNumber END,
               WorkPermitExpiryDate = CASE WHEN @ComplianceKey = 'WORK_PERMIT' THEN @ExpiryDate ELSE WorkPermitExpiryDate END,
               WorkPermitNumber     = CASE WHEN @ComplianceKey = 'WORK_PERMIT' AND @DocumentNumber IS NOT NULL THEN LEFT(@DocumentNumber, 50) ELSE WorkPermitNumber END,
               ModifiedBy = @UserId, ModifiedDate = @Now
         WHERE EmployeeId = @EmployeeId;

        COMMIT TRANSACTION;

        SET @ResultMessage = CASE WHEN @IsRenewal = 1
                                  THEN N'Renewal confirmed - the previous images are archived and the expiry date is updated.'
                                  ELSE N'Images confirmed against the expiry date.' END;
        RETURN;
    END;
END;
GO

PRINT N'71_Compliance_Document_Images complete.';
GO
SET NOEXEC OFF;
GO
