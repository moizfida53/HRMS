/* =====================================================================
   64_Document_Type_Order.sql  -  HRMS: drag to order document types
   ---------------------------------------------------------------------
   Run after 63 (re-run 63 first: it now adds a SortOrder column when
   Documents.DocumentTypes has no sort column of its own, and saving a
   document type keeps its place instead of clearing it). Safe to re-run.

   The Sort Order box is gone from the document type form: on
   Organization > Employee Documents the rows are dragged into order
   within their section and the new order is saved on the drop.

     1. Documents.usp_DocumentType_Reorder - takes the ids of one
        section in their new order and numbers them 1..n; any type of
        that section not in the list keeps its relative order after them.
     2. Labels (English + Arabic), including the document viewer popup
        and the Replace confirmation on the employee's Documents tab.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Documents].[vw_DocumentTypes]', N'V') IS NULL
   OR OBJECT_ID(N'[Documents].[usp_DocumentType_Manage]', N'P') IS NULL
    RAISERROR(N'Run db/63 first.', 16, 1);
GO

/* ------------------------------------------------------------------
   1. Documents.usp_DocumentType_Reorder
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Documents].[usp_DocumentType_Reorder]
    @Ids               NVARCHAR(MAX),              -- document type ids, comma separated, in their new order
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
    CREATE TABLE #Sent (Pos INT IDENTITY(1, 1) PRIMARY KEY, DocumentTypeId INT NOT NULL UNIQUE);
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
        IF NOT EXISTS (SELECT 1 FROM #Sent WHERE DocumentTypeId = CAST(@Token AS INT))
            INSERT INTO #Sent (DocumentTypeId) VALUES (CAST(@Token AS INT));
    END;

    IF NOT EXISTS (SELECT 1 FROM #Sent)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The new order could not be read.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM #Sent s WHERE NOT EXISTS (SELECT 1 FROM [Documents].[vw_DocumentTypes] v WHERE v.DocumentTypeId = s.DocumentTypeId))
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
        RETURN;
    END;
    /* one section at a time: a type changes section on its form, not by dragging */
    IF (SELECT COUNT(DISTINCT ISNULL(v.SectionID, -1))
        FROM #Sent s JOIN [Documents].[vw_DocumentTypes] v ON v.DocumentTypeId = s.DocumentTypeId) > 1
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Document types can only be moved within their own section.';
        RETURN;
    END;

    /* the real key / sort columns of Documents.DocumentTypes (same rules as db/22 and db/63) */
    DECLARE @obj INT = OBJECT_ID(N'[Documents].[DocumentTypes]');
    DECLARE @IdCol SYSNAME =
        (SELECT TOP 1 c.name FROM sys.indexes i
         JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
         JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
         WHERE i.object_id = @obj AND i.is_primary_key = 1 ORDER BY ic.key_ordinal);
    IF @IdCol IS NULL SET @IdCol = (SELECT TOP 1 name FROM sys.columns WHERE object_id = @obj AND is_identity = 1);
    DECLARE @SortCol SYSNAME =
        (SELECT TOP 1 name FROM sys.columns
         WHERE object_id = @obj
           AND name IN (N'Seq_num', N'SeqNum', N'Seq_No', N'SeqNo', N'SortOrder', N'Sort_Order', N'DisplayOrder', N'Display_Order', N'OrderNo')
         ORDER BY column_id);

    IF @IdCol IS NULL OR @SortCol IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_SUPPORTED',
               @ResultMessage = N'Document types have no sort column yet. Re-run db/63, then try again.';
        RETURN;
    END;

    /* the dragged section: the sent ids 1..n, then the rest of the section in their current order */
    DECLARE @Section INT = (SELECT TOP 1 v.SectionID FROM #Sent s JOIN [Documents].[vw_DocumentTypes] v ON v.DocumentTypeId = s.DocumentTypeId);
    DECLARE @SentCount INT = (SELECT COUNT(1) FROM #Sent);

    CREATE TABLE #Final (DocumentTypeId INT NOT NULL PRIMARY KEY, Seq INT NOT NULL);
    INSERT INTO #Final (DocumentTypeId, Seq)
    SELECT DocumentTypeId, Pos FROM #Sent;

    INSERT INTO #Final (DocumentTypeId, Seq)
    SELECT v.DocumentTypeId,
           @SentCount + ROW_NUMBER() OVER (ORDER BY ISNULL(v.SortOrder, 2147483647), v.DocumentTypeName, v.DocumentTypeId)
    FROM   [Documents].[vw_DocumentTypes] AS v
    WHERE  ISNULL(v.SectionID, -1) = ISNULL(@Section, -1)
      AND  NOT EXISTS (SELECT 1 FROM #Sent s WHERE s.DocumentTypeId = v.DocumentTypeId);

    /* who / when, under the usual names */
    DECLARE @Audit NVARCHAR(MAX) = N'';
    SELECT @Audit += N', dt.' + QUOTENAME(name) + N' = '
                   + CASE WHEN name LIKE N'%By' THEN N'@UserId' ELSE N'SYSUTCDATETIME()' END
    FROM   sys.columns
    WHERE  object_id = @obj
      AND  name IN (N'ModifiedBy', N'Modified_By', N'ModifiedDate', N'Modified_Date', N'ModifiedOn', N'Modified_On',
                    N'UpdatedBy', N'Updated_By', N'UpdatedDate', N'Updated_Date', N'UpdatedOn', N'Updated_On');

    DECLARE @Sql NVARCHAR(MAX) =
          N'UPDATE dt SET dt.' + QUOTENAME(@SortCol) + N' = f.Seq' + @Audit
        + N' FROM [Documents].[DocumentTypes] AS dt JOIN #Final AS f ON f.DocumentTypeId = dt.' + QUOTENAME(@IdCol)
        + N' WHERE ISNULL(dt.' + QUOTENAME(@SortCol) + N', -1) <> f.Seq;';

    BEGIN TRY
        EXEC sys.sp_executesql @Sql, N'@UserId BIGINT', @UserId = @UserId;
        SELECT @NewId = @SentCount, @ResultMessage = N'Document order saved.';
    END TRY
    BEGIN CATCH
        SELECT @ResultCode = 'DB_ERROR', @ResultMessage = LEFT(CONCAT(N'The new order could not be saved: ', ERROR_MESSAGE()), 400);
    END CATCH;
END;
GO

/* ------------------------------------------------------------------
   2. Labels (English + Arabic) - new keys only
   ------------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('org.doc_order', 'org', N'Order', N'الترتيب', NULL),
        ('org.doc_drag_hint', 'org', N'Drag a row by its handle to change the order within its section - it is saved when you drop it.', N'اسحب الصف من مقبضه لتغيير ترتيبه داخل قسمه - يُحفظ الترتيب عند الإفلات.', NULL),
        ('org.doc_drag_off_hint', 'org', N'Clear the search, the status filter and the column sort to drag rows into order.', N'امسح البحث وفلتر الحالة وترتيب الأعمدة لتتمكن من سحب الصفوف وترتيبها.', NULL),
        ('org.doc_drag_handle', 'org', N'Drag to reorder {0}', N'اسحب لإعادة ترتيب {0}', NULL),
        ('js.doc_order_saved', 'js', N'Order saved.', N'تم حفظ الترتيب.', NULL),
        ('js.doc_order_failed', 'js', N'The new order could not be saved.', N'تعذّر حفظ الترتيب الجديد.', NULL),
        ('js.doc_order_moved', 'js', N'{0} moved to position {1}.', N'نُقل {0} إلى الموضع {1}.', NULL),
        ('js.docview_zoom', 'js', N'Click to toggle actual size', N'انقر للتبديل إلى الحجم الفعلي', NULL),
        ('emp.docview_maximize', 'emp', N'Maximize', N'تكبير', NULL),
        ('emp.docview_restore', 'emp', N'Restore', N'استعادة', NULL),
        ('emp.replace_document', 'emp', N'Replace document', N'استبدال المستند', NULL),
        ('emp.replace_the_file_for', 'emp', N'The file already uploaded for', N'سيتم استبدال الملف المرفوع مسبقاً لـ', NULL),
        ('emp.replace_the_file_for_end', 'emp', N' will be replaced with the one you chose. Continue?', N' بالملف الذي اخترته. هل تريد المتابعة؟', NULL),
        ('msg.doc_order_saved', 'msg', N'Document order saved.', N'تم حفظ ترتيب المستندات.', N'Document order saved.'),
        ('msg.doc_order_unreadable', 'msg', N'The new order could not be read.', N'تعذّرت قراءة الترتيب الجديد.', N'The new order could not be read.'),
        ('msg.doc_order_one_section', 'msg', N'Document types can only be moved within their own section.', N'يمكن نقل أنواع المستندات داخل قسمها فقط.', N'Document types can only be moved within their own section.'),
        ('msg.doc_order_no_column', 'msg', N'Document types have no sort column yet. Re-run db/63, then try again.', N'لا يوجد عمود ترتيب لأنواع المستندات بعد. أعد تشغيل db/63 ثم حاول مرة أخرى.', N'Document types have no sort column yet. Re-run db/63, then try again.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Document order labels inserted: ', @LabelsInserted);
GO
