/* =====================================================================
   33_Localization.sql  -  HRMS Kuwait: bilingual UI (English / Arabic)
   ---------------------------------------------------------------------
   Run AFTER 28_Soft_Delete.sql (and 29-32 if you have them). Idempotent:
   safe to re-run; it never overwrites a label you have edited.

   WHAT IT DOES
     1. Core.UiLabels               every piece of UI text, in English and
                                    Arabic, keyed by a stable LabelKey
                                    (e.g. 'org.branch_name').
     2. Security.Users              + PreferredLanguage ('en' / 'ar'):
                                    the language a user sees after sign-in.
     3. Core.usp_UiLabel_Get        ALL / VERSION - read by the web app,
                                    which caches the labels and re-checks
                                    the VERSION every 30 seconds.
     4. Core.usp_UiLabel_Manage     LIST / GET / INSERT / UPDATE / DELETE /
                                    TOGGLE (for a label-maintenance screen)
                                    + CAPTURE (the app records text it could
                                    not find, so it can be translated here).
     5. Security.usp_User_Language  GET / SET of PreferredLanguage.
     6. Seed: every label of the current application (views, scripts,
        validation and procedure messages) in English AND Arabic.
     7. Harvest: every literal @ResultMessage = N'...' found in the
        database's stored procedures that is not seeded yet is added with
        an empty ArabicText, ready to translate.

   HOW TO CORRECT A LABEL (no code change, no restart)
       UPDATE Core.UiLabels
          SET ArabicText = N'...', ModifiedDate = SYSUTCDATETIME()
        WHERE LabelKey = 'org.branch_name';
     The site picks the change up within ~30 seconds.

   Find text that still needs Arabic:
       SELECT LabelKey, EnglishText FROM Core.UiLabels
        WHERE Deleted = 0 AND (ArabicText IS NULL OR ArabicText = N'');

   COLUMNS
     LabelKey     what the code asks for: views use @L["org.branch_name"].
     EnglishText  English wording shown to the user.
     ArabicText   Arabic wording (falls back to English when empty).
     SourceText   only for sentences produced elsewhere (procedure / C#
                  messages with variable parts): the English template with
                  {0}, {1} placeholders, e.g.
                  'This account is locked ... Try again in {0} minutes.'
                  The app matches outgoing English messages against it.
     Module       grouping only: common, layout, auth, dash, org, emp, js,
                  msg (messages), mb (model binding), captured.

   Conventions: never physically deleted (Deleted flag), filtered unique
   index WHERE Deleted = 0, UTF-8 with BOM (Arabic literals are N'...').
   sqlcmd: run with -I (QUOTED_IDENTIFIER ON) and -f 65001.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* =====================================================================
   1. Core.UiLabels
   ===================================================================== */
IF OBJECT_ID(N'[Core].[UiLabels]', N'U') IS NULL
BEGIN
    CREATE TABLE [Core].[UiLabels](
        UiLabelId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UiLabels PRIMARY KEY,
        LabelKey      VARCHAR(150)    NOT NULL,
        Module        VARCHAR(30)     NOT NULL CONSTRAINT DF_UiLabels_Module DEFAULT ('common'),
        EnglishText   NVARCHAR(1000)  NOT NULL,
        ArabicText    NVARCHAR(1000)  NULL,
        SourceText    NVARCHAR(1000)  NULL,
        Notes         NVARCHAR(500)   NULL,
        IsActive      BIT             NOT NULL CONSTRAINT DF_UiLabels_IsActive DEFAULT (1),
        CreatedBy     BIGINT          NULL,
        CreatedDate   DATETIME2(0)    NOT NULL CONSTRAINT DF_UiLabels_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy    BIGINT          NULL,
        ModifiedDate  DATETIME2(0)    NULL,
        Deleted       BIT             NOT NULL CONSTRAINT DF_Core_UiLabels_Deleted DEFAULT (0),
        DeletedBy     BIGINT          NULL,
        DeletedDate   DATETIME2(7)    NULL,

        CONSTRAINT CK_UiLabels_Key CHECK (LabelKey NOT LIKE '%[^a-z0-9._]%' COLLATE Latin1_General_BIN AND LabelKey LIKE '%_._%')
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_UiLabels_Key' AND object_id = OBJECT_ID(N'[Core].[UiLabels]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_UiLabels_Key ON [Core].[UiLabels](LabelKey) WHERE Deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_UiLabels_Module' AND object_id = OBJECT_ID(N'[Core].[UiLabels]'))
    CREATE NONCLUSTERED INDEX IX_UiLabels_Module ON [Core].[UiLabels](Module, LabelKey) WHERE Deleted = 0;
GO
/* Same INSTEAD OF DELETE protection as every other table (28_Soft_Delete). */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Core', @TableName = N'UiLabels';
GO

/* =====================================================================
   2. Security.Users.PreferredLanguage
   ===================================================================== */
IF OBJECT_ID(N'[Security].[Users]', N'U') IS NULL
    RAISERROR (N'Security.Users was not found - run the base schema first.', 16, 1);
GO
IF COL_LENGTH(N'[Security].[Users]', N'PreferredLanguage') IS NULL
    ALTER TABLE [Security].[Users]
        ADD PreferredLanguage CHAR(2) NOT NULL
            CONSTRAINT DF_Users_PreferredLanguage DEFAULT ('en') WITH VALUES;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Users_PreferredLanguage')
    ALTER TABLE [Security].[Users] WITH CHECK
        ADD CONSTRAINT CK_Users_PreferredLanguage CHECK (PreferredLanguage IN ('en', 'ar'));
GO

/* =====================================================================
   3. Core.usp_UiLabel_Get   (read by the web application)
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Core].[usp_UiLabel_Get]
    @Action VARCHAR(20) = 'ALL'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'VERSION'
    BEGIN
        /* Changes whenever any label is added, edited, (de)activated or
           deleted. BINARY_CHECKSUM is case-sensitive, so fixing only the
           capitalisation of a label still counts as a change. */
        SELECT CONVERT(VARCHAR(20), COUNT_BIG(1)) + '-'
             + CONVERT(VARCHAR(20), ISNULL(CHECKSUM_AGG(BINARY_CHECKSUM(LabelKey, EnglishText, ArabicText, SourceText, IsActive, Deleted)), 0)) + '-'
             + ISNULL(CONVERT(VARCHAR(30), MAX(ISNULL(ModifiedDate, CreatedDate)), 126), '0')
        FROM   [Core].[UiLabels];
        RETURN;
    END;

    /* ALL */
    SELECT LabelKey, Module, EnglishText, ArabicText, SourceText
    FROM   [Core].[UiLabels]
    WHERE  Deleted = 0 AND IsActive = 1;
END;
GO

/* =====================================================================
   4. Core.usp_UiLabel_Manage   (label maintenance + CAPTURE)
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Core].[usp_UiLabel_Manage]
    @Action          VARCHAR(20),
    @Id              BIGINT          = NULL,

    @Search          NVARCHAR(200)   = NULL,
    @IsActiveFilter  BIT             = NULL,
    @ModuleFilter    VARCHAR(30)     = NULL,
    @MissingArabic   BIT             = NULL,    -- 1 = only rows without ArabicText
    @PageNumber      INT             = 1,
    @PageSize        INT             = 25,
    @SortColumn      VARCHAR(50)     = NULL,
    @SortDirection   VARCHAR(4)      = 'ASC',

    @LabelKey        VARCHAR(150)    = NULL,
    @Module          VARCHAR(30)     = NULL,
    @EnglishText     NVARCHAR(1000)  = NULL,
    @ArabicText      NVARCHAR(1000)  = NULL,
    @SourceText      NVARCHAR(1000)  = NULL,
    @Notes           NVARCHAR(500)   = NULL,
    @IsActive        BIT             = NULL,

    @ItemsJson       NVARCHAR(MAX)   = NULL,    -- CAPTURE: [{"key":"..."|null,"text":"..."}]

    @UserId          BIGINT          = NULL,

    @TotalCount      INT             = NULL OUTPUT,
    @NewId           BIGINT          = NULL OUTPUT,
    @ResultCode      VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage   NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE', 'CAPTURE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ---------------------------------------------------------- CAPTURE */
    IF @Action = 'CAPTURE'
    BEGIN
        IF ISJSON(@ItemsJson) <> 1 RETURN;

        ;WITH src AS (
            SELECT LabelKey = CASE WHEN j.[key] IS NOT NULL AND j.[key] NOT LIKE '%[^a-z0-9._]%' COLLATE Latin1_General_BIN
                                   THEN LEFT(j.[key], 150)
                                   ELSE 'msg.auto_' + LOWER(CONVERT(VARCHAR(40), HASHBYTES('SHA1', LEFT(j.[text], 1000)), 2)) END,
                   Module   = CASE WHEN j.[key] IS NOT NULL AND CHARINDEX('.', j.[key]) > 1 THEN LEFT(j.[key], CHARINDEX('.', j.[key]) - 1) ELSE 'captured' END,
                   [Text]   = LEFT(j.[text], 1000)
            FROM   OPENJSON(@ItemsJson) WITH ([key] VARCHAR(150) '$.key', [text] NVARCHAR(1000) '$.text') AS j
            WHERE  NULLIF(LTRIM(RTRIM(j.[text])), N'') IS NOT NULL
        )
        , one AS (   -- one row per key, even if a batch repeats it
            SELECT s.*, rn = ROW_NUMBER() OVER (PARTITION BY s.LabelKey ORDER BY s.Module)
            FROM   src AS s
        )
        INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, Notes, CreatedBy)
        SELECT s.LabelKey, LEFT(s.Module, 30), s.[Text], NULL,
               N'Captured automatically - the application asked for this text and found no label. Add the Arabic (and correct the English if needed).',
               @UserId
        FROM   one AS s
        WHERE  s.rn = 1
          AND  s.LabelKey LIKE '%_._%'
          AND  NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey AND l.Deleted = 0)
          AND  NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.EnglishText = s.[Text] COLLATE Latin1_General_BIN AND l.Deleted = 0);

        SET @TotalCount = @@ROWCOUNT;
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 500 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    /* ------------------------------------------------------------- LIST */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Core].[UiLabels] AS l
        WHERE  l.Deleted = 0
          AND (@IsActiveFilter IS NULL OR l.IsActive = @IsActiveFilter)
          AND (@ModuleFilter IS NULL OR l.Module = @ModuleFilter)
          AND (ISNULL(@MissingArabic, 0) = 0 OR NULLIF(l.ArabicText, N'') IS NULL)
          AND (@Pattern IS NULL OR l.LabelKey LIKE @Pattern ESCAPE '\' OR l.EnglishText LIKE @Pattern ESCAPE '\'
               OR l.ArabicText LIKE @Pattern ESCAPE '\' OR l.SourceText LIKE @Pattern ESCAPE '\');

        SELECT l.UiLabelId, l.LabelKey, l.Module, l.EnglishText, l.ArabicText, l.SourceText, l.Notes, l.IsActive,
               l.CreatedDate, l.ModifiedDate
        FROM   [Core].[UiLabels] AS l
        WHERE  l.Deleted = 0
          AND (@IsActiveFilter IS NULL OR l.IsActive = @IsActiveFilter)
          AND (@ModuleFilter IS NULL OR l.Module = @ModuleFilter)
          AND (ISNULL(@MissingArabic, 0) = 0 OR NULLIF(l.ArabicText, N'') IS NULL)
          AND (@Pattern IS NULL OR l.LabelKey LIKE @Pattern ESCAPE '\' OR l.EnglishText LIKE @Pattern ESCAPE '\'
               OR l.ArabicText LIKE @Pattern ESCAPE '\' OR l.SourceText LIKE @Pattern ESCAPE '\')
        ORDER BY
            CASE WHEN @SortDirection = 'ASC' THEN
                CASE @SortColumn WHEN 'Module' THEN l.Module WHEN 'EnglishText' THEN CONVERT(NVARCHAR(400), l.EnglishText)
                                 WHEN 'ArabicText' THEN CONVERT(NVARCHAR(400), l.ArabicText) ELSE l.LabelKey END END ASC,
            CASE WHEN @SortDirection = 'DESC' THEN
                CASE @SortColumn WHEN 'Module' THEN l.Module WHEN 'EnglishText' THEN CONVERT(NVARCHAR(400), l.EnglishText)
                                 WHEN 'ArabicText' THEN CONVERT(NVARCHAR(400), l.ArabicText) ELSE l.LabelKey END END DESC,
            l.UiLabelId
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* -------------------------------------------------------------- GET */
    IF @Action = 'GET'
    BEGIN
        SELECT l.UiLabelId, l.LabelKey, l.Module, l.EnglishText, l.ArabicText, l.SourceText, l.Notes, l.IsActive,
               l.CreatedDate, l.ModifiedDate
        FROM   [Core].[UiLabels] AS l
        WHERE  l.UiLabelId = @Id AND l.Deleted = 0;

        IF @@ROWCOUNT = 0
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists.';
        RETURN;
    END;

    /* --------------------------------------------------- INSERT / UPDATE */
    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SET @LabelKey    = LOWER(LTRIM(RTRIM(@LabelKey)));
        SET @EnglishText = NULLIF(LTRIM(RTRIM(@EnglishText)), N'');
        SET @ArabicText  = NULLIF(LTRIM(RTRIM(@ArabicText)), N'');
        SET @SourceText  = NULLIF(LTRIM(RTRIM(@SourceText)), N'');
        SET @Module      = ISNULL(NULLIF(LTRIM(RTRIM(@Module)), ''),
                                  CASE WHEN CHARINDEX('.', @LabelKey) > 1 THEN LEFT(@LabelKey, CHARINDEX('.', @LabelKey) - 1) ELSE 'common' END);

        IF NULLIF(@LabelKey, '') IS NULL OR @EnglishText IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Label key and English text are required.';
            RETURN;
        END;

        IF @LabelKey LIKE '%[^a-z0-9._]%' COLLATE Latin1_General_BIN OR @LabelKey NOT LIKE '%_._%'
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A label key uses lower-case letters, digits, dots and underscores (e.g. org.branch_name).';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Core].[UiLabels]
                   WHERE LabelKey = @LabelKey AND Deleted = 0 AND (@Action = 'INSERT' OR UiLabelId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That label key is already in use. Enter a different key.';
            RETURN;
        END;

        IF @Action = 'INSERT'
        BEGIN
            INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText, Notes, IsActive, CreatedBy)
            VALUES (@LabelKey, @Module, @EnglishText, @ArabicText, @SourceText, @Notes, ISNULL(@IsActive, 1), @UserId);

            SELECT @NewId = SCOPE_IDENTITY(), @ResultMessage = N'UI label created successfully.';
            RETURN;
        END;

        UPDATE [Core].[UiLabels]
           SET LabelKey = @LabelKey, Module = @Module, EnglishText = @EnglishText, ArabicText = @ArabicText,
               SourceText = @SourceText, Notes = @Notes, IsActive = ISNULL(@IsActive, IsActive),
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE UiLabelId = @Id AND Deleted = 0;

        IF @@ROWCOUNT = 0
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        ELSE
            SET @ResultMessage = N'UI label updated successfully.';
        RETURN;
    END;

    /* ----------------------------------------------------------- TOGGLE */
    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Core].[UiLabels]
           SET IsActive = 1 - IsActive, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE UiLabelId = @Id AND Deleted = 0;

        IF @@ROWCOUNT = 0
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        ELSE
            SET @ResultMessage = N'UI label updated successfully.';
        RETURN;
    END;

    /* ----------------------------------------------------------- DELETE */
    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Core].[UiLabels]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE UiLabelId = @Id AND Deleted = 0;

        IF @@ROWCOUNT = 0
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        ELSE
            SET @ResultMessage = N'UI label deleted successfully.';
        RETURN;
    END;
END;
GO

/* =====================================================================
   5. Security.usp_User_Language
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Security].[usp_User_Language]
    @Action    VARCHAR(10),
    @UserId    BIGINT,
    @Language  CHAR(2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'GET'
    BEGIN
        SELECT PreferredLanguage FROM [Security].[Users] WHERE UserId = @UserId;
        RETURN;
    END;

    IF @Action = 'SET'
    BEGIN
        IF @Language NOT IN ('en', 'ar')
        BEGIN
            RAISERROR (N'Language must be en or ar.', 16, 1);
            RETURN;
        END;

        UPDATE [Security].[Users] SET PreferredLanguage = @Language WHERE UserId = @UserId;
        RETURN;
    END;

    RAISERROR (N'Unsupported action.', 16, 1);
END;
GO

/* =====================================================================
   6. Seed - English + Arabic for the whole current application
   ---------------------------------------------------------------------
   New keys are inserted. Existing keys are only completed (an empty
   ArabicText / SourceText is filled in) - text you have already edited
   in the table is never overwritten by a re-run.
   ===================================================================== */
