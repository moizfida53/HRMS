/* =====================================================================
   55_Payroll_Exclusion_Labels.sql  -  HRMS: English + Arabic labels of
   excluding employees from a payroll and paying them separately
   ---------------------------------------------------------------------
   Run after db/35 (re-run it: exclude / include in Validation, the
   off-cycle catch-up of excluded employees). Idempotent: new keys are
   inserted, existing keys only completed (text already edited in
   Core.UiLabels is never overwritten).

     pr.*       Payrolls grid, Validation, the excluded list
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
    ('pr.0_excluded', 'pr', N'{0} excluded', N'{0} مستبعد', NULL),
    ('pr.0_excluded_hint', 'pr', N'{0} employees are left out of this payroll and are paid separately', N'{0} موظفين مستبعدون من هذه الرواتب ويُدفع لهم بشكل منفصل', NULL),
    ('pr.exclude_0_from_this_payroll', 'pr', N'Exclude {0} from this payroll', N'استبعاد {0} من هذه الرواتب', NULL),
    ('pr.exclude_issue_text', 'pr', N'The employee is not paid by this payroll and is flagged "Excluded". Once this payroll is closed, an off-cycle payroll of the same period pays the employee separately (salary, pay items of the month, PIFSS), with its own payslip. The checks re-run.', N'لن يُدفع للموظف في هذه الرواتب وسيُعلَّم بأنه "مستبعد". بعد إغلاق هذه الرواتب، تدفع له رواتب خارج الدورة لنفس الفترة بشكل منفصل (الراتب وبنود الشهر والتأمينات) مع قسيمة راتب خاصة. ستُعاد عمليات التحقق.', NULL),
    ('pr.exclude_here_or_correct', 'pr', N'Exclude the employee from this payroll (Exclude on the issue) or go back to the register to correct the data.', N'استبعد الموظف من هذه الرواتب (زر استبعاد على الملاحظة) أو ارجع إلى السجل لتصحيح البيانات.', NULL),
    ('pr.create_offcycle_for_excluded', 'pr', N'Create off-cycle payroll', N'إنشاء رواتب خارج الدورة', NULL),
    ('pr.separate_payment', 'pr', N'Separate payment', N'الدفع المنفصل', NULL),
    ('pr.net_0_kwd', 'pr', N'Net {0} KWD', N'الصافي {0} د.ك', NULL),
    ('pr.payment_pending', 'pr', N'Payment pending', N'الدفع معلق', NULL),
    ('pr.paid_by_next_offcycle', 'pr', N'Paid by the next off-cycle payroll of this period', N'يُدفع في الرواتب التالية خارج الدورة لهذه الفترة', NULL),
    ('pr.after_this_payroll_closes', 'pr', N'Off-cycle payroll after this payroll is closed', N'رواتب خارج الدورة بعد إغلاق هذه الرواتب', NULL);
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

PRINT CONCAT(N'Payroll exclusion labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
