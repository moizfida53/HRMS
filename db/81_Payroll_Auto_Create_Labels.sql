/* =====================================================================
   81_Payroll_Auto_Create_Labels.sql  -  HRMS: labels for 80
   ---------------------------------------------------------------------
   Run after 80. Safe to re-run. Labels only (English + Arabic): Create
   Payroll by month - the payrolls of the month are worked out from each
   employee's payroll calendar, not chosen.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.cr_month_hint_auto', 'pr', N'Pick the month to pay. Each employee is paid by their assigned payroll calendar - nobody is paid twice for a month.', N'اختر الشهر المراد صرفه. يُصرف لكل موظف حسب تقويم الرواتب المعيّن له - ولا يُصرف لأحد مرتين في الشهر نفسه.', NULL),
        ('pr.cr_plan_title', 'pr', N'Payrolls for {0}', N'كشوف رواتب {0}', NULL),
        ('pr.cr_plan_auto_hint', 'pr', N'Worked out from each employee''s payroll calendar and its pay period of the month - nothing to choose.', N'تُحدَّد من تقويم الرواتب لكل موظف وفترة الصرف الخاصة به في الشهر - لا حاجة للاختيار.', NULL),
        ('pr.cr_plan_details', 'pr', N'Show how it is split', N'عرض طريقة التقسيم', NULL),
        ('pr.cr_nothing_to_create', 'pr', N'There is nothing to create for this month.', N'لا يوجد ما يُنشأ لهذا الشهر.', NULL),
        ('pr.cr_state_no_period', 'pr', N'No pay period in this month', N'لا توجد فترة صرف في هذا الشهر', NULL),
        ('pr.cr_state_generate', 'pr', N'Ready - the period is created on Next', N'جاهز - تُنشأ الفترة عند الضغط على التالي', NULL),
        ('pr.cr_state_closed', 'pr', N'Period closed', N'الفترة مغلقة', NULL),
        ('pr.cr_summary_one', 'pr', N'1 payroll · {0} employees', N'كشف رواتب واحد · {0} موظف', NULL),
        ('pr.cr_all_created', 'pr', N'Every regular payroll of {0} is already created - nobody is paid twice for a month. Choose Off-cycle for an extra payment.', N'تم إنشاء جميع كشوف الرواتب العادية لشهر {0} - لا يُصرف لأحد مرتين في الشهر. اختر خارج الدورة لصرف إضافي.', NULL),
        ('pr.cr_no_open_period_in', 'pr', N'{0} has no open pay period on the payroll calendars in use.', N'لا توجد فترة صرف مفتوحة لشهر {0} في تقاويم الرواتب المستخدمة.', NULL),
        ('pr.cr_nobody_to_pay', 'pr', N'No employee of this company is paid by an active payroll calendar.', N'لا يوجد موظف في هذه الشركة يُصرف له حسب تقويم رواتب نشط.', NULL),
        ('pr.cr_this_month', 'pr', N'this month', N'هذا الشهر', NULL),
        ('pr.cr_state_later', 'pr', N'Starts later', N'تبدأ لاحقاً', NULL),
        ('pr.cr_month_closed', 'pr', N'The pay periods of {0} are closed - its payrolls are done. Choose Off-cycle for an extra payment.', N'فترات الصرف لشهر {0} مغلقة - تم إنجاز كشوفها. اختر خارج الدورة لصرف إضافي.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Create Payroll by month labels inserted: ', @LabelsInserted);
GO
