/* =====================================================================
   103_Launcher_App_Access.sql  -  App access per role (/apps launcher)
   ---------------------------------------------------------------------
   Safe to re-run. Run after db/57 (Security) and the QR Menu merge
   scripts (db/qrmenu-merge/01..03).

   Security > Create Roles now has an "App access" section: one tick per
   launcher tile (AccessCatalog.Apps). A role sees a tile on /apps when it
   holds that tile's code; System Administrator sees every tile.

     APP_HRMS          HRMS
     APP_POS           POS
     APP_ONLINE_ORDER  Online Order (the customer menu, /?id=<Brand>,<Branch>)
     APP_ASSETS        Assets
     APP_FEEDBACK      Feedback
     APP_MENU_COLORS   Menu Colors
     APP_ITEMS         Item Management
     APP_PRINTERS      Printer Setup
     APP_SETTINGS      Settings
     APP_SECURITY      Security
     APP_POS_USERS     POS Users

   First run only (a code that is new): every role gets the codes of the
   tiles it already saw - the rules the launcher used before this script -
   so nobody loses a tile on deployment:
     HRMS                 any EMPLOYEE_ / LEAVE_ / PAYROLL_ / PAYCOMPONENT_ /
                          PAYSLIP_ / ORGANIZATION_ / ORG_ / ASSET_ /
                          SECURITY_ / AUDIT_ / DASHBOARD_ right
     POS, Online Order    a QR Menu role (RoleCode QR_...) or any POS_ right
     Assets               any ASSET_ right
     Feedback, Menu Colors, Item Management, Settings
                          a QR Menu role
     Printer Setup, POS Users
                          POS_MANAGE_MASTERS, or a QR Menu role whose POS
                          flags manage masters (dbo.fn_QR_RoleFlags)
     Security             any SECURITY_ / AUDIT_ right
   and System Administrator gets them all. After that the ticks on
   Create Roles decide; re-running this script changes nothing.

   Note: before this script a user with an employee record but no HRMS
   right still saw the HRMS tile. Tile visibility is now per role - tick
   "HRMS" on the role those users have.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID('tempdb..#Apps') IS NOT NULL DROP TABLE #Apps;
CREATE TABLE #Apps (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY,
                    Action VARCHAR(30) COLLATE DATABASE_DEFAULT NOT NULL,
                    IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Apps (PermissionCode, Action) VALUES
    ('APP_HRMS', 'Hrms'),
    ('APP_POS', 'Pos'),
    ('APP_ONLINE_ORDER', 'OnlineOrder'),
    ('APP_ASSETS', 'Assets'),
    ('APP_FEEDBACK', 'Feedback'),
    ('APP_MENU_COLORS', 'MenuColors'),
    ('APP_ITEMS', 'Items'),
    ('APP_PRINTERS', 'Printers'),
    ('APP_SETTINGS', 'Settings'),
    ('APP_SECURITY', 'Security'),
    ('APP_POS_USERS', 'PosUsers');

UPDATE a SET IsNew = 1 FROM #Apps a
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = a.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT a.PermissionCode, 'App', a.Action FROM #Apps a WHERE a.IsNew = 1;

/* ------------------------------------------------------------------
   First-run grants: who saw each tile before
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#RoleFacts') IS NOT NULL DROP TABLE #RoleFacts;
SELECT r.RoleId,
       IsSysAdmin = CAST(CASE WHEN r.RoleCode = N'SYSADMIN' THEN 1 ELSE 0 END AS BIT),
       IsQr       = CAST(CASE WHEN r.RoleCode LIKE N'QR[_]%' THEN 1 ELSE 0 END AS BIT),
       HasHrms    = CAST(CASE WHEN EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp
                                           JOIN [Security].[Permissions] p ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
                                           WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0
                                             AND (p.PermissionCode LIKE 'EMPLOYEE[_]%' OR p.PermissionCode LIKE 'LEAVE[_]%'
                                               OR p.PermissionCode LIKE 'PAYROLL[_]%' OR p.PermissionCode LIKE 'PAYCOMPONENT[_]%'
                                               OR p.PermissionCode LIKE 'PAYSLIP[_]%' OR p.PermissionCode LIKE 'ORGANIZATION[_]%'
                                               OR p.PermissionCode LIKE 'ORG[_]%' OR p.PermissionCode LIKE 'ASSET[_]%'
                                               OR p.PermissionCode LIKE 'SECURITY[_]%' OR p.PermissionCode LIKE 'AUDIT[_]%'
                                               OR p.PermissionCode LIKE 'DASHBOARD[_]%'))
                             THEN 1 ELSE 0 END AS BIT),
       HasPos     = CAST(CASE WHEN EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp
                                           JOIN [Security].[Permissions] p ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
                                           WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND p.PermissionCode LIKE 'POS[_]%')
                             THEN 1 ELSE 0 END AS BIT),
       HasAsset   = CAST(CASE WHEN EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp
                                           JOIN [Security].[Permissions] p ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
                                           WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND p.PermissionCode LIKE 'ASSET[_]%')
                             THEN 1 ELSE 0 END AS BIT),
       HasSec     = CAST(CASE WHEN EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp
                                           JOIN [Security].[Permissions] p ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
                                           WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0
                                             AND (p.PermissionCode LIKE 'SECURITY[_]%' OR p.PermissionCode LIKE 'AUDIT[_]%'))
                             THEN 1 ELSE 0 END AS BIT),
       PosAdmin   = CAST(CASE WHEN EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp
                                           JOIN [Security].[Permissions] p ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
                                           WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND p.PermissionCode = 'POS_MANAGE_MASTERS')
                             THEN 1 ELSE 0 END AS BIT)
INTO   #RoleFacts
FROM   [Security].[Roles] r
WHERE  r.Deleted = 0;

/* QR Menu roles whose POS flags manage masters (merge script 02) */
IF OBJECT_ID(N'dbo.fn_QR_RoleFlags', N'IF') IS NOT NULL AND COL_LENGTH('Security.Roles', 'LegacyRoleId') IS NOT NULL
    EXEC sp_executesql N'
        UPDATE f SET PosAdmin = 1
        FROM   #RoleFacts f
        JOIN   [Security].[Roles] r ON r.RoleId = f.RoleId
        CROSS APPLY dbo.fn_QR_RoleFlags(r.LegacyRoleId) q
        WHERE  r.LegacyRoleId IS NOT NULL AND q.CanManageMasters = 1;';

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT DISTINCT f.RoleId, p.PermissionId
FROM   #RoleFacts f
CROSS JOIN #Apps a
JOIN   [Security].[Permissions] p ON p.PermissionCode = a.PermissionCode AND p.Deleted = 0
WHERE  a.IsNew = 1
  AND (f.IsSysAdmin = 1
       OR (a.PermissionCode = 'APP_HRMS'                               AND f.HasHrms = 1)
       OR (a.PermissionCode IN ('APP_POS', 'APP_ONLINE_ORDER')         AND (f.IsQr = 1 OR f.HasPos = 1))
       OR (a.PermissionCode = 'APP_ASSETS'                             AND f.HasAsset = 1)
       OR (a.PermissionCode IN ('APP_FEEDBACK', 'APP_MENU_COLORS', 'APP_ITEMS', 'APP_SETTINGS') AND f.IsQr = 1)
       OR (a.PermissionCode IN ('APP_PRINTERS', 'APP_POS_USERS')       AND f.PosAdmin = 1)
       OR (a.PermissionCode = 'APP_SECURITY'                           AND f.HasSec = 1))
  AND NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x
                  WHERE x.RoleId = f.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);

