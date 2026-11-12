/* ============================================================================
   148 - Employee Self Service: Arabic for the "Add to Home Screen" button and steps
   (the button is now on every page of /ess, not only the sign-in page - db/146 had the first labels)
   Safe to run more than once.
   ============================================================================ */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('ess.install_app', 'ess', N'Install app', N'تثبيت التطبيق', NULL),
        ('ess.install_intro', 'ess', N'Add Self Service to your home screen to open it like an app.', N'أضف الخدمة الذاتية إلى الشاشة الرئيسية لفتحها كأنها تطبيق.', NULL),
        ('ess.install_ios_title', 'ess', N'iPhone and iPad', N'آيفون وآيباد', NULL),
        ('ess.install_ios_1', 'ess', N'Open this page in Safari.', N'افتح هذه الصفحة في متصفح Safari.', NULL),
        ('ess.install_ios_2', 'ess', N'Tap the Share button (the square with an arrow).', N'اضغط زر المشاركة (المربع الذي فيه سهم).', NULL),
        ('ess.install_ios_3', 'ess', N'Choose Add to Home Screen, then tap Add.', N'اختر «إضافة إلى الشاشة الرئيسية» ثم اضغط «إضافة».', NULL),
        ('ess.install_android_title', 'ess', N'Android', N'أندرويد', NULL),
        ('ess.install_android_1', 'ess', N'Open this page in Chrome.', N'افتح هذه الصفحة في متصفح Chrome.', NULL),
        ('ess.install_android_2', 'ess', N'Tap the menu (three dots) at the top right.', N'اضغط القائمة (ثلاث نقاط) في أعلى الشاشة.', NULL),
        ('ess.install_android_3', 'ess', N'Choose Install app (or Add to Home screen), then tap Install.', N'اختر «تثبيت التطبيق» (أو «إضافة إلى الشاشة الرئيسية») ثم اضغط «تثبيت».', NULL),
        ('ess.install_replace', 'ess', N'Already added? On Android, adding it again replaces the old icon. On iPhone, delete the old icon first (touch and hold it), then add it again.', N'أضفته من قبل؟ على أندرويد تؤدي إضافته مرة أخرى إلى استبدال الأيقونة القديمة. على آيفون احذف الأيقونة القديمة أولاً (بالضغط المطوّل عليها) ثم أضفه من جديد.', NULL),
        ('ess.ok', 'ess', N'OK', N'حسناً', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO

PRINT '148_Ess_Install_Labels.sql applied.';
GO