IF OBJECT_ID(N'tempdb..#Seed') IS NOT NULL DROP TABLE #Seed;
CREATE TABLE #Seed (
    LabelKey    VARCHAR(150)   COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    Module      VARCHAR(30)    COLLATE DATABASE_DEFAULT NOT NULL,
    EnglishText NVARCHAR(1000) COLLATE DATABASE_DEFAULT NOT NULL,
    ArabicText  NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
    SourceText  NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('org.organization_masters', 'org', N'Organization masters', N'البيانات الأساسية للمؤسسة', NULL),
    ('common.close', 'common', N'Close', N'إغلاق', NULL),
    ('org.delete_record', 'org', N'Delete record', N'حذف السجل', NULL),
    ('common.are_you_sure_you_want_to_delete', 'common', N'Are you sure you want to delete', N'هل أنت متأكد من حذف', NULL),
    ('org.the_record_is_hidden_everywhere_in_the_app_but_k', 'org', N'The record is hidden everywhere in the app but kept in the database (flagged as deleted). If it is still referenced elsewhere the delete is refused and you can deactivate it instead.', N'سيُخفى السجل من جميع شاشات النظام مع الاحتفاظ به في قاعدة البيانات (بعلامة محذوف). إذا كان السجل مستخدمًا في مكان آخر فسيُرفض الحذف، ويمكنك إلغاء تفعيله بدلًا من ذلك.', NULL),
    ('common.cancel', 'common', N'Cancel', N'إلغاء', NULL),
    ('common.delete', 'common', N'Delete', N'حذف', NULL),
    ('common.export', 'common', N'Export', N'تصدير', NULL),
    ('common.identity', 'common', N'Identity', N'التعريف', NULL),
    ('common.company', 'common', N'Company', N'الشركة', NULL),
    ('common.select', 'common', N'— Select —', N'— اختر —', NULL),
    ('org.branch_code', 'org', N'Branch Code', N'رمز الفرع', NULL),
    ('org.letters_numbers_hyphen_or_underscore_must_be_uni', 'org', N'Letters, numbers, hyphen or underscore. Must be unique.', N'أحرف وأرقام وشرطة أو شرطة سفلية. يجب أن يكون فريدًا.', NULL),
    ('org.branch_name', 'org', N'Branch Name', N'اسم الفرع', NULL),
    ('common.address', 'common', N'Address', N'العنوان', NULL),
    ('org.governorate', 'org', N'Governorate', N'المحافظة', NULL),
    ('org.area', 'org', N'Area', N'المنطقة', NULL),
    ('common.contact', 'common', N'Contact', N'الاتصال', NULL),
    ('org.telephone', 'org', N'Telephone', N'الهاتف', NULL),
    ('org.email', 'org', N'Email', N'البريد الإلكتروني', NULL),
    ('common.status', 'common', N'Status', N'الحالة', NULL),
    ('org.active', 'org', N'Active', N'نشط', NULL),
    ('org.inactive_records_stay_in_the_system_and_in_histo', 'org', N'Inactive records stay in the system and in history, but stop appearing in dropdowns.', N'تبقى السجلات غير النشطة في النظام وفي السجل التاريخي، لكنها لا تظهر في القوائم المنسدلة.', NULL),
    ('common.edit', 'common', N'Edit', N'تعديل', NULL),
    ('common.employees', 'common', N'Employees', N'الموظفون', NULL),
    ('common.actions', 'common', N'Actions', N'الإجراءات', NULL),
    ('org.inactive', 'org', N'Inactive', N'غير نشط', NULL),
    ('org.cr_no', 'org', N'CR No.', N'رقم السجل التجاري', NULL),
    ('org.branches', 'org', N'Branches', N'الفروع', NULL),
    ('org.company_code', 'org', N'Company Code', N'رمز الشركة', NULL),
    ('org.company_name', 'org', N'Company Name', N'اسم الشركة', NULL),
    ('org.legal_name', 'org', N'Legal Name', N'الاسم القانوني', NULL),
    ('org.full_registered_name_as_it_appears_on_the_commer', 'org', N'Full registered name as it appears on the commercial licence.', N'الاسم المسجل كاملًا كما يظهر في الرخصة التجارية.', NULL),
    ('org.registration', 'org', N'Registration', N'التسجيل', NULL),
    ('org.cr_number', 'org', N'CR Number', N'رقم السجل التجاري', NULL),
    ('org.tax_number', 'org', N'Tax Number', N'الرقم الضريبي', NULL),
    ('org.country', 'org', N'Country', N'الدولة', NULL),
    ('org.default_currency', 'org', N'Default Currency', N'العملة الافتراضية', NULL),
    ('org.website', 'org', N'Website', N'الموقع الإلكتروني', NULL),
    ('org.cost_center_code', 'org', N'Cost Center Code', N'رمز مركز التكلفة', NULL),
    ('org.cost_center_name', 'org', N'Cost Center Name', N'اسم مركز التكلفة', NULL),
    ('org.structure', 'org', N'Structure', N'الهيكل', NULL),
    ('org.rolls_up_to', 'org', N'Rolls Up To', N'يتبع إلى', NULL),
    ('org.top_level', 'org', N'— Top level —', N'— المستوى الأعلى —', NULL),
    ('org.leave_blank_for_a_top_level_cost_center', 'org', N'Leave blank for a top-level cost center.', N'اتركه فارغًا لمركز تكلفة في المستوى الأعلى.', NULL),
    ('org.departments', 'org', N'Departments', N'الإدارات', NULL),
    ('org.department_code', 'org', N'Department Code', N'رمز الإدارة', NULL),
    ('org.department_name', 'org', N'Department Name', N'اسم الإدارة', NULL),
    ('org.reports_to', 'org', N'Reports To', N'يتبع إلى', NULL),
    ('org.leave_blank_for_a_top_level_department', 'org', N'Leave blank for a top-level department.', N'اتركه فارغًا لإدارة في المستوى الأعلى.', NULL),
    ('common.cost_center', 'common', N'Cost Center', N'مركز التكلفة', NULL),
    ('org.sections', 'org', N'Sections', N'الأقسام', NULL),
    ('org.designation_code', 'org', N'Designation Code', N'رمز المسمى الوظيفي', NULL),
    ('org.designation_name', 'org', N'Designation Name', N'المسمى الوظيفي', NULL),
    ('org.use_the_wording_that_appears_on_the_civil_id_and', 'org', N'Use the wording that appears on the Civil ID and work permit.', N'استخدم الصياغة الواردة في البطاقة المدنية وإذن العمل.', NULL),
    ('org.arabic_name', 'org', N'Arabic Name', N'الاسم بالعربية', NULL),
    ('org.classification', 'org', N'Classification', N'التصنيف', NULL),
    ('common.grade', 'common', N'Grade', N'الدرجة', NULL),
    ('org.description', 'org', N'Description', N'الوصف', NULL),
    ('org.responsibilities_reporting_line_required_experie', 'org', N'Responsibilities, reporting line, required experience…', N'المسؤوليات، خط التبعية، الخبرة المطلوبة…', NULL),
    ('org.position_code', 'org', N'Position Code', N'رمز الوظيفة', NULL),
    ('org.position_name', 'org', N'Position Name', N'اسم الوظيفة', NULL),
    ('org.job_description', 'org', N'Job Description', N'الوصف الوظيفي', NULL),
    ('org.office_warehouse', 'org', N'Office, Warehouse…', N'مكتب، مستودع…', NULL),
    ('common.branch', 'common', N'Branch', N'الفرع', NULL),
    ('org.not_tied_to_a_branch', 'org', N'— Not tied to a branch —', N'— غير مرتبط بفرع —', NULL),
    ('org.location_code', 'org', N'Location Code', N'رمز الموقع', NULL),
    ('org.location_name', 'org', N'Location Name', N'اسم الموقع', NULL),
    ('org.type', 'org', N'Type', N'النوع', NULL),
    ('common.block', 'common', N'Block', N'القطعة', NULL),
    ('org.street', 'org', N'Street', N'الشارع', NULL),
    ('org.building', 'org', N'Building', N'المبنى', NULL),
    ('org.coordinates', 'org', N'Coordinates', N'الإحداثيات', NULL),
    ('org.latitude', 'org', N'Latitude', N'خط العرض', NULL),
    ('org.longitude', 'org', N'Longitude', N'خط الطول', NULL),
    ('org.filters_the_department_list_below', 'org', N'Filters the department list below.', N'يُصفّي قائمة الإدارات أدناه.', NULL),
    ('common.department', 'common', N'Department', N'الإدارة', NULL),
    ('org.section_code', 'org', N'Section Code', N'رمز القسم', NULL),
    ('org.section_name', 'org', N'Section Name', N'اسم القسم', NULL),
    ('org.nothing_matches_the_current_search_and_filter_tr', 'org', N'Nothing matches the current search and filter. Try a different term, or clear the filters to see every record.', N'لا توجد نتائج مطابقة للبحث والتصفية الحالية. جرّب كلمة أخرى أو امسح عوامل التصفية لعرض جميع السجلات.', NULL),
    ('common.clear_filters', 'common', N'Clear filters', N'مسح عوامل التصفية', NULL),
    ('common.filter_by_status', 'common', N'Filter by status', N'تصفية حسب الحالة', NULL),
    ('common.all_statuses', 'common', N'All statuses', N'جميع الحالات', NULL),
    ('common.active_only', 'common', N'Active only', N'النشطة فقط', NULL),
    ('common.inactive_only', 'common', N'Inactive only', N'غير النشطة فقط', NULL),
    ('common.pagination', 'common', N'Pagination', N'ترقيم الصفحات', NULL),
    ('common.previous_page', 'common', N'Previous page', N'الصفحة السابقة', NULL),
    ('common.next_page', 'common', N'Next page', N'الصفحة التالية', NULL),
    ('emp.delete_employee', 'emp', N'Delete employee', N'حذف الموظف', NULL),
    ('emp.the_employee_is_hidden_everywhere_in_the_app_but', 'emp', N'The employee is hidden everywhere in the app but kept in the database (flagged as deleted). If they are referenced elsewhere (as a manager or a system login) the delete is refused and you can deactivate them instead.', N'سيُخفى الموظف من جميع شاشات النظام مع الاحتفاظ به في قاعدة البيانات (بعلامة محذوف). إذا كان مرتبطًا بسجلات أخرى (كمدير أو كمستخدم للنظام) فسيُرفض الحذف، ويمكنك إلغاء تفعيله بدلًا من ذلك.', NULL),
    ('emp.add_employee', 'emp', N'Add Employee', N'إضافة موظف', NULL),
    ('emp.photo_upload_is_coming_soon', 'emp', N'Photo upload is coming soon', N'رفع الصورة قريبًا', NULL),
    ('emp.employee_photo_placeholder', 'emp', N'Employee photo placeholder', N'مكان صورة الموظف', NULL),
    ('emp.employee_steps', 'emp', N'Employee steps', N'خطوات إضافة الموظف', NULL),
    ('emp.e_g_4521', 'emp', N'e.g. 4521', N'مثال: 4521', NULL),
    ('emp.nearby_landmark_to_help_locate_the_address', 'emp', N'Nearby landmark to help locate the address', N'معلم قريب يساعد في تحديد العنوان', NULL),
    ('emp.e_g_laptop_mobile_company_vehicle', 'emp', N'e.g. Laptop, Mobile, Company Vehicle', N'مثال: حاسوب محمول، هاتف، سيارة الشركة', NULL),
    ('emp.e_g_nbk', 'emp', N'e.g. NBK', N'مثال: NBK', NULL),
    ('emp.e_g_article_18', 'emp', N'e.g. Article 18', N'مثال: المادة 18', NULL),
    ('emp.deactivated', 'emp', N'Deactivated', N'معطّل', NULL),
    ('emp.personal_info', 'emp', N'Personal Info', N'البيانات الشخصية', NULL),
    ('emp.employment', 'emp', N'Employment', N'التوظيف', NULL),
    ('common.kuwait_compliance', 'common', N'Kuwait Compliance', N'الامتثال الكويتي', NULL),
    ('emp.dependents', 'emp', N'Dependents', N'المعالون', NULL),
    ('emp.documents', 'emp', N'Documents', N'المستندات', NULL),
    ('emp.employee_no', 'emp', N'Employee No', N'الرقم الوظيفي', NULL),
    ('emp.employee_code', 'emp', N'Employee Code', N'رمز الموظف', NULL),
    ('emp.leave_blank_to_assign_later_must_be_unique_per_c', 'emp', N'Leave blank to assign later. Must be unique per company.', N'اتركه فارغًا لتعيينه لاحقًا. يجب أن يكون فريدًا داخل الشركة.', NULL),
    ('emp.name_arabic', 'emp', N'Name (Arabic)', N'الاسم (بالعربية)', NULL),
    ('emp.first_name', 'emp', N'First Name', N'الاسم الأول', NULL),
    ('emp.middle_name', 'emp', N'Middle Name', N'الاسم الأوسط', NULL),
    ('emp.last_name', 'emp', N'Last Name', N'اسم العائلة', NULL),
    ('emp.gender', 'emp', N'Gender', N'الجنس', NULL),
    ('emp.male', 'emp', N'Male', N'ذكر', NULL),
    ('emp.female', 'emp', N'Female', N'أنثى', NULL),
    ('emp.date_of_birth', 'emp', N'Date of Birth', N'تاريخ الميلاد', NULL),
    ('emp.marital_status', 'emp', N'Marital Status', N'الحالة الاجتماعية', NULL),
    ('emp.nationality', 'emp', N'Nationality', N'الجنسية', NULL),
    ('emp.religion', 'emp', N'Religion', N'الديانة', NULL),
    ('emp.blood_group', 'emp', N'Blood Group', N'فصيلة الدم', NULL),
    ('emp.mobile_number', 'emp', N'Mobile Number', N'رقم الهاتف النقال', NULL),
    ('emp.extension', 'emp', N'Extension', N'الرقم الداخلي', NULL),
    ('emp.personal_email', 'emp', N'Personal Email', N'البريد الإلكتروني الشخصي', NULL),
    ('emp.work_email', 'emp', N'Work Email', N'البريد الإلكتروني للعمل', NULL),
    ('emp.company_phone', 'emp', N'Company Phone', N'هاتف الشركة', NULL),
    ('emp.neighborhood', 'emp', N'Neighborhood', N'الحي', NULL),
    ('emp.street_name', 'emp', N'Street Name', N'اسم الشارع', NULL),
    ('emp.building_villa_number', 'emp', N'Building / Villa Number', N'رقم المبنى / الفيلا', NULL),
    ('emp.floor_number', 'emp', N'Floor Number', N'رقم الدور', NULL),
    ('emp.flat_number', 'emp', N'Flat Number', N'رقم الشقة', NULL),
    ('emp.paci_number', 'emp', N'PACI Number', N'الرقم الآلي (PACI)', NULL),
    ('emp.landmark', 'emp', N'Landmark', N'معلم قريب', NULL),
    ('emp.emergency_contact', 'emp', N'Emergency Contact', N'جهة الاتصال في الطوارئ', NULL),
    ('emp.contact_name', 'emp', N'Contact Name', N'اسم جهة الاتصال', NULL),
    ('emp.contact_phone', 'emp', N'Contact Phone', N'هاتف جهة الاتصال', NULL),
    ('emp.relationship', 'emp', N'Relationship', N'صلة القرابة', NULL),
    ('emp.father_s_details', 'emp', N'Father''s Details', N'بيانات الأب', NULL),
    ('emp.name_occupation_and_contact_number_of_the_employ', 'emp', N'Name, occupation and contact number of the employee''s father', N'اسم والد الموظف ومهنته ورقم هاتفه', NULL),
    ('emp.father_s_name', 'emp', N'Father''s Name', N'اسم الأب', NULL),
    ('emp.father_s_occupation', 'emp', N'Father''s Occupation', N'مهنة الأب', NULL),
    ('emp.father_s_mobile_number', 'emp', N'Father''s Mobile Number', N'رقم هاتف الأب', NULL),
    ('emp.currently_residing_in', 'emp', N'Currently Residing In', N'مكان الإقامة الحالي', NULL),
    ('emp.deceased', 'emp', N'Deceased', N'متوفى', NULL),
    ('emp.organization', 'emp', N'Organization', N'المؤسسة', NULL),
    ('emp.work_location', 'emp', N'Work Location', N'موقع العمل', NULL),
    ('emp.section', 'emp', N'Section', N'القسم', NULL),
    ('emp.role', 'emp', N'Role', N'الدور', NULL),
    ('emp.job_position', 'emp', N'Job Position', N'الوظيفة', NULL),
    ('emp.designation', 'emp', N'Designation', N'المسمى الوظيفي', NULL),
    ('emp.reporting_manager', 'emp', N'Reporting Manager', N'المدير المباشر', NULL);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('emp.none', 'emp', N'— None —', N'— لا يوجد —', NULL),
    ('emp.employment_terms', 'emp', N'Employment Terms', N'شروط التوظيف', NULL),
    ('emp.hire_date', 'emp', N'Hire Date', N'تاريخ التعيين', NULL),
    ('emp.probation_end_date', 'emp', N'Probation End Date', N'تاريخ انتهاء فترة التجربة', NULL),
    ('emp.termination_date', 'emp', N'Termination Date', N'تاريخ انتهاء الخدمة', NULL),
    ('emp.employment_type', 'emp', N'Employment Type', N'نوع التوظيف', NULL),
    ('emp.employment_status', 'emp', N'Employment Status', N'الحالة الوظيفية', NULL),
    ('emp.independent_of_active_deactivated_below_an_emplo', 'emp', N'Independent of Active/Deactivated below - an employee is never hard-deleted for payroll and Kuwait labour-law history.', N'مستقلة عن خيار نشط/معطّل أدناه - لا يُحذف الموظف نهائيًا أبدًا حفاظًا على سجلات الرواتب وقانون العمل الكويتي.', NULL),
    ('emp.notice_period_days', 'emp', N'Notice Period (Days)', N'فترة الإنذار (بالأيام)', NULL),
    ('emp.company_assets', 'emp', N'Company Assets', N'عُهد الشركة', NULL),
    ('emp.separate_items_with_commas', 'emp', N'Separate items with commas.', N'افصل بين العناصر بفواصل.', NULL),
    ('emp.payroll_bank', 'emp', N'Payroll & Bank', N'الرواتب والبنك', NULL),
    ('emp.basic_salary_kwd', 'emp', N'Basic Salary (KWD)', N'الراتب الأساسي (د.ك)', NULL),
    ('emp.allowances_kwd', 'emp', N'Allowances (KWD)', N'البدلات (د.ك)', NULL),
    ('emp.gross_monthly_kwd', 'emp', N'Gross Monthly (KWD)', N'إجمالي الراتب الشهري (د.ك)', NULL),
    ('emp.basic_allowances_updates_after_saving', 'emp', N'Basic + allowances. Updates after saving.', N'الأساسي + البدلات. يتم التحديث بعد الحفظ.', NULL),
    ('emp.bank_name', 'emp', N'Bank Name', N'اسم البنك', NULL),
    ('emp.iban_account_no', 'emp', N'IBAN / Account No.', N'الآيبان / رقم الحساب', NULL),
    ('emp.save_the_employee_s_personal_info_first_then_add', 'emp', N'Save the employee''s Personal Info first, then add Kuwait compliance details here.', N'احفظ البيانات الشخصية للموظف أولًا، ثم أضف بيانات الامتثال الكويتي هنا.', NULL),
    ('emp.civil_id', 'emp', N'Civil ID', N'البطاقة المدنية', NULL),
    ('emp.civil_id_number', 'emp', N'Civil ID Number', N'الرقم المدني', NULL),
    ('emp.civil_id_expiry', 'emp', N'Civil ID Expiry', N'تاريخ انتهاء البطاقة المدنية', NULL),
    ('emp.passport', 'emp', N'Passport', N'جواز السفر', NULL),
    ('emp.passport_number', 'emp', N'Passport Number', N'رقم جواز السفر', NULL),
    ('emp.issuing_country', 'emp', N'Issuing Country', N'بلد الإصدار', NULL),
    ('emp.passport_expiry', 'emp', N'Passport Expiry', N'تاريخ انتهاء جواز السفر', NULL),
    ('emp.residency_iqama_sponsorship', 'emp', N'Residency (Iqama) & Sponsorship', N'الإقامة والكفالة', NULL),
    ('emp.residency_number', 'emp', N'Residency Number', N'رقم الإقامة', NULL),
    ('emp.residency_type', 'emp', N'Residency Type', N'نوع الإقامة', NULL),
    ('emp.residency_expiry', 'emp', N'Residency Expiry', N'تاريخ انتهاء الإقامة', NULL),
    ('emp.sponsor_name', 'emp', N'Sponsor Name', N'اسم الكفيل', NULL),
    ('emp.sponsor_file_number', 'emp', N'Sponsor File Number', N'رقم ملف الكفيل', NULL),
    ('emp.sponsor_status', 'emp', N'Sponsor Status', N'حالة الكفالة', NULL),
    ('emp.residency_status', 'emp', N'Residency Status', N'حالة الإقامة', NULL),
    ('emp.ministry_of_labour_work_permit', 'emp', N'Ministry of Labour & Work Permit', N'الهيئة العامة للقوى العاملة وإذن العمل', NULL),
    ('emp.mol_file_number', 'emp', N'MOL File Number', N'رقم ملف القوى العاملة', NULL),
    ('emp.work_permit_number', 'emp', N'Work Permit Number', N'رقم إذن العمل', NULL),
    ('emp.work_permit_expiry', 'emp', N'Work Permit Expiry', N'تاريخ انتهاء إذن العمل', NULL),
    ('emp.paci_civil_address', 'emp', N'PACI Civil Address', N'العنوان المدني (PACI)', NULL),
    ('emp.paci_address', 'emp', N'PACI Address', N'عنوان الهيئة العامة للمعلومات المدنية', NULL),
    ('emp.driving_medical', 'emp', N'Driving & Medical', N'القيادة والفحص الطبي', NULL),
    ('emp.driving_license_number', 'emp', N'Driving License Number', N'رقم رخصة القيادة', NULL),
    ('emp.driving_license_expiry', 'emp', N'Driving License Expiry', N'تاريخ انتهاء رخصة القيادة', NULL),
    ('emp.blood_type', 'emp', N'Blood Type', N'فصيلة الدم', NULL),
    ('emp.health_cert_expiry', 'emp', N'Health Cert. Expiry', N'تاريخ انتهاء الشهادة الصحية', NULL),
    ('emp.save_compliance_details', 'emp', N'Save Compliance Details', N'حفظ بيانات الامتثال', NULL),
    ('emp.save_the_employee_s_personal_info_first_then_add_2', 'emp', N'Save the employee''s Personal Info first, then add dependents here.', N'احفظ البيانات الشخصية للموظف أولًا، ثم أضف المعالين هنا.', NULL),
    ('emp.save_the_employee_s_personal_info_first_then_upl', 'emp', N'Save the employee''s Personal Info first, then upload documents here.', N'احفظ البيانات الشخصية للموظف أولًا، ثم ارفع المستندات هنا.', NULL),
    ('emp.previous', 'emp', N'Previous', N'السابق', NULL),
    ('emp.next', 'emp', N'Next', N'التالي', NULL),
    ('emp.finish', 'emp', N'Finish', N'إنهاء', NULL),
    ('emp.create_employee', 'emp', N'Create Employee', N'إنشاء الموظف', NULL),
    ('emp.are_you_sure_you_want_to_create_employee', 'emp', N'Are you sure you want to Create Employee?', N'هل أنت متأكد من إنشاء الموظف؟', NULL),
    ('emp.yes_create_employee', 'emp', N'Yes, create employee', N'نعم، أنشئ الموظف', NULL),
    ('emp.add_dependent', 'emp', N'Add Dependent', N'إضافة معال', NULL),
    ('emp.full_name', 'emp', N'Full Name', N'الاسم الكامل', NULL),
    ('emp.health_insurance_coverage', 'emp', N'Health Insurance Coverage', N'التغطية بالتأمين الصحي', NULL),
    ('emp.save', 'emp', N'Save', N'حفظ', NULL),
    ('emp.delete_dependent', 'emp', N'Delete dependent', N'حذف المعال', NULL),
    ('emp.are_you_sure_you_want_to_remove', 'emp', N'Are you sure you want to remove', N'هل أنت متأكد من إزالة', NULL),
    ('emp.remove_document', 'emp', N'Remove document', N'إزالة المستند', NULL),
    ('emp.remove_the_uploaded_file_for', 'emp', N'Remove the uploaded file for', N'إزالة الملف المرفوع لـ', NULL),
    ('emp.you_can_upload_a_new_one_afterwards', 'emp', N'? You can upload a new one afterwards.', N'؟ يمكنك رفع ملف جديد بعد ذلك.', NULL),
    ('emp.remove', 'emp', N'Remove', N'إزالة', NULL),
    ('emp.open_profile', 'emp', N'Open profile', N'فتح الملف', NULL),
    ('emp.no_dependents_added_yet', 'emp', N'No dependents added yet', N'لم تتم إضافة معالين بعد', NULL),
    ('emp.register_a_spouse_children_or_other_dependents_u', 'emp', N'Register a spouse, children or other dependents - useful for health-insurance coverage and Kuwait labour-law records.', N'سجّل الزوج/الزوجة أو الأبناء أو المعالين الآخرين - مفيد للتغطية بالتأمين الصحي وسجلات قانون العمل الكويتي.', NULL),
    ('emp.name', 'emp', N'Name', N'الاسم', NULL),
    ('emp.coverage', 'emp', N'Coverage', N'التغطية', NULL),
    ('emp.health_insurance', 'emp', N'Health Insurance', N'التأمين الصحي', NULL),
    ('emp.not_covered', 'emp', N'Not Covered', N'غير مشمول', NULL),
    ('emp.mandatory_documents_complete', 'emp', N'Mandatory documents complete', N'المستندات الإلزامية مكتملة', NULL),
    ('emp.search_document_types', 'emp', N'Search document types…', N'ابحث في أنواع المستندات…', NULL),
    ('emp.search_document_types_2', 'emp', N'Search document types', N'البحث في أنواع المستندات', NULL),
    ('emp.filter_by_requirement', 'emp', N'Filter by requirement', N'تصفية حسب الإلزامية', NULL),
    ('emp.mandatory', 'emp', N'Mandatory', N'إلزامي', NULL),
    ('emp.view', 'emp', N'View', N'عرض', NULL),
    ('emp.download', 'emp', N'Download', N'تنزيل', NULL),
    ('emp.upload', 'emp', N'Upload', N'رفع', NULL),
    ('emp.employee_documents', 'emp', N'Employee Documents', N'مستندات الموظف', NULL),
    ('emp.mandatory_attachment', 'emp', N'Mandatory attachment', N'مرفق إلزامي', NULL),
    ('emp.missing_required', 'emp', N'Missing required', N'إلزامي ناقص', NULL),
    ('emp.no_document_types_are_set_up_yet', 'emp', N'No document types are set up yet', N'لم يتم إعداد أنواع المستندات بعد', NULL),
    ('emp.add_rows_to_documents_documenttypes_and_assign_e', 'emp', N'Add rows to Documents.DocumentTypes (and assign each a SectionID) - they will appear here, grouped by Document Section, each with its own upload slot.', N'أضف صفوفًا إلى الجدول Documents.DocumentTypes (وحدد لكل منها SectionID) - ستظهر هنا مجمّعة حسب قسم المستندات، ولكل منها خانة رفع خاصة.', NULL),
    ('emp.document_types', 'emp', N'Document types', N'أنواع المستندات', NULL),
    ('emp.uploaded', 'emp', N'Uploaded', N'مرفوع', NULL),
    ('emp.mandatory_missing', 'emp', N'Mandatory missing', N'إلزامي ناقص', NULL),
    ('emp.mandatory_complete', 'emp', N'Mandatory complete', N'الإلزامي مكتمل', NULL),
    ('emp.all_requirements', 'emp', N'All requirements', N'جميع المتطلبات', NULL),
    ('emp.mandatory_only', 'emp', N'Mandatory only', N'الإلزامي فقط', NULL),
    ('emp.optional_only', 'emp', N'Optional only', N'الاختياري فقط', NULL),
    ('emp.not_uploaded', 'emp', N'Not uploaded', N'غير مرفوع', NULL),
    ('emp.collapse_all', 'emp', N'Collapse all', N'طي الكل', NULL),
    ('emp.all_mandatory_documents_are_attached', 'emp', N'All mandatory documents are attached.', N'جميع المستندات الإلزامية مرفقة.', NULL),
    ('emp.employee_documents_grouped_by_section', 'emp', N'Employee documents grouped by section', N'مستندات الموظف مجمّعة حسب القسم', NULL),
    ('emp.document_type', 'emp', N'Document Type', N'نوع المستند', NULL),
    ('emp.requirement', 'emp', N'Requirement', N'الإلزامية', NULL),
    ('emp.attachment', 'emp', N'Attachment', N'المرفق', NULL),
    ('emp.uploaded_on', 'emp', N'Uploaded On', N'تاريخ الرفع', NULL),
    ('emp.optional', 'emp', N'Optional', N'اختياري', NULL),
    ('emp.replace', 'emp', N'Replace', N'استبدال', NULL),
    ('emp.choose_file', 'emp', N'Choose file', N'اختر ملفًا', NULL),
    ('emp.or_drag_drop', 'emp', N'or drag & drop', N'أو اسحبه وأفلته هنا', NULL),
    ('emp.browse', 'emp', N'Browse', N'استعراض', NULL),
    ('emp.required', 'emp', N'Required', N'مطلوب', NULL),
    ('emp.pending', 'emp', N'Pending', N'معلّق', NULL),
    ('emp.no_document_types_match', 'emp', N'No document types match', N'لا توجد أنواع مستندات مطابقة', NULL),
    ('emp.try_a_different_search_or_filter', 'emp', N'Try a different search or filter.', N'جرّب بحثًا أو تصفية مختلفة.', NULL),
    ('emp.no_matching_employees', 'emp', N'No matching employees', N'لا يوجد موظفون مطابقون', NULL),
    ('emp.nothing_matches_the_current_search_and_filter_tr', 'emp', N'Nothing matches the current search and filter. Try a different term, or clear the filters to see every employee.', N'لا توجد نتائج مطابقة للبحث والتصفية الحالية. جرّب كلمة أخرى أو امسح عوامل التصفية لعرض جميع الموظفين.', NULL),
    ('emp.no_employees_yet', 'emp', N'No employees yet', N'لا يوجد موظفون بعد', NULL),
    ('emp.add_the_first_employee_to_get_started', 'emp', N'Add the first employee to get started.', N'أضف الموظف الأول للبدء.', NULL),
    ('emp.search_employees', 'emp', N'Search employees…', N'ابحث عن موظف…', NULL),
    ('emp.search_employees_2', 'emp', N'Search employees', N'البحث عن الموظفين', NULL),
    ('layout.something_went_wrong', 'layout', N'Something went wrong', N'حدث خطأ ما', NULL),
    ('layout.the_request_could_not_be_completed_nothing_was_s', 'layout', N'The request could not be completed. Nothing was saved. If this keeps happening, quote the reference below to your system administrator.', N'تعذّر إكمال الطلب ولم يتم حفظ أي شيء. إذا تكرر ذلك، أبلغ مسؤول النظام بالرقم المرجعي أدناه.', NULL),
    ('layout.reference', 'layout', N'Reference:', N'الرقم المرجعي:', NULL),
    ('common.back_to_organization_setup', 'common', N'Back to Organization Setup', N'العودة إلى إعداد المؤسسة', NULL),
    ('layout.close_navigation', 'layout', N'Close navigation', N'إغلاق القائمة', NULL),
    ('layout.main_navigation', 'layout', N'Main navigation', N'القائمة الرئيسية', NULL),
    ('layout.open_an_employee_s_profile_for_their_kuwait_comp', 'layout', N'Open an employee''s profile for their Kuwait Compliance tab', N'افتح ملف الموظف للوصول إلى تبويب الامتثال الكويتي', NULL),
    ('layout.account_menu', 'layout', N'Account menu', N'قائمة الحساب', NULL),
    ('layout.open_navigation', 'layout', N'Open navigation', N'فتح القائمة', NULL),
    ('layout.search_ctrl_k', 'layout', N'Search (Ctrl K)', N'بحث (Ctrl K)', NULL),
    ('layout.search_employees_documents_requests', 'layout', N'Search employees, documents, requests…', N'ابحث عن موظفين، مستندات، طلبات…', NULL),
    ('layout.global_search', 'layout', N'Global search', N'البحث العام', NULL),
    ('layout.notifications', 'layout', N'Notifications', N'الإشعارات', NULL),
    ('common.show_password', 'common', N'Show password', N'إظهار كلمة المرور', NULL),
    ('layout.skip_to_main_content', 'layout', N'Skip to main content', N'انتقل إلى المحتوى الرئيسي', NULL),
    ('common.hr_payroll', 'common', N'HR & Payroll', N'الموارد البشرية والرواتب', NULL),
    ('common.kuwait_edition', 'common', N'Kuwait Edition', N'إصدار الكويت', NULL),
    ('layout.dashboard', 'layout', N'Dashboard', N'لوحة المعلومات', NULL),
    ('layout.workforce', 'layout', N'Workforce', N'القوى العاملة', NULL),
    ('layout.per_employee', 'layout', N'Per employee', N'لكل موظف', NULL),
    ('layout.time_attendance', 'layout', N'Time & Attendance', N'الوقت والحضور', NULL),
    ('layout.attendance', 'layout', N'Attendance', N'الحضور', NULL),
    ('common.soon', 'common', N'Soon', N'قريبًا', NULL),
    ('layout.overtime', 'layout', N'Overtime', N'العمل الإضافي', NULL),
    ('layout.payroll', 'layout', N'Payroll', N'الرواتب', NULL),
    ('layout.leave', 'layout', N'Leave', N'الإجازات', NULL),
    ('layout.loans_advances', 'layout', N'Loans & Advances', N'القروض والسلف', NULL),
    ('layout.end_of_service', 'layout', N'End of Service', N'نهاية الخدمة', NULL),
    ('layout.system', 'layout', N'System', N'النظام', NULL),
    ('layout.reports', 'layout', N'Reports', N'التقارير', NULL),
    ('layout.system_admin', 'layout', N'System Admin', N'إدارة النظام', NULL),
    ('layout.setup', 'layout', N'Setup', N'الإعدادات', NULL),
    ('layout.change_password', 'layout', N'Change password', N'تغيير كلمة المرور', NULL),
    ('layout.sign_out', 'layout', N'Sign out', N'تسجيل الخروج', NULL),
    ('layout.show_data_for', 'layout', N'Show data for', N'عرض بيانات', NULL),
    ('layout.all_companies', 'layout', N'All companies', N'جميع الشركات', NULL);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('layout.show_all', 'layout', N'Show all', N'عرض الكل', NULL),
    ('layout.apply', 'layout', N'Apply', N'تطبيق', NULL),
    ('layout.this_account_is_still_using_its_initial_password', 'layout', N'This account is still using its initial password.', N'هذا الحساب لا يزال يستخدم كلمة المرور الأولية.', NULL),
    ('layout.change_it_now_to_keep_the_account_secure', 'layout', N'Change it now to keep the account secure.', N'غيّرها الآن للحفاظ على أمان الحساب.', NULL),
    ('layout.current_password', 'layout', N'Current password', N'كلمة المرور الحالية', NULL),
    ('layout.new_password', 'layout', N'New password', N'كلمة المرور الجديدة', NULL),
    ('layout.at_least_8_characters', 'layout', N'At least 8 characters', N'8 أحرف على الأقل', NULL),
    ('layout.upper_and_lower_case_letters', 'layout', N'Upper- and lower-case letters', N'أحرف كبيرة وصغيرة', NULL),
    ('layout.at_least_one_number', 'layout', N'At least one number', N'رقم واحد على الأقل', NULL),
    ('layout.confirm_new_password', 'layout', N'Confirm new password', N'تأكيد كلمة المرور الجديدة', NULL),
    ('layout.your_other_signed_in_sessions_other_browsers_or', 'layout', N'Your other signed-in sessions (other browsers or devices) will be signed out.', N'سيتم تسجيل خروج جلساتك الأخرى (المتصفحات أو الأجهزة الأخرى).', NULL),
    ('dash.key_figures', 'dash', N'Key figures', N'المؤشرات الرئيسية', NULL),
    ('dash.compared_with_last_month', 'dash', N'Compared with last month', N'مقارنة بالشهر السابق', NULL),
    ('dash.employees_by_company', 'dash', N'Employees by company', N'الموظفون حسب الشركة', NULL),
    ('dash.available_once_the_leave_module_is_built', 'dash', N'Available once the Leave module is built', N'متاح بعد تطوير وحدة الإجازات', NULL),
    ('dash.gross_payroll_by_month_for_the_last_12_months', 'dash', N'Gross payroll by month for the last 12 months', N'إجمالي الرواتب شهريًا لآخر 12 شهرًا', NULL),
    ('dash.month', 'dash', N'Month', N'الشهر', NULL),
    ('dash.show', 'dash', N'Show', N'عرض', NULL),
    ('dash.no_companies_yet', 'dash', N'No companies yet.', N'لا توجد شركات بعد.', NULL),
    ('dash.highlighted_the_companies_selected_in_the_compan', 'dash', N'Highlighted: the companies selected in the company filter. All other figures on this page cover only those companies.', N'المميّزة: الشركات المحددة في تصفية الشركات. جميع الأرقام الأخرى في هذه الصفحة تخص هذه الشركات فقط.', NULL),
    ('dash.hr_actions_required', 'dash', N'HR actions required', N'إجراءات الموارد البشرية المطلوبة', NULL),
    ('dash.next_30_days', 'dash', N'Next 30 days', N'الـ 30 يومًا القادمة', NULL),
    ('dash.documents_expiring_within_30_days', 'dash', N'Documents expiring within 30 days', N'مستندات تنتهي خلال 30 يومًا', NULL),
    ('dash.probation_ending_within_30_days', 'dash', N'Probation ending within 30 days', N'فترات تجربة تنتهي خلال 30 يومًا', NULL),
    ('dash.employees_missing_a_mandatory_document_upload', 'dash', N'Employees missing a mandatory document upload', N'موظفون ينقصهم رفع مستند إلزامي', NULL),
    ('dash.leave_approvals_pending', 'dash', N'Leave approvals pending', N'طلبات إجازة بانتظار الموافقة', NULL),
    ('dash.payroll_summary', 'dash', N'Payroll summary', N'ملخص الرواتب', NULL),
    ('dash.monthly_current_salaries', 'dash', N'Monthly, current salaries', N'شهريًا، الرواتب الحالية', NULL),
    ('dash.gross', 'dash', N'Gross', N'الإجمالي', NULL),
    ('dash.basic_salary', 'dash', N'Basic salary', N'الراتب الأساسي', NULL),
    ('dash.allowances', 'dash', N'Allowances', N'البدلات', NULL),
    ('dash.employees_with_salary', 'dash', N'Employees with salary', N'موظفون لديهم راتب', NULL),
    ('dash.deductions_net_pay_and_employer_cost_pifss_appea', 'dash', N'Deductions, net pay and employer cost (PIFSS) appear once payroll runs are processed in the Payroll module.', N'تظهر الاستقطاعات وصافي الراتب وتكلفة صاحب العمل (التأمينات الاجتماعية) بعد معالجة مسيرات الرواتب في وحدة الرواتب.', NULL),
    ('dash.leave_summary', 'dash', N'Leave summary', N'ملخص الإجازات', NULL),
    ('dash.annual_leave', 'dash', N'Annual leave', N'إجازة سنوية', NULL),
    ('dash.sick_leave', 'dash', N'Sick leave', N'إجازة مرضية', NULL),
    ('dash.emergency_leave', 'dash', N'Emergency leave', N'إجازة طارئة', NULL),
    ('dash.other', 'dash', N'Other', N'أخرى', NULL),
    ('dash.on_leave', 'dash', N'On leave', N'في إجازة', NULL),
    ('dash.payroll_trend', 'dash', N'Payroll trend', N'اتجاه الرواتب', NULL),
    ('dash.gross_payroll_last_12_months', 'dash', N'Gross payroll, last 12 months', N'إجمالي الرواتب، آخر 12 شهرًا', NULL),
    ('dash.no_salaries_recorded_yet_add_basic_salary_on_an', 'dash', N'No salaries recorded yet. Add Basic Salary on an employee''s Employment tab, or run db/21.', N'لم تُسجل رواتب بعد. أضف الراتب الأساسي في تبويب التوظيف للموظف، أو شغّل db/21.', NULL),
    ('dash.based_on_the_current_basic_allowances_of_the_emp', 'dash', N'Based on the current basic + allowances of the employees on the books each month. Net payroll and employer cost lines are added once payroll runs exist.', N'مبني على الراتب الأساسي والبدلات الحالية للموظفين المسجلين في كل شهر. تُضاف خطوط صافي الرواتب وتكلفة صاحب العمل عند وجود مسيرات رواتب.', NULL),
    ('dash.employees_by_department', 'dash', N'Employees by department', N'الموظفون حسب الإدارة', NULL),
    ('dash.today_2', 'dash', N'Today', N'اليوم', NULL),
    ('dash.no_employees_yet', 'dash', N'No employees yet.', N'لا يوجد موظفون بعد.', NULL),
    ('dash.upcoming_events', 'dash', N'Upcoming events', N'الأحداث القادمة', NULL),
    ('dash.nothing_in_the_next_30_days_no_birthdays_anniver', 'dash', N'Nothing in the next 30 days - no birthdays, anniversaries, document expiries or probation end dates.', N'لا شيء خلال الـ 30 يومًا القادمة - لا أعياد ميلاد ولا ذكرى سنوية ولا انتهاء مستندات أو فترات تجربة.', NULL),
    ('dash.recent_hr_activities', 'dash', N'Recent HR activities', N'أحدث أنشطة الموارد البشرية', NULL),
    ('dash.no_activity_yet', 'dash', N'No activity yet.', N'لا يوجد نشاط بعد.', NULL),
    ('dash.employee', 'dash', N'Employee', N'الموظف', NULL),
    ('dash.activity', 'dash', N'Activity', N'النشاط', NULL),
    ('dash.date', 'dash', N'Date', N'التاريخ', NULL),
    ('auth.you_do_not_have_access_to_that_page', 'auth', N'You do not have access to that page', N'ليس لديك صلاحية الوصول إلى هذه الصفحة', NULL),
    ('auth.your_account_is_signed_in_but_it_does_not_hold_t', 'auth', N'Your account is signed in, but it does not hold the permission this page requires. If you believe this is wrong, ask your HR administrator to review your role.', N'تم تسجيل دخول حسابك، لكنه لا يملك الصلاحية التي تتطلبها هذه الصفحة. إذا كنت تعتقد أن هذا خطأ، اطلب من مسؤول الموارد البشرية مراجعة دورك.', NULL),
    ('auth.forgot_password_is_the_next_part_of_module_1', 'auth', N'Forgot Password is the next part of Module 1', N'استعادة كلمة المرور هي الجزء التالي من الوحدة 1', NULL),
    ('auth.enter_your_password', 'auth', N'Enter your password', N'أدخل كلمة المرور', NULL),
    ('auth.built_for_kuwait_labour_law_compliance', 'auth', N'Built for Kuwait Labour Law compliance', N'مصمم للامتثال لقانون العمل الكويتي', NULL),
    ('auth.hr_payroll_run_with_total_confidence', 'auth', N'HR & Payroll, run with total confidence.', N'الموارد البشرية والرواتب بثقة تامة.', NULL),
    ('auth.one_workspace_for_employee_records_attendance_le', 'auth', N'One workspace for employee records, attendance, leave, payroll and Kuwait regulatory documents.', N'مساحة عمل واحدة لسجلات الموظفين والحضور والإجازات والرواتب والمستندات الرسمية الكويتية.', NULL),
    ('auth.wps_ready_payroll', 'auth', N'WPS-ready payroll', N'رواتب جاهزة لنظام حماية الأجور', NULL),
    ('auth.generate_compliant_wages_protection_system_bank', 'auth', N'Generate compliant Wages Protection System bank files in one step.', N'أنشئ ملفات البنك المتوافقة مع نظام حماية الأجور بخطوة واحدة.', NULL),
    ('auth.civil_id_passport_residency_tracking', 'auth', N'Civil ID, passport & residency tracking', N'متابعة البطاقة المدنية وجواز السفر والإقامة', NULL),
    ('auth.automated_expiry_alerts_before_documents_lapse', 'auth', N'Automated expiry alerts before documents lapse.', N'تنبيهات تلقائية قبل انتهاء صلاحية المستندات.', NULL),
    ('auth.end_of_service_calculated_automatically', 'auth', N'End of Service, calculated automatically', N'مكافأة نهاية الخدمة تُحتسب تلقائيًا', NULL),
    ('auth.indemnity_and_final_settlement_per_kuwait_labour', 'auth', N'Indemnity and final settlement per Kuwait Labour Law.', N'مكافأة نهاية الخدمة والتسوية النهائية وفق قانون العمل الكويتي.', NULL),
    ('auth.sign_in', 'auth', N'Sign in', N'تسجيل الدخول', NULL),
    ('auth.enter_your_workspace_credentials_to_continue', 'auth', N'Enter your workspace credentials to continue.', N'أدخل بيانات الدخول للمتابعة.', NULL),
    ('auth.username_or_company_email', 'auth', N'Username or company email', N'اسم المستخدم أو البريد الإلكتروني للشركة', NULL),
    ('auth.password', 'auth', N'Password', N'كلمة المرور', NULL),
    ('auth.forgot_password', 'auth', N'Forgot password?', N'نسيت كلمة المرور؟', NULL),
    ('auth.keep_me_signed_in', 'auth', N'Keep me signed in', N'إبقائي مسجلًا للدخول', NULL),
    ('auth.two_factor_authentication_password_reset_and_pas', 'auth', N'Two-factor authentication, password reset and password change are the remaining parts of Module 1 and are not wired up yet.', N'المصادقة الثنائية واستعادة كلمة المرور وتغييرها هي الأجزاء المتبقية من الوحدة 1 ولم تُفعّل بعد.', NULL),
    ('auth.trouble_signing_in_contact_your_hr_administrator', 'auth', N'Trouble signing in? Contact your HR administrator.', N'تواجه مشكلة في تسجيل الدخول؟ تواصل مع مسؤول الموارد البشرية.', NULL),
    ('common.edit_named', 'common', N'Edit {0}', N'تعديل {0}', NULL),
    ('common.delete_named', 'common', N'Delete {0}', N'حذف {0}', NULL),
    ('common.open_named', 'common', N'Open {0}', N'فتح {0}', NULL),
    ('common.download_named', 'common', N'Download {0}', N'تنزيل {0}', NULL),
    ('common.remove_named', 'common', N'Remove {0}', N'إزالة {0}', NULL),
    ('common.upload_named', 'common', N'Upload {0}', N'رفع {0}', NULL),
    ('common.view_named', 'common', N'View {0}', N'عرض {0}', NULL),
    ('common.page_n', 'common', N'Page {0}', N'صفحة {0}', NULL),
    ('common.deactivate', 'common', N'Deactivate', N'إلغاء التفعيل', NULL),
    ('common.activate', 'common', N'Activate', N'تفعيل', NULL),
    ('common.deactivate_named', 'common', N'Deactivate {0}', N'إلغاء تفعيل {0}', NULL),
    ('common.activate_named', 'common', N'Activate {0}', N'تفعيل {0}', NULL),
    ('common.records_page_of', 'common', N'Records, page {0} of {1}', N'السجلات، صفحة {0} من {1}', NULL),
    ('common.create', 'common', N'Create', N'إنشاء', NULL),
    ('common.save_changes', 'common', N'Save changes', N'حفظ التغييرات', NULL),
    ('common.add_named', 'common', N'Add {0}', N'إضافة {0}', NULL),
    ('common.question_mark', 'common', N'?', N'؟', NULL),
    ('common.search_named', 'common', N'Search {0}', N'البحث في {0}', NULL),
    ('common.search_named_ellipsis', 'common', N'Search {0}…', N'ابحث في {0}…', NULL),
    ('common.n_records', 'common', N'{0} records', N'{0} سجل', NULL),
    ('common.one_record', 'common', N'1 record', N'سجل واحد', NULL),
    ('common.showing_range', 'common', N'Showing {0}–{1} of {2}', N'عرض {0}–{1} من {2}', NULL),
    ('org.no_matching_x', 'org', N'No matching {0}', N'لا توجد {0} مطابقة', NULL),
    ('org.no_x_yet', 'org', N'No {0} yet', N'لا توجد {0} بعد', NULL),
    ('org.empty_add_first', 'org', N'{0}. Add the first one to get started.', N'{0}. أضف أول سجل للبدء.', NULL),
    ('emp.n_employees', 'emp', N'{0} employees', N'{0} موظف', NULL),
    ('emp.one_employee', 'emp', N'1 employee', N'موظف واحد', NULL),
    ('common.male', 'common', N'Male', N'ذكر', NULL),
    ('common.female', 'common', N'Female', N'أنثى', NULL),
    ('emp.docs_sub', 'emp', N'Grouped by document section · PDF, JPG or PNG up to {0} MB · uploads save immediately', N'مجمّعة حسب قسم المستندات · PDF أو JPG أو PNG حتى {0} ميجابايت · يُحفظ الرفع فورًا', NULL),
    ('emp.docs_count_of', 'emp', N'{0} of {1} documents', N'{0} من {1} مستند', NULL),
    ('emp.docs_missing_one', 'emp', N'1 mandatory document is missing:', N'مستند إلزامي واحد ناقص:', NULL),
    ('emp.docs_missing_many', 'emp', N'{0} mandatory documents are missing:', N'{0} مستندات إلزامية ناقصة:', NULL),
    ('emp.docs_uploaded_of', 'emp', N'{0}/{1} uploaded', N'{0}/{1} مرفوع', NULL),
    ('emp.docs_or_drag_drop', 'emp', N'or drag & drop', N'أو اسحبه وأفلته هنا', NULL),
    ('emp.docs_hint', 'emp', N'PDF, JPG, PNG · max {0} MB', N'PDF أو JPG أو PNG · بحد أقصى {0} ميجابايت', NULL),
    ('common.replace_named', 'common', N'Replace {0}', N'استبدال {0}', NULL),
    ('common.list_separator', 'common', N', ', N'، ', NULL),
    ('emp.no_code_assigned', 'emp', N'No code assigned', N'لم يُحدد رمز', NULL),
    ('emp.emp_code', 'emp', N'Emp. Code {0}', N'رمز الموظف {0}', NULL),
    ('emp.save_changes', 'emp', N'Save Changes', N'حفظ التغييرات', NULL),
    ('emp.save_employee_first', 'emp', N'Save the employee first', N'احفظ الموظف أولًا', NULL),
    ('dash.total_employees', 'dash', N'Total employees', N'إجمالي الموظفين', NULL),
    ('dash.on_books_today', 'dash', N'On the books today', N'المسجلون اليوم', NULL),
    ('dash.on_books_month_end', 'dash', N'On the books at month end', N'المسجلون في نهاية الشهر', NULL),
    ('dash.active_employees', 'dash', N'Active employees', N'الموظفون النشطون', NULL),
    ('dash.active_probation', 'dash', N'Active + probation', N'نشط + فترة تجربة', NULL),
    ('dash.status_on_leave', 'dash', N'Status: On leave', N'الحالة: في إجازة', NULL),
    ('dash.new_joiners', 'dash', N'New joiners', N'المنضمون الجدد', NULL),
    ('dash.hired_this_month', 'dash', N'Hired this month', N'عُيّنوا هذا الشهر', NULL),
    ('dash.separations', 'dash', N'Separations', N'حالات انتهاء الخدمة', NULL),
    ('dash.left_this_month', 'dash', N'Left this month', N'غادروا هذا الشهر', NULL),
    ('dash.ev_birthday', 'dash', N'Birthday', N'عيد ميلاد', NULL),
    ('dash.ev_anniversary', 'dash', N'Work anniversary', N'ذكرى التعيين', NULL),
    ('dash.ev_expiry', 'dash', N'Document expiry', N'انتهاء مستند', NULL),
    ('dash.ev_probation', 'dash', N'Probation', N'فترة تجربة', NULL),
    ('common.today', 'common', N'Today', N'اليوم', NULL),
    ('common.tomorrow', 'common', N'Tomorrow', N'غدًا', NULL),
    ('common.in_n_days', 'common', N'In {0} days', N'بعد {0} أيام', NULL),
    ('dash.increase_vs_last_month', 'dash', N'increase vs last month', N'زيادة مقارنة بالشهر السابق', NULL),
    ('dash.decrease_vs_last_month', 'dash', N'decrease vs last month', N'انخفاض مقارنة بالشهر السابق', NULL),
    ('dash.company_headcount_tip', 'dash', N'{0}: {1} employees', N'{0}: {1} موظف', NULL),
    ('dash.n_employees_today', 'dash', N'{0} employees · today', N'{0} موظف · اليوم', NULL),
    ('dash.n_employees_end_of', 'dash', N'{0} employees · end of {1}', N'{0} موظف · نهاية {1}', NULL),
    ('dash.open_employees', 'dash', N'Open employees', N'فتح الموظفين', NULL),
    ('dash.employees_with_expired', 'dash', N'Employees with an <strong>expired</strong> Civil ID, passport, residency or work permit', N'موظفون لديهم بطاقة مدنية أو جواز سفر أو إقامة أو إذن عمل <strong>منتهي</strong>', NULL),
    ('dash.leave_counts_note', 'dash', N'Leave counts appear once the Leave module (under Payroll) is built. Employees marked <em>On leave</em> today: <strong>{0}</strong>.', N'تظهر أعداد الإجازات بعد تطوير وحدة الإجازات (ضمن الرواتب). الموظفون بحالة <em>في إجازة</em> اليوم: <strong>{0}</strong>', NULL),
    ('dash.utc_suffix', 'dash', N'{0} UTC', N'{0} بالتوقيت العالمي', NULL),
    ('auth.copyright', 'auth', N'© {0} HR & Payroll — Kuwait Edition', N'© {0} الموارد البشرية والرواتب — إصدار الكويت', NULL),
    ('layout.app_name', 'layout', N'HR & Payroll', N'الموارد البشرية والرواتب', NULL),
    ('layout.back', 'layout', N'Back', N'رجوع', NULL),
    ('layout.switch_language', 'layout', N'Switch language', N'تغيير اللغة', NULL),
    ('layout.company_locked', 'layout', N'Your account is limited to this company', N'حسابك مقصور على هذه الشركة', NULL),
    ('layout.filter_by_company', 'layout', N'Filter by company', N'تصفية حسب الشركة', NULL),
    ('common.month_1', 'common', N'January', N'يناير', NULL),
    ('common.month_short_1', 'common', N'Jan', N'يناير', NULL);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('common.month_2', 'common', N'February', N'فبراير', NULL),
    ('common.month_short_2', 'common', N'Feb', N'فبراير', NULL),
    ('common.month_3', 'common', N'March', N'مارس', NULL),
    ('common.month_short_3', 'common', N'Mar', N'مارس', NULL),
    ('common.month_4', 'common', N'April', N'أبريل', NULL),
    ('common.month_short_4', 'common', N'Apr', N'أبريل', NULL),
    ('common.month_5', 'common', N'May', N'مايو', NULL),
    ('common.month_short_5', 'common', N'May', N'مايو', NULL),
    ('common.month_6', 'common', N'June', N'يونيو', NULL),
    ('common.month_short_6', 'common', N'Jun', N'يونيو', NULL),
    ('common.month_7', 'common', N'July', N'يوليو', NULL),
    ('common.month_short_7', 'common', N'Jul', N'يوليو', NULL),
    ('common.month_8', 'common', N'August', N'أغسطس', NULL),
    ('common.month_short_8', 'common', N'Aug', N'أغسطس', NULL),
    ('common.month_9', 'common', N'September', N'سبتمبر', NULL),
    ('common.month_short_9', 'common', N'Sep', N'سبتمبر', NULL),
    ('common.month_10', 'common', N'October', N'أكتوبر', NULL),
    ('common.month_short_10', 'common', N'Oct', N'أكتوبر', NULL),
    ('common.month_11', 'common', N'November', N'نوفمبر', NULL),
    ('common.month_short_11', 'common', N'Nov', N'نوفمبر', NULL),
    ('common.month_12', 'common', N'December', N'ديسمبر', NULL),
    ('common.month_short_12', 'common', N'Dec', N'ديسمبر', NULL),
    ('js.dismiss', 'js', N'Dismiss', N'إغلاق', NULL),
    ('js.server_rejected', 'js', N'The server rejected the request ({0}).', N'رفض الخادم الطلب ({0}).', NULL),
    ('js.could_not_load_data', 'js', N'Could not load data ({0}).', N'تعذّر تحميل البيانات ({0}).', NULL),
    ('js.could_not_load_panel', 'js', N'Could not load the panel ({0}).', N'تعذّر تحميل اللوحة ({0}).', NULL),
    ('js.hide_password', 'js', N'Hide password', N'إخفاء كلمة المرور', NULL),
    ('js.show_password', 'js', N'Show password', N'إظهار كلمة المرور', NULL),
    ('js.enter_current_password', 'js', N'Enter your current password.', N'أدخل كلمة المرور الحالية.', NULL),
    ('js.enter_new_password', 'js', N'Enter a new password.', N'أدخل كلمة مرور جديدة.', NULL),
    ('js.max_50_chars', 'js', N'Use at most 50 characters.', N'استخدم 50 حرفًا كحد أقصى.', NULL),
    ('js.password_must_differ', 'js', N'The new password must be different from the current one.', N'يجب أن تختلف كلمة المرور الجديدة عن الحالية.', NULL),
    ('js.password_rules_not_met', 'js', N'The new password doesn''t meet the rules below.', N'كلمة المرور الجديدة لا تستوفي الشروط أدناه.', NULL),
    ('js.passwords_dont_match', 'js', N'The two new passwords don''t match.', N'كلمتا المرور الجديدتان غير متطابقتين.', NULL),
    ('js.saving', 'js', N'Saving…', N'جارٍ الحفظ…', NULL),
    ('js.signing_in', 'js', N'Signing in…', N'جارٍ تسجيل الدخول…', NULL),
    ('js.password_reset_not_built', 'js', N'Password reset is the next part of Module 1 - not built yet.', N'استعادة كلمة المرور هي الجزء التالي من الوحدة 1 - لم تُطوّر بعد.', NULL),
    ('js.chart_employees', 'js', N'employees', N'موظف', NULL),
    ('js.chart_joined', 'js', N'joined', N'انضموا', NULL),
    ('js.chart_left', 'js', N'left', N'غادروا', NULL),
    ('js.chart_gross_payroll', 'js', N'gross payroll', N'إجمالي الرواتب', NULL),
    ('js.panel_load_failed', 'js', N'This panel could not be loaded', N'تعذّر تحميل هذه اللوحة', NULL),
    ('js.try_again', 'js', N'Try again', N'إعادة المحاولة', NULL),
    ('js.actions', 'js', N'Actions', N'الإجراءات', NULL),
    ('js.exported_rows', 'js', N'Exported {0} rows from this page.', N'تم تصدير {0} صف من هذه الصفحة.', NULL),
    ('js.dependents_load_failed', 'js', N'Dependents could not be loaded', N'تعذّر تحميل المعالين', NULL),
    ('js.documents_load_failed', 'js', N'Documents could not be loaded', N'تعذّر تحميل المستندات', NULL),
    ('js.this_employee', 'js', N'this employee', N'هذا الموظف', NULL),
    ('js.nothing_to_export', 'js', N'There is nothing to export.', N'لا يوجد ما يمكن تصديره.', NULL),
    ('js.add_dependent', 'js', N'Add Dependent', N'إضافة معال', NULL),
    ('js.edit_dependent', 'js', N'Edit Dependent', N'تعديل المعال', NULL),
    ('js.this_dependent', 'js', N'this dependent', N'هذا المعال', NULL),
    ('js.docs_count_of', 'js', N'{0} of {1} documents', N'{0} من {1} مستند', NULL),
    ('js.expand_all', 'js', N'Expand all', N'توسيع الكل', NULL),
    ('js.collapse_all', 'js', N'Collapse all', N'طي الكل', NULL),
    ('js.only_pdf_jpg_png', 'js', N'Only PDF, JPG or PNG files can be uploaded.', N'يمكن رفع ملفات PDF أو JPG أو PNG فقط.', NULL),
    ('js.file_too_large', 'js', N'The file is {0} MB - the limit is {1} MB.', N'حجم الملف {0} ميجابايت - الحد الأقصى {1} ميجابايت.', NULL),
    ('js.file_empty', 'js', N'This file is empty.', N'هذا الملف فارغ.', NULL),
    ('js.document', 'js', N'Document', N'المستند', NULL),
    ('js.doc_uploaded', 'js', N'{0} uploaded.', N'تم رفع {0}.', NULL),
    ('js.this_document', 'js', N'this document', N'هذا المستند', NULL),
    ('js.enter_field_before_continuing', 'js', N'Enter {0} before continuing.', N'أدخل {0} قبل المتابعة.', NULL),
    ('js.create_employee_continue', 'js', N'Create Employee & Continue', N'إنشاء الموظف والمتابعة', NULL),
    ('js.next', 'js', N'Next', N'التالي', NULL),
    ('js.employee_saved', 'js', N'Employee saved.', N'تم حفظ الموظف.', NULL),
    ('js.add_named', 'js', N'Add {0}', N'إضافة {0}', NULL),
    ('js.select_placeholder', 'js', N'— Select —', N'— اختر —', NULL),
    ('js.dependent_list_refresh_failed', 'js', N'Could not refresh the dependent list.', N'تعذّر تحديث القائمة التابعة.', NULL),
    ('js.code_in_use', 'js', N'That code is already in use.', N'هذا الرمز مستخدم بالفعل.', NULL),
    ('js.this_record', 'js', N'this record', N'هذا السجل', NULL),
    ('js.nothing_to_export_tab', 'js', N'There is nothing to export on this tab.', N'لا يوجد ما يمكن تصديره في هذا التبويب.', NULL),
    ('common.code', 'common', N'Code', N'الرمز', NULL),
    ('common.location', 'common', N'Location', N'الموقع', NULL),
    ('org.companies', 'org', N'Companies', N'الشركات', NULL),
    ('org.group_companies_and_legal_entities', 'org', N'Group companies and legal entities', N'شركات المجموعة والكيانات القانونية', NULL),
    ('org.offices_showrooms_and_satellite_sites', 'org', N'Offices, showrooms and satellite sites', N'المكاتب والمعارض والمواقع الفرعية', NULL),
    ('org.functional_divisions_and_their_reporting_lines', 'org', N'Functional divisions and their reporting lines', N'الإدارات الوظيفية وخطوط تبعيتها', NULL),
    ('org.teams_within_each_department', 'org', N'Teams within each department', N'الفرق داخل كل إدارة', NULL),
    ('org.designations', 'org', N'Designations', N'المسميات الوظيفية', NULL),
    ('org.job_titles_as_printed_on_civil_ids_and_work_perm', 'org', N'Job titles as printed on Civil IDs and work permits', N'المسميات الوظيفية كما تظهر في البطاقات المدنية وأذونات العمل', NULL),
    ('org.job_positions', 'org', N'Job Positions', N'الوظائف', NULL),
    ('org.job_position', 'org', N'Job position', N'وظيفة', NULL),
    ('org.seats_in_the_organisation_chart', 'org', N'Seats in the organisation chart', N'المناصب في الهيكل التنظيمي', NULL),
    ('org.locations', 'org', N'Locations', N'المواقع', NULL),
    ('org.physical_work_sites_for_attendance_and_cost_trac', 'org', N'Physical work sites for attendance and cost tracking', N'مواقع العمل الفعلية لمتابعة الحضور والتكاليف', NULL),
    ('org.cost_centers', 'org', N'Cost Centers', N'مراكز التكلفة', NULL),
    ('org.cost_center', 'org', N'Cost center', N'مركز تكلفة', NULL),
    ('org.financial_roll_up_used_by_payroll_reporting', 'org', N'Financial roll-up used by payroll reporting', N'التجميع المالي المستخدم في تقارير الرواتب', NULL),
    ('org.organization_setup', 'org', N'Organization Setup', N'إعداد المؤسسة', NULL),
    ('emp.personal_info_employment_and_kuwait_compliance_i', 'emp', N'Personal info, employment and Kuwait compliance in one profile per employee', N'البيانات الشخصية والتوظيف والامتثال الكويتي في ملف واحد لكل موظف', NULL),
    ('emp.on_leave', 'emp', N'On Leave', N'في إجازة', NULL),
    ('emp.suspended', 'emp', N'Suspended', N'موقوف', NULL),
    ('emp.terminated', 'emp', N'Terminated', N'منتهية خدمته', NULL),
    ('emp.resigned', 'emp', N'Resigned', N'مستقيل', NULL),
    ('emp.spouse', 'emp', N'Spouse', N'زوج/زوجة', NULL),
    ('emp.son', 'emp', N'Son', N'ابن', NULL),
    ('emp.daughter', 'emp', N'Daughter', N'ابنة', NULL),
    ('emp.father', 'emp', N'Father', N'الأب', NULL),
    ('emp.mother', 'emp', N'Mother', N'الأم', NULL),
    ('emp.other_documents', 'emp', N'Other Documents', N'مستندات أخرى', NULL),
    ('emp.new_employee', 'emp', N'New Employee', N'موظف جديد', NULL),
    ('emp.employee_profile', 'emp', N'Employee Profile', N'ملف الموظف', NULL),
    ('emp.back_to_employees', 'emp', N'Back to Employees', N'العودة إلى الموظفين', NULL),
    ('emp.single', 'emp', N'Single', N'أعزب', NULL),
    ('emp.married', 'emp', N'Married', N'متزوج', NULL),
    ('emp.divorced', 'emp', N'Divorced', N'مطلق', NULL),
    ('emp.widowed', 'emp', N'Widowed', N'أرمل', NULL),
    ('emp.full_time', 'emp', N'Full-Time', N'دوام كامل', NULL),
    ('emp.part_time', 'emp', N'Part-Time', N'دوام جزئي', NULL),
    ('emp.temporary', 'emp', N'Temporary', N'مؤقت', NULL),
    ('emp.contract', 'emp', N'Contract', N'عقد', NULL),
    ('emp.onleave', 'emp', N'OnLeave', N'في إجازة', NULL),
    ('emp.company_sponsor', 'emp', N'Company Sponsor', N'كفالة الشركة', NULL),
    ('emp.family_sponsor', 'emp', N'Family Sponsor', N'كفالة عائلية', NULL),
    ('emp.self_sponsor', 'emp', N'Self Sponsor', N'كفالة ذاتية', NULL),
    ('emp.government_sponsor', 'emp', N'Government Sponsor', N'كفالة حكومية', NULL),
    ('emp.valid', 'emp', N'Valid', N'سارية', NULL),
    ('emp.under_process', 'emp', N'Under Process', N'قيد الإجراء', NULL),
    ('emp.expired', 'emp', N'Expired', N'منتهية', NULL),
    ('emp.cancelled', 'emp', N'Cancelled', N'ملغاة', NULL),
    ('dash.completed', 'dash', N'Completed', N'مكتمل', NULL),
    ('auth.access_denied', 'auth', N'Access denied', N'تم رفض الوصول', NULL),
    ('msg.branch_code_is_required', 'msg', N'Branch code is required.', N'رمز الفرع مطلوب.', NULL),
    ('msg.branch_name_is_required', 'msg', N'Branch name is required.', N'اسم الفرع مطلوب.', NULL),
    ('msg.choose_a_file_to_upload', 'msg', N'Choose a file to upload.', N'اختر ملفًا لرفعه.', NULL),
    ('msg.civil_id_is_numeric_up_to_12_digits', 'msg', N'Civil ID is numeric, up to 12 digits.', N'الرقم المدني رقمي، بحد أقصى 12 خانة.', NULL),
    ('msg.company_code_cannot_exceed_30_characters', 'msg', N'Company code cannot exceed 30 characters.', N'لا يمكن أن يتجاوز رمز الشركة 30 حرفًا.', NULL),
    ('msg.company_code_is_required', 'msg', N'Company code is required.', N'رمز الشركة مطلوب.', NULL),
    ('msg.company_is_required', 'msg', N'Company is required.', N'الشركة مطلوبة.', NULL),
    ('msg.company_name_is_required', 'msg', N'Company name is required.', N'اسم الشركة مطلوب.', NULL),
    ('msg.cost_center_code_is_required', 'msg', N'Cost center code is required.', N'رمز مركز التكلفة مطلوب.', NULL),
    ('msg.cost_center_name_is_required', 'msg', N'Cost center name is required.', N'اسم مركز التكلفة مطلوب.', NULL),
    ('msg.department_code_is_required', 'msg', N'Department code is required.', N'رمز الإدارة مطلوب.', NULL),
    ('msg.department_is_required', 'msg', N'Department is required.', N'الإدارة مطلوبة.', NULL),
    ('msg.department_name_is_required', 'msg', N'Department name is required.', N'اسم الإدارة مطلوب.', NULL),
    ('msg.designation_code_is_required', 'msg', N'Designation code is required.', N'رمز المسمى الوظيفي مطلوب.', NULL),
    ('msg.designation_name_is_required', 'msg', N'Designation name is required.', N'المسمى الوظيفي مطلوب.', NULL),
    ('msg.emergency_contact_name', 'msg', N'Emergency Contact Name', N'اسم جهة الاتصال في الطوارئ', NULL),
    ('msg.emergency_contact_phone', 'msg', N'Emergency Contact Phone', N'هاتف جهة الاتصال في الطوارئ', NULL),
    ('msg.employee_no_is_required', 'msg', N'Employee No is required.', N'الرقم الوظيفي مطلوب.', NULL),
    ('msg.enter_a_basic_salary_of_0_or_more', 'msg', N'Enter a basic salary of 0 or more.', N'أدخل راتبًا أساسيًا قيمته 0 أو أكثر.', NULL),
    ('msg.enter_a_notice_period_between_0_and_365_days', 'msg', N'Enter a notice period between 0 and 365 days.', N'أدخل فترة إنذار بين 0 و 365 يومًا.', NULL),
    ('msg.enter_a_valid_email_address', 'msg', N'Enter a valid email address.', N'أدخل بريدًا إلكترونيًا صحيحًا.', NULL),
    ('msg.enter_allowances_of_0_or_more', 'msg', N'Enter allowances of 0 or more.', N'أدخل بدلات قيمتها 0 أو أكثر.', NULL),
    ('msg.enter_your_password', 'msg', N'Enter your password.', N'أدخل كلمة المرور.', NULL),
    ('msg.enter_your_username_or_company_email', 'msg', N'Enter your username or company email.', N'أدخل اسم المستخدم أو البريد الإلكتروني للشركة.', NULL),
    ('msg.father_deceased', 'msg', N'Father Deceased', N'الأب متوفى', NULL),
    ('msg.first_name_is_required', 'msg', N'First name is required.', N'الاسم الأول مطلوب.', NULL),
    ('msg.full_name_is_required', 'msg', N'Full name is required.', N'الاسم الكامل مطلوب.', NULL),
    ('msg.health_certificate_expiry', 'msg', N'Health Certificate Expiry', N'تاريخ انتهاء الشهادة الصحية', NULL);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('msg.iban_account_number_can_contain_letters_digits_a', 'msg', N'IBAN / account number can contain letters, digits and spaces only.', N'يمكن أن يحتوي الآيبان / رقم الحساب على أحرف وأرقام ومسافات فقط.', NULL),
    ('msg.latitude_must_be_between_90_and_90', 'msg', N'Latitude must be between -90 and 90.', N'يجب أن يكون خط العرض بين -90 و 90.', NULL),
    ('msg.location_type', 'msg', N'Location Type', N'نوع الموقع', NULL),
    ('msg.location_code_is_required', 'msg', N'Location code is required.', N'رمز الموقع مطلوب.', NULL),
    ('msg.location_name_is_required', 'msg', N'Location name is required.', N'اسم الموقع مطلوب.', NULL),
    ('msg.logo', 'msg', N'Logo', N'الشعار', NULL),
    ('msg.longitude_must_be_between_180_and_180', 'msg', N'Longitude must be between -180 and 180.', N'يجب أن يكون خط الطول بين -180 و 180.', NULL),
    ('msg.manager', 'msg', N'Manager', N'المدير', NULL),
    ('msg.parent_cost_center', 'msg', N'Parent Cost Center', N'مركز التكلفة الأعلى', NULL),
    ('msg.parent_department', 'msg', N'Parent Department', N'الإدارة الأعلى', NULL),
    ('msg.passport_issuing_country', 'msg', N'Passport Issuing Country', N'بلد إصدار جواز السفر', NULL),
    ('msg.password_changed_you_stay_signed_in_here_other_s', 'msg', N'Password changed. You stay signed in here; other sessions have been signed out.', N'تم تغيير كلمة المرور. ستبقى مسجلًا هنا، وتم تسجيل خروج الجلسات الأخرى.', NULL),
    ('msg.position_code_is_required', 'msg', N'Position code is required.', N'رمز الوظيفة مطلوب.', NULL),
    ('msg.position_name_is_required', 'msg', N'Position name is required.', N'اسم الوظيفة مطلوب.', NULL),
    ('msg.re_enter_the_new_password', 'msg', N'Re-enter the new password.', N'أعد إدخال كلمة المرور الجديدة.', NULL),
    ('msg.save_the_employee_first_then_add_dependents', 'msg', N'Save the employee first, then add dependents.', N'احفظ الموظف أولًا، ثم أضف المعالين.', NULL),
    ('msg.save_the_employee_first_then_upload_documents', 'msg', N'Save the employee first, then upload documents.', N'احفظ الموظف أولًا، ثم ارفع المستندات.', NULL),
    ('msg.saved_successfully', 'msg', N'Saved successfully.', N'تم الحفظ بنجاح.', NULL),
    ('msg.section_code_is_required', 'msg', N'Section code is required.', N'رمز القسم مطلوب.', NULL),
    ('msg.section_name_is_required', 'msg', N'Section name is required.', N'اسم القسم مطلوب.', NULL),
    ('msg.select_a_company', 'msg', N'Select a company.', N'اختر شركة.', NULL),
    ('msg.select_a_department', 'msg', N'Select a department.', N'اختر إدارة.', NULL),
    ('msg.select_a_gender', 'msg', N'Select a gender.', N'اختر الجنس.', NULL),
    ('msg.select_a_relationship', 'msg', N'Select a relationship.', N'اختر صلة القرابة.', NULL),
    ('msg.that_account_is_not_active_contact_your_hr_admin', 'msg', N'That account is not active. Contact your HR administrator.', N'هذا الحساب غير نشط. تواصل مع مسؤول الموارد البشرية.', NULL),
    ('msg.that_is_longer_than_any_valid_username', 'msg', N'That is longer than any valid username.', N'هذا أطول من أي اسم مستخدم صحيح.', NULL),
    ('msg.that_password_is_too_long', 'msg', N'That password is too long.', N'كلمة المرور طويلة جدًا.', NULL),
    ('msg.the_operation_could_not_be_completed', 'msg', N'The operation could not be completed.', N'تعذّر إكمال العملية.', NULL),
    ('msg.the_username_or_password_is_incorrect', 'msg', N'The username or password is incorrect.', N'اسم المستخدم أو كلمة المرور غير صحيحة.', NULL),
    ('msg.this_account_is_locked_after_too_many_failed_att', 'msg', N'This account is locked after too many failed attempts. Try again in 1 minute.', N'تم قفل هذا الحساب بسبب كثرة المحاولات الفاشلة. حاول مرة أخرى بعد دقيقة واحدة.', NULL),
    ('msg.use_at_least_8_characters', 'msg', N'Use at least 8 characters.', N'استخدم 8 أحرف على الأقل.', NULL),
    ('msg.use_at_most_128_characters', 'msg', N'Use at most 128 characters.', N'استخدم 128 حرفًا كحد أقصى.', NULL),
    ('msg.use_letters_numbers_hyphen_or_underscore_only', 'msg', N'Use letters, numbers, hyphen or underscore only.', N'استخدم الأحرف والأرقام والشرطة أو الشرطة السفلية فقط.', NULL),
    ('msg.use_upper_and_lower_case_letters_and_at_least_on', 'msg', N'Use upper- and lower-case letters and at least one number.', N'استخدم أحرفًا كبيرة وصغيرة ورقمًا واحدًا على الأقل.', NULL),
    ('msg.you_have_been_signed_out', 'msg', N'You have been signed out.', N'تم تسجيل خروجك.', NULL),
    ('msg.your_session_expired_please_sign_in_again', 'msg', N'Your session expired. Please sign in again.', N'انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.', NULL),
    ('msg.your_session_has_ended_sign_in_again_then_change', 'msg', N'Your session has ended. Sign in again, then change your password.', N'انتهت جلستك. سجّل الدخول مرة أخرى ثم غيّر كلمة المرور.', NULL),
    ('msg.a_swift_bic_code_is_8_or_11_letters_and_digits', 'msg', N'A SWIFT / BIC code is 8 or 11 letters and digits.', N'رمز السويفت / BIC يتكون من 8 أو 11 حرفًا ورقمًا.', NULL),
    ('msg.a_company_bank_account_uses_this_bank_so_it_cann', 'msg', N'A company bank account uses this bank, so it cannot be deleted. Deactivate it instead.', N'يستخدم أحد حسابات الشركة البنكية هذا البنك، لذا لا يمكن حذفه. ألغِ تفعيله بدلًا من ذلك.', NULL),
    ('msg.a_component_can_appear_only_once_in_a_structure', 'msg', N'A component can appear only once in a structure.', N'لا يمكن أن يظهر العنصر إلا مرة واحدة في الهيكل.', NULL),
    ('msg.a_cost_center_cannot_roll_up_to_itself', 'msg', N'A cost center cannot roll up to itself.', N'لا يمكن أن يتبع مركز التكلفة نفسه.', NULL),
    ('msg.a_department_cannot_report_to_itself', 'msg', N'A department cannot report to itself.', N'لا يمكن أن تتبع الإدارة نفسها.', NULL),
    ('msg.a_later_period_of_this_calendar_has_already_been', 'msg', N'A later period of this calendar has already been processed, so this one cannot be deleted.', N'تمت معالجة فترة لاحقة من هذا التقويم، لذا لا يمكن حذف هذه الفترة.', NULL),
    ('msg.a_monthly_calendar_needs_a_cut_off_day_and_a_pay', 'msg', N'A monthly calendar needs a cut-off day and a payment day between 1 and 31.', N'يتطلب التقويم الشهري يوم إقفال ويوم دفع بين 1 و 31.', NULL),
    ('msg.a_salary_structure_must_include_basic_salary', 'msg', N'A salary structure must include Basic Salary.', N'يجب أن يتضمن هيكل الراتب الراتب الأساسي.', NULL),
    ('msg.a_weekly_bi_weekly_calendar_needs_cut_off_and_pa', 'msg', N'A weekly / bi-weekly calendar needs cut-off and payment offsets (days from period end).', N'يتطلب التقويم الأسبوعي / نصف الشهري فارقي الإقفال والدفع (بالأيام من نهاية الفترة).', NULL),
    ('msg.add_at_least_one_service_slab', 'msg', N'Add at least one service slab.', N'أضف شريحة خدمة واحدة على الأقل.', NULL),
    ('msg.add_at_least_the_basic_salary_line_to_the_struct', 'msg', N'Add at least the Basic Salary line to the structure.', N'أضف بند الراتب الأساسي على الأقل إلى الهيكل.', NULL),
    ('msg.an_active_rate_for_this_overtime_type_already_co', 'msg', N'An active rate for this overtime type already covers overlapping dates. End-date it first.', N'يوجد معدل نشط لهذا النوع من العمل الإضافي يغطي تواريخ متداخلة. حدد تاريخ انتهائه أولًا.', NULL),
    ('msg.an_earlier_period_of_this_calendar_is_not_posted', 'msg', N'An earlier period of this calendar is not posted yet. Payroll periods must be processed in order.', N'لم تُرحّل فترة سابقة من هذا التقويم بعد. يجب معالجة فترات الرواتب بالترتيب.', NULL),
    ('msg.an_employee_cannot_report_to_themselves', 'msg', N'An employee cannot report to themselves.', N'لا يمكن أن يكون الموظف مديرًا لنفسه.', NULL),
    ('msg.an_employee_must_be_specified', 'msg', N'An employee must be specified.', N'يجب تحديد موظف.', NULL),
    ('msg.an_inactive_component_cannot_be_added_to_a_struc', 'msg', N'An inactive component cannot be added to a structure.', N'لا يمكن إضافة عنصر غير نشط إلى الهيكل.', NULL),
    ('msg.another_active_indemnity_rule_set_is_in_force_fo', 'msg', N'Another active indemnity rule set is in force for overlapping dates. End-date it first.', N'توجد مجموعة قواعد مكافأة نهاية خدمة نشطة لتواريخ متداخلة. حدد تاريخ انتهائها أولًا.', NULL),
    ('msg.another_active_rate_for_this_contribution_and_na', 'msg', N'Another active rate for this contribution and nationality group overlaps these dates. End-date the existing rate first.', N'يوجد معدل نشط آخر لهذا الاشتراك وفئة الجنسية يتداخل مع هذه التواريخ. حدد تاريخ انتهاء المعدل الحالي أولًا.', NULL),
    ('msg.another_active_rate_overlaps_these_dates_so_this', 'msg', N'Another active rate overlaps these dates, so this one cannot be re-activated.', N'يتداخل معدل نشط آخر مع هذه التواريخ، لذا لا يمكن إعادة تفعيل هذا المعدل.', NULL),
    ('msg.another_active_rule_set_overlaps_these_dates_so', 'msg', N'Another active rule set overlaps these dates, so this one cannot be re-activated.', N'تتداخل مجموعة قواعد نشطة أخرى مع هذه التواريخ، لذا لا يمكن إعادة تفعيل هذه المجموعة.', NULL),
    ('msg.another_active_structure_already_covers_this_des', 'msg', N'Another active structure already covers this designation / job position / grade for overlapping dates. End-date it first.', N'يوجد هيكل نشط آخر يغطي هذا المسمى الوظيفي / الوظيفة / الدرجة لتواريخ متداخلة. حدد تاريخ انتهائه أولًا.', NULL),
    ('msg.another_active_structure_covers_the_same_designa', 'msg', N'Another active structure covers the same designation / job position / grade for overlapping dates.', N'يوجد هيكل نشط آخر يغطي نفس المسمى الوظيفي / الوظيفة / الدرجة لتواريخ متداخلة.', NULL),
    ('msg.bank_code_and_name_are_required', 'msg', N'Bank code and name are required.', N'رمز البنك واسمه مطلوبان.', NULL),
    ('msg.bank_created_successfully', 'msg', N'Bank created successfully.', N'تم إنشاء البنك بنجاح.', NULL),
    ('msg.bank_deleted_successfully', 'msg', N'Bank deleted successfully.', N'تم حذف البنك بنجاح.', NULL),
    ('msg.bank_updated_successfully', 'msg', N'Bank updated successfully.', N'تم تحديث البنك بنجاح.', NULL),
    ('msg.basic_salary_is_required_by_the_payroll_engine_a', 'msg', N'Basic Salary is required by the payroll engine and cannot be deactivated.', N'الراتب الأساسي مطلوب لمحرك الرواتب ولا يمكن إلغاء تفعيله.', NULL),
    ('msg.branch_created_successfully', 'msg', N'Branch created successfully.', N'تم إنشاء الفرع بنجاح.', NULL),
    ('msg.branch_deleted_successfully', 'msg', N'Branch deleted successfully.', N'تم حذف الفرع بنجاح.', NULL),
    ('msg.branch_updated_successfully', 'msg', N'Branch updated successfully.', N'تم تحديث الفرع بنجاح.', NULL),
    ('msg.check_the_daily_wage_divisor_1_31_the_cap_and_th', 'msg', N'Check the daily-wage divisor (1 - 31), the cap and the effective dates.', N'تحقق من مقسوم الأجر اليومي (1 - 31) والحد الأقصى وتواريخ السريان.', NULL),
    ('msg.check_the_multiplier_hours_divisor_and_effective', 'msg', N'Check the multiplier, hours, divisor and effective dates.', N'تحقق من المعامل والساعات والمقسوم وتواريخ السريان.', NULL),
    ('msg.check_the_rates_0_100_the_salary_floor_ceiling_a', 'msg', N'Check the rates (0 - 100 %), the salary floor / ceiling and the effective dates.', N'تحقق من النسب (0 - 100 %) والحد الأدنى / الأعلى للراتب وتواريخ السريان.', NULL),
    ('msg.choose_fixed_or_variable', 'msg', N'Choose Fixed or Variable.', N'اختر ثابت أو متغير.', NULL),
    ('msg.choose_a_calculation_method_amount_percentage_da', 'msg', N'Choose a calculation method: Amount, Percentage, Days, Hours or Formula.', N'اختر طريقة الاحتساب: مبلغ، نسبة، أيام، ساعات أو معادلة.', NULL),
    ('msg.choose_whether_this_is_an_earning_or_a_deduction', 'msg', N'Choose whether this is an Earning or a Deduction.', N'اختر ما إذا كان هذا استحقاقًا أم استقطاعًا.', NULL),
    ('msg.code_name_and_effective_from_date_are_required', 'msg', N'Code, name and effective-from date are required.', N'الرمز والاسم وتاريخ بدء السريان مطلوبة.', NULL),
    ('msg.code_name_employee_rate_employer_rate_and_effect', 'msg', N'Code, name, employee rate, employer rate and effective-from date are required.', N'الرمز والاسم ونسبة الموظف ونسبة صاحب العمل وتاريخ بدء السريان مطلوبة.', NULL),
    ('msg.company_bank_account_created_successfully', 'msg', N'Company bank account created successfully.', N'تم إنشاء الحساب البنكي للشركة بنجاح.', NULL),
    ('msg.company_bank_account_deleted_successfully', 'msg', N'Company bank account deleted successfully.', N'تم حذف الحساب البنكي للشركة بنجاح.', NULL),
    ('msg.company_bank_account_updated_successfully', 'msg', N'Company bank account updated successfully.', N'تم تحديث الحساب البنكي للشركة بنجاح.', NULL),
    ('msg.company_created_successfully', 'msg', N'Company created successfully.', N'تم إنشاء الشركة بنجاح.', NULL),
    ('msg.company_deleted_successfully', 'msg', N'Company deleted successfully.', N'تم حذف الشركة بنجاح.', NULL),
    ('msg.company_updated_successfully', 'msg', N'Company updated successfully.', N'تم تحديث الشركة بنجاح.', NULL),
    ('msg.company_bank_account_code_and_account_title_are', 'msg', N'Company, bank, account code and account title are required.', N'الشركة والبنك ورمز الحساب واسم الحساب مطلوبة.', NULL),
    ('msg.company_code_and_name_are_required', 'msg', N'Company, code and name are required.', N'الشركة والرمز والاسم مطلوبة.', NULL),
    ('msg.company_code_name_and_effective_from_date_are_re', 'msg', N'Company, code, name and effective-from date are required.', N'الشركة والرمز والاسم وتاريخ بدء السريان مطلوبة.', NULL),
    ('msg.company_code_name_and_first_period_start_date_ar', 'msg', N'Company, code, name and first period start date are required.', N'الشركة والرمز والاسم وتاريخ بداية الفترة الأولى مطلوبة.', NULL),
    ('msg.component_deleted_successfully', 'msg', N'Component deleted successfully.', N'تم حذف العنصر بنجاح.', NULL),
    ('msg.component_updated_successfully', 'msg', N'Component updated successfully.', N'تم تحديث العنصر بنجاح.', NULL),
    ('msg.cost_center_created_successfully', 'msg', N'Cost center created successfully.', N'تم إنشاء مركز التكلفة بنجاح.', NULL),
    ('msg.cost_center_deleted_successfully', 'msg', N'Cost center deleted successfully.', N'تم حذف مركز التكلفة بنجاح.', NULL),
    ('msg.cost_center_updated_successfully', 'msg', N'Cost center updated successfully.', N'تم تحديث مركز التكلفة بنجاح.', NULL),
    ('msg.department_created_successfully', 'msg', N'Department created successfully.', N'تم إنشاء الإدارة بنجاح.', NULL),
    ('msg.department_deleted_successfully', 'msg', N'Department deleted successfully.', N'تم حذف الإدارة بنجاح.', NULL),
    ('msg.department_updated_successfully', 'msg', N'Department updated successfully.', N'تم تحديث الإدارة بنجاح.', NULL),
    ('msg.dependent_added_successfully', 'msg', N'Dependent added successfully.', N'تمت إضافة المعال بنجاح.', NULL),
    ('msg.dependent_removed_successfully', 'msg', N'Dependent removed successfully.', N'تمت إزالة المعال بنجاح.', NULL),
    ('msg.dependent_updated_successfully', 'msg', N'Dependent updated successfully.', N'تم تحديث المعال بنجاح.', NULL),
    ('msg.designation_created_successfully', 'msg', N'Designation created successfully.', N'تم إنشاء المسمى الوظيفي بنجاح.', NULL),
    ('msg.designation_deleted_successfully', 'msg', N'Designation deleted successfully.', N'تم حذف المسمى الوظيفي بنجاح.', NULL),
    ('msg.designation_updated_successfully', 'msg', N'Designation updated successfully.', N'تم تحديث المسمى الوظيفي بنجاح.', NULL),
    ('msg.designation_job_position_grade_and_payroll_calen', 'msg', N'Designation, job position, grade and payroll calendar must all belong to the selected company.', N'يجب أن تتبع المسميات الوظيفية والوظيفة والدرجة وتقويم الرواتب جميعها الشركة المحددة.', NULL),
    ('msg.document_removed', 'msg', N'Document removed.', N'تمت إزالة المستند.', NULL),
    ('msg.document_uploaded', 'msg', N'Document uploaded.', N'تم رفع المستند.', NULL),
    ('msg.effective_to_date_cannot_be_before_the_effective', 'msg', N'Effective-to date cannot be before the effective-from date.', N'لا يمكن أن يكون تاريخ انتهاء السريان قبل تاريخ بدايته.', NULL),
    ('msg.employee_created_successfully', 'msg', N'Employee created successfully.', N'تم إنشاء الموظف بنجاح.', NULL),
    ('msg.employee_deleted_successfully', 'msg', N'Employee deleted successfully.', N'تم حذف الموظف بنجاح.', NULL),
    ('msg.employee_updated_successfully', 'msg', N'Employee updated successfully.', N'تم تحديث الموظف بنجاح.', NULL),
    ('msg.end_date_must_be_on_or_after_the_start_date_and', 'msg', N'End date must be on or after the start date, and cut-off and payment dates are required.', N'يجب أن يكون تاريخ النهاية في تاريخ البداية أو بعده، وتاريخا الإقفال والدفع مطلوبان.', NULL),
    ('msg.enter_the_iban_or_the_account_number', 'msg', N'Enter the IBAN or the account number.', N'أدخل الآيبان أو رقم الحساب.', NULL),
    ('msg.enter_the_default_percentage', 'msg', N'Enter the default percentage.', N'أدخل النسبة الافتراضية.', NULL),
    ('msg.enter_the_formula', 'msg', N'Enter the formula.', N'أدخل المعادلة.', NULL),
    ('msg.enter_the_year_to_generate_2000_2100', 'msg', N'Enter the year to generate (2000 - 2100).', N'أدخل السنة المراد إنشاؤها (2000 - 2100).', NULL),
    ('msg.entitlement_factors_need_a_valid_separation_type', 'msg', N'Entitlement factors need a valid separation type, non-overlapping year ranges and a percentage between 0 and 100.', N'تتطلب عوامل الاستحقاق نوع انتهاء خدمة صحيحًا ونطاقات سنوات غير متداخلة ونسبة بين 0 و 100.', NULL),
    ('msg.every_component_must_belong_to_the_selected_comp', 'msg', N'Every component must belong to the selected company.', N'يجب أن يتبع كل عنصر الشركة المحددة.', NULL),
    ('msg.for_a_monthly_calendar_the_period_start_day_must', 'msg', N'For a monthly calendar the period start day must be between 1 and 28 so every month has it.', N'في التقويم الشهري يجب أن يكون يوم بداية الفترة بين 1 و 28 ليوجد في كل شهر.', NULL),
    ('msg.indemnity_rule_set_created_successfully', 'msg', N'Indemnity rule set created successfully.', N'تم إنشاء مجموعة قواعد مكافأة نهاية الخدمة بنجاح.', NULL),
    ('msg.indemnity_rule_set_deleted_successfully', 'msg', N'Indemnity rule set deleted successfully.', N'تم حذف مجموعة قواعد مكافأة نهاية الخدمة بنجاح.', NULL),
    ('msg.indemnity_rule_set_updated_successfully', 'msg', N'Indemnity rule set updated successfully.', N'تم تحديث مجموعة قواعد مكافأة نهاية الخدمة بنجاح.', NULL),
    ('msg.job_position_created_successfully', 'msg', N'Job position created successfully.', N'تم إنشاء الوظيفة بنجاح.', NULL),
    ('msg.job_position_deleted_successfully', 'msg', N'Job position deleted successfully.', N'تم حذف الوظيفة بنجاح.', NULL),
    ('msg.job_position_updated_successfully', 'msg', N'Job position updated successfully.', N'تم تحديث الوظيفة بنجاح.', NULL),
    ('msg.location_created_successfully', 'msg', N'Location created successfully.', N'تم إنشاء الموقع بنجاح.', NULL),
    ('msg.location_deleted_successfully', 'msg', N'Location deleted successfully.', N'تم حذف الموقع بنجاح.', NULL),
    ('msg.location_updated_successfully', 'msg', N'Location updated successfully.', N'تم تحديث الموقع بنجاح.', NULL),
    ('msg.maximum_amount_cannot_be_less_than_the_minimum_a', 'msg', N'Maximum amount cannot be less than the minimum amount.', N'لا يمكن أن يكون الحد الأقصى أقل من الحد الأدنى.', NULL),
    ('msg.no_salary_structure_matches_this_designation_job', 'msg', N'No salary structure matches this designation / job position / grade.', N'لا يوجد هيكل راتب مطابق لهذا المسمى الوظيفي / الوظيفة / الدرجة.', NULL),
    ('msg.one_of_the_lines_has_an_invalid_method_amount_or', 'msg', N'One of the lines has an invalid method, amount or percentage.', N'يحتوي أحد البنود على طريقة أو مبلغ أو نسبة غير صحيحة.', NULL),
    ('msg.only_an_open_period_can_be_deleted', 'msg', N'Only an OPEN period can be deleted.', N'يمكن حذف الفترة المفتوحة (OPEN) فقط.', NULL),
    ('msg.only_an_open_period_can_be_edited', 'msg', N'Only an OPEN period can be edited.', N'يمكن تعديل الفترة المفتوحة (OPEN) فقط.', NULL),
    ('msg.overtime_rate_created_successfully', 'msg', N'Overtime rate created successfully.', N'تم إنشاء معدل العمل الإضافي بنجاح.', NULL),
    ('msg.overtime_rate_deleted_successfully', 'msg', N'Overtime rate deleted successfully.', N'تم حذف معدل العمل الإضافي بنجاح.', NULL),
    ('msg.overtime_rate_updated_successfully', 'msg', N'Overtime rate updated successfully.', N'تم تحديث معدل العمل الإضافي بنجاح.', NULL),
    ('msg.overtime_type_name_multiplier_and_effective_from', 'msg', N'Overtime type, name, multiplier and effective-from date are required.', N'نوع العمل الإضافي والاسم والمعامل وتاريخ بدء السريان مطلوبة.', NULL),
    ('msg.payroll_calendar_created_successfully_use_genera', 'msg', N'Payroll calendar created successfully. Use "Generate periods" to create its pay periods.', N'تم إنشاء تقويم الرواتب بنجاح. استخدم "إنشاء الفترات" لإنشاء فترات الدفع.', NULL),
    ('msg.payroll_calendar_deleted_successfully', 'msg', N'Payroll calendar deleted successfully.', N'تم حذف تقويم الرواتب بنجاح.', NULL),
    ('msg.payroll_calendar_updated_successfully_existing_o', 'msg', N'Payroll calendar updated successfully. Existing OPEN periods keep their dates; edit them on the Periods list if needed.', N'تم تحديث تقويم الرواتب بنجاح. تحتفظ الفترات المفتوحة الحالية بتواريخها؛ عدّلها من قائمة الفترات عند الحاجة.', NULL),
    ('msg.payroll_frequency_must_be_monthly_bi_weekly_or_w', 'msg', N'Payroll frequency must be Monthly, Bi-weekly or Weekly.', N'يجب أن يكون تكرار الرواتب شهريًا أو نصف شهري أو أسبوعيًا.', NULL),
    ('msg.payroll_has_already_been_processed_on_this_calen', 'msg', N'Payroll has already been processed on this calendar, so its company, frequency and start date can no longer change. Create a new calendar instead.', N'تمت معالجة رواتب على هذا التقويم، لذا لا يمكن تغيير الشركة أو التكرار أو تاريخ البداية. أنشئ تقويمًا جديدًا بدلًا من ذلك.', NULL),
    ('msg.percentage_days_and_hours_methods_need_a_calcula', 'msg', N'Percentage, Days and Hours methods need a calculation base (Basic, Fixed gross, Overtime base or Indemnity base).', N'تتطلب طرق النسبة والأيام والساعات أساس احتساب (الأساسي، الإجمالي الثابت، أساس العمل الإضافي أو أساس مكافأة نهاية الخدمة).', NULL),
    ('msg.period_deleted_successfully', 'msg', N'Period deleted successfully.', N'تم حذف الفترة بنجاح.', NULL),
    ('msg.period_updated_successfully', 'msg', N'Period updated successfully.', N'تم تحديث الفترة بنجاح.', NULL),
    ('msg.salary_structure_created_successfully', 'msg', N'Salary structure created successfully.', N'تم إنشاء هيكل الراتب بنجاح.', NULL),
    ('msg.salary_structure_deleted_successfully', 'msg', N'Salary structure deleted successfully.', N'تم حذف هيكل الراتب بنجاح.', NULL),
    ('msg.salary_structure_updated_successfully', 'msg', N'Salary structure updated successfully.', N'تم تحديث هيكل الراتب بنجاح.', NULL),
    ('msg.section_created_successfully', 'msg', N'Section created successfully.', N'تم إنشاء القسم بنجاح.', NULL),
    ('msg.section_deleted_successfully', 'msg', N'Section deleted successfully.', N'تم حذف القسم بنجاح.', NULL),
    ('msg.section_updated_successfully', 'msg', N'Section updated successfully.', N'تم تحديث القسم بنجاح.', NULL),
    ('msg.select_a_company_first', 'msg', N'Select a company first.', N'اختر شركة أولًا.', NULL),
    ('msg.select_a_payroll_calendar_first', 'msg', N'Select a payroll calendar first.', N'اختر تقويم رواتب أولًا.', NULL),
    ('msg.select_a_valid_bank', 'msg', N'Select a valid bank.', N'اختر بنكًا صحيحًا.', NULL),
    ('msg.service_slabs_need_valid_non_overlapping_year_ra', 'msg', N'Service slabs need valid, non-overlapping year ranges and an entitlement in Days or Months.', N'تتطلب شرائح الخدمة نطاقات سنوات صحيحة وغير متداخلة واستحقاقًا بالأيام أو الأشهر.', NULL);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('msg.social_security_rate_created_successfully', 'msg', N'Social security rate created successfully.', N'تم إنشاء نسبة التأمينات الاجتماعية بنجاح.', NULL),
    ('msg.social_security_rate_deleted_successfully', 'msg', N'Social security rate deleted successfully.', N'تم حذف نسبة التأمينات الاجتماعية بنجاح.', NULL),
    ('msg.social_security_rate_updated_successfully', 'msg', N'Social security rate updated successfully.', N'تم تحديث نسبة التأمينات الاجتماعية بنجاح.', NULL),
    ('msg.social_security_end_of_service_overtime_and_leav', 'msg', N'Social security, end-of-service, overtime and leave-salary flags apply to earnings only.', N'تنطبق مؤشرات التأمينات الاجتماعية ونهاية الخدمة والعمل الإضافي وراتب الإجازة على الاستحقاقات فقط.', NULL),
    ('msg.that_iban_is_not_valid_kuwait_ibans_are_30_chara', 'msg', N'That IBAN is not valid. Kuwait IBANs are 30 characters starting with KW - check for a mistyped digit.', N'رقم الآيبان غير صحيح. يتكون الآيبان الكويتي من 30 خانة ويبدأ بـ KW - تحقق من وجود رقم مكتوب خطأ.', NULL),
    ('msg.that_code_is_already_in_use_enter_a_different_co', 'msg', N'That code is already in use. Enter a different code.', N'هذا الرمز مستخدم بالفعل. أدخل رمزًا مختلفًا.', NULL),
    ('msg.that_dependent_no_longer_exists', 'msg', N'That dependent no longer exists.', N'هذا المعال لم يعد موجودًا.', NULL),
    ('msg.that_dependent_no_longer_exists_refresh_and_try', 'msg', N'That dependent no longer exists. Refresh and try again.', N'هذا المعال لم يعد موجودًا. حدّث الصفحة وحاول مرة أخرى.', NULL),
    ('msg.that_document_type_is_not_available_any_more_ref', 'msg', N'That document type is not available any more. Refresh and try again.', N'نوع المستند هذا لم يعد متاحًا. حدّث الصفحة وحاول مرة أخرى.', NULL),
    ('msg.that_document_was_already_removed_refresh_and_tr', 'msg', N'That document was already removed. Refresh and try again.', N'تمت إزالة هذا المستند بالفعل. حدّث الصفحة وحاول مرة أخرى.', NULL),
    ('msg.that_employee_no_is_already_in_use_enter_a_diffe', 'msg', N'That employee No is already in use. Enter a different one.', N'هذا الرقم الوظيفي مستخدم بالفعل. أدخل رقمًا مختلفًا.', NULL),
    ('msg.that_employee_code_is_already_in_use_enter_a_dif', 'msg', N'That employee code is already in use. Enter a different code.', N'رمز الموظف هذا مستخدم بالفعل. أدخل رمزًا مختلفًا.', NULL),
    ('msg.that_employee_no_longer_exists', 'msg', N'That employee no longer exists.', N'هذا الموظف لم يعد موجودًا.', NULL),
    ('msg.that_employee_no_longer_exists_refresh_and_try_a', 'msg', N'That employee no longer exists. Refresh and try again.', N'هذا الموظف لم يعد موجودًا. حدّث الصفحة وحاول مرة أخرى.', NULL),
    ('msg.that_period_no_longer_exists_refresh_and_try_aga', 'msg', N'That period no longer exists. Refresh and try again.', N'هذه الفترة لم تعد موجودة. حدّث الصفحة وحاول مرة أخرى.', NULL),
    ('msg.that_record_no_longer_exists', 'msg', N'That record no longer exists.', N'هذا السجل لم يعد موجودًا.', NULL),
    ('msg.that_record_no_longer_exists_refresh_and_try_aga', 'msg', N'That record no longer exists. Refresh and try again.', N'هذا السجل لم يعد موجودًا. حدّث الصفحة وحاول مرة أخرى.', NULL),
    ('msg.the_entitlement_factors_could_not_be_read', 'msg', N'The entitlement factors could not be read.', N'تعذّرت قراءة عوامل الاستحقاق.', NULL),
    ('msg.the_selected_cost_center_does_not_belong_to_this', 'msg', N'The selected cost center does not belong to this company.', N'مركز التكلفة المحدد لا يتبع هذه الشركة.', NULL),
    ('msg.the_service_slabs_could_not_be_read', 'msg', N'The service slabs could not be read.', N'تعذّرت قراءة شرائح الخدمة.', NULL),
    ('msg.the_structure_lines_could_not_be_read', 'msg', N'The structure lines could not be read.', N'تعذّرت قراءة بنود الهيكل.', NULL),
    ('msg.the_uploaded_file_is_empty', 'msg', N'The uploaded file is empty.', N'الملف المرفوع فارغ.', NULL),
    ('msg.these_dates_overlap_another_period_of_the_same_c', 'msg', N'These dates overlap another period of the same calendar.', N'تتداخل هذه التواريخ مع فترة أخرى من نفس التقويم.', NULL),
    ('msg.this_iban_is_already_registered_as_a_company_acc', 'msg', N'This IBAN is already registered as a company account.', N'هذا الآيبان مسجل بالفعل كحساب للشركة.', NULL),
    ('msg.this_branch_is_referenced_by_other_records_and_c', 'msg', N'This branch is referenced by other records and cannot be deleted. Deactivate it instead.', N'هذا الفرع مرتبط بسجلات أخرى ولا يمكن حذفه. ألغِ تفعيله بدلًا من ذلك.', NULL),
    ('msg.this_calendar_has_processed_periods_or_is_used_b', 'msg', N'This calendar has processed periods or is used by a salary structure and cannot be deleted. Deactivate it instead.', N'يحتوي هذا التقويم على فترات معالجة أو يستخدمه هيكل راتب ولا يمكن حذفه. ألغِ تفعيله بدلًا من ذلك.', NULL),
    ('msg.this_calendar_is_inactive_activate_it_before_gen', 'msg', N'This calendar is inactive. Activate it before generating periods.', N'هذا التقويم غير نشط. فعّله قبل إنشاء الفترات.', NULL),
    ('msg.this_company_is_referenced_by_other_records_and', 'msg', N'This company is referenced by other records and cannot be deleted. Deactivate it instead.', N'هذه الشركة مرتبطة بسجلات أخرى ولا يمكن حذفها. ألغِ تفعيلها بدلًا من ذلك.', NULL),
    ('msg.this_component_is_used_in_a_salary_structure_and', 'msg', N'This component is used in a salary structure and cannot be deleted. Remove it from the structure or deactivate it instead.', N'هذا العنصر مستخدم في هيكل راتب ولا يمكن حذفه. أزله من الهيكل أو ألغِ تفعيله بدلًا من ذلك.', NULL),
    ('msg.this_component_is_used_in_a_salary_structure_so', 'msg', N'This component is used in a salary structure, so it cannot be switched between Earning and Deduction.', N'هذا العنصر مستخدم في هيكل راتب، لذا لا يمكن تحويله بين استحقاق واستقطاع.', NULL),
    ('msg.this_cost_center_is_referenced_by_other_records', 'msg', N'This cost center is referenced by other records and cannot be deleted. Deactivate it instead.', N'مركز التكلفة هذا مرتبط بسجلات أخرى ولا يمكن حذفه. ألغِ تفعيله بدلًا من ذلك.', NULL),
    ('msg.this_department_is_referenced_by_other_records_a', 'msg', N'This department is referenced by other records and cannot be deleted. Deactivate it instead.', N'هذه الإدارة مرتبطة بسجلات أخرى ولا يمكن حذفها. ألغِ تفعيلها بدلًا من ذلك.', NULL),
    ('msg.this_employee_is_referenced_elsewhere_as_a_manag', 'msg', N'This employee is referenced elsewhere (as a manager or a system login) and cannot be deleted. Deactivate instead.', N'هذا الموظف مرتبط بسجلات أخرى (كمدير أو كمستخدم للنظام) ولا يمكن حذفه. ألغِ تفعيله بدلًا من ذلك.', NULL),
    ('msg.this_job_position_is_referenced_by_other_records', 'msg', N'This job position is referenced by other records and cannot be deleted. Deactivate it instead.', N'هذه الوظيفة مرتبطة بسجلات أخرى ولا يمكن حذفها. ألغِ تفعيلها بدلًا من ذلك.', NULL),
    ('msg.this_section_is_referenced_by_other_records_and', 'msg', N'This section is referenced by other records and cannot be deleted. Deactivate it instead.', N'هذا القسم مرتبط بسجلات أخرى ولا يمكن حذفه. ألغِ تفعيله بدلًا من ذلك.', NULL),
    ('msg.unsupported_action', 'msg', N'Unsupported action.', N'إجراء غير مدعوم.', NULL),
    ('msg.working_days_basis_is_invalid_a_fixed_basis_need', 'msg', N'Working days basis is invalid. A fixed basis needs the number of days (e.g. 26 or 30).', N'أساس أيام العمل غير صحيح. يتطلب الأساس الثابت عدد الأيام (مثل 26 أو 30).', NULL),
    ('msg.the_current_password_is_incorrect', 'msg', N'The current password is incorrect.', N'كلمة المرور الحالية غير صحيحة.', NULL),
    ('msg.please_correct_the_highlighted_fields', 'msg', N'Please correct the highlighted fields.', N'يرجى تصحيح الحقول المميزة.', NULL),
    ('msg.this_account_is_temporarily_locked_after_too_man', 'msg', N'This account is temporarily locked after too many failed attempts.', N'تم قفل هذا الحساب مؤقتًا بسبب كثرة المحاولات الفاشلة.', NULL),
    ('msg.save_the_employee_s_personal_info_first_then_add', 'msg', N'Save the employee''s Personal Info first, then add Kuwait compliance details.', N'احفظ البيانات الشخصية للموظف أولًا، ثم أضف بيانات الامتثال الكويتي.', NULL),
    ('msg.the_file_could_not_be_saved', 'msg', N'The file could not be saved.', N'تعذّر حفظ الملف.', NULL),
    ('msg.system_administrator', 'msg', N'System Administrator', N'مسؤول النظام', NULL),
    ('msg.account_unlocked', 'msg', N'Account unlocked.', N'تم فتح الحساب.', NULL),
    ('msg.kuwait_compliance_details_saved', 'msg', N'Kuwait compliance details saved.', N'تم حفظ بيانات الامتثال الكويتي.', NULL),
    ('msg.password_changed_successfully', 'msg', N'Password changed successfully.', N'تم تغيير كلمة المرور بنجاح.', NULL),
    ('msg.that_account_no_longer_exists', 'msg', N'That account no longer exists.', N'هذا الحساب لم يعد موجودًا.', NULL),
    ('msg.locked_minutes', 'msg', N'This account is locked after too many failed attempts. Try again in {0} minutes.', N'تم قفل هذا الحساب بسبب كثرة المحاولات الفاشلة. حاول مرة أخرى بعد {0} دقائق.', N'This account is locked after too many failed attempts. Try again in {0} minutes.'),
    ('msg.file_over_limit', 'msg', N'The file is {0} MB - the limit is {1} MB.', N'حجم الملف {0} ميجابايت - الحد الأقصى {1} ميجابايت.', N'The file is {0} MB - the limit is {1} MB.'),
    ('msg.file_not_real', 'msg', N'This file is not a real {0} file. Re-save it and try again.', N'هذا ليس ملف {0} حقيقيًا. أعد حفظه وحاول مرة أخرى.', N'This file is not a real {0} file. Re-save it and try again.'),
    ('msg.use_at_most_n', 'msg', N'Use at most {0} characters.', N'استخدم {0} حرفًا كحد أقصى.', N'Use at most {0} characters.'),
    ('msg.dept_other_n', 'msg', N'Other ({0})', N'أخرى ({0})', N'Other ({0})'),
    ('msg.n_companies', 'msg', N'{0} companies', N'{0} شركات', N'{0} companies'),
    ('msg.period_cannot_move', 'msg', N'A period cannot move from {0} to {1}.', N'لا يمكن نقل الفترة من {0} إلى {1}.', N'A period cannot move from {0} to {1}.'),
    ('msg.period_status_changed', 'msg', N'Period status changed to {0}.', N'تم تغيير حالة الفترة إلى {0}.', N'Period status changed to {0}.'),
    ('mb.value_invalid', 'mb', N'The value ''{0}'' is invalid.', N'القيمة ''{0}'' غير صالحة.', N'The value ''{0}'' is invalid.'),
    ('mb.value_not_valid_for', 'mb', N'The value ''{0}'' is not valid for {1}.', N'القيمة ''{0}'' غير صالحة للحقل {1}.', N'The value ''{0}'' is not valid for {1}.'),
    ('mb.must_be_number', 'mb', N'The field {0} must be a number.', N'يجب أن يكون الحقل {0} رقمًا.', N'The field {0} must be a number.'),
    ('mb.missing_bind', 'mb', N'A value for the ''{0}'' parameter or property was not provided.', N'لم يتم توفير قيمة للحقل ''{0}''.', N'A value for the ''{0}'' parameter or property was not provided.'),
    ('mb.value_required', 'mb', N'A value is required.', N'القيمة مطلوبة.', N'A value is required.'),
    ('mb.supplied_invalid_for', 'mb', N'The supplied value is invalid for {0}.', N'القيمة المُدخلة غير صالحة للحقل {0}.', N'The supplied value is invalid for {0}.'),
    ('mb.value_not_valid', 'mb', N'The value ''{0}'' is not valid.', N'القيمة ''{0}'' غير صالحة.', N'The value ''{0}'' is not valid.'),
    ('mb.supplied_invalid', 'mb', N'The supplied value is invalid.', N'القيمة المُدخلة غير صالحة.', N'The supplied value is invalid.'),
    ('mb.must_be_number_np', 'mb', N'The field must be a number.', N'يجب أن يكون الحقل رقمًا.', N'The field must be a number.'),
    ('mb.body_required', 'mb', N'A non-empty request body is required.', N'يجب ألا يكون محتوى الطلب فارغًا.', N'A non-empty request body is required.'),
    ('msg.ui_label_created_successfully', 'msg', N'UI label created successfully.', N'تم إنشاء التسمية بنجاح.', NULL),
    ('msg.ui_label_updated_successfully', 'msg', N'UI label updated successfully.', N'تم تحديث التسمية بنجاح.', NULL),
    ('msg.ui_label_deleted_successfully', 'msg', N'UI label deleted successfully.', N'تم حذف التسمية بنجاح.', NULL),
    ('msg.that_label_key_is_already_in_use_enter_a_differe', 'msg', N'That label key is already in use. Enter a different key.', N'مفتاح التسمية هذا مستخدم بالفعل. أدخل مفتاحًا مختلفًا.', NULL),
    ('msg.label_key_and_english_text_are_required', 'msg', N'Label key and English text are required.', N'مفتاح التسمية والنص الإنجليزي مطلوبان.', NULL),
    ('msg.a_label_key_uses_lower_case_letters_digits_dots', 'msg', N'A label key uses lower-case letters, digits, dots and underscores (e.g. org.branch_name).', N'يتكون مفتاح التسمية من أحرف صغيرة وأرقام ونقاط وشرطات سفلية (مثل org.branch_name).', NULL),
    ('msg.language_must_be_en_or_ar', 'msg', N'Language must be en or ar.', N'يجب أن تكون اللغة en أو ar.', NULL),
    ('msg.preferred_language_saved', 'msg', N'Preferred language saved.', N'تم حفظ اللغة المفضلة.', NULL);
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM   #Seed AS s
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey AND l.Deleted = 0);

