/* =====================================================================
   87_Leave_Unpaid_Resume_Settlement_Labels.sql  -  HRMS: labels for 86
   ---------------------------------------------------------------------
   Run after 86. Safe to re-run. Labels only (English + Arabic): the paid /
   unpaid split of a leave request, the resume date, and the leave salary
   settlement (cash before the leave or the monthly payroll).
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('lv.resume_date', 'lv', N'Resume work on', N'تاريخ العودة للعمل', NULL),
        ('lv.resume_date_hint', 'lv', N'The next working day after the leave - for reference only, it does not change the balance.', N'أول يوم عمل بعد الإجازة - للعلم فقط ولا يؤثر على الرصيد.', NULL),
        ('lv.paid_days', 'lv', N'Paid days', N'أيام مدفوعة', NULL),
        ('lv.unpaid_days', 'lv', N'Unpaid days', N'أيام بدون راتب', NULL),
        ('lv.unpaid_note', 'lv', N'The balance does not cover all the days - the days over it are unpaid leave and are deducted from the salary.', N'الرصيد لا يغطي كل الأيام - الأيام الزائدة إجازة بدون راتب وتُخصم من الراتب.', NULL),
        ('lv.unpaid_confirm_title', 'lv', N'Send with unpaid leave?', N'إرسال الطلب مع إجازة بدون راتب؟', NULL),
        ('lv.unpaid_confirm_text', 'lv', N'Only {0} of the {1} days are covered by the leave balance. The other {2} days are unpaid leave and are deducted from the salary.', N'يغطي رصيد الإجازة {0} يوماً فقط من أصل {1}. الأيام الـ {2} الأخرى إجازة بدون راتب وتُخصم من الراتب.', NULL),
        ('lv.unpaid_confirm_ok', 'lv', N'Yes, send with unpaid days', N'نعم، أرسل مع الأيام بدون راتب', NULL),
        ('lv.h_unpaid', 'lv', N'Unpaid days agreed', N'الموافقة على أيام بدون راتب', NULL),
        ('lv.h_settled', 'lv', N'Leave salary settled', N'تمت تسوية راتب الإجازة', NULL),
        ('lv.leave_salary', 'lv', N'Leave salary', N'راتب الإجازة', NULL),
        ('lv.settle_cash', 'lv', N'In cash before the leave', N'نقداً قبل الإجازة', NULL),
        ('lv.settle_payroll', 'lv', N'With the monthly payroll', N'مع الراتب الشهري', NULL),
        ('lv.settle_not_yet', 'lv', N'Not settled - with the monthly payroll', N'لم تتم التسوية - مع الراتب الشهري', NULL),
        ('lv.cash_paid_on', 'lv', N'Paid on {0}', N'دُفع في {0}', NULL),
        ('lv.settlement', 'lv', N'Settlement', N'التسوية', NULL),
        ('lv.settlement_title', 'lv', N'Leave salary settlement', N'تسوية راتب الإجازة', NULL),
        ('lv.save_settlement', 'lv', N'Save settlement', N'حفظ التسوية', NULL),
        ('lv.monthly_salary', 'lv', N'Monthly salary', N'الراتب الشهري', NULL),
        ('lv.leave_salary_base', 'lv', N'Leave salary basis', N'أساس راتب الإجازة', NULL),
        ('lv.daily_leave_salary', 'lv', N'Daily leave salary', N'راتب الإجازة اليومي', NULL),
        ('lv.divided_by_n', 'lv', N'÷ {0} days', N'÷ {0} يوماً', NULL),
        ('lv.leave_salary_amount', 'lv', N'Leave salary due', N'راتب الإجازة المستحق', NULL),
        ('lv.no_salary_found', 'lv', N'No salary was found for the employee - add it on Pay Items or enter the amount.', N'لم يُعثر على راتب للموظف - أضفه في بنود الراتب أو أدخل المبلغ.', NULL),
        ('lv.how_paid', 'lv', N'How is the leave salary paid?', N'كيف يُدفع راتب الإجازة؟', NULL),
        ('lv.settle_payroll_hint', 'lv', N'Paid with the salary of the leave month(s), as usual.', N'يُدفع مع راتب شهر (أشهر) الإجازة كالمعتاد.', NULL),
        ('lv.settle_cash_hint', 'lv', N'Paid in cash before the leave starts - the payroll of the leave month(s) recovers it.', N'يُدفع نقداً قبل بدء الإجازة - ويُسترد من راتب شهر (أشهر) الإجازة.', NULL),
        ('lv.no_paid_days', 'lv', N'This leave has no paid days.', N'لا توجد أيام مدفوعة في هذه الإجازة.', NULL),
        ('lv.cash_amount', 'lv', N'Amount paid in cash', N'المبلغ المدفوع نقداً', NULL),
        ('lv.use_calculated', 'lv', N'Use the calculated amount ({0})', N'استخدم المبلغ المحسوب ({0})', NULL),
        ('lv.cash_paid_date', 'lv', N'Paid on', N'تاريخ الدفع', NULL),
        ('lv.cash_paid_date_hint', 'lv', N'Usually before the first day of the leave.', N'عادةً قبل أول يوم من الإجازة.', NULL),
        ('lv.remarks', 'lv', N'Remarks', N'ملاحظات', NULL),
        ('lv.settlement_locked', 'lv', N'A payroll has already started to recover the cash paid - the settlement can no longer be changed here.', N'بدأ أحد الرواتب باسترداد المبلغ النقدي - لم يعد بالإمكان تغيير التسوية هنا.', NULL),
        ('lv.payroll_effect', 'lv', N'What the payroll does', N'أثر ذلك على الرواتب', NULL),
        ('lv.payroll_effect_none', 'lv', N'Nothing extra - the salary is paid as usual.', N'لا شيء إضافي - يُدفع الراتب كالمعتاد.', NULL),
        ('lv.payroll_effect_hint', 'lv', N'Each line is a one-time pay item of the leave month (Payroll > Pay Items). A month whose payroll is already closed moves to the next month.', N'كل سطر بند راتب لمرة واحدة في شهر الإجازة (الرواتب > بنود الراتب). الشهر الذي أُغلق راتبه يُنقل إلى الشهر التالي.', NULL),
        ('lv.in_payroll', 'lv', N'In a payroll', N'ضمن مسير رواتب', NULL),
        ('lv.waiting_payroll', 'lv', N'Waiting for the payroll', N'بانتظار مسير الرواتب', NULL),
        ('sec.fn_leave_settle', 'sec', N'Leave salary settlement', N'تسوية راتب الإجازة', NULL),
        ('sec.fn_leave_settle_hint', 'sec', N'For an approved leave: pay the leave salary in cash before the leave, or with the monthly payroll', N'للإجازة المعتمدة: دفع راتب الإجازة نقداً قبل الإجازة أو مع الراتب الشهري', NULL),
        ('js.lv_split', 'js', N'Paid {0} days · Unpaid {1} days', N'مدفوعة {0} يوماً · بدون راتب {1} يوماً', NULL),
        ('js.lv_cash_amount_needed', 'js', N'Enter the amount paid in cash.', N'أدخل المبلغ المدفوع نقداً.', NULL),
        ('js.lv_cash_date_needed', 'js', N'Enter the day the cash is paid.', N'أدخل تاريخ الدفع النقدي.', NULL),
        ('msg.lv_resume', 'msg', N'The resume date must be after the last day of the leave.', N'يجب أن يكون تاريخ العودة للعمل بعد آخر يوم في الإجازة.', N'The resume date must be after the last day of the leave.'),
        ('msg.lv_settle_status', 'msg', N'The leave salary is settled for an approved leave only.', N'تتم تسوية راتب الإجازة للإجازة المعتمدة فقط.', N'The leave salary is settled for an approved leave only.'),
        ('msg.lv_settle_mode', 'msg', N'Choose how the leave salary is paid.', N'اختر طريقة دفع راتب الإجازة.', N'Choose how the leave salary is paid.'),
        ('msg.lv_settle_no_paid', 'msg', N'This leave has no paid days to pay in cash.', N'لا توجد أيام مدفوعة في هذه الإجازة لدفعها نقداً.', N'This leave has no paid days to pay in cash.'),
        ('msg.lv_settle_amount', 'msg', N'Enter the amount paid in cash.', N'أدخل المبلغ المدفوع نقداً.', N'Enter the amount paid in cash.'),
        ('msg.lv_settle_locked', 'msg', N'A payroll has already started to recover the cash paid - the settlement can no longer be changed (use Pay Items).', N'بدأ أحد الرواتب باسترداد المبلغ النقدي - لم يعد بالإمكان تغيير التسوية (استخدم بنود الراتب).', N'A payroll has already started to recover the cash paid - the settlement can no longer be changed (use Pay Items).'),
        ('msg.lv_settled_cash', 'msg', N'Settlement saved - the payroll of the leave month recovers the cash paid.', N'تم حفظ التسوية - يسترد راتب شهر الإجازة المبلغ النقدي المدفوع.', N'Settlement saved - the payroll of the leave month recovers the cash paid.'),
        ('msg.lv_settled_payroll', 'msg', N'Settlement saved - the leave salary is paid with the monthly payroll.', N'تم حفظ التسوية - يُدفع راتب الإجازة مع الراتب الشهري.', N'Settlement saved - the leave salary is paid with the monthly payroll.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Leave unpaid / resume / settlement labels inserted: ', @LabelsInserted);
GO
