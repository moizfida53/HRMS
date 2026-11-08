/* =====================================================================
   131_Bank_Steps_Collapse.sql  -  Bank File: the two steps fold
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   Bank File > Two steps: the step to do now is open, the other folded to
   a one-line summary (status, employees, amount, bank file) - Step 1
   open until its file is generated, then Step 2. Either opens on a click.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('fin.step_done', 'fin', N'Done', N'تم', NULL),
        ('fin.step_todo', 'fin', N'To do', N'مطلوب', NULL),
        ('fin.step_waiting', 'fin', N'After step 1', N'بعد الخطوة 1', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
