/* =====================================================================
   109_PayItem_Reference_Labels.sql  -  Add pay item: what the employee has now
   ---------------------------------------------------------------------
   Labels only (English + Arabic); safe to re-run. Picking an employee in
   Add / edit pay item shows their salary, allowances, earnings, deductions
   and loans with what was paid and what is still due; picking a class shows
   its items, picking an item type sums up the current (or earlier) amount.
   ===================================================================== */
SET NOCOUNT ON;
GO
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pi.ref_title', 'pi', N'What the employee has now', N'ما لدى الموظف حالياً', NULL),
        ('pi.ref_monthly_earnings', 'pi', N'Monthly earnings', N'الاستحقاقات الشهرية', NULL),
        ('pi.ref_monthly_deductions', 'pi', N'Monthly deductions', N'الاستقطاعات الشهرية', NULL),
        ('pi.ref_loans_due', 'pi', N'Loans / advances due', N'القروض / السلف المستحقة', NULL),
        ('pi.ref_none', 'pi', N'This employee has no pay items yet.', N'لا توجد بنود رواتب لهذا الموظف بعد.', NULL),
        ('pi.ref_none_of_class', 'pi', N'Nothing of this class now.', N'لا يوجد شيء من هذا النوع حالياً.', NULL),
        ('pi.ref_paid', 'pi', N'Paid', N'المدفوع', NULL),
        ('pi.ref_due', 'pi', N'Due', N'المستحق', NULL),
        ('pi.ref_paid_n', 'pi', N'{0} payrolls', N'{0} مسيرات', NULL),
        ('pi.ref_due_0', 'pi', N'KWD {0} due', N'مستحق {0} د.ك', NULL),
        ('pi.ref_earlier_n', 'pi', N'Earlier items ({0})', N'بنود سابقة ({0})', NULL),
        ('pi.ref_focus_current', 'pi', N'{0} - current', N'{0} - الحالي', NULL),
        ('pi.ref_focus_before', 'pi', N'{0} - before (not in force now)', N'{0} - سابقاً (غير سارٍ الآن)', NULL),
        ('pi.select_employee_first', 'pi', N'Select the employee first - the item types are those of their company.', N'اختر الموظف أولاً - أنواع البنود هي الخاصة بشركته.', NULL),
        ('common.rows_per_page', 'common', N'Rows per page', N'عدد الصفوف في الصفحة', NULL),
        ('pi.ref_focus_none', 'pi', N'{0} - none yet for this employee', N'{0} - لا يوجد بعد لهذا الموظف', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Pay item reference labels inserted: ', @@ROWCOUNT);
GO
