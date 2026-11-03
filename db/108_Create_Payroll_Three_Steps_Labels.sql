/* =====================================================================
   108_Create_Payroll_Three_Steps_Labels.sql  -  Create Payroll in three steps
   ---------------------------------------------------------------------
   Labels only (English + Arabic); safe to re-run. Create Payroll now has
   three steps - Scope, Employees, Check & create. "Create payroll" on the
   Check step creates the payroll AND completes its registration (straight
   to Validation). "Save draft" keeps the work; Payrolls shows saved drafts
   first so they can be continued.
   ===================================================================== */
SET NOCOUNT ON;
GO
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.cr_three_steps', 'pr', N'Create a payroll in three steps', N'إنشاء مسير رواتب في ثلاث خطوات', NULL),
        ('pr.cr_check_create', 'pr', N'Check & create', N'التحقق والإنشاء', NULL),
        ('pr.cr_create_goes_to_validation', 'pr', N'Everything was checked above. Create payroll creates it and completes the registration - it goes straight to Validation.', N'تم التحقق من كل شيء أعلاه. زر إنشاء المسير ينشئه ويكمل التسجيل - ينتقل مباشرة إلى التدقيق.', NULL),
        ('pr.cr_save_draft', 'pr', N'Save draft', N'حفظ كمسودة', NULL),
        ('pr.cr_saved_drafts', 'pr', N'Saved drafts', N'المسودات المحفوظة', NULL),
        ('pr.cr_saved_drafts_text', 'pr', N'Payrolls you started in Create Payroll - continue where you left off.', N'مسيرات بدأتها في إنشاء المسير - تابع من حيث توقفت.', NULL),
        ('js.pr_draft_saved', 'js', N'Draft saved. Continue it any time from Payrolls.', N'تم حفظ المسودة. يمكنك متابعتها في أي وقت من صفحة المسيرات.', NULL),
        ('msg.pr_created_to_validation', 'msg', N'Payroll created. Registration is complete - it is now in Validation.', N'تم إنشاء المسير. اكتمل التسجيل - وهو الآن في مرحلة التدقيق.', N'Payroll created. Registration is complete - it is now in Validation.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Create Payroll labels inserted: ', @@ROWCOUNT);
GO
