/* =============================================================================
   03_Labels_TMM.sql  -  HRMS_Kuwait
   -----------------------------------------------------------------------------
   English / Arabic text for the TMM theme:
     - "All Apps" in the HRMS sidebar and the launcher (/apps)
     - the new sign-in page (HR, Payroll and POS)
   The pages already show the English text without this script; it adds the
   Arabic. The pages look the text up by its English wording (SourceText), so
   keep EnglishText / SourceText exactly as written here.
   Safe to run more than once: a key that already exists is left as it is.
   ========================================================================== */
SET NOCOUNT ON;

DECLARE @Labels TABLE (LabelKey VARCHAR(150), EnglishText NVARCHAR(1000), ArabicText NVARCHAR(1000));
INSERT INTO @Labels (LabelKey, EnglishText, ArabicText) VALUES
 ('layout.all_apps',               N'All Apps',                     N'جميع التطبيقات'),
 ('layout.choose_an_application',  N'Choose an application',        N'اختر تطبيقاً'),
 ('layout.sign_out_tmm',           N'Sign out',                     N'تسجيل الخروج'),
 ('auth.tmm_business_suite',       N'Business Suite',               N'مجموعة الأعمال'),
 ('auth.tmm_products',             N'HR · Payroll · POS',           N'الموارد البشرية · الرواتب · نقاط البيع'),
 ('auth.tmm_hero_title_1',         N'Your people and your restaurants,', N'موظفوك ومطاعمك،'),
 ('auth.tmm_hero_title_2',         N'one sign-in.',                 N'بتسجيل دخول واحد.'),
 ('auth.tmm_hero_lede',            N'Run payroll, track leave and documents, and take Dine-In and online orders from the same place, built for Kuwait.',
                                   N'شغّل الرواتب، وتابع الإجازات والمستندات، واستقبل طلبات الصالة والطلبات الإلكترونية من مكان واحد، مصمم للكويت.'),
 ('auth.tmm_hr',                   N'HR',                           N'الموارد البشرية'),
 ('auth.tmm_hr_text',              N'Employees, leave, documents, assets and Kuwait compliance.', N'الموظفون والإجازات والمستندات والأصول والامتثال لقوانين الكويت.'),
 ('auth.tmm_payroll',              N'Payroll',                      N'الرواتب'),
 ('auth.tmm_payroll_text',         N'Monthly runs, payslips, bank files and final settlement.', N'مسيرات الرواتب الشهرية وقسائم الرواتب وملفات البنوك والتسوية النهائية.'),
 ('auth.tmm_pos',                  N'POS',                          N'نقاط البيع'),
 ('auth.tmm_pos_text',             N'QR menu, Dine-In tables, online orders and kitchen printing.', N'قائمة QR وطاولات الصالة والطلبات الإلكترونية وطباعة المطبخ.'),
 ('auth.tmm_secure',               N'Secure sign-in · Data stays in your company', N'تسجيل دخول آمن · بياناتك تبقى داخل شركتك'),
 ('auth.tmm_welcome_back',         N'Welcome back',                 N'مرحباً بعودتك'),
 ('auth.tmm_sign_in_subtitle',     N'Sign in to continue to your workspace.', N'سجّل الدخول للمتابعة إلى مساحة عملك.'),
 ('auth.tmm_after_sign_in',        N'After signing in you''ll see the apps you have access to: HRMS, POS, Item Management and more.',
                                   N'بعد تسجيل الدخول سترى التطبيقات المتاحة لك: الموارد البشرية ونقاط البيع وإدارة الأصناف وغيرها.');

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT l.LabelKey, LEFT(l.LabelKey, CHARINDEX('.', l.LabelKey) - 1), l.EnglishText, l.ArabicText, l.EnglishText
FROM @Labels l
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] u WHERE u.LabelKey = l.LabelKey AND u.Deleted = 0)
  AND NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] u WHERE u.SourceText = l.EnglishText AND u.Deleted = 0);

PRINT CONCAT(@@ROWCOUNT, ' TMM label(s) added. Restart the site (or wait for the label cache) to see the Arabic text.');
