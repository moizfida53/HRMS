/* =====================================================================
   101_Organization_Document_Groups_Labels.sql  -  HRMS: labels
   ---------------------------------------------------------------------
   Safe to re-run. Labels only (English + Arabic): the foldable document
   categories on Workforce > Organizations (Collapse all / Expand all).
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('od.collapse_all', 'od', N'Collapse all', N'طي الكل', NULL),
        ('od.expand_all', 'od', N'Expand all', N'توسيع الكل', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Organization document group labels inserted: ', @LabelsInserted);
GO
