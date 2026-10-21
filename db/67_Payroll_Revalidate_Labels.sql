/* =====================================================================
   67_Payroll_Revalidate_Labels.sql  -  HRMS: Revalidate refreshes the figures
   ---------------------------------------------------------------------
   Run after re-running 35_Payroll_Processing_StoredProcedures1.sql.
   Safe to re-run. Labels only (English + Arabic).

   Revalidate on Payroll Validation now first recalculates every employee
   of the payroll from the current employee records and pay items (a salary
   added from a "Fix" link counts), then re-runs the checks. A company
   without the default pay components gets them (Basic Salary pays the
   profile salary), and "No salary items" (V01) now says which of these it is.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('msg.pr_recalculated_and_validated', 'msg', N'Payroll recalculated and validation re-run.', N'أُعيد احتساب الرواتب وأُعيد التحقق.', N'Payroll recalculated and validation re-run.'),
        ('msg.pr_v01_item_not_in_force', 'msg', N'No salary item in force for this month - check the start / end month of the salary items on Pay Items', N'لا يوجد بند راتب سارٍ لهذا الشهر - تحقق من شهر البداية / النهاية لبنود الراتب في بنود الدفع', N'No salary item in force for this month - check the start / end month of the salary items on Pay Items'),
        ('msg.pr_v01_no_basic_component', 'msg', N'Salary on the employee profile could not be paid - the company has no Basic Salary pay component (Payroll Settings > Pay item types)', N'تعذّر صرف الراتب المسجّل في ملف الموظف - لا يوجد للشركة بند دفع للراتب الأساسي (إعدادات الرواتب > أنواع بنود الدفع)', N'Salary on the employee profile could not be paid - the company has no Basic Salary pay component (Payroll Settings > Pay item types)'),
        ('msg.pr_v01_no_salary_anywhere', 'msg', N'No salary items and no salary on the employee profile', N'لا توجد بنود راتب ولا راتب مسجّل في ملف الموظف', N'No salary items and no salary on the employee profile')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Revalidate labels inserted: ', @LabelsInserted);
GO
