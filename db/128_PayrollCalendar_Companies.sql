/* =====================================================================
   128_PayrollCalendar_Companies.sql  -  Payroll calendars for several companies
   ---------------------------------------------------------------------
   Labels only. Safe to re-run. (Uses the st.* company labels of db/124.)

   Payroll Calendar: a calendar is set up for the companies ticked in its
   form - one Payroll.PayrollCalendars row per company (each with its own
   pay periods, employees and payrolls), kept the same in each. The list
   shows it once, with its companies: "All", the company's name, or
   "3 companies" (their names on hover). Editing, activating /
   deactivating and deleting apply to every company it is set up for;
   unticking a company removes it there (refused while used). A company
   whose calendar already has processed payrolls keeps it, with its
   frequency and start date.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.cal_set_up_for', 'pr', N'Companies', N'الشركات', NULL),
        ('pr.cal_set_up_for_hint', 'pr', N'The calendar is set up once for each company ticked (each keeps its own pay periods and employees) and kept the same in each. Unticking a company removes it there - refused while that company''s periods, employees or payrolls use it.', N'يُعدّ التقويم مرة لكل شركة محددة (لكل منها فتراتها وموظفوها) ويبقى متطابقاً فيها. إلغاء تحديد شركة يحذفه منها - ويُرفض إذا كانت فترات أو موظفو أو مسيرات تلك الشركة تستخدمه.', NULL),
        ('pr.cal_company_locked', 'pr', N'Payroll has been processed on this company''s calendar - it stays.', N'تمت معالجة رواتب على تقويم هذه الشركة - يبقى.', NULL),
        ('pr.cal_default_mixed_0', 'pr', N'Now the default of: {0}. Tick it to make it the default of every company ticked; left unticked, each company keeps its own.', N'هو الافتراضي حالياً لـ: {0}. حدده ليصبح الافتراضي لكل الشركات المحددة؛ وإن تُرك، تحتفظ كل شركة بإعدادها.', NULL),
        ('pr.cal_settings_differ', 'pr', N'The companies'' calendars of this code do not all have the same settings - saving the form makes them the same.', N'تقاويم الشركات بهذا الرمز ليست بنفس الإعدادات - حفظ النموذج يوحّدها.', NULL),
        ('pr.cal_default_of_0', 'pr', N'Default calendar of: {0}', N'التقويم الافتراضي لـ: {0}', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Payroll calendar company labels inserted: ', @@ROWCOUNT);
GO

/* the delete question now speaks of every company */
UPDATE [Core].[UiLabels]
SET    EnglishText = N'Delete this payroll calendar in every company it is set up for? It can only be deleted where no period has been processed and no employee or payroll uses it.',
       ArabicText  = N'حذف تقويم الرواتب هذا من كل الشركات التي أُعدّ لها؟ لا يُحذف إلا حيث لم تُعالج أي فترة ولا يستخدمه موظف أو مسير.'
WHERE  LabelKey = 'pr.delete_this_payroll_calendar_it_can_only_be_deleted_whil' AND Deleted = 0;
GO
