/* =====================================================================
   145_Employee_Deactivate_Confirm.sql  -  Employees list: Deactivate asks first
   ---------------------------------------------------------------------
   Labels only. Safe to re-run.

   Employees list: Activate / Deactivate moved into the row's ... menu
   (Deactivate asks "Deactivate this employee?" first); the Edit icon
   (the employee's General details) took its place in the row.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('js.deactivate_title', 'js', N'Deactivate this employee?', N'إلغاء تفعيل هذا الموظف؟', NULL),
        ('js.deactivate_text', 'js', N'They are marked inactive and left out of new payrolls. You can activate them again at any time.', N'سيُعلَّم الموظف غير نشط ويُستثنى من مسيرات الرواتب الجديدة. يمكنك إعادة تفعيله في أي وقت.', NULL),
        ('js.deactivate', 'js', N'Deactivate', N'إلغاء التفعيل', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
