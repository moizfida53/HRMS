/* =====================================================================
   114_Deduction_Form_Labels.sql  -  Add deduction: Total Amount and period
   ---------------------------------------------------------------------
   Labels only (English + Arabic); safe to re-run. The Add deduction form
   no longer asks for the amount per instalment. It asks for the Item type
   and Applies, then the From and To month, then the Total Amount, and shows
   the Monthly Deductible amount worked out from them (total / months, From
   and To both counted). No table or procedure changes: the monthly amount
   is posted as the item's Amount and the months as its instalments.
   ===================================================================== */
SET NOCOUNT ON;
GO
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.to_month', 'pr', N'To month', N'إلى شهر', NULL),
        ('pr.total_deduction_kwd', 'pr', N'Total amount of the deduction (KWD)', N'إجمالي مبلغ الاستقطاع (د.ك)', NULL),
        ('pr.monthly_deductible_kwd', 'pr', N'Monthly deductible amount (KWD)', N'مبلغ الاستقطاع الشهري (د.ك)', NULL),
        ('pr.monthly_deduction_kwd', 'pr', N'Monthly deduction amount (KWD)', N'مبلغ الاستقطاع الشهري (د.ك)', NULL),
        ('js.pi_ded_open', 'js', N'No To month: deducted every month until it is ended.', N'بدون شهر انتهاء: يُستقطع كل شهر حتى يتم إنهاؤه.', NULL),
        ('js.pi_ded_months', 'js', N'{0} × {1} months', N'{0} × {1} أشهر', NULL),
        ('js.pi_ded_rounded', 'js', N'{0} × {1} months = {2} (rounded to the fils)', N'{0} × {1} أشهر = {2} (بعد التقريب إلى الفلس)', NULL),
        ('js.pi_ded_enter_total', 'js', N'Enter the total amount of the deduction.', N'أدخل إجمالي مبلغ الاستقطاع.', NULL),
        ('js.pi_ded_enter_monthly', 'js', N'Enter the monthly deduction amount.', N'أدخل مبلغ الاستقطاع الشهري.', NULL),
        ('js.pi_ded_pick_to', 'js', N'Select the month of the last instalment.', N'اختر شهر آخر قسط.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Deduction form labels inserted: ', @LabelsInserted);
GO
