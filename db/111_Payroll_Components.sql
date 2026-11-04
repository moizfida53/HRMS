/* =====================================================================
   111_Payroll_Components.sql  -  Pay Items become Payroll Components (4 pages)
   ---------------------------------------------------------------------
   Run after db/38, db/57, db/107 and db/110. Safe to re-run. It replaces
   Payroll.usp_PayItem_Manage (db/38) and Core.usp_PendingApprovals (db/110):
   run this script again whenever one of those is run.

   The salary of the employment contract (Basic Salary + Allowances on the
   employee profile) is the default component: no approval, always paid
   (db/107). Everything else is an exception on one of four pages, each
   with its own rights and its own approval:

     Salary Revisions       SALARY     PAYROLL_SALREV_VIEW / _EDIT / _DELETE, APPROVE_L1 / _L2 / _SELF
     Earnings & Allowances  EARNING    PAYROLL_EARN_...
     Deductions             DEDUCTION  PAYROLL_DED_...
     Loans & Advances       LOAN       PAYROLL_LOAN_...

   First run: every role gets the new rights matching what it had on Pay
   Items (PAYROLL_ITEM_VIEW -> the four _VIEW, CREATE / EDIT -> _EDIT,
   DELETE -> _DELETE, APPROVE_L1 / _L2 / _SELF -> the same on all four);
   System Administrator gets them all.

   A role can also be LIMITED TO CHOSEN ITEM TYPES of a page (e.g. only
   Overtime in Earnings & Allowances) - Security.RoleComponentTypes, by
   pay component code. A page without ticks = every item type of it. A user
   sees an item type when one of their roles giving the page allows it.

   An approved salary revision is applied to the employee profile
   (Employee.EmployeePayroll): Basic Salary = the Basic Salary component,
   Allowances = the other salary components (Payroll.usp_SalaryRevision_Apply).

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[usp_PayItem_Manage]', N'P') IS NULL OR OBJECT_ID(N'[Security].[RolePermissions]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/38 and db/57 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the rights of the four pages (first run: from the Pay Items rights) ---- */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, FromCode1 VARCHAR(60) COLLATE DATABASE_DEFAULT,
                     FromCode2 VARCHAR(60) COLLATE DATABASE_DEFAULT NULL, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action, FromCode1, FromCode2)
SELECT CONCAT('PAYROLL_', p.Prefix, '_', a.Suffix), CONCAT('PayrollComponent', p.Prefix), a.Suffix, a.From1, a.From2
FROM  (VALUES ('SALREV'), ('EARN'), ('DED'), ('LOAN')) AS p(Prefix)
CROSS JOIN (VALUES ('VIEW', 'PAYROLL_ITEM_VIEW', NULL),
                   ('EDIT', 'PAYROLL_ITEM_CREATE', 'PAYROLL_ITEM_EDIT'),
                   ('DELETE', 'PAYROLL_ITEM_DELETE', NULL),
                   ('APPROVE_L1', 'PAYROLL_ITEM_APPROVE_L1', NULL),
                   ('APPROVE_L2', 'PAYROLL_ITEM_APPROVE_L2', NULL),
                   ('APPROVE_SELF', 'PAYROLL_ITEM_APPROVE_SELF', NULL)) AS a(Suffix, From1, From2);

UPDATE c SET IsNew = 1 FROM #Codes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #Codes c WHERE c.IsNew = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT DISTINCT r.RoleId, p.PermissionId
FROM   #Codes c
JOIN   [Security].[Permissions] p ON p.PermissionCode = c.PermissionCode AND p.Deleted = 0
JOIN   [Security].[Roles] r ON r.Deleted = 0
WHERE  c.IsNew = 1
  AND (r.RoleCode = N'SYSADMIN'
       OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                  WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode IN (c.FromCode1, c.FromCode2)))
  AND NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);

DECLARE @RightsGranted INT = @@ROWCOUNT;
DECLARE @RightsCreated INT = (SELECT COUNT(1) FROM #Codes WHERE IsNew = 1);
PRINT CONCAT(N'Payroll component rights created: ', @RightsCreated, N', granted: ', @RightsGranted);
DROP TABLE #Codes;
GO

/* ---- 2. a role limited to chosen item types of a page ---------------------- */
IF OBJECT_ID(N'[Security].[RoleComponentTypes]', N'U') IS NULL
BEGIN
    CREATE TABLE [Security].[RoleComponentTypes](
        RoleComponentTypeId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RoleComponentTypes PRIMARY KEY,
        RoleId               INT            NOT NULL,
        ItemClass            VARCHAR(10)    NOT NULL,     -- SALARY / EARNING / DEDUCTION / LOAN (the page)
        ComponentCode        NVARCHAR(30)   NOT NULL,     -- Payroll.PayComponents.ComponentCode (every company)
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_RoleComponentTypes_Created DEFAULT (SYSUTCDATETIME()),
        Deleted              BIT            NOT NULL CONSTRAINT DF_Security_RoleComponentTypes_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,
        CONSTRAINT FK_RoleComponentTypes_Role FOREIGN KEY (RoleId) REFERENCES [Security].[Roles](RoleId),
        CONSTRAINT CK_RoleComponentTypes_Class CHECK (ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN'))
    );
    CREATE INDEX IX_RoleComponentTypes_Role ON [Security].[RoleComponentTypes](RoleId, ItemClass) WHERE Deleted = 0;
END;
GO

/* What item types of each page a user may work with: one row per page they can open -
   Unrestricted = 1 (every type), else one row per type allowed (ComponentCode). */
CREATE OR ALTER FUNCTION [Security].[tvf_UserComponentTypes] (@UserId BIGINT)
RETURNS TABLE
AS
RETURN
WITH pg AS (
    SELECT * FROM (VALUES ('SALARY', 'PAYROLL_SALREV_VIEW'), ('EARNING', 'PAYROLL_EARN_VIEW'),
                          ('DEDUCTION', 'PAYROLL_DED_VIEW'), ('LOAN', 'PAYROLL_LOAN_VIEW')) AS v(ItemClass, ViewCode)
), roles AS (
    /* the user's roles that open the page (System Administrator opens every page) */
    SELECT DISTINCT r.RoleId, pg.ItemClass, CAST(CASE WHEN r.RoleCode = N'SYSADMIN' THEN 1 ELSE 0 END AS BIT) AS IsAdmin
    FROM   [Security].[UserRoles] AS ur
    JOIN   [Security].[Roles] AS r ON r.RoleId = ur.RoleId AND r.Deleted = 0
    CROSS JOIN pg
    WHERE  ur.UserId = @UserId AND ur.Deleted = 0
      AND (r.RoleCode = N'SYSADMIN'
           OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] AS rp
                      JOIN [Security].[Permissions] AS p ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
                      WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND p.PermissionCode IN (pg.ViewCode, 'SYSTEM_ADMIN')))
), lim AS (
    SELECT ro.RoleId, ro.ItemClass, ro.IsAdmin,
           CAST(CASE WHEN ro.IsAdmin = 0 AND EXISTS (SELECT 1 FROM [Security].[RoleComponentTypes] AS t
                                                     WHERE t.RoleId = ro.RoleId AND t.ItemClass = ro.ItemClass AND t.Deleted = 0)
                     THEN 1 ELSE 0 END AS BIT) AS IsLimited
    FROM   roles AS ro
)
SELECT ItemClass, CAST(NULL AS NVARCHAR(30)) AS ComponentCode, CAST(1 AS BIT) AS Unrestricted
FROM   lim GROUP BY ItemClass HAVING MIN(CAST(IsLimited AS INT)) = 0
UNION ALL
SELECT DISTINCT t.ItemClass, t.ComponentCode, CAST(0 AS BIT)
FROM   lim
JOIN   [Security].[RoleComponentTypes] AS t ON t.RoleId = lim.RoleId AND t.ItemClass = lim.ItemClass AND t.Deleted = 0
WHERE  lim.IsLimited = 1
  AND  NOT EXISTS (SELECT 1 FROM lim AS l2 WHERE l2.ItemClass = lim.ItemClass AND l2.IsLimited = 0);
