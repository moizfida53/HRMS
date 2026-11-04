/* =====================================================================
   112_Salary_Revision_Form_Labels.sql  -  Salary Revisions: increment / decrement
   ---------------------------------------------------------------------
   Labels only (English + Arabic); safe to re-run. The Add salary revision
   form no longer asks for the item type (always the Basic Salary): the user
   picks Increment or Decrement and the amount, and sees the new revised
   salary worked out from the latest approved amount. The change is an
   amount (default) or a percentage. Salary Revisions show their own key
   figures (monthly salary, this month's increments / decrements) and table
   (Emp No, Employee, Basic, Increment, Decrement, Effective from, Comment,
   Status, Actions).
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
        ('pc.increment_by', 'pc', N'Increment by', N'زيادة بمقدار', NULL),
        ('pc.decrement_by', 'pc', N'Decrement by', N'تخفيض بمقدار', NULL),
        ('pc.revise_by', 'pc', N'Amount or percentage', N'مبلغ أو نسبة مئوية', NULL),
        ('pc.unit_amount', 'pc', N'Amount', N'مبلغ', NULL),
        ('js.pr_kwd', 'js', N'KWD', N'د.ك', NULL),
        ('js.pc_on_0', 'js', N'on {0}', N'على {0}', NULL),
        ('pc.kpi_increments_0', 'pc', N'Salary increments · {0}', N'زيادات الرواتب · {0}', NULL),
        ('pc.kpi_decrements_0', 'pc', N'Salary decrements · {0}', N'تخفيضات الرواتب · {0}', NULL),
        ('pc.kpi_n_revisions', 'pc', N'KWD · {0} revisions effective this month', N'د.ك · {0} تعديلات سارية هذا الشهر', NULL),
        ('pc.kpi_pending_n', 'pc', N'{0} salary revisions are waiting for approval - they are not paid until approved.', N'{0} تعديلات رواتب بانتظار الاعتماد - لا تُصرف قبل اعتمادها.', NULL),
        ('pc.col_emp_no', 'pc', N'Emp No', N'الرقم الوظيفي', NULL),
        ('pc.col_employee', 'pc', N'Employee Name', N'اسم الموظف', NULL),
        ('pc.col_basic', 'pc', N'Basic', N'الأساسي', NULL),
        ('pc.no_revisions_yet', 'pc', N'No salary revisions yet', N'لا توجد تعديلات رواتب بعد', NULL),
        ('pc.no_revisions_text', 'pc', N'The contract salary is paid every month. Add a salary revision for an increment or a decrement.', N'يُصرف راتب العقد كل شهر. أضف تعديل راتب للزيادة أو التخفيض.', NULL),
        ('pc.revise', 'pc', N'Revise the salary', N'تعديل الراتب', NULL),
        ('js.pc_enter_revision', 'js', N'Enter the increment or decrement amount.', N'أدخل مبلغ الزيادة أو التخفيض.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Salary revision form labels inserted: ', @LabelsInserted);
GO
