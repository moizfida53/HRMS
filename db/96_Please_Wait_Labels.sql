/* =====================================================================
   96_Please_Wait_Labels.sql  -  HRMS: "Please wait" and the Employees list
   ---------------------------------------------------------------------
   Safe to re-run. Labels only (English + Arabic): the "Please wait"
   overlay shown over every page while the server works, and the
   Employees list that now searches, sorts and pages in the browser.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('js.please_wait', 'js', N'Please wait', N'يرجى الانتظار', NULL),
        ('js.wait_loading_data', 'js', N'Getting your data…', N'جارٍ جلب البيانات…', NULL),
        ('js.wait_loading_page', 'js', N'Loading the page…', N'جارٍ تحميل الصفحة…', NULL),
        ('js.wait_slow', 'js', N'Still working - the connection is slow…', N'ما زلنا نعمل - الاتصال بطيء…', NULL),
        ('js.page_of', 'js', N'Page {0} of {1}', N'الصفحة {0} من {1}', NULL),
        ('js.exported_employees', 'js', N'Exported {0} employees.', N'تم تصدير {0} موظف.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Please wait labels inserted: ', @LabelsInserted);
GO