GO

/* TYPES the item types to choose from (every company, by code) - ROLE_GET a role's ticks -
   ROLE_SET replace them (@Codes = CSV of CLASS:CODE) - USER the item types a user may work with */
CREATE OR ALTER PROCEDURE [Security].[usp_RoleComponentTypes]
    @Action   VARCHAR(10),
    @RoleId   INT            = NULL,
    @UserId   BIGINT         = NULL,
    @Codes    NVARCHAR(MAX)  = NULL,
    @ActionBy BIGINT         = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Action = 'TYPES'
    BEGIN
        SELECT  c.ItemClass, c.ComponentCode, MIN(c.ComponentName) AS ComponentName, MIN(c.ArabicName) AS ArabicName, MIN(c.DisplayOrder) AS DisplayOrder
        FROM    [Payroll].[PayComponents] AS c
        WHERE   c.Deleted = 0 AND c.IsActive = 1 AND c.ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN')
        GROUP BY c.ItemClass, c.ComponentCode
        ORDER BY c.ItemClass, MIN(c.DisplayOrder), c.ComponentCode;
        RETURN;
    END;

    IF @Action = 'ROLE_GET'
    BEGIN
        SELECT ItemClass, ComponentCode FROM [Security].[RoleComponentTypes] WHERE RoleId = @RoleId AND Deleted = 0;
        RETURN;
    END;

    IF @Action = 'ROLE_SET'
    BEGIN
        DECLARE @New TABLE (ItemClass VARCHAR(10), ComponentCode NVARCHAR(30), PRIMARY KEY (ItemClass, ComponentCode));
        INSERT INTO @New (ItemClass, ComponentCode)
        /* "CLASS:CODE" values; the position is worked out once and never negative (an empty
           value, or one without ":", gives an empty class and is left out) */
        SELECT DISTINCT x.Cls, x.Code
        FROM  (SELECT LTRIM(RTRIM(value)) AS v FROM STRING_SPLIT(ISNULL(@Codes, N''), N',')) AS s
        CROSS APPLY (SELECT CHARINDEX(':', s.v) AS Pos) AS c
        CROSS APPLY (SELECT LEFT(s.v, CASE WHEN c.Pos > 1 THEN c.Pos - 1 ELSE 0 END) AS Cls,
                            SUBSTRING(s.v, CASE WHEN c.Pos > 1 THEN c.Pos + 1 ELSE 1 END, 30) AS Code) AS x
        WHERE  c.Pos > 1 AND x.Cls IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN') AND LEN(x.Code) > 0;

        BEGIN TRANSACTION;
            UPDATE t SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = SYSUTCDATETIME()
            FROM   [Security].[RoleComponentTypes] AS t
            WHERE  t.RoleId = @RoleId AND t.Deleted = 0
              AND  NOT EXISTS (SELECT 1 FROM @New n WHERE n.ItemClass = t.ItemClass AND n.ComponentCode = t.ComponentCode);
            INSERT INTO [Security].[RoleComponentTypes] (RoleId, ItemClass, ComponentCode, CreatedBy)
            SELECT @RoleId, n.ItemClass, n.ComponentCode, @ActionBy
            FROM   @New n
            WHERE  NOT EXISTS (SELECT 1 FROM [Security].[RoleComponentTypes] t
                               WHERE t.RoleId = @RoleId AND t.Deleted = 0 AND t.ItemClass = n.ItemClass AND t.ComponentCode = n.ComponentCode);
        COMMIT TRANSACTION;
        RETURN;
    END;

    IF @Action = 'USER'
    BEGIN
        SELECT ItemClass, ComponentCode, Unrestricted FROM [Security].[tvf_UserComponentTypes](@UserId);
        RETURN;
    END;
END;
GO

/* ---- 3. an approved salary revision updates the employee profile ----------- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_SalaryRevision_Apply]
    @PayItemId  BIGINT,
    @UserId     BIGINT = NULL,
    @Applied    BIT    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Applied = 0;

    DECLARE @Emp BIGINT;
    SELECT @Emp = i.EmployeeId
    FROM   [Payroll].[EmployeePayItems] AS i
    JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
    WHERE  i.EmployeePayItemId = @PayItemId AND i.Deleted = 0 AND i.Status = 'ACTIVE' AND c.ItemClass = 'SALARY';
    IF @Emp IS NULL RETURN;      -- not (yet) an approved salary item

    /* the salary in force from now on: the latest approved amount of each salary component */
    DECLARE @Basic DECIMAL(12,3), @Allow DECIMAL(12,3);
    ;WITH cur AS (
        SELECT c.ComponentCode, i.Amount,
               ROW_NUMBER() OVER (PARTITION BY i.PayComponentId ORDER BY i.StartMonth DESC, i.EmployeePayItemId DESC) AS rn
        FROM   [Payroll].[EmployeePayItems] AS i
        JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
        WHERE  i.EmployeeId = @Emp AND i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
          AND  c.ItemClass = 'SALARY' AND i.AppliesMode = 'MONTHLY'
          AND  (i.EndMonth IS NULL OR i.EndMonth >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1))
    )
    SELECT @Basic = SUM(CASE WHEN ComponentCode = N'BASIC' THEN Amount END),
           @Allow = SUM(CASE WHEN ComponentCode <> N'BASIC' THEN Amount END)
    FROM   cur WHERE rn = 1;

    IF EXISTS (SELECT 1 FROM [Employee].[EmployeePayroll] WHERE EmployeeId = @Emp)
        UPDATE [Employee].[EmployeePayroll]
           SET BasicSalary = ISNULL(@Basic, BasicSalary), Allowances = ISNULL(@Allow, 0),
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        WHERE  EmployeeId = @Emp;
    ELSE
        INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, Allowances, CreatedBy)
        VALUES (@Emp, @Basic, ISNULL(@Allow, 0), @UserId);
    SET @Applied = 1;
END;
GO

