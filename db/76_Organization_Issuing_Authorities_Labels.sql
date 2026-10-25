/* =====================================================================
   76_Organization_Issuing_Authorities_Labels.sql  -  HRMS: labels for 75
   ---------------------------------------------------------------------
   Run after 75. Safe to re-run. Labels only (English + Arabic): the
   issuing authority on the organization document type and document
   forms, and the Setup > Organization previous / next arrows.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('od.authority_choose', 'od', N'Choose the issuing authority', N'اختر جهة الإصدار', NULL),
        ('od.authority_government', 'od', N'Kuwait government authorities', N'الجهات الحكومية الكويتية', NULL),
        ('od.authority_other', 'od', N'Other', N'أخرى', NULL),
        ('od.authority_hint', 'od', N'Chosen once here - every company''s document of this type shows it.', N'يُختار مرة واحدة هنا - ويظهر في مستند كل شركة من هذا النوع.', NULL),
        ('od.authority_from_setup', 'od', N'Set on the document type (Setup > Organization > Organization Documents)', N'محدّدة في نوع المستند (الإعداد > المؤسسة > مستندات المؤسسة)', NULL),
        ('od.authority_not_set', 'od', N'Not set - choose it on Setup > Organization > Organization Documents', N'غير محدّدة - اخترها من الإعداد > المؤسسة > مستندات المؤسسة', NULL),
        ('org.previous_master', 'org', N'Previous', N'السابق', NULL),
        ('org.next_master', 'org', N'Next', N'التالي', NULL),
        ('msg.od_authority_list', 'msg', N'Choose the issuing authority from the list.', N'اختر جهة الإصدار من القائمة.', N'Choose the issuing authority from the list.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Issuing authority labels inserted: ', @LabelsInserted);
GO
