/* =====================================================================
   45_Payroll_Processing_Sections_Labels.sql  -  HRMS: labels of the split
   Payroll Processing sections (Payrolls / Payroll Calendar / Period /
   Payroll History), the Payslips sub-sections and the record counts in
   the sidebar
   ---------------------------------------------------------------------
   Run after 33 (Core.UiLabels). No table or procedure changes - only
   labels. Idempotent: new keys are inserted, existing keys only completed
   (text already edited in Core.UiLabels is never overwritten).
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
    ('pr.payrolls_subtitle', 'pr', N'Open payrolls and their stage - open one to work on it at its stage', N'مسيرات الرواتب المفتوحة ومرحلتها - افتح المسير للعمل عليه في مرحلته', NULL),
    ('pr.calendars_subtitle', 'pr', N'Pay groups: frequency, cut-off and pay day, working-days basis', N'مجموعات الرواتب: الدورية ويوم الإقفال ويوم الصرف وأساس أيام العمل', NULL),
    ('pr.periods_subtitle', 'pr', N'The periods of a payroll calendar - generate a year, edit or delete an open period', N'فترات تقويم الرواتب - أنشئ فترات سنة أو عدّل فترة مفتوحة أو احذفها', NULL),
    ('pr.open_payrolls', 'pr', N'Open payrolls', N'المسيرات المفتوحة', NULL),
    ('pr.no_open_payrolls', 'pr', N'No open payrolls', N'لا توجد مسيرات مفتوحة', NULL),
    ('pr.no_open_payrolls_text', 'pr', N'Every payroll is closed or cancelled - see Payroll History, or create the next payroll.', N'جميع المسيرات مغلقة أو ملغاة - راجع سجل الرواتب أو أنشئ المسير التالي.', NULL),
    ('pr.no_calendars_for_periods', 'pr', N'Add a payroll calendar first - periods belong to a calendar.', N'أضف تقويم رواتب أولاً - الفترات تتبع التقويم.', NULL),
    ('pr.periods_of_0', 'pr', N'Periods of {0}', N'فترات {0}', NULL),
    ('layout.nav_count_payrolls', 'layout', N'{0} open payrolls', N'{0} مسيرات مفتوحة', NULL),
    ('layout.nav_count_calendars', 'layout', N'{0} active payroll calendars', N'{0} تقاويم رواتب نشطة', NULL),
    ('layout.nav_count_periods', 'layout', N'{0} open periods this year', N'{0} فترات مفتوحة هذا العام', NULL),
    ('layout.nav_count_slips_to_generate', 'layout', N'{0} payslips to generate (new or outdated)', N'{0} كشوف بانتظار الإصدار (جديدة أو غير محدّثة)', NULL),
    ('layout.nav_count_slips_generated', 'layout', N'{0} payslips generated', N'{0} كشوف صادرة', NULL),
    ('layout.nav_count_slips_to_email', 'layout', N'{0} payslip emails to send (not sent or failed)', N'{0} رسائل كشوف بانتظار الإرسال (لم تُرسل أو تعذّر إرسالها)', NULL);
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

PRINT CONCAT(N'Payroll Processing section labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
