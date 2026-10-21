/* =====================================================================
   66_Profile_Save_Labels.sql  -  HRMS: one Save Changes on the employee profile
   ---------------------------------------------------------------------
   Safe to re-run. Labels only (English + Arabic):
   Save Changes now saves Personal Info / Employment and Kuwait Compliance
   together, then returns to the Employees page; the separate "Save
   Compliance Details" button is gone.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('js.all_changes_saved', 'js', N'All changes saved.', N'تم حفظ جميع التغييرات.', NULL),
        ('js.nothing_to_save', 'js', N'There are no changes to save.', N'لا توجد تغييرات للحفظ.', NULL),
        ('js.changes_saved_successfully', 'js', N'Changes saved successfully.', N'تم حفظ التغييرات بنجاح.', NULL),
        ('js.alert_not_stored', 'js', N'The database did not store these alerts as entered - it holds the ones shown. Run db/65 again, then retry.', N'لم تحفظ قاعدة البيانات هذه التنبيهات كما أُدخلت - المحفوظ هو المعروض. أعد تشغيل db/65 ثم حاول مرة أخرى.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Profile save labels inserted: ', @LabelsInserted);
GO
