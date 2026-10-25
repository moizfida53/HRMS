/* =====================================================================
   75_Organization_Issuing_Authorities.sql  -  HRMS: who issues each
   organization document
   ---------------------------------------------------------------------
   Run after 73 and 74. Safe to re-run. Then run 76 (labels).

   The issuing authority of a company document is chosen once, on its
   document type (Setup > Organization > Organization Documents), from
   the Kuwait government authorities - no longer typed on each document.

     1. Documents.IssuingAuthorities  the authorities (English / Arabic /
        short name), seeded with the Kuwait government bodies that issue
        company documents; add rows for others
     2. Documents.OrganizationDocumentTypes.IssuingAuthorityId, filled for
        the db/73 starter types by name (only where it is still empty)
     3. Documents.usp_OrgDocumentType_Manage / usp_OrgDocument_Manage
        (db/73) re-created with the authority; a saved document records
        its type's authority (so a version keeps who issued it)
     4. Documents.usp_IssuingAuthority_Manage LIST (the dropdown)
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Documents].[OrganizationDocumentTypes]', N'U') IS NULL
BEGIN
    RAISERROR(N'Run db/73 first.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------
   1. Documents.IssuingAuthorities
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Documents].[IssuingAuthorities]', N'U') IS NULL
BEGIN
    CREATE TABLE [Documents].[IssuingAuthorities](
        IssuingAuthorityId  INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_IssuingAuthorities PRIMARY KEY,
        AuthorityName       NVARCHAR(150)  NOT NULL,
        ArabicName          NVARCHAR(150)  NULL,
        ShortName           NVARCHAR(20)   NULL,
        IsGovernment        BIT            NOT NULL CONSTRAINT DF_IssuingAuthorities_Gov DEFAULT (1),
        SortOrder           INT            NULL,
        IsActive            BIT            NOT NULL CONSTRAINT DF_IssuingAuthorities_Active DEFAULT (1),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_IssuingAuthorities_Created DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_IssuingAuthorities_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(0)   NULL
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_IssuingAuthorities_Name ON [Documents].[IssuingAuthorities] (AuthorityName) WHERE Deleted = 0;');
    PRINT N'Created [Documents].[IssuingAuthorities].';
END
GO

/* the Kuwait government bodies that issue company documents (each added once, by name) */
INSERT INTO [Documents].[IssuingAuthorities] (AuthorityName, ArabicName, ShortName, IsGovernment, SortOrder)
SELECT s.AuthorityName, s.ArabicName, s.ShortName, s.IsGovernment, s.SortOrder
FROM (VALUES
    (N'Ministry of Commerce and Industry',                          N'وزارة التجارة والصناعة',                          N'MOCI',   1, 1),
    (N'Kuwait Chamber of Commerce and Industry',                    N'غرفة تجارة وصناعة الكويت',                        N'KCCI',   1, 2),
    (N'Public Authority for Manpower',                              N'الهيئة العامة للقوى العاملة',                     N'PAM',    1, 3),
    (N'Public Institution for Social Security',                     N'المؤسسة العامة للتأمينات الاجتماعية',             N'PIFSS',  1, 4),
    (N'Kuwait Municipality',                                        N'بلدية الكويت',                                    N'KM',     1, 5),
    (N'Kuwait Fire Force',                                          N'قوة الإطفاء العام',                               N'KFF',    1, 6),
    (N'Ministry of Interior',                                       N'وزارة الداخلية',                                  N'MOI',    1, 7),
    (N'General Department of Residency Affairs (Ministry of Interior)', N'الإدارة العامة لشؤون الإقامة - وزارة الداخلية', N'GDRA', 1, 8),
    (N'Public Authority for Civil Information',                     N'الهيئة العامة للمعلومات المدنية',                 N'PACI',   1, 9),
    (N'Ministry of Justice',                                        N'وزارة العدل',                                     N'MOJ',    1, 10),
    (N'Ministry of Finance',                                        N'وزارة المالية',                                   N'MOF',    1, 11),
    (N'Ministry of Social Affairs',                                 N'وزارة الشؤون الاجتماعية',                         N'MOSA',   1, 12),
    (N'Ministry of Health',                                         N'وزارة الصحة',                                     N'MOH',    1, 13),
    (N'Ministry of Electricity, Water and Renewable Energy',        N'وزارة الكهرباء والماء والطاقة المتجددة',          N'MEW',    1, 14),
    (N'Ministry of Information',                                    N'وزارة الإعلام',                                   N'MOInf',  1, 15),
    (N'General Administration of Customs',                          N'الإدارة العامة للجمارك',                          N'KGAC',   1, 16),
    (N'Environment Public Authority',                               N'الهيئة العامة للبيئة',                            N'EPA',    1, 17),
    (N'Public Authority for Industry',                              N'الهيئة العامة للصناعة',                           N'PAI',    1, 18),
    (N'Public Authority for Food and Nutrition',                    N'الهيئة العامة للغذاء والتغذية',                   N'PAFN',   1, 19),
    (N'Kuwait Direct Investment Promotion Authority',               N'هيئة تشجيع الاستثمار المباشر',                    N'KDIPA',  1, 20),
    (N'Capital Markets Authority',                                  N'هيئة أسواق المال',                                N'CMA',    1, 21),
    (N'Central Bank of Kuwait',                                     N'بنك الكويت المركزي',                              N'CBK',    1, 22),
    (N'Insurance Regulatory Unit',                                  N'وحدة تنظيم التأمين',                              N'IRU',    1, 23),
    (N'Communication and Information Technology Regulatory Authority', N'هيئة الاتصالات وتقنية المعلومات',             N'CITRA',  1, 24),
    (N'Kuwait Ports Authority',                                     N'مؤسسة الموانئ الكويتية',                          N'KPA',    1, 25),
    (N'Directorate General of Civil Aviation',                      N'الإدارة العامة للطيران المدني',                   N'DGCA',   1, 26),
    (N'Private party (landlord, insurer, bank)',                    N'جهة خاصة (مالك العقار، شركة التأمين، البنك)',     NULL,      0, 99)
) AS s (AuthorityName, ArabicName, ShortName, IsGovernment, SortOrder)
WHERE NOT EXISTS (SELECT 1 FROM [Documents].[IssuingAuthorities] a WHERE a.AuthorityName = s.AuthorityName AND a.Deleted = 0);
DECLARE @AuthoritiesAdded INT = @@ROWCOUNT;
PRINT CONCAT(N'Issuing authorities added: ', @AuthoritiesAdded);
GO