DECLARE @Inserted INT = @@ROWCOUNT;

UPDATE l
   SET l.ArabicText = ISNULL(NULLIF(l.ArabicText, N''), s.ArabicText),
       l.SourceText = ISNULL(l.SourceText, s.SourceText)
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.LabelKey = l.LabelKey
WHERE  l.Deleted = 0
  AND (   (NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL)
       OR (l.SourceText IS NULL AND s.SourceText IS NOT NULL));

DECLARE @Completed INT = @@ROWCOUNT;

/* A message captured automatically before this seed ran ("msg.auto_...")
   gets the Arabic from the seeded row with the same English wording. */
UPDATE l
   SET l.ArabicText = s.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.EnglishText = l.EnglishText COLLATE Latin1_General_BIN
WHERE  l.Deleted = 0 AND NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL;

PRINT N'UiLabels: ' + CONVERT(NVARCHAR(10), @Inserted) + N' inserted, ' + CONVERT(NVARCHAR(10), @Completed) + N' completed.';
DROP TABLE #Seed;
GO

/* =====================================================================
   7. Harvest - procedure messages not seeded yet
   ---------------------------------------------------------------------
   Every literal  @ResultMessage = N'...'  in this database's procedures
   becomes a label (module 'msg', ArabicText empty) unless a label with
   the same English wording exists. Translate them with the query in the
   header. Messages built by concatenation are not picked up here; the
   application captures those (CAPTURE) the first time they are shown in
   Arabic.
   ===================================================================== */
