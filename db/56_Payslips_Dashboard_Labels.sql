/* =====================================================================
   56_Payslips_Dashboard_Labels.sql  -  HRMS: English + Arabic labels of
   the Generate Payslips list (payrolls, View / View Payslips popups) and
   the per-company bars of the Payroll Dashboard trend
   ---------------------------------------------------------------------
   Run after db/43 (re-run it: RUNS returns the payslips still to
   generate) and db/53 (re-run it: TREND_CO). Idempotent: new keys are
   inserted, existing keys only completed.

     ps.*       Views/Payslips/Generate.cshtml
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
    ('dash.companies', 'dash', N'Companies', N'الشركات', NULL),
    ('dash.total_0', 'dash', N'Total {0}', N'الإجمالي {0}', NULL),
    ('dash.trend_by_company', 'dash', N'Net payroll per company, last 12 months', N'صافي الرواتب لكل شركة، آخر 12 شهراً', NULL),
    ('ps.0_of_1_generated', 'ps', N'{0} of {1} generated', N'تم إنشاء {0} من {1}', NULL),
    ('ps.after_close', 'ps', N'After the payroll is closed', N'بعد إغلاق الرواتب', NULL),
    ('ps.all_generated_title', 'ps', N'Every payslip is generated', N'تم إنشاء جميع قسائم الرواتب', NULL),
    ('ps.all_generated_text', 'ps', N'No closed payroll has payslips left to generate. Show all payrolls to see them.', N'لا توجد رواتب مغلقة متبقٍ لها قسائم للإنشاء. اعرض جميع الرواتب لرؤيتها.', NULL),
    ('ps.email_payslips', 'ps', N'Email payslips', N'إرسال القسائم بالبريد', NULL),
    ('ps.n_payrolls_pending', 'ps', N'{0} payrolls have payslips to generate.', N'{0} رواتب لديها قسائم للإنشاء.', NULL),
    ('ps.n_to_generate', 'ps', N'{0} to generate', N'{0} للإنشاء', NULL),
    ('ps.search_payrolls', 'ps', N'Search payroll, company or calendar', N'ابحث عن الرواتب أو الشركة أو التقويم', NULL),
    ('ps.show', 'ps', N'Show', N'عرض', NULL),
    ('ps.show_pending', 'ps', N'To generate', N'للإنشاء', NULL),
    ('ps.show_open', 'ps', N'Not closed yet', N'غير مغلقة بعد', NULL),
    ('ps.show_done', 'ps', N'All generated', N'تم إنشاء الكل', NULL),
    ('ps.show_all', 'ps', N'All payrolls', N'جميع الرواتب', NULL),
    ('ps.show_pending_link', 'ps', N'Show them', N'اعرضها', NULL),
    ('ps.view_payroll_0', 'ps', N'Generate the payslips of payroll {0}', N'إنشاء قسائم الرواتب {0}', NULL),
    ('pr.pending_generate_payslips', 'pr', N'Pending Generate PaySlips', N'قسائم بانتظار الإنشاء', NULL),
    ('pr.goto_payslips', 'pr', N'Goto PaySlips', N'الانتقال إلى القسائم', NULL),
    ('pr.no_payslips_pending_text', 'pr', N'Every closed payroll has its payslips generated.', N'تم إنشاء قسائم جميع الرواتب المغلقة.', NULL);
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

PRINT CONCAT(N'Payslips and dashboard labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