/* ------------------------------------------------------------------
   2. The authority of each document type
   ------------------------------------------------------------------ */
IF COL_LENGTH(N'Documents.OrganizationDocumentTypes', N'IssuingAuthorityId') IS NULL
BEGIN
    ALTER TABLE [Documents].[OrganizationDocumentTypes] ADD IssuingAuthorityId INT NULL
        CONSTRAINT FK_OrgDocTypes_Authority FOREIGN KEY REFERENCES [Documents].[IssuingAuthorities](IssuingAuthorityId);
    PRINT N'Added [Documents].[OrganizationDocumentTypes].[IssuingAuthorityId].';
END
GO

/* the db/73 starter types, by name - only where nothing is chosen yet */
UPDATE t
   SET IssuingAuthorityId = a.IssuingAuthorityId
  FROM [Documents].[OrganizationDocumentTypes] t
  JOIN (VALUES
        (N'Commercial License',                    N'MOCI'),
        (N'Municipality License',                  N'KM'),
        (N'Civil Defense Certificate',             N'KFF'),
        (N'Commercial Registration',               N'MOCI'),
        (N'Chamber of Commerce Membership',        N'KCCI'),
        (N'PAM Company File (Manpower)',           N'PAM'),
        (N'PIFSS Employer Registration',           N'PIFSS'),
        (N'Authorized Signatory Certificate',      N'MOCI'),
        (N'Memorandum & Articles of Association',  N'MOJ')
       ) AS m (TypeName, ShortName) ON m.TypeName = t.TypeName
  JOIN [Documents].[IssuingAuthorities] a ON a.ShortName = m.ShortName AND a.Deleted = 0
 WHERE t.IssuingAuthorityId IS NULL AND t.Deleted = 0;
UPDATE t
   SET IssuingAuthorityId = a.IssuingAuthorityId
  FROM [Documents].[OrganizationDocumentTypes] t
  JOIN [Documents].[IssuingAuthorities] a ON a.IsGovernment = 0 AND a.Deleted = 0
 WHERE t.TypeName = N'Office Lease Agreement' AND t.IssuingAuthorityId IS NULL AND t.Deleted = 0;
GO