DECLARE @AppGrants INT = @@ROWCOUNT, @AppCodes INT = (SELECT COUNT(1) FROM #Apps WHERE IsNew = 1);
PRINT CONCAT(N'App codes created: ', @AppCodes, N', role app grants: ', @AppGrants);

/* signed-in users pick up the new codes on their next permission refresh */
DROP TABLE #RoleFacts; DROP TABLE #Apps;
GO

/* ------------------------------------------------------------------
   Labels (English + Arabic)
   ------------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('sec.app_access', 'sec', N'App access', N'الوصول إلى التطبيقات', NULL),
        ('sec.app_access_text', 'sec', N'The applications this role sees on the All Apps page. Hover over an app to see what it is for.', N'التطبيقات التي يراها هذا الدور في صفحة جميع التطبيقات. مرّر المؤشر فوق التطبيق لمعرفة الغرض منه.', NULL),
        ('sec.app_access_note', 'sec', N'An app only shows on All Apps - each app still checks the page access below when it is opened.', N'يظهر التطبيق فقط في صفحة جميع التطبيقات - ويتحقق كل تطبيق من صلاحيات الصفحات أدناه عند فتحه.', NULL),
        ('sec.apps_all', 'sec', N'All apps', N'كل التطبيقات', NULL),
        ('sec.apps_none', 'sec', N'None', N'لا شيء', NULL),
        ('js.sec_apps_count', 'js', N'{0} of {1} apps', N'{0} من {1} تطبيقات', NULL),
        ('app.hrms', 'app', N'HRMS', N'الموارد البشرية', NULL),
        ('app.pos', 'app', N'POS', N'نقاط البيع', NULL),
        ('app.online_order', 'app', N'Online Order', N'الطلب أونلاين', NULL),
        ('app.assets', 'app', N'Assets', N'الأصول', NULL),
        ('app.feedback', 'app', N'Feedback', N'آراء العملاء', NULL),
        ('app.menu_colors', 'app', N'Menu Colors', N'ألوان القائمة', NULL),
        ('app.items', 'app', N'Item Management', N'إدارة الأصناف', NULL),
        ('app.printers', 'app', N'Printer Setup', N'إعداد الطابعات', NULL),
        ('app.settings', 'app', N'Settings', N'الإعدادات', NULL),
        ('app.security', 'app', N'Security', N'الأمان', NULL),
        ('app.pos_users', 'app', N'POS Users', N'مستخدمو نقاط البيع', NULL),
        ('app.hrms_text', 'app', N'Employees, leave, payroll, payslips and company setup.', N'الموظفون والإجازات والرواتب وكشوف الرواتب وإعداد الشركة.', NULL),
        ('app.pos_text', 'app', N'Dine-In tables, take away and online orders, payments and the order dashboard.', N'طاولات الصالة والطلبات الخارجية والأونلاين والمدفوعات ولوحة الطلبات.', NULL),
        ('app.online_order_text', 'app', N'The customer menu for taking online orders, for your brand and branch.', N'قائمة العملاء لاستقبال الطلبات أونلاين لعلامتك التجارية وفرعك.', NULL),
        ('app.assets_text', 'app', N'Company assets, who holds them and their history.', N'أصول الشركة ومن يحتفظ بها وسجلها.', NULL),
        ('app.feedback_text', 'app', N'Customer feedback from the QR menu, by question and branch.', N'آراء العملاء من قائمة QR حسب السؤال والفرع.', NULL),
        ('app.menu_colors_text', 'app', N'Menu design, colours and banner images, with a live preview.', N'تصميم القائمة وألوانها وصور البانر مع معاينة مباشرة.', NULL),
        ('app.items_text', 'app', N'Categories, items, modifiers, allergens and images.', N'الفئات والأصناف والإضافات ومسببات الحساسية والصور.', NULL),
        ('app.printers_text', 'app', N'Kitchen and receipt printers of each branch.', N'طابعات المطبخ والإيصالات لكل فرع.', NULL),
        ('app.settings_text', 'app', N'Tab theme, slide shows and menu labels.', N'سمة التبويبات وعروض الشرائح ونصوص القائمة.', NULL),
        ('app.security_text', 'app', N'Roles, permissions, user accounts and the audit report.', N'الأدوار والصلاحيات وحسابات المستخدمين وتقرير التدقيق.', NULL),
        ('app.pos_users_text', 'app', N'Restaurant staff: POS role, branches and POS password.', N'موظفو المطعم: دور نقاط البيع والفروع وكلمة مرور نقاط البيع.', NULL),
        ('app.coming_soon', 'app', N'Coming soon', N'قريباً', NULL),
        ('app.online_order_no_branch', 'app', N'No branch is set up for your account yet, so the online order menu cannot open. Ask an administrator to assign you a brand and a branch.', N'لا يوجد فرع مُعدّ لحسابك بعد، لذلك لا يمكن فتح قائمة الطلب أونلاين. اطلب من المسؤول تعيين علامة تجارية وفرع لك.', NULL),
        ('app.no_apps', 'app', N'Your account has no applications assigned yet. Ask an administrator to give your role access.', N'لم يتم تعيين أي تطبيقات لحسابك بعد. اطلب من المسؤول منح دورك صلاحية الوصول.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'App access labels inserted: ', @LabelsInserted);
GO
