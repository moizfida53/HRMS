/* =====================================================================
   135_Calendar_Deduction_Basis_Labels.sql  -  "Deduction Calculation Basis (Days)"
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   Payroll Calendar: "Days basis" is renamed "Deduction Calculation Basis
   (Days)" and the form explains what one day of salary is worth with each
   choice (example: KWD 520, October = 31 days), and what the payroll
   applies today.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

UPDATE [Core].[UiLabels]
SET    EnglishText = N'Deduction Calculation Basis (Days)',
       ArabicText  = N'أساس احتساب الخصم (الأيام)'
WHERE  LabelKey = 'pr.days_basis' AND Deleted = 0;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.basis_help_q', 'pr', N'What one day of salary is worth (example: KWD 520, October = 31 days)', N'قيمة يوم الراتب (مثال: 520 د.ك، أكتوبر = 31 يوماً)', NULL),
        ('pr.basis_help_fixed', 'pr', N'- the salary / the days per month (e.g. 26): 520 / 26 = 20.000 every month. The usual Kuwait practice (Labour Law daily wage); deductions are the same each month.', N'- الراتب / أيام الشهر (مثلاً 26): 520 / 26 = 20.000 كل شهر. الممارسة المعتادة في الكويت (الأجر اليومي في قانون العمل)؛ الخصم ثابت كل شهر.', NULL),
        ('pr.basis_help_calendar', 'pr', N'- the salary / the days of the period: 520 / 31 = 16.774 in October, 520 / 28 = 18.571 in February. Every day counts, weekends too.', N'- الراتب / أيام الفترة: 520 / 31 = 16.774 في أكتوبر و520 / 28 = 18.571 في فبراير. كل الأيام تُحتسب بما فيها العطل.', NULL),
        ('pr.basis_help_working', 'pr', N'- the salary / the working days of the period (weekly rest days left out): October with Friday and Saturday off = 21 days, 520 / 21 = 24.762.', N'- الراتب / أيام العمل في الفترة (دون أيام الراحة): أكتوبر مع راحة الجمعة والسبت = 21 يوماً، 520 / 21 = 24.762.', NULL),
        ('pr.basis_help_now', 'pr', N'Applied today: a joiner / leaver of the period is paid by calendar days; unpaid leave uses the daily wage divisor of the Indemnity rules (26 by default) and attendance deductions the day divisor of the attendance pattern.', N'المطبق حالياً: يُدفع للموظف المنضم / المغادر خلال الفترة حسب الأيام الميلادية؛ وتستخدم الإجازة غير المدفوعة مقسوم الأجر اليومي في قواعد مكافأة نهاية الخدمة (26 افتراضياً) وخصومات الحضور مقسوم اليوم في نمط الحضور.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
