/* =====================================================================
   138_Attendance_Sheet_Short_Column.sql  -  Attendance Sheet: the Short hours total
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   The Attendance Sheet's totals show S - the days with short hours (a day
   late and short counts in L and in S, as in the Monthly Summary) - and
   the Excel export has the column too.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('att.t_short', 'att', N'S', N'ن', NULL),
        ('att.t_short_hint', 'att', N'Days with short hours (late and short included)', N'أيام نقص الساعات (مع التأخير والنقص)', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
