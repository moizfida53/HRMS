/* =====================================================================
   54_Payroll_Dashboard_Labels.sql  -  HRMS: English + Arabic labels of
   the Payroll Dashboard (/payroll/dashboard)
   ---------------------------------------------------------------------
   Run after 53. Idempotent: new keys are inserted, existing keys only
   completed (text already edited in Core.UiLabels is never overwritten).

     dash.*     Views/PayrollDashboard/Index.cshtml
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
    ('dash.subtitle', 'dash', N'{0} at a glance: figures, trend and what needs attention', N'{0} في لمحة: الأرقام والاتجاه وما يحتاج إلى متابعة', NULL),
    ('dash.kwd', 'dash', N'KWD', N'د.ك', NULL),
    ('dash.kwd_thousands', 'dash', N'KWD thousands', N'آلاف د.ك', NULL),
    ('dash.show', 'dash', N'Show', N'عرض', NULL),
    ('dash.cut_off_0', 'dash', N'cut-off {0}', N'تاريخ الإقفال {0}', NULL),
    ('dash.no_payroll_yet', 'dash', N'No payroll calendar for this month yet', N'لا يوجد تقويم رواتب لهذا الشهر بعد', NULL),
    ('dash.not_started', 'dash', N'Not started', N'لم يبدأ', NULL),
    ('dash.n_payrolls', 'dash', N'{0} payrolls', N'{0} رواتب', NULL),
    ('dash.create_payroll', 'dash', N'Create the payroll', N'إنشاء الرواتب', NULL),
    ('dash.vs_0', 'dash', N'vs {0}', N'مقارنة بـ {0}', NULL),
    ('dash.cost_hint', 'dash', N'Gross {0} + employer PIFSS {1}', N'الإجمالي {0} + حصة صاحب العمل في التأمينات {1}', NULL),
    ('dash.no_figures', 'dash', N'No payroll figures yet', N'لا توجد أرقام رواتب بعد', NULL),
    ('dash.n_employees', 'dash', N'{0} employees', N'{0} موظفين', NULL),
    ('dash.n_items', 'dash', N'{0} items', N'{0} بنود', NULL),
    ('dash.all_clear', 'dash', N'All clear', N'لا توجد ملاحظات', NULL),
    ('dash.all_clear_text', 'dash', N'Nothing needs your attention for this month.', N'لا شيء يحتاج إلى متابعتك لهذا الشهر.', NULL),
    ('dash.n_more_departments', 'dash', N'+ {0} more departments', N'+ {0} أقسام أخرى', NULL),
    ('dash.no_periods', 'dash', N'No pay periods yet', N'لا توجد فترات رواتب بعد', NULL),
    ('dash.qa_payrolls', 'dash', N'Process payroll', N'معالجة الرواتب', NULL),
    ('dash.qa_journal', 'dash', N'Payroll journal', N'قيد الرواتب', NULL),
    ('dash.qa_reports', 'dash', N'Payroll reports', N'تقارير الرواتب', NULL),
    ('dash.att_errors', 'dash', N'Validation errors to fix', N'أخطاء تحقق يجب تصحيحها', NULL),
    ('dash.att_payments_failed', 'dash', N'Bank payments failed', N'دفعات بنكية فاشلة', NULL),
    ('dash.att_warnings', 'dash', N'Payroll warnings to review', N'تنبيهات رواتب للمراجعة', NULL),
    ('dash.att_permits', 'dash', N'Work permits expiring this month', N'تصاريح عمل تنتهي هذا الشهر', NULL),
    ('dash.att_unverified', 'dash', N'Payroll rules not verified yet', N'قواعد رواتب لم يتم التحقق منها بعد', NULL),
    ('dash.att_items_pending', 'dash', N'Pay items waiting for approval', N'بنود رواتب بانتظار الموافقة', NULL),
    ('dash.att_loans_pending', 'dash', N'Loans and advances waiting for approval', N'قروض وسلف بانتظار الموافقة', NULL),
    ('dash.att_bank_files', 'dash', N'Closed payrolls without a bank file', N'رواتب مغلقة بدون ملف بنك', NULL),
    ('dash.att_journals_make', 'dash', N'Closed payrolls without a journal', N'رواتب مغلقة بدون قيد', NULL),
    ('dash.att_journals_post', 'dash', N'Journals not posted to the GL yet', N'قيود لم تُرحّل إلى دفتر الأستاذ بعد', NULL);
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

/* messages harvested by an earlier run of db/33 (msg.auto_*) get their Arabic too */
UPDATE l
   SET l.ArabicText = s.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.Module = 'msg' AND l.EnglishText = s.EnglishText COLLATE Latin1_General_BIN
WHERE  l.Deleted = 0 AND l.LabelKey LIKE 'msg.auto[_]%' AND NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL;

PRINT CONCAT(N'Payroll Dashboard labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
