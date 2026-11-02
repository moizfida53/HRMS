/* 104_Closed_Payroll_Final_Labels.sql - a closed payroll can no longer be reopened. Labels only; safe to re-run. */
SET NOCOUNT ON;
GO
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.closed_payrolls_are_final', 'pr', N'A closed payroll is final: it cannot be changed or reopened. The bank file, journal and payslips are built from it.', N'الرواتب المقفلة نهائية: لا يمكن تعديلها أو إعادة فتحها. يتم إنشاء ملف البنك والقيد وكشوف الرواتب منها.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
