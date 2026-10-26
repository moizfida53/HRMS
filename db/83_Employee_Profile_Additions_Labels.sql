/* =====================================================================
   83_Employee_Profile_Additions_Labels.sql  -  HRMS: labels for 82
   ---------------------------------------------------------------------
   Run after 82. Safe to re-run. Labels only (English + Arabic): the work
   permit salary and designations, annual leave on Employment Terms, and
   the profile tab rows on Security > Create Roles.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('emp.work_permit_salary', 'emp', N'Work permit salary', N'راتب إذن العمل', NULL),
        ('emp.work_permit_designation_en', 'emp', N'Designation in English', N'المسمى الوظيفي بالإنجليزية', NULL),
        ('emp.work_permit_designation_ar', 'emp', N'Designation in Arabic', N'المسمى الوظيفي بالعربية', NULL),
        ('emp.annual_leave_days', 'emp', N'Annual leave', N'الإجازة السنوية', NULL),
        ('emp.days_per_year', 'emp', N'days / year', N'يوم / سنة', NULL),
        ('emp.annual_leave_hint', 'emp', N'The employee''s own agreement. Leave blank to use the Annual Leave type''s days (Leave > Settings).', N'اتفاقية الموظف الخاصة. اتركه فارغاً لاستخدام أيام نوع الإجازة السنوية (الإجازات > الإعدادات).', NULL),
        ('emp.annual_leave_hint_default', 'emp', N'The employee''s own agreement. Blank = {0} days a year, the Annual Leave type (Leave > Settings).', N'اتفاقية الموظف الخاصة. فارغ = {0} يوماً في السنة حسب نوع الإجازة السنوية (الإجازات > الإعدادات).', NULL),
        ('sec.fn_personal_tab', 'sec', N'Personal Info tab', N'تبويب البيانات الشخصية', NULL),
        ('sec.fn_employment_tab', 'sec', N'Employment tab', N'تبويب التوظيف', NULL),
        ('sec.fn_tab_hint', 'sec', N'None hides the tab; Read shows it; Write = edit', N'بدون = إخفاء التبويب؛ القراءة = عرضه؛ الكتابة = التعديل', NULL),
        ('sec.fn_leave_tab', 'sec', N'Leave tab', N'تبويب الإجازات', NULL),
        ('sec.fn_leave_tab_hint', 'sec', N'balances and requests on the profile - also needs Leave access', N'الأرصدة والطلبات في الملف - يتطلب صلاحية الإجازات أيضاً', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Employee profile labels inserted: ', @LabelsInserted);
GO