DECLARE @Found TABLE (Msg NVARCHAR(400) COLLATE DATABASE_DEFAULT PRIMARY KEY);
DECLARE @def NVARCHAR(MAX), @pos INT, @start INT, @end INT, @msg NVARCHAR(MAX);
DECLARE @marker NVARCHAR(40) = N'ResultMessage = N''';

DECLARE mods CURSOR LOCAL STATIC FOR
    SELECT m.definition
    FROM   sys.sql_modules AS m
    JOIN   sys.objects     AS o ON o.object_id = m.object_id
    WHERE  o.type = 'P' AND m.definition LIKE N'%ResultMessage = N''%';

OPEN mods;
FETCH NEXT FROM mods INTO @def;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @pos = CHARINDEX(@marker, @def);
    WHILE @pos > 0
    BEGIN
        SET @start = @pos + LEN(@marker);
        SET @end = @start;
        /* find the closing quote, skipping doubled '' */
        WHILE @end <= LEN(@def)
        BEGIN
            IF SUBSTRING(@def, @end, 1) = N''''
            BEGIN
                IF SUBSTRING(@def, @end + 1, 1) = N'''' SET @end = @end + 2;
                ELSE BREAK;
            END
            ELSE SET @end = @end + 1;
        END;

        SET @msg = REPLACE(SUBSTRING(@def, @start, @end - @start), N'''''', N'''');
        /* literal only: the next non-blank character must end the expression */
        IF LTRIM(SUBSTRING(@def, @end + 1, 3)) NOT LIKE N'+%' AND LEN(@msg) BETWEEN 1 AND 400
           AND NOT EXISTS (SELECT 1 FROM @Found WHERE Msg = @msg)
            INSERT INTO @Found (Msg) VALUES (@msg);

        SET @pos = CHARINDEX(@marker, @def, @end + 1);
    END;
    FETCH NEXT FROM mods INTO @def;
END;
CLOSE mods; DEALLOCATE mods;

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, Notes)
SELECT 'msg.auto_' + LOWER(CONVERT(VARCHAR(40), HASHBYTES('SHA1', f.Msg), 2)), 'msg', f.Msg, NULL,
       N'Harvested from a stored procedure by 33_Localization.sql - add the Arabic.'
FROM   @Found AS f
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.EnglishText = f.Msg COLLATE Latin1_General_BIN AND l.Deleted = 0)
  AND  NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = 'msg.auto_' + LOWER(CONVERT(VARCHAR(40), HASHBYTES('SHA1', f.Msg), 2)) AND l.Deleted = 0);

PRINT N'Procedure messages harvested (need Arabic): ' + CONVERT(NVARCHAR(10), @@ROWCOUNT);
GO

/* ---------------------------------------------------------------------
   Summary
--------------------------------------------------------------------- */
SELECT Module,
       COUNT(1)                                                  AS Labels,
       SUM(CASE WHEN NULLIF(ArabicText, N'') IS NULL THEN 1 ELSE 0 END) AS MissingArabic
FROM   [Core].[UiLabels]
WHERE  Deleted = 0
GROUP BY Module
ORDER BY Module;
GO
