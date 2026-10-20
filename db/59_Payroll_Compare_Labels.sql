/* =====================================================================
   59_Payroll_Compare_Labels.sql  -  HRMS: English + Arabic labels of Payroll Comparison
   ---------------------------------------------------------------------
   Run after 33 (Core.UiLabels) and 36. Idempotent: new keys are
   inserted; existing keys are only completed (an empty ArabicText /
   SourceText is filled in) - text already edited in the table is never
   overwritten by a re-run. No table or procedure change: the comparison
   reads the existing LIST / LINES actions of Payroll.usp_PayrollRunEmployee_Manage.

     pr.cmp_*      Payroll Comparison page (/payroll/compare) and its Excel export
     js.pr_cmp_*   texts used by wwwroot/js/payroll.js
     msg.pr_cmp_*  PayrollController messages - matched by their SourceText
   ===================================================================== */
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'tempdb..#Seed') IS NOT NULL DROP TABLE #Seed;
CREATE TABLE #Seed (
    LabelKey    VARCHAR(150)   COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    Module      VARCHAR(30)    COLLATE DATABASE_DEFAULT NOT NULL,
    EnglishText NVARCHAR(1000) COLLATE DATABASE_DEFAULT NOT NULL,
    ArabicText  NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
    SourceText  NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('pr.payroll_comparison', 'pr', N'Payroll Comparison', N'مقارنة الرواتب', NULL),
    ('pr.cmp_subtitle', 'pr', N'Compare up to three payrolls of one company - closed or still in progress', N'قارن حتى ثلاثة مسيرات رواتب لشركة واحدة - مغلقة أو قيد المعالجة', NULL),
    ('pr.cmp_compare_payrolls', 'pr', N'Compare payrolls', N'مقارنة المسيرات', NULL),
    ('pr.cmp_pick_hint', 'pr', N'Pick the company, then two or three of its payrolls. The first one is the baseline; every difference is shown against it.', N'اختر الشركة ثم مسيرين أو ثلاثة من مسيراتها. المسير الأول هو الأساس، وتُحسب كل الفروقات مقارنةً به.', NULL),
    ('pr.cmp_same_company_only', 'pr', N'Only payrolls of the same company can be compared.', N'يمكن مقارنة مسيرات الشركة نفسها فقط.', NULL),
    ('pr.cmp_payroll_baseline', 'pr', N'Payroll A (baseline)', N'المسير أ (الأساس)', NULL),
    ('pr.cmp_payroll_2', 'pr', N'Payroll B', N'المسير ب', NULL),
    ('pr.cmp_payroll_3_optional', 'pr', N'Payroll C (optional)', N'المسير ج (اختياري)', NULL),
    ('pr.cmp_choose_payroll', 'pr', N'Choose a payroll', N'اختر مسيراً', NULL),
    ('pr.cmp_none', 'pr', N'None', N'لا يوجد', NULL),
    ('pr.cmp_not_closed', 'pr', N'Not closed', N'غير مغلق', NULL),
    ('pr.cmp_not_closed_may_change', 'pr', N'Not closed - figures can still change', N'غير مغلق - قد تتغير الأرقام', NULL),
    ('pr.cmp_final', 'pr', N'Closed - final figures', N'مغلق - أرقام نهائية', NULL),
    ('pr.cmp_figures', 'pr', N'Figures', N'الأرقام', NULL),
    ('pr.cmp_swap', 'pr', N'Swap A and B', N'تبديل أ و ب', NULL),
    ('pr.cmp_swap_hint', 'pr', N'Make payroll B the baseline', N'اجعل المسير ب هو الأساس', NULL),
    ('pr.cmp_export_excel', 'pr', N'Export to Excel', N'تصدير إلى Excel', NULL),
    ('pr.cmp_needs_two_payrolls', 'pr', N'This company needs at least two payrolls (registered or later, not cancelled) to compare.', N'تحتاج هذه الشركة إلى مسيرين على الأقل (مسجلين أو بعد ذلك، وغير ملغيين) للمقارنة.', NULL),
    ('pr.cmp_empty_title', 'pr', N'Pick two or three payrolls', N'اختر مسيرين أو ثلاثة', NULL),
    ('pr.cmp_empty_text', 'pr', N'Totals, pay items and employees are compared side by side, with the differences against the baseline.', N'تُقارن الإجماليات وبنود الرواتب والموظفون جنباً إلى جنب، مع الفروقات مقارنةً بالأساس.', NULL),
    ('pr.cmp_baseline', 'pr', N'Baseline', N'الأساس', NULL),
    ('pr.cmp_vs_baseline', 'pr', N'vs baseline', N'مقارنةً بالأساس', NULL),
    ('pr.cmp_one_not_closed', 'pr', N'1 selected payroll is not closed yet:', N'مسير واحد من المسيرات المختارة لم يُغلق بعد:', NULL),
    ('pr.cmp_n_not_closed', 'pr', N'{0} selected payrolls are not closed yet:', N'{0} من المسيرات المختارة لم تُغلق بعد:', NULL),
    ('pr.cmp_not_closed_explain', 'pr', N'Their figures can still change until they are approved and closed - use this to check the current payroll against a previous one.', N'قد تتغير أرقامها حتى يتم اعتمادها وإغلاقها - استخدم ذلك لمراجعة المسير الحالي مقابل مسير سابق.', NULL),
    ('pr.cmp_sheet_summary', 'pr', N'Summary', N'الملخص', NULL),
    ('pr.cmp_sheet_items', 'pr', N'Pay items', N'بنود الرواتب', NULL),
    ('pr.cmp_sheet_employees', 'pr', N'Employees', N'الموظفون', NULL),
    ('pr.cmp_measure', 'pr', N'Measure', N'البند', NULL),
    ('pr.cmp_joiners', 'pr', N'Joiners', N'المنضمون', NULL),
    ('pr.cmp_leavers', 'pr', N'Leavers', N'المغادرون', NULL),
    ('pr.cmp_pay_item', 'pr', N'Pay item', N'بند الراتب', NULL),
    ('pr.cmp_employees_short', 'pr', N'employees', N'موظف', NULL),
    ('pr.cmp_no_items', 'pr', N'No pay item lines in these payrolls.', N'لا توجد بنود رواتب في هذه المسيرات.', NULL),
    ('pr.cmp_change', 'pr', N'Change', N'التغيير', NULL),
    ('pr.cmp_search_employee', 'pr', N'Search employee', N'بحث عن موظف', NULL),
    ('pr.cmp_all_employees', 'pr', N'All employees', N'جميع الموظفين', NULL),
    ('pr.cmp_with_difference', 'pr', N'With a difference', N'بها فرق', NULL),
    ('pr.cmp_kind_changed', 'pr', N'Changed', N'تغيّر', NULL),
    ('pr.cmp_kind_new', 'pr', N'New', N'جديد', NULL),
    ('pr.cmp_kind_missing', 'pr', N'Not in every payroll', N'غير موجود في كل المسيرات', NULL),
    ('pr.cmp_kind_same', 'pr', N'No change', N'بلا تغيير', NULL),
    ('pr.cmp_0_of_1_employees', 'pr', N'{0} of {1} employees', N'{0} من {1} موظف', NULL),
    ('pr.cmp_not_in_payroll', 'pr', N'Not in payroll', N'غير مدرج', NULL),
    ('pr.cmp_no_employee_matches', 'pr', N'No employee matches the filter.', N'لا يوجد موظف يطابق التصفية.', NULL),
    ('js.pr_cmp_not_closed', 'js', N'Not closed - figures can still change', N'غير مغلق - قد تتغير الأرقام', NULL),
    ('js.pr_cmp_pick_two', 'js', N'Choose at least two different payrolls to compare.', N'اختر مسيرين مختلفين على الأقل للمقارنة.', NULL),
    ('msg.pr_cmp_choose_two', 'msg', N'Choose at least two different payrolls to compare.', N'اختر مسيرين مختلفين على الأقل للمقارنة.', N'Choose at least two different payrolls to compare.'),
    ('msg.pr_cmp_up_to_three', 'msg', N'Up to three payrolls can be compared at a time.', N'يمكن مقارنة ثلاثة مسيرات كحد أقصى في المرة الواحدة.', N'Up to three payrolls can be compared at a time.'),
    ('msg.pr_cmp_not_found', 'msg', N'A selected payroll was not found, or it is cancelled.', N'لم يتم العثور على أحد المسيرات المختارة، أو أنه ملغى.', N'A selected payroll was not found, or it is cancelled.'),
    ('msg.pr_cmp_same_company', 'msg', N'Only payrolls of the same company can be compared.', N'يمكن مقارنة مسيرات الشركة نفسها فقط.', N'Only payrolls of the same company can be compared.');
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM   #Seed AS s
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey AND l.Deleted = 0);

DECLARE @Inserted INT = @@ROWCOUNT;

UPDATE l
   SET l.ArabicText = ISNULL(NULLIF(l.ArabicText, N''), s.ArabicText),
       l.SourceText = ISNULL(l.SourceText, s.SourceText)
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.LabelKey = l.LabelKey
WHERE  l.Deleted = 0
  AND (   (NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL)
       OR (l.SourceText IS NULL AND s.SourceText IS NOT NULL));

DECLARE @Completed INT = @@ROWCOUNT;

/* controller messages harvested earlier as msg.auto_* get their Arabic too */
UPDATE l
   SET l.ArabicText = s.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.Module = 'msg' AND l.EnglishText = s.EnglishText COLLATE Latin1_General_BIN
WHERE  l.Deleted = 0 AND l.LabelKey LIKE 'msg.auto[_]%' AND NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL;

PRINT CONCAT(N'Payroll comparison labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
