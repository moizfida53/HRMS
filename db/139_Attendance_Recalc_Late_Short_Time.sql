/* =====================================================================
   139_Attendance_Recalc_Late_Short_Time.sql  -  L / S as time, Recalculate
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   - Attendance Sheet: L and S show the late / short time (h:mm) the
     deduction is worked out on (the days on hover); the tooltip of a day
     always gives its late / short time, also under the first slab.
   - Recalculate (Attendance Sheet, Monthly Summary, Attendance): works the
     payroll month out again with the attendance settings now - not once a
     payroll is created for it (Registered or later).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('att.recalc_locked', 'att', N'The payroll of this month is already created - its attendance can no longer be worked out again.', N'تم إنشاء مسير رواتب هذا الشهر - لا يمكن إعادة حساب حضوره.', NULL),
        ('att.t_days_0', 'att', N'{0} days', N'{0} أيام', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO

UPDATE [Core].[UiLabels] SET EnglishText = N'Late time (h:mm) the deduction is worked out on', ArabicText = N'وقت التأخير (س:د) الذي يُحتسب عليه الخصم'
WHERE  LabelKey = 'att.t_late_hint' AND Deleted = 0;
UPDATE [Core].[UiLabels] SET EnglishText = N'Short time (h:mm) the deduction is worked out on', ArabicText = N'وقت النقص (س:د) الذي يُحتسب عليه الخصم'
WHERE  LabelKey = 'att.t_short_hint' AND Deleted = 0;
UPDATE [Core].[UiLabels] SET EnglishText = N'Recalculate', ArabicText = N'إعادة الحساب'
WHERE  LabelKey = 'att.recalculate' AND Deleted = 0;
UPDATE [Core].[UiLabels] SET EnglishText = N'Work the month out again with the attendance settings now (patterns, slabs, assignments, salaries, leave) - until its payroll is created',
                             ArabicText  = N'إعادة حساب الشهر بإعدادات الحضور الحالية (الأنماط والشرائح والتعيينات والرواتب والإجازات) - حتى يُنشأ مسير رواتبه'
WHERE  LabelKey = 'att.recalculate_hint' AND Deleted = 0;
GO
