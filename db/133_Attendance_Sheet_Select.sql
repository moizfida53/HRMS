/* =====================================================================
   133_Attendance_Sheet_Select.sql  -  Attendance Sheet: select days, mark them together
   ---------------------------------------------------------------------
   Labels only. Run after db/129. Safe to re-run.

   A click on a day selects it (another click unselects it, Shift+click a
   range); the box of a row selects the employee's days, a day's header
   the column, the box in the corner every day. The bar that appears marks
   the days selected Present, Absent or Leave; a right click on a selected
   day applies any mark (Late / Short ask for the minutes, Excused for a
   comment) to every day selected. A double click opens the day's form.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('att.sel_hint', 'att', N'Click days to select them (Shift+click a range, a row''s box, a day''s header or the corner box for all) - then mark them, or right-click. Double-click opens a day.', N'انقر الأيام لتحديدها (Shift+نقر لنطاق، مربع الصف، رأس اليوم أو المربع العلوي للكل) - ثم علّمها أو انقر بالزر الأيمن. النقر المزدوج يفتح اليوم.', NULL),
        ('att.sel_region', 'att', N'Days selected', N'الأيام المحددة', NULL),
        ('att.sel_1_day', 'att', N'1 day selected', N'يوم واحد محدد', NULL),
        ('att.sel_0_days', 'att', N'{0} days selected', N'{0} أيام محددة', NULL),
        ('att.sel_mark_as', 'att', N'Mark as', N'تعليم كـ', NULL),
        ('att.sel_apply', 'att', N'Apply', N'تطبيق', NULL),
        ('att.sel_clear', 'att', N'Clear selection', N'إلغاء التحديد', NULL),
        ('att.sel_more', 'att', N'Late, Short, Holiday, Excused: right-click a selected day.', N'تأخير، نقص، عطلة، معذور: انقر بالزر الأيمن على يوم محدد.', NULL),
        ('att.sel_all', 'att', N'Select every day', N'تحديد كل الأيام', NULL),
        ('att.sel_row', 'att', N'Select the employee''s days', N'تحديد أيام الموظف', NULL),
        ('att.sel_col', 'att', N'Click to select the day for everyone', N'انقر لتحديد اليوم للجميع', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
