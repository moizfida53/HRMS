/* =====================================================================
   67_Payroll_Revalidate_Labels.sql  -  HRMS: Revalidate refreshes the figures
   ---------------------------------------------------------------------
   Run after re-running 35_Payroll_Processing_StoredProcedures1.sql.
   Safe to re-run. Labels only (English + Arabic).

   Revalidate on Payroll Validation now first recalculates every employee
   of the payroll from the current employee records and pay items (a salary
   added from a "Fix" link counts), then re-runs the checks.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('msg.pr_recalculated_and_validated', 'msg', N'Payroll recalculated and validation re-run.', N'أُعيد احتساب الرواتب وأُعيد التحقق.', N'Payroll recalculated and validation re-run.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Revalidate labels inserted: ', @LabelsInserted);
GO
