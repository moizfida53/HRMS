/* =============================================================================
   03_Label_AllApps.sql  -  HRMS_Kuwait
   -----------------------------------------------------------------------------
   English / Arabic text for the "All Apps" link at the top of the HRMS sidebar
   (Views/Shared/_Layout.cshtml). Without it the link still shows "All Apps";
   this only adds the Arabic text. Safe to run more than once.
   ========================================================================== */
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] WHERE LabelKey = 'layout.all_apps' AND Deleted = 0)
    INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
    VALUES ('layout.all_apps', 'layout', N'All Apps', N'جميع التطبيقات', N'All Apps');

PRINT 'layout.all_apps label ready. Restart the site (or wait for the label cache) to see the Arabic text.';
