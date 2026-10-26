/* =====================================================================
   88_Leave_Management_Labels.sql  -  HRMS: labels for the Leave Management page
   ---------------------------------------------------------------------
   Run after 87. Safe to re-run. Labels only (English + Arabic): the page
   renamed to Leave Management, the leave / paid / unpaid days columns and
   the row menu (cancel the request, mark the return).
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('lv.leave_management', 'lv', N'Leave Management', N'إدارة الإجازات', NULL),
        ('lv.leave_days', 'lv', N'Leave days', N'أيام الإجازة', NULL),
        ('lv.more_actions', 'lv', N'More actions', N'إجراءات أخرى', NULL),
        ('lv.more_actions_named', 'lv', N'More actions for {0}', N'إجراءات أخرى لـ {0}', NULL),
        ('lv.mark_return', 'lv', N'Mark return', N'تسجيل العودة للعمل', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Leave Management labels inserted: ', @LabelsInserted);
GO