/* ---- 4. what waits for the user's approval (db/110), per component page ---- */
CREATE OR ALTER PROCEDURE [Core].[usp_PendingApprovals]
    @UserId      BIGINT,
    @EmployeeId  BIGINT          = NULL,
    @CompanyId   INT             = NULL,
    @CompanyIds  NVARCHAR(2000)  = NULL,
    @PrL1 BIT = 0, @PrL2 BIT = 0, @PrSelf BIT = 0,
    @SrL1 BIT = 0, @SrL2 BIT = 0, @SrSelf BIT = 0,      -- Salary Revisions
    @ErL1 BIT = 0, @ErL2 BIT = 0, @ErSelf BIT = 0,      -- Earnings & Allowances
    @DdL1 BIT = 0, @DdL2 BIT = 0, @DdSelf BIT = 0,      -- Deductions
    @LnL1 BIT = 0, @LnL2 BIT = 0, @LnSelf BIT = 0,      -- Loans & Advances
    @FsL1 BIT = 0, @FsL2 BIT = 0, @FsSelf BIT = 0,
    @LvL1 BIT = 0, @LvL2 BIT = 0, @LvSelf BIT = 0,
    @IsAdmin BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Csv NVARCHAR(2010) = CASE WHEN NULLIF(LTRIM(RTRIM(@CompanyIds)), N'') IS NULL THEN NULL
                                       ELSE N',' + REPLACE(@CompanyIds, N' ', N'') + N',' END;
    DECLARE @R TABLE (Kind VARCHAR(20) PRIMARY KEY, Cnt INT NOT NULL, Oldest DATETIME2(0) NULL);

    IF (@PrL1 = 1 OR @PrL2 = 1)
        INSERT INTO @R (Kind, Cnt, Oldest)
        SELECT 'PAYROLL', COUNT(1), MIN(r.SubmittedDate)
        FROM   [Payroll].[PayrollRuns] AS r
        WHERE  r.Deleted = 0 AND r.Stage = 'AWAITING_APPROVAL'
          AND  (@CompanyId IS NULL OR r.CompanyId = @CompanyId)
          AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(r.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND  ((r.ApprovalLevel = 0 AND @PrL1 = 1) OR (r.ApprovalLevel = 1 AND @PrL2 = 1))
          AND  (@PrSelf = 1 OR r.SubmittedBy IS NULL OR r.SubmittedBy <> @UserId);

    /* the four component pages: only the item types the user may work with */
    ;WITH rt AS (
        SELECT * FROM (VALUES ('SALARY', 'SALREV', @SrL1, @SrL2, @SrSelf), ('EARNING', 'EARN', @ErL1, @ErL2, @ErSelf),
                              ('DEDUCTION', 'DED', @DdL1, @DdL2, @DdSelf), ('LOAN', 'LOAN', @LnL1, @LnL2, @LnSelf)) AS v(ItemClass, Kind, L1, L2, Self)
    ), allowed AS (
        SELECT * FROM [Security].[tvf_UserComponentTypes](@UserId)
    )
    INSERT INTO @R (Kind, Cnt, Oldest)
    SELECT rt.Kind, COUNT(1), MIN(i.SubmittedDate)
    FROM   [Payroll].[EmployeePayItems] AS i
    JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
    JOIN   rt ON rt.ItemClass = c.ItemClass
    WHERE  i.Deleted = 0 AND i.Status = 'PENDING'
      AND  (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
      AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(i.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
      AND  ((i.ApprovalLevel = 0 AND rt.L1 = 1) OR (i.ApprovalLevel = 1 AND rt.L2 = 1))
      AND  (rt.Self = 1 OR i.SubmittedBy IS NULL OR i.SubmittedBy <> @UserId)
      AND  (@IsAdmin = 1
            OR EXISTS (SELECT 1 FROM allowed a WHERE a.ItemClass = c.ItemClass AND (a.Unrestricted = 1 OR a.ComponentCode = c.ComponentCode)))
    GROUP BY rt.Kind;

    IF (@FsL1 = 1 OR @FsL2 = 1) AND OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NOT NULL
        INSERT INTO @R (Kind, Cnt, Oldest)
        SELECT 'SETTLEMENT', COUNT(1), MIN(s.SubmittedDate)
        FROM   [Payroll].[FinalSettlements] AS s
        WHERE  s.Deleted = 0 AND s.Status = 'PENDING'
          AND  (@CompanyId IS NULL OR s.CompanyId = @CompanyId)
          AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(s.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND  ((s.ApprovalLevel = 0 AND @FsL1 = 1) OR (s.ApprovalLevel = 1 AND @FsL2 = 1))
          AND  (@FsSelf = 1 OR s.SubmittedBy IS NULL OR s.SubmittedBy <> @UserId);

    IF OBJECT_ID(N'[Leave].[LeaveRequests]', N'U') IS NOT NULL
        INSERT INTO @R (Kind, Cnt, Oldest)
        SELECT 'LEAVE', COUNT(1), MIN(r.CreatedDate)
        FROM   [Leave].[LeaveRequests] AS r
        WHERE  r.Deleted = 0 AND r.Status = 'PENDING'
          AND  (@CompanyId IS NULL OR r.CompanyId = @CompanyId)
          AND  (@Csv IS NULL OR CHARINDEX(N',' + CAST(r.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND  ((r.ApprovalLevel = 1 AND (r.ManagerUserId = @UserId OR @LvL1 = 1)) OR (r.ApprovalLevel = 2 AND @LvL2 = 1))
          AND  (@LvSelf = 1 OR @EmployeeId IS NULL OR r.EmployeeId <> @EmployeeId);

    SELECT Kind, Cnt AS [Count], Oldest FROM @R WHERE Cnt > 0 ORDER BY Kind;
END;
GO

/* ---- 5. Payroll.usp_PayItem_Manage (db/38) + @ComponentCodes on LIST ---- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayItem_Manage]
    @Action             VARCHAR(20),
    @Id                 BIGINT          = NULL,

    /* scope and filters */
    @CompanyId          INT             = NULL,     -- the user's own company (company users)
    @CompanyIds         NVARCHAR(2000)  = NULL,     -- the company filter of the top bar
    @EmployeeId         BIGINT          = NULL,
    @ItemClass          VARCHAR(10)     = NULL,
    @ComponentCodes     NVARCHAR(MAX)   = NULL,     -- db/111 LIST: only these item types (CSV of codes; a user limited to some types)
    @StatusFilter       VARCHAR(10)     = NULL,     -- OPEN (active + pending, default), ACTIVE, PENDING, ENDED, ALL
    @Search             NVARCHAR(200)   = NULL,
    @Month              DATE            = NULL,
    @PageNumber         INT             = 1,
    @PageSize           INT             = 25,

    /* save */
    @PayComponentId     INT             = NULL,
    @Amount             DECIMAL(12,3)   = NULL,
    @AppliesMode        VARCHAR(10)     = NULL,
    @StartMonth         DATE            = NULL,
    @EndMonth           DATE            = NULL,
    @InstalmentCount    SMALLINT        = NULL,
    @TotalAmount        DECIMAL(12,3)   = NULL,
    @Comment            NVARCHAR(500)   = NULL,

    @AllowSelfApproval  BIT             = 0,
    @ExpectedLevel      TINYINT         = NULL,     -- APPROVE / REJECT: the level the user saw (stops a double approval)
    @UserId             BIGINT          = NULL,

    @TotalCount         INT             = NULL OUTPUT,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @CompanyIds = NULLIF(LTRIM(RTRIM(@CompanyIds)), N'');
    SET @ItemClass  = NULLIF(UPPER(LTRIM(RTRIM(@ItemClass))), '');
    SET @StatusFilter = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@StatusFilter))), ''), 'OPEN');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 10000 THEN 10000 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @ThisMonth DATE = DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1);
    SET @Month = ISNULL(DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1), @ThisMonth);

    IF @Action NOT IN ('LIST', 'GET', 'SUMMARY', 'EMP_SUMMARY', 'TYPES', 'EMPLOYEES', 'HISTORY', 'SAVE', 'APPROVE', 'REJECT', 'END', 'DELETE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* what has been paid of each item (live and closed payrolls) */
    DECLARE @Paid TABLE (EmployeePayItemId BIGINT PRIMARY KEY, PaidCount INT, PaidAmount DECIMAL(14,3), LastPaidMonth DATE);
    IF @Action IN ('LIST', 'GET', 'SUMMARY', 'EMP_SUMMARY')
        INSERT INTO @Paid
        SELECT l.EmployeePayItemId, COUNT(1), SUM(ABS(l.Amount)), MAX(r.RunMonth)
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   [Payroll].[PayrollRuns]     AS r ON r.PayrollRunId = l.PayrollRunId
        JOIN   [Payroll].[EmployeePayItems] AS i ON i.EmployeePayItemId = l.EmployeePayItemId
        WHERE  l.Deleted = 0 AND r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED') AND i.PayrollRunId IS NULL
          AND  (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
          AND  (@EmployeeId IS NULL OR i.EmployeeId = @EmployeeId OR @Action <> 'EMP_SUMMARY')
        GROUP BY l.EmployeePayItemId;

    /* ======================= LIST / GET ========================== */
    IF @Action IN ('LIST', 'GET')
    BEGIN
        IF OBJECT_ID('tempdb..#L') IS NOT NULL DROP TABLE #L;
        SELECT  i.EmployeePayItemId, i.CompanyId, co.CompanyName, i.EmployeeId, e.EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                i.PayComponentId, c.ComponentCode, c.ComponentName, c.ArabicName AS ComponentArabicName, c.ItemClass, c.SystemCode,
                i.Amount, i.AppliesMode, i.StartMonth, i.EndMonth, i.InstalmentCount, i.TotalAmount, i.Comment, i.Status,
                i.ApprovalLevel, i.SubmittedBy, i.SubmittedDate, i.ReplacesItemId, ri.Amount AS ReplacedAmount, i.SourceRef,
                i.CreatedBy, i.CreatedDate,
                ISNULL(p.PaidCount, 0) AS PaidCount, ISNULL(p.PaidAmount, 0) AS PaidAmount, p.LastPaidMonth,
                CASE WHEN i.AppliesMode = 'INSTALMENT' AND i.TotalAmount IS NOT NULL
                     THEN CASE WHEN i.TotalAmount - ISNULL(p.PaidAmount, 0) > 0 THEN i.TotalAmount - ISNULL(p.PaidAmount, 0) ELSE 0 END END AS Balance,
                CASE WHEN i.Status = 'ACTIVE' AND (
                             (i.AppliesMode = 'INSTALMENT' AND ISNULL(p.PaidCount, 0) >= i.InstalmentCount)
                          OR (i.AppliesMode = 'MONTHLY' AND i.EndMonth IS NOT NULL AND i.EndMonth < @ThisMonth)
                          OR (i.AppliesMode = 'ONCE' AND i.StartMonth < @ThisMonth AND ISNULL(p.PaidCount, 0) > 0))
                     THEN 'ENDED' ELSE i.Status END AS EffectiveStatus,
                CASE c.ItemClass WHEN 'SALARY' THEN 1 WHEN 'EARNING' THEN 2 WHEN 'DEDUCTION' THEN 3 ELSE 4 END AS ClassOrder,
                c.DisplayOrder
        INTO    #L
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents]    AS c  ON c.PayComponentId = i.PayComponentId
        JOIN    [Employee].[Employees]       AS e  ON e.EmployeeId = i.EmployeeId
        LEFT JOIN [Core].[Companies]         AS co ON co.CompanyId = i.CompanyId
        LEFT JOIN [Payroll].[EmployeePayItems] AS ri ON ri.EmployeePayItemId = i.ReplacesItemId
        LEFT JOIN @Paid AS p ON p.EmployeePayItemId = i.EmployeePayItemId
        WHERE   i.Deleted = 0 AND i.PayrollRunId IS NULL
          AND   (@CompanyId  IS NULL OR i.CompanyId = @CompanyId)
          AND   (   (@Action = 'GET' AND i.EmployeePayItemId = @Id)
                 OR (@Action = 'LIST'
                     AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(i.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
                     AND (@EmployeeId IS NULL OR i.EmployeeId = @EmployeeId)
                     AND (@ItemClass  IS NULL OR c.ItemClass = @ItemClass)
                     AND (@ComponentCodes IS NULL OR c.ComponentCode IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@ComponentCodes, N',')))
                     AND (@Pattern IS NULL OR e.EmployeeNo LIKE @Pattern ESCAPE '\' OR CONCAT(e.FirstName, N' ', e.LastName) LIKE @Pattern ESCAPE '\'
                          OR e.ArabicName LIKE @Pattern ESCAPE '\' OR c.ComponentName LIKE @Pattern ESCAPE '\' OR c.ArabicName LIKE @Pattern ESCAPE '\'
                          OR i.Comment LIKE @Pattern ESCAPE '\' OR i.SourceRef LIKE @Pattern ESCAPE '\')));

        IF @Action = 'LIST' AND @StatusFilter <> 'ALL'
            DELETE FROM #L WHERE NOT ((@StatusFilter = 'OPEN' AND EffectiveStatus IN ('ACTIVE', 'PENDING')) OR EffectiveStatus = @StatusFilter);

        SELECT @TotalCount = COUNT(1) FROM #L;
        SELECT * FROM #L
        ORDER BY EmployeeName, EmployeeNo, ClassOrder, DisplayOrder, StartMonth, EmployeePayItemId
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= SUMMARY (KPIs) ====================== */
    IF @Action = 'SUMMARY'
    BEGIN
        ;WITH base AS (
            SELECT i.*, c.ItemClass, ISNULL(p.PaidCount, 0) AS PaidCount, ISNULL(p.PaidAmount, 0) AS PaidAmount
            FROM   [Payroll].[EmployeePayItems] AS i
            JOIN   [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
            JOIN   [Employee].[Employees]       AS e ON e.EmployeeId = i.EmployeeId AND e.Deleted = 0 AND e.IsDeleted = 0
            LEFT JOIN @Paid AS p ON p.EmployeePayItemId = i.EmployeePayItemId
            WHERE  i.Deleted = 0 AND i.PayrollRunId IS NULL
              AND  (@CompanyId  IS NULL OR i.CompanyId = @CompanyId)
              AND  (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(i.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        ), sal AS (
            SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.EmployeeId, b.PayComponentId ORDER BY b.StartMonth DESC, b.EmployeePayItemId DESC) AS rn
            FROM   base AS b
            WHERE  b.ItemClass = 'SALARY' AND b.Status = 'ACTIVE' AND b.StartMonth <= @Month AND (b.EndMonth IS NULL OR b.EndMonth >= @Month)
        ), mon AS (
            SELECT b.*
            FROM   base AS b
            WHERE  b.Status = 'ACTIVE' AND b.ItemClass IN ('EARNING', 'DEDUCTION')
              AND  (   (b.AppliesMode = 'ONCE' AND b.StartMonth = @Month)
                    OR (b.AppliesMode = 'MONTHLY' AND b.StartMonth <= @Month AND (b.EndMonth IS NULL OR b.EndMonth >= @Month))
                    OR (b.AppliesMode = 'INSTALMENT' AND b.StartMonth <= @Month AND b.PaidCount < b.InstalmentCount))
        )
        SELECT  @Month AS SummaryMonth,
                (SELECT ISNULL(SUM(Amount), 0) FROM sal WHERE rn = 1)                 AS MonthlySalary,
                (SELECT COUNT(DISTINCT EmployeeId) FROM sal WHERE rn = 1)             AS SalaryEmployees,
                (SELECT COUNT(1) FROM sal WHERE rn = 1)                               AS SalaryItems,
                (SELECT ISNULL(SUM(Amount), 0) FROM mon WHERE ItemClass = 'EARNING')  AS Earnings,
                (SELECT COUNT(1) FROM mon WHERE ItemClass = 'EARNING')                AS EarningItems,
                (SELECT ISNULL(SUM(Amount), 0) FROM mon WHERE ItemClass = 'DEDUCTION') AS Deductions,
                (SELECT COUNT(1) FROM mon WHERE ItemClass = 'DEDUCTION')              AS DeductionItems,
                (SELECT ISNULL(SUM(CASE WHEN TotalAmount - PaidAmount > 0 THEN TotalAmount - PaidAmount ELSE 0 END), 0)
                   FROM base WHERE ItemClass = 'LOAN' AND Status = 'ACTIVE' AND PaidCount < InstalmentCount) AS LoanOutstanding,
                (SELECT COUNT(1) FROM base WHERE ItemClass = 'LOAN' AND Status = 'ACTIVE' AND PaidCount < InstalmentCount) AS LoansRunning,
                (SELECT COUNT(1) FROM base WHERE ItemClass = 'LOAN' AND Status = 'PENDING')  AS LoansPending,
                (SELECT COUNT(1) FROM base WHERE Status = 'PENDING')                         AS PendingApprovals;
        RETURN;
    END;

    /* ======================= EMP_SUMMARY ========================= */
    IF @Action = 'EMP_SUMMARY'
    BEGIN
        ;WITH base AS (
            SELECT i.*, c.ItemClass, ISNULL(p.PaidCount, 0) AS PaidCount, ISNULL(p.PaidAmount, 0) AS PaidAmount
            FROM   [Payroll].[EmployeePayItems] AS i
            JOIN   [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
            LEFT JOIN @Paid AS p ON p.EmployeePayItemId = i.EmployeePayItemId
            WHERE  i.Deleted = 0 AND i.PayrollRunId IS NULL AND i.EmployeeId = @EmployeeId
        ), sal AS (
            SELECT b.Amount, ROW_NUMBER() OVER (PARTITION BY b.PayComponentId ORDER BY b.StartMonth DESC, b.EmployeePayItemId DESC) AS rn
            FROM   base AS b
            WHERE  b.ItemClass = 'SALARY' AND b.Status = 'ACTIVE' AND b.StartMonth <= @Month AND (b.EndMonth IS NULL OR b.EndMonth >= @Month)
        )
        SELECT  e.EmployeeId, e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                e.CompanyId, d.DepartmentName, ds.DesignationName,
                (SELECT ISNULL(SUM(Amount), 0) FROM sal WHERE rn = 1) AS MonthlySalary,
                (SELECT ISNULL(SUM(CASE WHEN TotalAmount - PaidAmount > 0 THEN TotalAmount - PaidAmount ELSE 0 END), 0)
                   FROM base WHERE ItemClass = 'LOAN' AND Status = 'ACTIVE' AND PaidCount < InstalmentCount) AS LoanBalance,
                (SELECT ISNULL(SUM(TotalAmount), 0) FROM base WHERE ItemClass = 'LOAN' AND Status = 'PENDING') AS LoanPending,
                (SELECT ISNULL(SUM(Amount), 0) FROM base
                  WHERE Status = 'ACTIVE' AND ItemClass IN ('DEDUCTION', 'LOAN')
                    AND ((AppliesMode = 'MONTHLY' AND StartMonth <= @Month AND (EndMonth IS NULL OR EndMonth >= @Month))
                      OR (AppliesMode = 'INSTALMENT' AND StartMonth <= @Month AND PaidCount < InstalmentCount))) AS MonthlyDeductions,
                CASE WHEN NULLIF(LTRIM(RTRIM(ep.Iban)), N'') IS NULL THEN 0 ELSE 1 END AS HasIban,
                ep.BankName
        FROM    [Employee].[Employees] AS e
        LEFT JOIN [Core].[Departments]  AS d  ON d.DepartmentId = e.DepartmentId
        LEFT JOIN [Core].[Designations] AS ds ON ds.DesignationId = e.DesignationId
        LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId AND ep.Deleted = 0
        WHERE   e.EmployeeId = @EmployeeId AND e.Deleted = 0
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId);
        RETURN;
    END;

    /* ======================= TYPES / EMPLOYEES =================== */
    IF @Action = 'TYPES'
    BEGIN
        SELECT  c.PayComponentId, c.CompanyId, c.ComponentCode, c.ComponentName, c.ArabicName, c.ItemClass, c.SystemCode, c.IsActive
        FROM    [Payroll].[PayComponents] AS c
        WHERE   c.Deleted = 0 AND c.ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN')
          AND   (@CompanyId  IS NULL OR c.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(c.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        ORDER BY CASE c.ItemClass WHEN 'SALARY' THEN 1 WHEN 'EARNING' THEN 2 WHEN 'DEDUCTION' THEN 3 ELSE 4 END, c.DisplayOrder, c.ComponentName;
        RETURN;
    END;

    IF @Action = 'EMPLOYEES'
    BEGIN
        SELECT  e.EmployeeId, e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                e.CompanyId,
                CAST(CASE WHEN e.EmploymentStatus IN (N'Terminated', N'Resigned') THEN 0 ELSE 1 END AS BIT) AS IsActive
        FROM    [Employee].[Employees] AS e
        WHERE   e.Deleted = 0 AND e.IsDeleted = 0
          AND   (@CompanyId  IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        ORDER BY e.FirstName, e.LastName, e.EmployeeNo;
        RETURN;
    END;

    /* ======================= HISTORY ============================= */
    IF @Action = 'HISTORY'
    BEGIN
        /* the item, the salary items it replaced and the change waiting to replace it */
        ;WITH up AS (
            SELECT i.EmployeePayItemId, i.ReplacesItemId, 0 AS Depth
            FROM   [Payroll].[EmployeePayItems] AS i
            WHERE  i.EmployeePayItemId = @Id AND (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
            UNION ALL
            SELECT p.EmployeePayItemId, p.ReplacesItemId, up.Depth + 1
            FROM   up JOIN [Payroll].[EmployeePayItems] AS p ON p.EmployeePayItemId = up.ReplacesItemId
            WHERE  up.Depth < 50
        ), chain AS (
            SELECT EmployeePayItemId FROM up
            UNION
            SELECT n.EmployeePayItemId FROM [Payroll].[EmployeePayItems] AS n JOIN up ON n.ReplacesItemId = up.EmployeePayItemId
        )
        , h AS (
            SELECT  h.PayItemHistoryId, h.EmployeePayItemId, h.ActionCode, h.ApprovalLevel, h.OldAmount, h.NewAmount, h.Comment, h.ActionBy, h.ActionDate
            FROM    [Payroll].[EmployeePayItemHistory] AS h
            JOIN    chain ON chain.EmployeePayItemId = h.EmployeePayItemId
            WHERE   h.Deleted = 0
            UNION ALL
            /* items created before the history existed (e.g. salary moved from the employee profile) */
            SELECT  0, i.EmployeePayItemId, 'CREATED', NULL, NULL, i.Amount, i.Comment, i.CreatedBy, i.CreatedDate
            FROM    [Payroll].[EmployeePayItems] AS i
            JOIN    chain ON chain.EmployeePayItemId = i.EmployeePayItemId
            WHERE   NOT EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItemHistory] x WHERE x.EmployeePayItemId = i.EmployeePayItemId
                                AND x.Deleted = 0 AND x.ActionCode IN ('CREATED', 'REVISED'))
        )
        SELECT  h.PayItemHistoryId, h.EmployeePayItemId, h.ActionCode, h.ApprovalLevel, h.OldAmount, h.NewAmount, h.Comment, h.ActionBy, h.ActionDate,
                i.StartMonth, i.EndMonth, i.AppliesMode, i.Status,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    h
        JOIN    [Payroll].[EmployeePayItems] AS i ON i.EmployeePayItemId = h.EmployeePayItemId
        LEFT JOIN [Security].[Users] u ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] ue ON ue.EmployeeId = u.EmployeeId
        ORDER BY h.ActionDate DESC, h.PayItemHistoryId DESC
        OPTION (MAXRECURSION 60);
        RETURN;
    END;

    /* ======================= SAVE ================================ */
    IF @Action = 'SAVE'
    BEGIN
        BEGIN TRANSACTION;
        EXEC [Payroll].[usp_PayItem_Save]
             @Id = @Id, @EmployeeId = @EmployeeId, @PayComponentId = @PayComponentId, @Amount = @Amount, @AppliesMode = @AppliesMode,
             @StartMonth = @StartMonth, @EndMonth = @EndMonth, @InstalmentCount = @InstalmentCount, @TotalAmount = @TotalAmount,
             @Comment = @Comment, @CompanyScope = @CompanyId, @CompanyIds = @CompanyIds, @UserId = @UserId,
             @NewId = @NewId OUTPUT, @ResultCode = @ResultCode OUTPUT, @ResultMessage = @ResultMessage OUTPUT;
        IF @ResultCode = 'SUCCESS' COMMIT TRANSACTION; ELSE ROLLBACK TRANSACTION;
        RETURN;
    END;

    /* ======================= item actions ======================== */
    DECLARE @iStatus VARCHAR(10), @iLevel TINYINT, @iSubmittedBy BIGINT, @iSubmittedDate DATETIME2(0), @iReplaces BIGINT, @iStart DATE,
            @iEmp BIGINT, @iAmount DECIMAL(12,3), @iMode VARCHAR(10), @iClass VARCHAR(10), @iUsed BIT = 0;
    SELECT @iStatus = i.Status, @iLevel = i.ApprovalLevel, @iSubmittedBy = i.SubmittedBy, @iSubmittedDate = i.SubmittedDate,
           @iReplaces = i.ReplacesItemId, @iStart = i.StartMonth, @iEmp = i.EmployeeId, @iAmount = i.Amount, @iMode = i.AppliesMode,
           @iClass = c.ItemClass
    FROM   [Payroll].[EmployeePayItems] AS i
    JOIN   [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
    WHERE  i.EmployeePayItemId = @Id AND i.Deleted = 0 AND i.PayrollRunId IS NULL
      AND  (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
      AND  (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(i.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0);

    IF @iStatus IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This pay item no longer exists.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = l.PayrollRunId
               WHERE l.EmployeePayItemId = @Id AND l.Deleted = 0 AND r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED'))
        SET @iUsed = 1;
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');

    /* ---------- APPROVE: level 1 (HR), then level 2 (Finance) ---------- */
    IF @Action = 'APPROVE'
    BEGIN
        IF @iStatus <> 'PENDING'
        BEGIN
            SELECT @ResultCode = 'NOT_PENDING', @ResultMessage = N'This item is not waiting for approval.';
            RETURN;
        END;
        IF @ExpectedLevel IS NOT NULL AND @ExpectedLevel <> @iLevel
        BEGIN
            SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
            RETURN;
        END;
        DECLARE @aLevel TINYINT = @iLevel + 1;
        IF @AllowSelfApproval = 0 AND (
               @UserId = @iSubmittedBy
            OR (@aLevel = 2 AND EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItemHistory] WHERE EmployeePayItemId = @Id AND Deleted = 0
                                        AND ActionCode = 'APPROVED' AND ApprovalLevel = 1 AND ActionBy = @UserId
                                        AND ActionDate >= ISNULL(@iSubmittedDate, '19000101'))))
        BEGIN
            SELECT @ResultCode = 'SEGREGATION',
                   @ResultMessage = N'You cannot approve an item you sent for approval or already approved at the previous level.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, ApprovalLevel, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'APPROVED', @aLevel, @iAmount, @Comment, @UserId);

            IF @aLevel >= 2
            BEGIN
                UPDATE [Payroll].[EmployeePayItems]
                   SET Status = 'ACTIVE', ApprovalLevel = 2, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE EmployeePayItemId = @Id AND Status = 'PENDING' AND ApprovalLevel = @iLevel;
                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
                    RETURN;
                END;

                /* a salary change: the replaced item ends the month before */
                IF @iReplaces IS NOT NULL
                BEGIN
                    UPDATE [Payroll].[EmployeePayItems]
                       SET EndMonth = DATEADD(MONTH, -1, @iStart), ModifiedBy = @UserId, ModifiedDate = @Now
                    WHERE  EmployeePayItemId = @iReplaces AND Deleted = 0 AND Status = 'ACTIVE'
                      AND  StartMonth <= DATEADD(MONTH, -1, @iStart) AND (EndMonth IS NULL OR EndMonth >= @iStart);
                    IF @@ROWCOUNT > 0
                        INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
                        SELECT EmployeePayItemId, EmployeeId, 'ENDED', Amount, N'Replaced by the approved salary change', @UserId
                        FROM   [Payroll].[EmployeePayItems] WHERE EmployeePayItemId = @iReplaces;
                END;
                SET @ResultMessage = N'Approved. The item is now active.';
            END
            ELSE
            BEGIN
                UPDATE [Payroll].[EmployeePayItems] SET ApprovalLevel = @aLevel, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  EmployeePayItemId = @Id AND Status = 'PENDING' AND ApprovalLevel = @iLevel;
                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
                    RETURN;
                END;
                SET @ResultMessage = N'Approved. Waiting for the Finance Manager.';
            END;
        COMMIT TRANSACTION;
        SET @NewId = @aLevel;
        RETURN;
    END;

    /* ---------- REJECT: the pending item is removed ---------- */
    IF @Action = 'REJECT'
    BEGIN
        IF @iStatus <> 'PENDING'
        BEGIN
            SELECT @ResultCode = 'NOT_PENDING', @ResultMessage = N'This item is not waiting for approval.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter the reason for rejecting it.';
            RETURN;
        END;
        IF @ExpectedLevel IS NOT NULL AND @ExpectedLevel <> @iLevel
        BEGIN
            SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, ApprovalLevel, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'REJECTED', @iLevel + 1, @iAmount, @Comment, @UserId);
            UPDATE [Payroll].[EmployeePayItems] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE EmployeePayItemId = @Id;
        COMMIT TRANSACTION;
        SET @ResultMessage = CASE WHEN @iReplaces IS NOT NULL THEN N'Rejected. The current amount stays.' ELSE N'Rejected. The item was removed.' END;
        RETURN;
    END;

    /* ---------- END: stop paying it ---------- */
    IF @Action = 'END'
    BEGIN
        IF @iStatus <> 'ACTIVE'
        BEGIN
            SELECT @ResultCode = 'NOT_ACTIVE', @ResultMessage = N'Only an active item can be ended. Delete or reject an item that waits for approval.';
            RETURN;
        END;
        IF @EndMonth IS NOT NULL SET @EndMonth = DATEFROMPARTS(YEAR(@EndMonth), MONTH(@EndMonth), 1);

        IF @iMode = 'MONTHLY' AND @EndMonth IS NOT NULL
        BEGIN
            IF @EndMonth < (SELECT MAX(r.RunMonth) FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = l.PayrollRunId
                            WHERE l.EmployeePayItemId = @Id AND l.Deleted = 0 AND r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED'))
            BEGIN
                SELECT @ResultCode = 'END_BEFORE_PAID', @ResultMessage = N'The last month cannot be before a month already paid.';
                RETURN;
            END;
            IF @EndMonth < @iStart
            BEGIN
                SELECT @ResultCode = 'END_BEFORE_START', @ResultMessage = N'The last month cannot be before the first month.';
                RETURN;
            END;
            BEGIN TRANSACTION;
                UPDATE [Payroll].[EmployeePayItems] SET EndMonth = @EndMonth, ModifiedBy = @UserId, ModifiedDate = @Now WHERE EmployeePayItemId = @Id;
                INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
                VALUES (@Id, @iEmp, 'ENDED', @iAmount, @Comment, @UserId);
            COMMIT TRANSACTION;
            SET @ResultMessage = N'Last month saved. The item is not paid after it.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE [Payroll].[EmployeePayItems]
               SET Status = 'ENDED',
                   EndMonth = CASE WHEN AppliesMode = 'MONTHLY'
                                   THEN CASE WHEN DATEADD(MONTH, -1, @ThisMonth) < StartMonth THEN StartMonth ELSE DATEADD(MONTH, -1, @ThisMonth) END
                                   ELSE EndMonth END,
                   ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  EmployeePayItemId = @Id;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'ENDED', @iAmount, @Comment, @UserId);
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Item ended. No further payroll pays it.';
        RETURN;
    END;

    /* ---------- DELETE: only when no payroll has paid it ---------- */
    IF @Action = 'DELETE'
    BEGIN
        IF @iUsed = 1
        BEGIN
            SELECT @ResultCode = 'ALREADY_PAID', @ResultMessage = N'This item has already been paid by a payroll and cannot be deleted. End it instead.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'DELETED', @iAmount, @Comment, @UserId);
            UPDATE [Payroll].[EmployeePayItems] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE EmployeePayItemId = @Id;

            /* an approved salary change: the amount it replaced applies again */
            IF @iStatus = 'ACTIVE' AND @iReplaces IS NOT NULL
            BEGIN
                UPDATE [Payroll].[EmployeePayItems]
                   SET EndMonth = NULL, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  EmployeePayItemId = @iReplaces AND Deleted = 0 AND Status = 'ACTIVE' AND EndMonth = DATEADD(MONTH, -1, @iStart);
                IF @@ROWCOUNT > 0
                    INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
                    SELECT EmployeePayItemId, EmployeeId, 'CHANGED', Amount, N'The salary change that replaced it was deleted - this amount applies again', @UserId
                    FROM   [Payroll].[EmployeePayItems] WHERE EmployeePayItemId = @iReplaces;
            END;
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Pay item deleted.';
        RETURN;
    END;
END;
GO

/* ---- 6. labels (English + Arabic) ----------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('sec.mod_components', 'sec', N'Payroll Components', N'مكونات الرواتب', NULL),
        ('sec.pg_pc_salary', 'sec', N'Salary Revisions', N'تعديلات الرواتب', NULL),
        ('sec.pg_pc_earnings', 'sec', N'Earnings & Allowances', N'الاستحقاقات والبدلات', NULL),
        ('sec.pg_pc_deductions', 'sec', N'Deductions', N'الاستقطاعات', NULL),
        ('sec.pg_pc_loans', 'sec', N'Loans & Advances', N'القروض والسلف', NULL),
        ('sec.pg_pc_hint', 'sec', N'Read = see; Write = add and change; Full = also delete', N'القراءة = العرض؛ الكتابة = الإضافة والتعديل؛ الكامل = الحذف أيضاً', NULL),
        ('sec.apr_pc_salary', 'sec', N'Salary revisions', N'تعديلات الرواتب', NULL),
        ('sec.apr_pc_earnings', 'sec', N'Earnings & allowances', N'الاستحقاقات والبدلات', NULL),
        ('sec.apr_pc_deductions', 'sec', N'Deductions', N'الاستقطاعات', NULL),
        ('sec.apr_pc_loans', 'sec', N'Loans & advances', N'القروض والسلف', NULL),
        ('sec.apr_pc_hint', 'sec', N'Level 1 HR, level 2 Finance - paid only once approved', N'المستوى الأول الموارد البشرية، والثاني المالية - لا يُصرف إلا بعد الاعتماد', NULL),
        ('sec.pc_types', 'sec', N'Payroll Components - item types', N'مكونات الرواتب - أنواع البنود', NULL),
        ('sec.pc_types_text', 'sec', N'Limit this role to chosen item types of a page (e.g. only Overtime). No ticks = every item type of the page.', N'قصر هذا الدور على أنواع بنود محددة في الصفحة (مثل العمل الإضافي فقط). بدون اختيار = كل أنواع البنود.', NULL),
        ('sec.pc_all_types', 'sec', N'Every type', N'كل الأنواع', NULL),
        ('sec.pc_some_types', 'sec', N'Only the ticked types', N'الأنواع المختارة فقط', NULL),
        ('pc.salary', 'pc', N'Salary Revisions', N'تعديلات الرواتب', NULL),
        ('pc.earnings', 'pc', N'Earnings & Allowances', N'الاستحقاقات والبدلات', NULL),
        ('pc.deductions', 'pc', N'Deductions', N'الاستقطاعات', NULL),
        ('pc.loans', 'pc', N'Loans & Advances', N'القروض والسلف', NULL),
        ('pc.salary_sub', 'pc', N'Increments and decrements of the contract salary - applied to the employee profile once approved', N'زيادات وتخفيضات راتب العقد - تُطبق على ملف الموظف بعد الاعتماد', NULL),
        ('pc.earnings_sub', 'pc', N'Allowances, overtime, bonuses, commissions and other earnings', N'البدلات والعمل الإضافي والمكافآت والعمولات والاستحقاقات الأخرى', NULL),
        ('pc.deductions_sub', 'pc', N'Absence, penalties, other deductions and statutory deductions', N'الغياب والجزاءات والاستقطاعات الأخرى والاستقطاعات القانونية', NULL),
        ('pc.loans_sub', 'pc', N'Employee loans, salary advances, repayments and outstanding balances', N'قروض الموظفين وسلف الرواتب والسداد والأرصدة المستحقة', NULL),
        ('pc.default_title', 'pc', N'The contract salary is the default.', N'راتب العقد هو الأساس.', NULL),
        ('pc.intro_salary', 'pc', N'Basic Salary and Allowances of the employment contract are paid every month without approval. A revision changes them from a month on, after approval (HR, then Finance) - then the employee profile shows the new salary.', N'يُصرف الراتب الأساسي والبدلات في عقد العمل كل شهر بدون اعتماد. التعديل يغيّرها اعتباراً من شهر، بعد الاعتماد (الموارد البشرية ثم المالية) - ثم يظهر الراتب الجديد في ملف الموظف.', NULL),
        ('pc.intro_earnings', 'pc', N'Earnings on top of the contract salary - each is paid only after approval.', N'استحقاقات فوق راتب العقد - كل منها يُصرف بعد الاعتماد فقط.', NULL),
        ('pc.intro_deductions', 'pc', N'Deductions from the salary - each is taken only after approval. PIFSS is worked out by the payroll.', N'استقطاعات من الراتب - كل منها يُخصم بعد الاعتماد فقط. التأمينات الاجتماعية تحسبها الرواتب.', NULL),
        ('pc.intro_loans', 'pc', N'A loan or advance cannot be more than the Basic Salary; an instalment above 50% of it is flagged for the approvers.', N'لا يمكن أن يزيد القرض أو السلفة عن الراتب الأساسي؛ القسط الذي يزيد عن 50% منه يُنبَّه عليه للمعتمدين.', NULL),
        ('pc.add_salary', 'pc', N'Add salary revision', N'إضافة تعديل راتب', NULL),
        ('pc.add_earnings', 'pc', N'Add earning', N'إضافة استحقاق', NULL),
        ('pc.add_deductions', 'pc', N'Add deduction', N'إضافة استقطاع', NULL),
        ('pc.add_loans', 'pc', N'Add loan / advance', N'إضافة قرض / سلفة', NULL),
        ('pc.loan_within_basic', 'pc', N'Loan within the Basic Salary', N'القرض ضمن الراتب الأساسي', NULL),
        ('pc.loan_share_basic', 'pc', N'Instalment + other deductions, share of the Basic Salary', N'القسط + الاستقطاعات الأخرى، نسبة من الراتب الأساسي', NULL),
        ('js.pc_no_basic', 'js', N'No Basic Salary for this employee', N'لا يوجد راتب أساسي لهذا الموظف', NULL),
        ('js.pc_share', 'js', N'{0}% of basic salary · limit {1}%', N'{0}% من الراتب الأساسي · الحد {1}%', NULL),
        ('pc.increment', 'pc', N'Increment', N'زيادة', NULL),
        ('pc.decrement', 'pc', N'Decrement', N'تخفيض', NULL),
        ('pc.contract_default', 'pc', N'Contract · default', N'العقد · أساسي', NULL),
        ('pc.revision', 'pc', N'Revision', N'تعديل', NULL),
        ('pc.salary_history', 'pc', N'Salary history', N'سجل الراتب', NULL),
        ('pc.salary_history_of_0', 'pc', N'Salary history of {0}', N'سجل راتب {0}', NULL),
        ('pc.salary_now', 'pc', N'Monthly salary now', N'الراتب الشهري الحالي', NULL),
        ('pc.no_salary_history', 'pc', N'No salary yet for this employee.', N'لا يوجد راتب لهذا الموظف بعد.', NULL),
        ('pc.in_force', 'pc', N'In force', N'سارٍ', NULL),
        ('ap.kind_salrev', 'ap', N'Salary revisions', N'تعديلات الرواتب', NULL),
        ('ap.kind_earn', 'ap', N'Earnings & allowances', N'الاستحقاقات والبدلات', NULL),
        ('ap.kind_ded', 'ap', N'Deductions', N'الاستقطاعات', NULL),
        ('ap.kind_loan', 'ap', N'Loans & advances', N'القروض والسلف', NULL),
        ('msg.pc_profile_updated', 'msg', N'The employee profile now shows the new salary.', N'يظهر الراتب الجديد الآن في ملف الموظف.', N'The employee profile now shows the new salary.'),
        ('msg.pc_loan_above_basic', 'msg', N'The loan ({0} KWD) cannot be more than the Basic Salary ({1} KWD).', N'لا يمكن أن يزيد القرض ({0} د.ك) عن الراتب الأساسي ({1} د.ك).', N'The loan ({0} KWD) cannot be more than the Basic Salary ({1} KWD).'),
        ('msg.pc_no_basic', 'msg', N'The employee has no Basic Salary - a loan or advance cannot be given.', N'لا يوجد راتب أساسي للموظف - لا يمكن منح قرض أو سلفة.', N'The employee has no Basic Salary - a loan or advance cannot be given.'),
        ('msg.pc_loan_share', 'msg', N'Note for the approvers: the instalment with the other monthly deductions is {0}% of the Basic Salary (more than 50%).', N'ملاحظة للمعتمدين: القسط مع الاستقطاعات الشهرية الأخرى يساوي {0}% من الراتب الأساسي (أكثر من 50%).', N'Note for the approvers: the instalment with the other monthly deductions is {0}% of the Basic Salary (more than 50%).'),
        ('msg.pc_import_refused', 'msg', N'Some rows are not item types of this page (or not ones you may add). Nothing was imported.', N'بعض الصفوف ليست من أنواع بنود هذه الصفحة (أو غير مسموح لك بإضافتها). لم يتم استيراد أي شيء.', N'Some rows are not item types of this page (or not ones you may add). Nothing was imported.'),
        ('msg.pc_import_row', 'msg', N'Item type not on this page or not allowed for you.', N'نوع البند ليس في هذه الصفحة أو غير مسموح لك.', N'Item type not on this page or not allowed for you.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Payroll Components labels inserted: ', @LabelsInserted);
GO

SET NOEXEC OFF;
GO