/* ------------------------------------------------------------------
   3. The db/73 procedures, with the authority
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Documents].[usp_OrgDocumentType_Manage]
    @Action            VARCHAR(10),
    @Id                BIGINT          = NULL,
    @UserId            BIGINT          = NULL,
    /* LIST */
    @Search            NVARCHAR(200)   = NULL,
    @IsActiveFilter    BIT             = NULL,
    @CompanyId         INT             = NULL,     -- envelope only: the types are group-wide
    @CompanyIds        NVARCHAR(2000)  = NULL,
    @ParentId          INT             = NULL,
    @PageNumber        INT             = 1,
    @PageSize          INT             = 25,
    @SortColumn        VARCHAR(50)     = NULL,
    @SortDirection     VARCHAR(4)      = NULL,
    /* INSERT / UPDATE */
    @TypeName          NVARCHAR(150)   = NULL,
    @ArabicName        NVARCHAR(150)   = NULL,
    @Category          VARCHAR(20)     = NULL,
    @IsMandatory       BIT             = NULL,
    @HasNumber         BIT             = NULL,
    @HasIssueDate      BIT             = NULL,
    @HasExpiryDate     BIT             = NULL,
    @AlertRules        VARCHAR(60)     = NULL,
    @IssuingAuthorityId INT            = NULL,
    @SortOrder         INT             = NULL,
    @IsActive          BIT             = NULL,

    @TotalCount        INT             = NULL OUTPUT,
    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @TypeName   = NULLIF(LTRIM(RTRIM(@TypeName)), N'');
    SET @ArabicName = NULLIF(LTRIM(RTRIM(@ArabicName)), N'');
    SET @AlertRules = NULLIF(REPLACE(LTRIM(RTRIM(@AlertRules)), ' ', ''), '');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 500 THEN 500 ELSE @PageSize END;
    SET @SortColumn = CASE WHEN @SortColumn IN ('TypeName', 'Category', 'IsMandatory', 'IsActive', 'UsageCount') THEN @SortColumn ELSE 'Category' END;
    SET @SortDirection = CASE WHEN UPPER(@SortDirection) = 'DESC' THEN 'DESC' ELSE 'ASC' END;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= LIST / GET =========================== */
    IF @Action IN ('LIST', 'GET')
    BEGIN
        ;WITH x AS (
            SELECT  t.OrgDocumentTypeId, t.TypeName, t.ArabicName, t.Category, t.IsMandatory, t.HasNumber, t.HasIssueDate,
                    t.HasExpiryDate, t.AlertRules, t.SortOrder, t.IsActive,
                    t.IssuingAuthorityId, ia.AuthorityName, ia.ArabicName AS AuthorityNameAr, ia.ShortName AS AuthorityShortName,
                    (SELECT COUNT(1) FROM [Documents].[OrganizationDocuments] d
                      WHERE d.OrgDocumentTypeId = t.OrgDocumentTypeId AND d.Deleted = 0 AND d.State = 'C') AS UsageCount,
                    CASE t.Category WHEN 'LICENSE' THEN 1 WHEN 'REGISTRATION' THEN 2 WHEN 'AUTHORIZATION' THEN 3
                                    WHEN 'CONTRACT' THEN 4 WHEN 'INSURANCE' THEN 5 ELSE 6 END AS CategorySeq
            FROM    [Documents].[OrganizationDocumentTypes] AS t
            LEFT JOIN [Documents].[IssuingAuthorities] AS ia ON ia.IssuingAuthorityId = t.IssuingAuthorityId
            WHERE   t.Deleted = 0
              AND   (@Action = 'LIST' OR t.OrgDocumentTypeId = @Id)
              AND   (@IsActiveFilter IS NULL OR t.IsActive = @IsActiveFilter)
              AND   (@Search IS NULL OR t.TypeName LIKE N'%' + @Search + N'%' OR t.ArabicName LIKE N'%' + @Search + N'%'
                     OR ia.AuthorityName LIKE N'%' + @Search + N'%' OR ia.ShortName LIKE N'%' + @Search + N'%')
        ),
        sorted AS (
            SELECT  x.*,
                    ROW_NUMBER() OVER (ORDER BY
                        CASE WHEN @SortColumn = 'TypeName'    AND @SortDirection = 'ASC'  THEN x.TypeName END ASC,
                        CASE WHEN @SortColumn = 'TypeName'    AND @SortDirection = 'DESC' THEN x.TypeName END DESC,
                        CASE WHEN @SortColumn = 'IsMandatory' AND @SortDirection = 'ASC'  THEN x.IsMandatory END ASC,
                        CASE WHEN @SortColumn = 'IsMandatory' AND @SortDirection = 'DESC' THEN x.IsMandatory END DESC,
                        CASE WHEN @SortColumn = 'IsActive'    AND @SortDirection = 'ASC'  THEN x.IsActive END ASC,
                        CASE WHEN @SortColumn = 'IsActive'    AND @SortDirection = 'DESC' THEN x.IsActive END DESC,
                        CASE WHEN @SortColumn = 'UsageCount'  AND @SortDirection = 'ASC'  THEN x.UsageCount END ASC,
                        CASE WHEN @SortColumn = 'UsageCount'  AND @SortDirection = 'DESC' THEN x.UsageCount END DESC,
                        CASE WHEN @SortColumn = 'Category'    AND @SortDirection = 'DESC' THEN x.CategorySeq END DESC,
                        x.CategorySeq, ISNULL(x.SortOrder, 2147483647), x.TypeName) AS RowNo,
                    COUNT(1) OVER () AS TotalRows
            FROM    x
        )
        SELECT  *
        INTO    #Page
        FROM    sorted
        WHERE   @Action = 'GET' OR (RowNo > (@PageNumber - 1) * @PageSize AND RowNo <= @PageNumber * @PageSize);

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #Page;
        SELECT OrgDocumentTypeId, TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate,
               AlertRules, SortOrder, IsActive, UsageCount, IssuingAuthorityId, AuthorityName, AuthorityNameAr, AuthorityShortName
        FROM   #Page
        ORDER BY RowNo;
        RETURN;
    END;

    /* ======================= INSERT / UPDATE ====================== */
    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        IF @TypeName IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the document type name.'; RETURN; END;
        IF ISNULL(@Category, '') NOT IN ('LICENSE', 'REGISTRATION', 'AUTHORIZATION', 'CONTRACT', 'INSURANCE', 'OTHER') SET @Category = 'OTHER';
        IF ISNULL(@HasExpiryDate, 0) = 0 SET @AlertRules = NULL;   -- alerts are on the expiry date
        /* every alert is M|W|D + 0..99 */
        IF @AlertRules IS NOT NULL AND EXISTS (
            SELECT 1 FROM STRING_SPLIT(@AlertRules, ',') s
            WHERE  LEN(s.value) < 2 OR LEFT(s.value, 1) NOT IN ('M', 'W', 'D')
               OR  TRY_CAST(SUBSTRING(s.value, 2, 3) AS INT) IS NULL
               OR  TRY_CAST(SUBSTRING(s.value, 2, 3) AS INT) NOT BETWEEN 0 AND 99)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The alerts could not be read.'; RETURN; END;
        IF @IssuingAuthorityId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [Documents].[IssuingAuthorities] WHERE IssuingAuthorityId = @IssuingAuthorityId AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the issuing authority from the list.'; RETURN; END;
        IF EXISTS (SELECT 1 FROM [Documents].[OrganizationDocumentTypes]
                   WHERE Deleted = 0 AND TypeName = @TypeName AND OrgDocumentTypeId <> ISNULL(@Id, 0))
        BEGIN SELECT @ResultCode = 'DUPLICATE_NAME', @ResultMessage = N'An organization document type with this name already exists.'; RETURN; END;

        IF @Action = 'INSERT'
        BEGIN
            INSERT INTO [Documents].[OrganizationDocumentTypes]
                (TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate, AlertRules, IssuingAuthorityId, SortOrder, IsActive, CreatedBy)
            VALUES (@TypeName, @ArabicName, @Category, ISNULL(@IsMandatory, 0), ISNULL(@HasNumber, 1), ISNULL(@HasIssueDate, 1),
                    ISNULL(@HasExpiryDate, 1), @AlertRules, @IssuingAuthorityId,
                    ISNULL(@SortOrder, (SELECT ISNULL(MAX(SortOrder), 0) + 1 FROM [Documents].[OrganizationDocumentTypes] WHERE Deleted = 0)),
                    ISNULL(@IsActive, 1), @UserId);
            SELECT @NewId = SCOPE_IDENTITY(), @ResultMessage = N'Organization document type added.';
            RETURN;
        END;

        UPDATE [Documents].[OrganizationDocumentTypes]
           SET TypeName = @TypeName, ArabicName = @ArabicName, Category = @Category, IsMandatory = ISNULL(@IsMandatory, 0),
               HasNumber = ISNULL(@HasNumber, 1), HasIssueDate = ISNULL(@HasIssueDate, 1), HasExpiryDate = ISNULL(@HasExpiryDate, 1),
               AlertRules = @AlertRules, IssuingAuthorityId = @IssuingAuthorityId, SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, IsActive),
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE OrgDocumentTypeId = @Id AND Deleted = 0;
        IF @@ROWCOUNT = 0
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        SELECT @NewId = @Id, @ResultMessage = N'Organization document type saved.';
        RETURN;
    END;

    /* ======================= TOGGLE / DELETE ====================== */
    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Documents].[OrganizationDocumentTypes]
           SET IsActive = 1 - IsActive, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE OrgDocumentTypeId = @Id AND Deleted = 0;
        SELECT @NewId = @Id, @ResultMessage = N'Status changed.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Documents].[OrganizationDocuments] WHERE OrgDocumentTypeId = @Id AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Companies keep documents of this type. Deactivate it instead.'; RETURN; END;
        UPDATE [Documents].[OrganizationDocumentTypes]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE OrgDocumentTypeId = @Id AND Deleted = 0;
        SELECT @NewId = @Id, @ResultMessage = N'Organization document type deleted.';
        RETURN;
    END;
