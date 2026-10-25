/* =====================================================================
   73_Organization_Documents.sql  -  HRMS: Legal & Compliance Documents
   ---------------------------------------------------------------------
   Run after 28 (soft delete) and 63. Safe to re-run. Then run 74 (labels).

   Each active company (organization) keeps its legal and compliance
   documents - commercial licence, commercial registration, authorised
   signatory, PAM file ... - with their number, dates and a scan, and an
   alert before each expiry date.

     1. Documents.OrganizationDocumentTypes  what can be kept (Setup >
        Organization > Organization Documents): name, category, which
        fields apply, mandatory, and the ALERTS on the expiry date
        ('M3,M1,W1' = 3 months, 1 month and 1 week before; D0 = on the day)
     2. Documents.OrganizationDocuments      one company's document; a
        renewal archives the previous one (State A) and adds the new one
        (State C) - one current per company + type
     3. Documents.usp_OrgDocumentType_Manage the Setup tab (master envelope)
     4. Documents.usp_OrgDocument_Manage
          COMPANIES  the active companies with their document health
          LIST       one company: every active type with its current document
          GET        one document (any state)
          SAVE       add / change / renew (@Renew = 1 archives the current one)
          DELETE     soft delete
          HISTORY    one company + type: current and archived
          DUE        documents whose expiry date reached an alert (Dashboard);
                     an expired document stays due until it is renewed
     5. Permissions ORG_DOCUMENT_VIEW / _EDIT / _DELETE (System Administrator)
     6. Kuwait starter types (only when there are none)

   Nothing is ever physically deleted (db/28).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Documents')
    EXEC (N'CREATE SCHEMA [Documents]');
GO

/* ------------------------------------------------------------------
   1. Documents.OrganizationDocumentTypes
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Documents].[OrganizationDocumentTypes]', N'U') IS NULL
BEGIN
    CREATE TABLE [Documents].[OrganizationDocumentTypes](
        OrgDocumentTypeId  INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_OrganizationDocumentTypes PRIMARY KEY,
        TypeName           NVARCHAR(150)  NOT NULL,
        ArabicName         NVARCHAR(150)  NULL,
        /* LICENSE, REGISTRATION, AUTHORIZATION, CONTRACT, INSURANCE, OTHER - groups and colours on screen */
        Category           VARCHAR(20)    NOT NULL CONSTRAINT DF_OrgDocTypes_Category DEFAULT ('OTHER'),
        IsMandatory        BIT            NOT NULL CONSTRAINT DF_OrgDocTypes_Mandatory DEFAULT (0),
        HasNumber          BIT            NOT NULL CONSTRAINT DF_OrgDocTypes_HasNumber DEFAULT (1),
        HasIssueDate       BIT            NOT NULL CONSTRAINT DF_OrgDocTypes_HasIssue DEFAULT (1),
        HasExpiryDate      BIT            NOT NULL CONSTRAINT DF_OrgDocTypes_HasExpiry DEFAULT (1),
        /* alerts before the expiry date: M = months, W = weeks, D = days; 'M3,M1,W1,D0' */
        AlertRules         VARCHAR(60)    NULL,
        SortOrder          INT            NULL,
        IsActive           BIT            NOT NULL CONSTRAINT DF_OrgDocTypes_IsActive DEFAULT (1),
        CreatedBy          BIGINT         NULL,
        CreatedDate        DATETIME2(0)   NOT NULL CONSTRAINT DF_OrgDocTypes_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy         BIGINT         NULL,
        ModifiedDate       DATETIME2(0)   NULL,
        Deleted            BIT            NOT NULL CONSTRAINT DF_OrgDocTypes_Deleted DEFAULT (0),
        DeletedBy          BIGINT         NULL,
        DeletedDate        DATETIME2(0)   NULL,
        CONSTRAINT CK_OrgDocTypes_Category CHECK (Category IN ('LICENSE', 'REGISTRATION', 'AUTHORIZATION', 'CONTRACT', 'INSURANCE', 'OTHER'))
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_OrgDocTypes_Name ON [Documents].[OrganizationDocumentTypes] (TypeName) WHERE Deleted = 0;');
    PRINT N'Created [Documents].[OrganizationDocumentTypes].';
END
GO

