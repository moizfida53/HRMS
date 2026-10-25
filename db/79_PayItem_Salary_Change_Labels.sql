/* =====================================================================
   79_PayItem_Salary_Change_Labels.sql  -  HRMS: Pay Items salary change
   ---------------------------------------------------------------------
   Safe to re-run. Labels only (English + Arabic): editing an approved
   salary item shows the current amount with its own Effective from, and
   the month the new amount starts ("New amount from").
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.current_amount', 'pr', N'Current amount', N'المبلغ الحالي', NULL),
        ('pr.new_amount_from', 'pr', N'New amount from', N'المبلغ الجديد اعتباراً من', NULL),
        ('pr.new_amount_kwd', 'pr', N'New amount (KWD)', N'المبلغ الجديد (د.ك)', NULL),
        ('pr.new_amount_from_hint', 'pr', N'The current amount stays effective from {0} and is paid until the new one starts.', N'يبقى المبلغ الحالي سارياً من {0} ويُصرف حتى يبدأ المبلغ الجديد.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Pay item salary change labels inserted: ', @LabelsInserted);
GO
