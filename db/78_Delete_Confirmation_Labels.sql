/* =====================================================================
   78_Delete_Confirmation_Labels.sql  -  HRMS: labels for the confirmation
   ---------------------------------------------------------------------
   Run after 77. Safe to re-run. Labels only (English + Arabic): the one
   confirmation popup every Delete / Remove click now opens (site.js
   HRMS.confirm) and the questions it asks.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('js.confirm_delete_title', 'js', N'Delete this record?', N'حذف هذا السجل؟', NULL),
        ('js.confirm_delete_note', 'js', N'It is hidden everywhere in the app but kept in the database, flagged as deleted.', N'يُخفى في كل مكان في التطبيق لكنه يبقى في قاعدة البيانات مُعلَّماً كمحذوف.', NULL),
        ('js.cancel', 'js', N'Cancel', N'إلغاء', NULL),
        ('js.delete', 'js', N'Delete', N'حذف', NULL),
        ('js.discard', 'js', N'Discard', N'تجاهل', NULL),
        ('js.sec_delete_role', 'js', N'Delete role', N'حذف الدور', NULL),
        ('js.sec_activate', 'js', N'Activate', N'تفعيل', NULL),
        ('js.sec_deactivate', 'js', N'Deactivate', N'إيقاف', NULL),
        ('js.pr_remove_line', 'js', N'Remove this line from the payroll?', N'حذف هذا البند من كشف الرواتب؟', NULL),
        ('js.fs_remove_line', 'js', N'Remove this line from the settlement?', N'حذف هذا البند من التسوية؟', NULL),
        ('js.date_alert_remove', 'js', N'Remove this alert?', N'حذف هذا التنبيه؟', NULL),
        ('js.date_alert_remove_note', 'js', N'It is dropped when you save the alerts.', N'يُحذف عند حفظ التنبيهات.', NULL),
        ('js.lv_remove_band', 'js', N'Remove this pay band?', N'حذف شريحة الأجر هذه؟', NULL),
        ('js.lv_remove_band_note', 'js', N'It is dropped when you save the leave type.', N'تُحذف عند حفظ نوع الإجازة.', NULL),
        ('js.st_remove_row', 'js', N'Remove this row?', N'حذف هذا الصف؟', NULL),
        ('js.st_remove_row_note', 'js', N'It is dropped when you save.', N'يُحذف عند الحفظ.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Delete confirmation labels inserted: ', @LabelsInserted);
GO