/* ------------------------------------------------------------------
   2. Documents.OrganizationDocuments
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Documents].[OrganizationDocuments]', N'U') IS NULL
BEGIN
    CREATE TABLE [Documents].[OrganizationDocuments](
        OrgDocumentId      BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_OrganizationDocuments PRIMARY KEY,
        CompanyId          INT            NOT NULL,
        OrgDocumentTypeId  INT            NOT NULL,
        State              CHAR(1)        NOT NULL CONSTRAINT DF_OrgDocs_State DEFAULT ('C'),   -- C current, A archived (renewed)
        DocumentNumber     NVARCHAR(100)  NULL,
        IssuingAuthority   NVARCHAR(150)  NULL,
        IssueDate          DATE           NULL,
        ExpiryDate         DATE           NULL,
        Notes              NVARCHAR(500)  NULL,
        /* the scan (optional): path relative to DocumentStorage:RootPath */
        OriginalFileName   NVARCHAR(260)  NULL,
        StoredFileName     NVARCHAR(400)  NULL,
        ContentType        NVARCHAR(100)  NULL,
        FileSizeBytes      BIGINT         NULL,
        ArchivedBy         BIGINT         NULL,
        ArchivedDate       DATETIME2(0)   NULL,
        CreatedBy          BIGINT         NULL,
        CreatedDate        DATETIME2(0)   NOT NULL CONSTRAINT DF_OrgDocs_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy         BIGINT         NULL,
        ModifiedDate       DATETIME2(0)   NULL,
        Deleted            BIT            NOT NULL CONSTRAINT DF_OrgDocs_Deleted DEFAULT (0),
        DeletedBy          BIGINT         NULL,
        DeletedDate        DATETIME2(0)   NULL,
        CONSTRAINT FK_OrgDocs_Company FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_OrgDocs_Type    FOREIGN KEY (OrgDocumentTypeId) REFERENCES [Documents].[OrganizationDocumentTypes](OrgDocumentTypeId),
        CONSTRAINT CK_OrgDocs_State   CHECK (State IN ('C', 'A')),
        CONSTRAINT CK_OrgDocs_Dates   CHECK (ExpiryDate IS NULL OR IssueDate IS NULL OR ExpiryDate >= IssueDate)
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_OrgDocs_Current ON [Documents].[OrganizationDocuments] (CompanyId, OrgDocumentTypeId) WHERE Deleted = 0 AND State = ''C'';');
    EXEC (N'CREATE NONCLUSTERED INDEX IX_OrgDocs_Expiry ON [Documents].[OrganizationDocuments] (ExpiryDate) INCLUDE (CompanyId, OrgDocumentTypeId) WHERE Deleted = 0 AND State = ''C'';');
    PRINT N'Created [Documents].[OrganizationDocuments].';
END
GO

/* ------------------------------------------------------------------
   3. Documents.usp_OrgDocumentType_Manage - Setup > Organization tab
      (the master envelope every Organization Setup tab uses)
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
                    (SELECT COUNT(1) FROM [Documents].[OrganizationDocuments] d
                      WHERE d.OrgDocumentTypeId = t.OrgDocumentTypeId AND d.Deleted = 0 AND d.State = 'C') AS UsageCount,
                    CASE t.Category WHEN 'LICENSE' THEN 1 WHEN 'REGISTRATION' THEN 2 WHEN 'AUTHORIZATION' THEN 3
                                    WHEN 'CONTRACT' THEN 4 WHEN 'INSURANCE' THEN 5 ELSE 6 END AS CategorySeq
            FROM    [Documents].[OrganizationDocumentTypes] AS t
            WHERE   t.Deleted = 0
              AND   (@Action = 'LIST' OR t.OrgDocumentTypeId = @Id)
              AND   (@IsActiveFilter IS NULL OR t.IsActive = @IsActiveFilter)
              AND   (@Search IS NULL OR t.TypeName LIKE N'%' + @Search + N'%' OR t.ArabicName LIKE N'%' + @Search + N'%')
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
               AlertRules, SortOrder, IsActive, UsageCount
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
        IF EXISTS (SELECT 1 FROM [Documents].[OrganizationDocumentTypes]
                   WHERE Deleted = 0 AND TypeName = @TypeName AND OrgDocumentTypeId <> ISNULL(@Id, 0))
        BEGIN SELECT @ResultCode = 'DUPLICATE_NAME', @ResultMessage = N'An organization document type with this name already exists.'; RETURN; END;

        IF @Action = 'INSERT'
        BEGIN
            INSERT INTO [Documents].[OrganizationDocumentTypes]
                (TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate, AlertRules, SortOrder, IsActive, CreatedBy)
            VALUES (@TypeName, @ArabicName, @Category, ISNULL(@IsMandatory, 0), ISNULL(@HasNumber, 1), ISNULL(@HasIssueDate, 1),
                    ISNULL(@HasExpiryDate, 1), @AlertRules,
                    ISNULL(@SortOrder, (SELECT ISNULL(MAX(SortOrder), 0) + 1 FROM [Documents].[OrganizationDocumentTypes] WHERE Deleted = 0)),
                    ISNULL(@IsActive, 1), @UserId);
            SELECT @NewId = SCOPE_IDENTITY(), @ResultMessage = N'Organization document type added.';
            RETURN;
        END;

        UPDATE [Documents].[OrganizationDocumentTypes]
           SET TypeName = @TypeName, ArabicName = @ArabicName, Category = @Category, IsMandatory = ISNULL(@IsMandatory, 0),
               HasNumber = ISNULL(@HasNumber, 1), HasIssueDate = ISNULL(@HasIssueDate, 1), HasExpiryDate = ISNULL(@HasExpiryDate, 1),
               AlertRules = @AlertRules, SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, IsActive),
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

/* ------------------------------------------------------------------
   4. Documents.usp_OrgDocument_Manage - Workforce > Organizations
   ------------------------------------------------------------------ */
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

        DECLARE @tNumber BIT, @tIssue BIT, @tExpiry BIT;
        SELECT @tNumber = HasNumber, @tIssue = HasIssueDate, @tExpiry = HasExpiryDate
        FROM   [Documents].[OrganizationDocumentTypes] WHERE OrgDocumentTypeId = @OrgDocumentTypeId AND Deleted = 0;
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
   5. Permissions (System Administrator, the first time)
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action) VALUES
    ('ORG_DOCUMENT_VIEW',   'Organization', 'DocumentView'),
    ('ORG_DOCUMENT_EDIT',   'Organization', 'DocumentEdit'),
    ('ORG_DOCUMENT_DELETE', 'Organization', 'DocumentDelete');

