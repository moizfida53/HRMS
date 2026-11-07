/* =====================================================================
   125_Deduction_Number_Of_Months.sql  -  Add deduction: Number of months
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   Add / Edit deduction (Every month or In instalments): a Number of
   months field sits beside To month. A number typed sets the To month
   (From month + months - 1) and locks it; with no number the To month is
   picked and the Number of months shows what it comes to (still
   editable). Changing the From month moves the To month with it.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.number_of_months', 'pr', N'Number of months', N'عدد الأشهر', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Deduction labels inserted: ', @@ROWCOUNT);
GO
