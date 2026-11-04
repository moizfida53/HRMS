/* =====================================================================
   112_Salary_Revision_Form_Labels.sql  -  Salary Revisions: increment / decrement
   ---------------------------------------------------------------------
   Labels only (English + Arabic); safe to re-run. The Add salary revision
   form no longer asks for the item type (always the Basic Salary): the user
   picks Increment or Decrement and the amount, and sees the new revised
   salary worked out from the current one.
   ===================================================================== */
SET NOCOUNT ON;
GO
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pc.current_basic', 'pc', N'Current Basic Salary', N'الراتب الأساسي الحالي', NULL),
        ('pc.current_basic_hint', 'pc', N'Basic Salary in force now', N'الراتب الأساسي الساري الآن', NULL),
        ('pc.revision_type', 'pc', N'Revision', N'نوع التعديل', NULL),
        ('pc.increment_hint', 'pc', N'Raise the salary', N'رفع الراتب', NULL),
        ('pc.decrement_hint', 'pc', N'Lower the salary', N'تخفيض الراتب', NULL),
        ('pc.increment_amount', 'pc', N'Increment amount (KWD)', N'مبلغ الزيادة (د.ك)', NULL),
        ('pc.decrement_amount', 'pc', N'Decrement amount (KWD)', N'مبلغ التخفيض (د.ك)', NULL),
        ('pc.new_revised_salary', 'pc', N'New revised salary amount (KWD)', N'مبلغ الراتب الجديد بعد التعديل (د.ك)', NULL),
        ('pc.decrement_too_big', 'pc', N'The decrement must be less than the current salary.', N'يجب أن يكون التخفيض أقل من الراتب الحالي.', NULL),
        ('js.pc_enter_revision', 'js', N'Enter the increment or decrement amount.', N'أدخل مبلغ الزيادة أو التخفيض.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Salary revision form labels inserted: ', @LabelsInserted);
GO