UPDATE c SET IsNew = 1 FROM #Codes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #Codes c WHERE c.IsNew = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] r
JOIN   [Security].[Permissions] p ON p.Deleted = 0
JOIN   #Codes c ON c.PermissionCode = p.PermissionCode AND c.IsNew = 1
WHERE  r.RoleCode = N'SYSADMIN' AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);

DECLARE @CodesCreated INT = (SELECT COUNT(1) FROM #Codes WHERE IsNew = 1);
PRINT CONCAT(N'Organization document permission codes created: ', @CodesCreated);
DROP TABLE #Codes;
GO

/* ------------------------------------------------------------------
   6. Kuwait starter types (only when there are none) - change freely
   ------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM [Documents].[OrganizationDocumentTypes] WHERE Deleted = 0)
BEGIN
    INSERT INTO [Documents].[OrganizationDocumentTypes]
        (TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate, AlertRules, SortOrder)
    VALUES
        (N'Commercial License',                N'الرخصة التجارية',                     'LICENSE',       1, 1, 1, 1, 'M3,M1,W2,D0', 1),
        (N'Municipality License',              N'رخصة البلدية',                        'LICENSE',       0, 1, 1, 1, 'M2,M1,W1',    2),
        (N'Civil Defense Certificate',         N'شهادة الدفاع المدني',                 'LICENSE',       0, 1, 1, 1, 'M2,M1,W1',    3),
        (N'Commercial Registration',           N'السجل التجاري',                       'REGISTRATION',  1, 1, 1, 1, 'M3,M1,W2,D0', 4),
        (N'Chamber of Commerce Membership',    N'عضوية غرفة تجارة وصناعة الكويت',      'REGISTRATION',  1, 1, 1, 1, 'M2,M1,W1',    5),
        (N'PAM Company File (Manpower)',       N'ملف الشركة - الهيئة العامة للقوى العاملة', 'REGISTRATION', 1, 1, 1, 1, 'M3,M1,W2', 6),
        (N'PIFSS Employer Registration',       N'تسجيل صاحب العمل - المؤسسة العامة للتأمينات الاجتماعية', 'REGISTRATION', 1, 1, 1, 0, NULL, 7),
        (N'Authorized Signatory Certificate',  N'شهادة المفوض بالتوقيع',               'AUTHORIZATION', 1, 1, 1, 1, 'M2,M1,W1',    8),
        (N'Memorandum & Articles of Association', N'عقد التأسيس والنظام الأساسي',      'CONTRACT',      1, 0, 1, 0, NULL,          9),
        (N'Office Lease Agreement',            N'عقد إيجار المكتب',                    'CONTRACT',      0, 1, 1, 1, 'M3,M1',       10);
    PRINT N'Kuwait starter organization document types added - review them on Setup > Organization > Organization Documents.';
END
GO

PRINT N'73_Organization_Documents complete.';
GO
