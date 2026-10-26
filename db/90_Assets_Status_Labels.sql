/* =====================================================================
   90_Assets_Status_Labels.sql  -  HRMS: labels for Workforce > Assets
   ---------------------------------------------------------------------
   Run after 85. Safe to re-run. Labels only (English + Arabic): the
   figures renamed In use (all assets) / Assigned / Not assigned, the same
   words on each asset's status, and the arrows that scroll the types.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('as.in_use', 'as', N'In use', N'قيد الاستخدام', NULL),
        ('as.assigned', 'as', N'Assigned', N'مُسلَّم', NULL),
        ('as.not_assigned', 'as', N'Not assigned', N'غير مُسلَّم', NULL),
        ('as.scroll_back', 'as', N'Previous types', N'الأنواع السابقة', NULL),
        ('as.scroll_more', 'as', N'More types', N'مزيد من الأنواع', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Asset status labels inserted: ', @LabelsInserted);
GO
