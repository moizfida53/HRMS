/* =====================================================================
   117_Create_Payroll_One_Per_Month_Labels.sql  -  one regular payroll a month
   ---------------------------------------------------------------------
   Labels only (English + Arabic); safe to re-run. Create Payroll no longer
   lets a regular monthly payroll be created for a company and month that
   already has one (Registered, Validation, Awaiting approval or Closed - a
   cancelled one does not count). Another payment for that month is an
   Off-cycle payroll. Weekly / bi-weekly calendars keep paying each period.
   ===================================================================== */
SET NOCOUNT ON;
GO
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.cr_month_created', 'pr', N'{0} already has a payroll for {1} ({2}, {3}). A company has one regular payroll a month - choose Off-cycle for an extra payment.', N'لدى {0} رواتب لشهر {1} بالفعل ({2}، {3}). للشركة رواتب اعتيادية واحدة في الشهر - اختر رواتب خارج الدورة لدفعة إضافية.', NULL),
        ('pr.cr_open_payrolls', 'pr', N'Open Payrolls', N'فتح الرواتب', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Create payroll labels inserted: ', @LabelsInserted);
GO
