/* =====================================================================
   113_Component_Pages_Labels.sql  -  Earnings, Deductions, Loans: own figures and tables
   ---------------------------------------------------------------------
   Labels only (English + Arabic); safe to re-run.
     Earnings & Allowances  Earnings this month, Recurring allowances, One-time
                            earnings this month, Pending approval
     Deductions             Deductions this month, Recurring deductions, One-time
                            deductions this month, Instalment balance outstanding
     Loans & Advances       Outstanding balance, Instalments due this month,
                            Issued this year, Pending approval
   ===================================================================== */
SET NOCOUNT ON;
GO
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pc.kpi_earnings_0', 'pc', N'Earnings · {0}', N'الاستحقاقات · {0}', NULL),
        ('pc.kpi_deductions_0', 'pc', N'Deductions · {0}', N'الاستقطاعات · {0}', NULL),
        ('pc.kpi_n_employees_items', 'pc', N'KWD · {0} employees · {1} items', N'د.ك · {0} موظف · {1} بند', NULL),
        ('pc.kpi_recurring_allowances', 'pc', N'Recurring allowances', N'البدلات الشهرية', NULL),
        ('pc.kpi_recurring_deductions', 'pc', N'Recurring deductions', N'الاستقطاعات الشهرية', NULL),
        ('pc.kpi_per_month_n', 'pc', N'KWD per month · {0} items', N'د.ك شهرياً · {0} بند', NULL),
        ('pc.kpi_one_time_earnings_0', 'pc', N'One-time earnings · {0}', N'استحقاقات لمرة واحدة · {0}', NULL),
        ('pc.kpi_one_time_deductions_0', 'pc', N'One-time deductions · {0}', N'استقطاعات لمرة واحدة · {0}', NULL),
        ('pc.kpi_n_items', 'pc', N'KWD · {0} items', N'د.ك · {0} بند', NULL),
        ('pc.kpi_pending', 'pc', N'Pending approval', N'بانتظار الاعتماد', NULL),
        ('pc.kpi_n_waiting', 'pc', N'KWD · {0} waiting', N'د.ك · {0} بالانتظار', NULL),
        ('pc.kpi_instalment_balance', 'pc', N'Instalment balance', N'رصيد الأقساط', NULL),
        ('pc.kpi_n_running', 'pc', N'KWD outstanding · {0} running', N'د.ك مستحق · {0} جارٍ', NULL),
        ('pc.kpi_outstanding', 'pc', N'Outstanding balance', N'الرصيد المستحق', NULL),
        ('pc.kpi_due_0', 'pc', N'Instalments due · {0}', N'الأقساط المستحقة · {0}', NULL),
        ('pc.kpi_n_instalments', 'pc', N'KWD · {0} instalments', N'د.ك · {0} قسط', NULL),
        ('pc.kpi_issued_0', 'pc', N'Issued in {0}', N'الممنوح في {0}', NULL),
        ('pc.kpi_n_loans', 'pc', N'KWD · {0} loans and advances', N'د.ك · {0} قرض وسلفة', NULL),
        ('pc.kpi_pending_items_n', 'pc', N'{0} items are waiting for approval - they are not paid until approved.', N'{0} بنود بانتظار الاعتماد - لا تُصرف قبل اعتمادها.', NULL),
        ('pc.kpi_pending_loans_n', 'pc', N'{0} loans and advances are waiting for approval - they are not paid until approved.', N'{0} قروض وسلف بانتظار الاعتماد - لا تُصرف قبل اعتمادها.', NULL),
        ('pc.col_earning_type', 'pc', N'Earning type', N'نوع الاستحقاق', NULL),
        ('pc.col_deduction_type', 'pc', N'Deduction type', N'نوع الاستقطاع', NULL),
        ('pc.col_loan_type', 'pc', N'Loan / advance', N'القرض / السلفة', NULL),
        ('pc.col_applies', 'pc', N'Applies', N'التطبيق', NULL),
        ('pc.col_period', 'pc', N'Period', N'الفترة', NULL),
        ('pc.col_loan_amount', 'pc', N'Loan amount', N'مبلغ القرض', NULL),
        ('pc.col_instalment', 'pc', N'Instalment', N'القسط', NULL),
        ('pc.col_repaid', 'pc', N'Repaid', N'المسدد', NULL),
        ('pc.col_balance', 'pc', N'Balance', N'الرصيد', NULL),
        ('pc.col_start', 'pc', N'Start', N'البداية', NULL),
        ('pc.open_ended', 'pc', N'no end month', N'بدون شهر نهاية', NULL),
        ('pc.n_of_m_paid', 'pc', N'{0} of {1} paid', N'{0} من {1} مدفوع', NULL),
        ('pc.no_earnings_yet', 'pc', N'No earnings or allowances yet', N'لا توجد استحقاقات أو بدلات بعد', NULL),
        ('pc.no_earnings_text', 'pc', N'Add allowances, overtime, bonuses and commissions - each is paid once approved.', N'أضف البدلات والعمل الإضافي والمكافآت والعمولات - كل منها يُصرف بعد الاعتماد.', NULL),
        ('pc.no_deductions_yet', 'pc', N'No deductions yet', N'لا توجد استقطاعات بعد', NULL),
        ('pc.no_deductions_text', 'pc', N'Add absence, penalties and other deductions - each is taken once approved.', N'أضف الغياب والجزاءات والاستقطاعات الأخرى - كل منها يُخصم بعد الاعتماد.', NULL),
        ('pc.no_loans_yet', 'pc', N'No loans or advances yet', N'لا توجد قروض أو سلف بعد', NULL),
        ('pc.no_loans_text', 'pc', N'A loan or advance is repaid in monthly instalments and cannot be more than the Basic Salary.', N'يُسدد القرض أو السلفة بأقساط شهرية ولا يمكن أن يزيد عن الراتب الأساسي.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Component page labels inserted: ', @LabelsInserted);
GO