END;
GO

CREATE OR ALTER PROCEDURE [Documents].[usp_OrgDocument_Manage]
    @Action            VARCHAR(10),
    @Id                BIGINT          = NULL,
    @CompanyId         INT             = NULL,     -- the company asked for
    @UserCompanyId     INT             = NULL,     -- a user pinned to one company
    @CompanyIds        NVARCHAR(2000)  = NULL,     -- top-bar company filter
    @OrgDocumentTypeId INT             = NULL,
    @DocumentNumber    NVARCHAR(100)   = NULL,
    @IssuingAuthority  NVARCHAR(150)   = NULL,
    @IssueDate         DATE            = NULL,
    @ExpiryDate        DATE            = NULL,
    @Notes             NVARCHAR(500)   = NULL,
    @OriginalFileName  NVARCHAR(260)   = NULL,
    @StoredFileName    NVARCHAR(400)   = NULL,
    @ContentType       NVARCHAR(100)   = NULL,
    @FileSizeBytes     BIGINT          = NULL,
    @RemoveFile        BIT             = 0,
    @Renew             BIT             = 0,
    @UserId            BIGINT          = NULL,
    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(ISNULL(@CompanyIds, N''), N' ', N'') + N',';

    /* the companies the user may see: active ones, their own when pinned, within the top-bar filter */
    DECLARE @Co TABLE (CompanyId INT PRIMARY KEY, CompanyCode NVARCHAR(100), CompanyName NVARCHAR(400), LegalName NVARCHAR(400),
                       CommercialRegistrationNo NVARCHAR(400));
    INSERT INTO @Co
    SELECT c.CompanyId, c.CompanyCode, c.CompanyName, c.LegalName, c.CommercialRegistrationNo
    FROM   [Core].[Companies] c
    WHERE  c.Deleted = 0 AND c.IsActive = 1
      AND  (@UserCompanyId IS NULL OR c.CompanyId = @UserCompanyId)
      AND  (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(c.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0);

    /* ======================= COMPANIES ============================ */
    IF @Action = 'COMPANIES'
    BEGIN
        ;WITH docs AS (
            SELECT  co.CompanyId, t.OrgDocumentTypeId, t.IsMandatory, t.HasExpiryDate, t.AlertRules,
                    d.OrgDocumentId, d.ExpiryDate
            FROM    @Co co
            CROSS JOIN [Documents].[OrganizationDocumentTypes] t
            LEFT JOIN  [Documents].[OrganizationDocuments] d ON d.CompanyId = co.CompanyId AND d.OrgDocumentTypeId = t.OrgDocumentTypeId
                                                            AND d.Deleted = 0 AND d.State = 'C'
            WHERE   t.Deleted = 0 AND t.IsActive = 1
        )
        SELECT  co.CompanyId, co.CompanyCode, co.CompanyName, co.LegalName, co.CommercialRegistrationNo,
                (SELECT COUNT(1) FROM docs x WHERE x.CompanyId = co.CompanyId) AS TypeCount,
                (SELECT COUNT(1) FROM docs x WHERE x.CompanyId = co.CompanyId AND x.OrgDocumentId IS NOT NULL) AS RecordedCount,
                (SELECT COUNT(1) FROM docs x WHERE x.CompanyId = co.CompanyId AND x.OrgDocumentId IS NULL AND x.IsMandatory = 1) AS MissingCount,
                (SELECT COUNT(1) FROM docs x WHERE x.CompanyId = co.CompanyId AND x.HasExpiryDate = 1 AND x.ExpiryDate < @Today) AS ExpiredCount,
                (SELECT COUNT(1) FROM docs x
                  WHERE x.CompanyId = co.CompanyId AND x.HasExpiryDate = 1 AND x.ExpiryDate >= @Today
                    AND EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(x.AlertRules, ''), ',') r
                                WHERE LEN(r.value) >= 2 AND TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT) IS NOT NULL
                                  AND CASE LEFT(r.value, 1) WHEN 'M' THEN DATEADD(MONTH, -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), x.ExpiryDate)
                                                            WHEN 'W' THEN DATEADD(WEEK,  -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), x.ExpiryDate)
                                                            ELSE          DATEADD(DAY,   -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), x.ExpiryDate) END <= @Today)
                ) AS DueCount,
                (SELECT MIN(x.ExpiryDate) FROM docs x WHERE x.CompanyId = co.CompanyId AND x.ExpiryDate >= @Today) AS NextExpiry
        FROM    @Co co
        ORDER BY co.CompanyName;
        RETURN;
    END;

    /* ======================= LIST ================================= */
    IF @Action = 'LIST'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM @Co WHERE CompanyId = @CompanyId)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That company was not found.'; RETURN; END;

        SELECT  t.OrgDocumentTypeId, t.TypeName, t.ArabicName, t.Category, t.IsMandatory, t.HasNumber, t.HasIssueDate,
                t.HasExpiryDate, t.AlertRules,
                ia.AuthorityName, ia.ArabicName AS AuthorityNameAr, ia.ShortName AS AuthorityShortName,
                d.OrgDocumentId, d.DocumentNumber, d.IssuingAuthority, d.IssueDate, d.ExpiryDate, d.Notes,
                d.OriginalFileName, d.ContentType, d.FileSizeBytes, ISNULL(d.ModifiedDate, d.CreatedDate) AS UpdatedDate,
                (SELECT COUNT(1) FROM [Documents].[OrganizationDocuments] a
                  WHERE a.CompanyId = @CompanyId AND a.OrgDocumentTypeId = t.OrgDocumentTypeId AND a.Deleted = 0 AND a.State = 'A') AS ArchivedCount,
                /* the alert that fired most recently, e.g. M1 (null = none yet) */
                (SELECT TOP (1) r.value
                   FROM STRING_SPLIT(ISNULL(t.AlertRules, ''), ',') r
                  CROSS APPLY (SELECT CASE LEFT(r.value, 1) WHEN 'M' THEN DATEADD(MONTH, -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), d.ExpiryDate)
                                                            WHEN 'W' THEN DATEADD(WEEK,  -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), d.ExpiryDate)
                                                            ELSE          DATEADD(DAY,   -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), d.ExpiryDate) END AS FiresOn) f
                  WHERE d.ExpiryDate IS NOT NULL AND LEN(r.value) >= 2 AND TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT) IS NOT NULL
                    AND f.FiresOn <= @Today
                  ORDER BY f.FiresOn DESC) AS FiredRule
        FROM        [Documents].[OrganizationDocumentTypes] t
        LEFT JOIN   [Documents].[IssuingAuthorities] ia ON ia.IssuingAuthorityId = t.IssuingAuthorityId
        LEFT JOIN   [Documents].[OrganizationDocuments] d ON d.CompanyId = @CompanyId AND d.OrgDocumentTypeId = t.OrgDocumentTypeId
                                                         AND d.Deleted = 0 AND d.State = 'C'
        WHERE   t.Deleted = 0 AND (t.IsActive = 1 OR d.OrgDocumentId IS NOT NULL)
        ORDER BY CASE t.Category WHEN 'LICENSE' THEN 1 WHEN 'REGISTRATION' THEN 2 WHEN 'AUTHORIZATION' THEN 3
                                 WHEN 'CONTRACT' THEN 4 WHEN 'INSURANCE' THEN 5 ELSE 6 END,
                 ISNULL(t.SortOrder, 2147483647), t.TypeName;
        RETURN;
    END;

    /* ======================= GET ================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  d.OrgDocumentId, d.CompanyId, d.OrgDocumentTypeId, d.State, d.DocumentNumber, d.IssuingAuthority, d.IssueDate,
                d.ExpiryDate, d.Notes, d.OriginalFileName, d.StoredFileName, d.ContentType, d.FileSizeBytes,
                d.CreatedDate, d.ArchivedDate, t.TypeName, t.ArabicName
        FROM    [Documents].[OrganizationDocuments] d
        JOIN    @Co co ON co.CompanyId = d.CompanyId
        JOIN    [Documents].[OrganizationDocumentTypes] t ON t.OrgDocumentTypeId = d.OrgDocumentTypeId
        WHERE   d.OrgDocumentId = @Id AND d.Deleted = 0;
        RETURN;
    END;

    /* ======================= HISTORY ============================== */
    IF @Action = 'HISTORY'
    BEGIN
        SELECT  d.OrgDocumentId, d.State, d.DocumentNumber, d.IssuingAuthority, d.IssueDate, d.ExpiryDate, d.Notes,
                d.OriginalFileName, d.ContentType, d.FileSizeBytes, d.CreatedDate, d.ArchivedDate,
                u.Username AS CreatedByName
        FROM    [Documents].[OrganizationDocuments] d
        JOIN    @Co co ON co.CompanyId = d.CompanyId
        LEFT JOIN [Security].[Users] u ON u.UserId = d.CreatedBy
        WHERE   d.CompanyId = @CompanyId AND d.OrgDocumentTypeId = @OrgDocumentTypeId AND d.Deleted = 0
        ORDER BY CASE d.State WHEN 'C' THEN 0 ELSE 1 END, ISNULL(d.ExpiryDate, '99991231') DESC, d.CreatedDate DESC;
        RETURN;
    END;

    /* ======================= SAVE ================================= */
    IF @Action = 'SAVE'
    BEGIN
        SET @DocumentNumber   = NULLIF(LTRIM(RTRIM(@DocumentNumber)), N'');
        SET @IssuingAuthority = NULLIF(LTRIM(RTRIM(@IssuingAuthority)), N'');
        SET @Notes            = NULLIF(LTRIM(RTRIM(@Notes)), N'');

        DECLARE @Current BIGINT, @CurCompany INT, @CurType INT, @CurExpiry DATE;
        IF ISNULL(@Id, 0) > 0
        BEGIN
            SELECT @Current = d.OrgDocumentId, @CurCompany = d.CompanyId, @CurType = d.OrgDocumentTypeId, @CurExpiry = d.ExpiryDate
            FROM   [Documents].[OrganizationDocuments] d JOIN @Co co ON co.CompanyId = d.CompanyId
            WHERE  d.OrgDocumentId = @Id AND d.Deleted = 0 AND d.State = 'C';
            IF @Current IS NULL
            BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That document was not found. Refresh and try again.'; RETURN; END;
            SELECT @CompanyId = @CurCompany, @OrgDocumentTypeId = @CurType;
        END;
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM @Co WHERE CompanyId = @CompanyId)
            BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That company was not found.'; RETURN; END;
            /* one current document per type: adding to a type that has one changes it */
            SELECT @Current = d.OrgDocumentId, @CurExpiry = d.ExpiryDate
            FROM   [Documents].[OrganizationDocuments] d
            WHERE  d.CompanyId = @CompanyId AND d.OrgDocumentTypeId = @OrgDocumentTypeId AND d.Deleted = 0 AND d.State = 'C';
            IF @Current IS NOT NULL AND ISNULL(@Renew, 0) = 0
            BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'This company already has this document - change it or renew it.'; RETURN; END;
        END;

        DECLARE @tNumber BIT, @tIssue BIT, @tExpiry BIT, @tAuthority NVARCHAR(150);
        SELECT @tNumber = t.HasNumber, @tIssue = t.HasIssueDate, @tExpiry = t.HasExpiryDate, @tAuthority = ia.AuthorityName
        FROM   [Documents].[OrganizationDocumentTypes] t
        LEFT JOIN [Documents].[IssuingAuthorities] ia ON ia.IssuingAuthorityId = t.IssuingAuthorityId
        WHERE  t.OrgDocumentTypeId = @OrgDocumentTypeId AND t.Deleted = 0;
        /* the issuing authority is set on the document type (Setup); typed text only when it has none */
        SET @IssuingAuthority = ISNULL(@tAuthority, @IssuingAuthority);
        IF @tExpiry IS NULL
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That document type is not available any more.'; RETURN; END;
        IF @tNumber = 0 SET @DocumentNumber = NULL;
        IF @tIssue  = 0 SET @IssueDate = NULL;
        IF @tExpiry = 0 SET @ExpiryDate = NULL;
        IF @tExpiry = 1 AND @ExpiryDate IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the expiry date.'; RETURN; END;
        IF @ExpiryDate IS NOT NULL AND @IssueDate IS NOT NULL AND @ExpiryDate < @IssueDate
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The expiry date must be on or after the issue date.'; RETURN; END;
        IF ISNULL(@Renew, 0) = 1 AND @Current IS NOT NULL AND @CurExpiry IS NOT NULL AND @ExpiryDate IS NOT NULL AND @ExpiryDate <= @CurExpiry
        BEGIN SELECT @ResultCode = 'VALIDATION',
                     @ResultMessage = CONCAT(N'The renewed document must expire after the current one (', FORMAT(@CurExpiry, 'dd MMM yyyy', 'en-US'), N').');
              RETURN; END;

        DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
        BEGIN TRANSACTION;

        IF ISNULL(@Renew, 0) = 1 OR @Current IS NULL
        BEGIN
            /* a renewal keeps the previous document as history */
            IF @Current IS NOT NULL
                UPDATE [Documents].[OrganizationDocuments]
                   SET State = 'A', ArchivedBy = @UserId, ArchivedDate = @Now
                 WHERE OrgDocumentId = @Current;

            INSERT INTO [Documents].[OrganizationDocuments]
                (CompanyId, OrgDocumentTypeId, State, DocumentNumber, IssuingAuthority, IssueDate, ExpiryDate, Notes,
                 OriginalFileName, StoredFileName, ContentType, FileSizeBytes, CreatedBy)
            VALUES (@CompanyId, @OrgDocumentTypeId, 'C', @DocumentNumber, @IssuingAuthority, @IssueDate, @ExpiryDate, @Notes,
                    @OriginalFileName, @StoredFileName, @ContentType, @FileSizeBytes, @UserId);
            SET @NewId = SCOPE_IDENTITY();
            SET @ResultMessage = CASE WHEN @Current IS NOT NULL THEN N'Document renewed - the previous one is kept in its history.'
                                      ELSE N'Document saved.' END;
        END;
        ELSE
        BEGIN
            UPDATE [Documents].[OrganizationDocuments]
               SET DocumentNumber = @DocumentNumber, IssuingAuthority = @IssuingAuthority, IssueDate = @IssueDate,
                   ExpiryDate = @ExpiryDate, Notes = @Notes,
                   OriginalFileName = CASE WHEN @StoredFileName IS NOT NULL THEN @OriginalFileName WHEN @RemoveFile = 1 THEN NULL ELSE OriginalFileName END,
                   StoredFileName   = CASE WHEN @StoredFileName IS NOT NULL THEN @StoredFileName   WHEN @RemoveFile = 1 THEN NULL ELSE StoredFileName END,
                   ContentType      = CASE WHEN @StoredFileName IS NOT NULL THEN @ContentType      WHEN @RemoveFile = 1 THEN NULL ELSE ContentType END,
                   FileSizeBytes    = CASE WHEN @StoredFileName IS NOT NULL THEN @FileSizeBytes    WHEN @RemoveFile = 1 THEN NULL ELSE FileSizeBytes END,
                   ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE OrgDocumentId = @Current;
            SELECT @NewId = @Current, @ResultMessage = N'Document saved.';
        END;

        COMMIT TRANSACTION;
        RETURN;
    END;

    /* ======================= DELETE =============================== */
    IF @Action = 'DELETE'
    BEGIN
        UPDATE d
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
          FROM [Documents].[OrganizationDocuments] d
          JOIN @Co co ON co.CompanyId = d.CompanyId
         WHERE d.OrgDocumentId = @Id AND d.Deleted = 0;
        IF @@ROWCOUNT = 0
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That document was already removed. Refresh and try again.'; RETURN; END;
        SELECT @NewId = @Id, @ResultMessage = N'Document removed.';
        RETURN;
    END;

    /* ======================= DUE ================================== */
    /* current documents whose expiry date reached one of the type's alerts (an expired one stays due) */
    IF @Action = 'DUE'
    BEGIN
        SELECT TOP (200)
                co.CompanyId, co.CompanyName, t.OrgDocumentTypeId, t.TypeName, t.ArabicName, t.Category,
                d.OrgDocumentId, d.DocumentNumber, d.ExpiryDate,
                DATEDIFF(DAY, @Today, d.ExpiryDate) AS DaysLeft,
                hit.RuleValue AS FiredRule
        FROM    [Documents].[OrganizationDocuments] d
        JOIN    @Co co ON co.CompanyId = d.CompanyId
        JOIN    [Documents].[OrganizationDocumentTypes] t ON t.OrgDocumentTypeId = d.OrgDocumentTypeId AND t.Deleted = 0 AND t.IsActive = 1
        CROSS APPLY (
            SELECT TOP (1) r.value AS RuleValue
            FROM   STRING_SPLIT(ISNULL(t.AlertRules, ''), ',') r
            CROSS APPLY (SELECT CASE LEFT(r.value, 1) WHEN 'M' THEN DATEADD(MONTH, -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), d.ExpiryDate)
                                                      WHEN 'W' THEN DATEADD(WEEK,  -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), d.ExpiryDate)
                                                      ELSE          DATEADD(DAY,   -TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT), d.ExpiryDate) END AS FiresOn) f
            WHERE  LEN(r.value) >= 2 AND TRY_CAST(SUBSTRING(r.value, 2, 3) AS INT) IS NOT NULL AND f.FiresOn <= @Today
            ORDER BY f.FiresOn DESC
        ) AS hit
        WHERE   d.Deleted = 0 AND d.State = 'C' AND d.ExpiryDate IS NOT NULL AND t.HasExpiryDate = 1
        ORDER BY d.ExpiryDate, co.CompanyName, t.TypeName;
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ------------------------------------------------------------------
   4. Documents.usp_IssuingAuthority_Manage - the dropdown
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Documents].[usp_IssuingAuthority_Manage]
    @Action         VARCHAR(10),
    @NewId          BIGINT          = NULL OUTPUT,
    @ResultCode     VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0;
    IF @Action = 'LIST'
    BEGIN
        SELECT IssuingAuthorityId, AuthorityName, ArabicName, ShortName, IsGovernment, IsActive
        FROM   [Documents].[IssuingAuthorities]
        WHERE  Deleted = 0
        ORDER BY ISNULL(SortOrder, 2147483647), AuthorityName;
        RETURN;
    END;
    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

PRINT N'75_Organization_Issuing_Authorities complete.';
GO
SET NOEXEC OFF;
GO
