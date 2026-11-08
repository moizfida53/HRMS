/* =====================================================================
   130_Payslip_Government_Basis.sql  -  Payslip "Government": work permit salary only
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   Payslips > Government: the payslip shows the salary on the work permit
   (Kuwait Compliance) as its only earning and as the net salary - none
   of the payroll's own lines (allowances, deductions). When the period
   was not paid in full it is the work permit salary for the days paid.
   Contract and Both are unchanged (the payroll's own lines).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('ps.doc_wp_salary_line', 'ps', N'Salary as per the work permit', N'الراتب حسب إذن العمل', NULL),
        ('ps.doc_wp_prorated_0_1_2', 'ps', N'{0} for {1} of {2} days', N'{0} عن {1} من {2} يوماً', NULL),
        ('ps.doc_wp_missing', 'ps', N'No work permit salary recorded (Kuwait Compliance)', N'لم يُسجَّل راتب إذن العمل (الامتثال الكويتي)', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO

/* the hint of the Government button now says the figures follow the work permit too */
UPDATE [Core].[UiLabels]
SET    EnglishText = N'The salary, designation and figures as per the work permit - the work permit salary is the amount payable',
       ArabicText  = N'الراتب والمسمى والمبالغ حسب إذن العمل - راتب إذن العمل هو المبلغ المستحق'
WHERE  LabelKey = 'ps.basis_gov_hint' AND Deleted = 0;
GO
