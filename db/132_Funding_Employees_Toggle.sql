/* =====================================================================
   132_Funding_Employees_Toggle.sql  -  Payroll funding: Show / Hide the employees
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   Payroll funding: "Show the 6 employees" opens the list and scrolls it
   into view; the button then says "Hide the 6 employees".
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('fund.hide_employees_0', 'fund', N'Hide the {0} employees', N'إخفاء الموظفين ({0})', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
