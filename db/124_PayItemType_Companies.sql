/* =====================================================================
   124_PayItemType_Companies.sql  -  Pay Item Types for several companies
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   Payroll Settings > Pay Item Types: a pay item type is created for the
   companies ticked in its form (one Payroll.PayComponents row per
   company, kept the same in each), so it is not entered again for every
   company. The list shows it once, with the companies it is created for:
   "All", the company's name, or "3 companies" (their names on hover).
   Editing, activating / deactivating and deleting apply to every company
   it is created for; unticking a company removes it there (refused while
   that company's pay items or payrolls use it).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('st.created_for', 'st', N'Created for', N'مُنشأ لـ', NULL),
        ('st.companies', 'st', N'Companies', N'الشركات', NULL),
        ('st.all', 'st', N'All', N'الكل', NULL),
        ('st.all_companies', 'st', N'All companies', N'كل الشركات', NULL),
        ('st.1_company', 'st', N'1 company', N'شركة واحدة', NULL),
        ('st.0_companies', 'st', N'{0} companies', N'{0} شركات', NULL),
        ('st.created_for_hint', 'st', N'It is created once for each company ticked and kept the same in each. Unticking a company removes it there - refused while that company''s pay items or payrolls use it.', N'يُنشأ مرة لكل شركة محددة ويبقى متطابقاً فيها. إلغاء تحديد شركة يحذفه منها - ويُرفض إذا كانت بنود رواتب أو مسيرات تلك الشركة تستخدمه.', NULL),
        ('st.created_for_standard_hint', 'st', N'A standard item type: use "Add standard types" to add it to another company.', N'نوع قياسي: استخدم "إضافة الأنواع القياسية" لإضافته إلى شركة أخرى.', NULL),
        ('st.cost_center_many_hint', 'st', N'Cost centers belong to one company - with several companies each keeps its own (or the employee''s).', N'مراكز التكلفة تخص شركة واحدة - مع عدة شركات تحتفظ كل شركة بمركزها (أو مركز الموظف).', NULL),
        ('st.active_0_of_1', 'st', N'Active in {0} of {1}', N'نشط في {0} من {1}', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Pay item type company labels inserted: ', @@ROWCOUNT);
GO

/* the texts that now speak of every company */
UPDATE [Core].[UiLabels]
SET    EnglishText = N'Delete this item type in every company it is created for? It can only be deleted where no pay item or payroll uses it.',
       ArabicText  = N'حذف نوع البند هذا من كل الشركات التي أُنشئ لها؟ لا يُحذف إلا حيث لا تستخدمه بنود رواتب أو مسيرات.'
WHERE  LabelKey = 'st.delete_item_type_text' AND Deleted = 0;
UPDATE [Core].[UiLabels]
SET    EnglishText = N'Adds the standard item types the companies are missing (Basic Salary, PIFSS, Loan ...)',
       ArabicText  = N'يضيف الأنواع القياسية الناقصة للشركات (الراتب الأساسي، التأمينات، القرض ...)'
WHERE  LabelKey = 'st.add_standard_types_hint' AND Deleted = 0;
GO
