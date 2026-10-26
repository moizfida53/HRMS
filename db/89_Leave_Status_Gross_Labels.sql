/* =====================================================================
   89_Leave_Status_Gross_Labels.sql  -  HRMS: labels
   ---------------------------------------------------------------------
   Run after 88. Safe to re-run. Labels only (English + Arabic): the
   "Currently on leave" filter and figure on Leave Management, and the
   hint under Gross Monthly on the employee profile (it now adds up as
   the figures are typed).
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('lv.f_currently_on_leave', 'lv', N'Currently on leave', N'في إجازة حالياً', NULL),
        ('lv.kpi_currently_on_leave', 'lv', N'Currently on leave', N'في إجازة حالياً', NULL),
        ('emp.basic_plus_allowances', 'emp', N'Basic + allowances.', N'الأساسي + البدلات.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Leave status / gross labels inserted: ', @LabelsInserted);
GO
