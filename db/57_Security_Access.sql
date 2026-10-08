/* =====================================================================
   57_Security_Access.sql  -  HRMS: Security > Create Roles / Assign Roles
   ---------------------------------------------------------------------
   Run after 01-56. Safe to re-run.

     1. Security.Roles.Description, Security.RoleAccessLog (who changed a
        role's rights or a user's roles, and when)
     2. the permission codes the role screen manages (pages, functions and
        approvals - the catalog is Security/AccessCatalog.cs)
     3. ONE-TIME grants that keep today's behaviour (only when a code is
        created by this run, so re-running never re-grants a right an
        administrator has since removed):
          - Employees and Organization Setup had no permission check: every
            role gets their codes (tighten them on Create Roles)
          - the shared codes split per page / process are granted to the roles
            that held the shared code (calendar <- payroll setup, pay item and
            settlement approvals <- payroll approvals, exclude <- process,
            payroll dashboard <- any payroll view)
          - "approve own submissions" and Security: System Administrator only
          - System Administrator (SYSADMIN) holds every permission
     4. Security.usp_Auth_Manage re-issued: GET_PERMISSIONS / GET_ROLES skip
        soft-deleted links (db/28 turns DELETE into Deleted = 1, so a revoked
        right used to keep working)
     5. Security.usp_SecurityAdmin_Manage
          ROLES            roles in scope (+ users, rights counts)
          ROLE_GET         one role
          ROLE_CODES       its permission codes
          ROLE_SAVE        insert / update a role and replace the codes the
                           catalog manages (@ManagedCodes) with @GrantedCodes
          ROLE_DELETE      soft delete (no users assigned; never SYSADMIN)
          USERS            users in scope with their roles (paged, search,
                           role filter; @UserId = that one user)
          USER_ROLES_SET   replace a user's roles (within the roles in scope)

   Rules: a user gets global roles and their own company's roles only.
   SYSADMIN is a system role - its rights cannot be edited and only a
   System Administrator may assign it; the last active System Administrator
   cannot lose the role. A user pinned to a company (@CompanyId) sees the
   global roles and their company's roles, edits only their company's roles,
   and assigns roles only to their company's users.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------
   1. Columns / log
   ------------------------------------------------------------------ */
IF COL_LENGTH('Security.Roles', 'Description') IS NULL
    ALTER TABLE [Security].[Roles] ADD [Description] NVARCHAR(500) NULL;
GO
IF COL_LENGTH('Security.Roles', 'ModifiedBy') IS NULL
    ALTER TABLE [Security].[Roles] ADD [ModifiedBy] BIGINT NULL;
GO
IF COL_LENGTH('Security.Roles', 'ModifiedDate') IS NULL
    ALTER TABLE [Security].[Roles] ADD [ModifiedDate] DATETIME2(0) NULL;
GO

IF OBJECT_ID(N'[Security].[RoleAccessLog]', N'U') IS NULL
BEGIN
    CREATE TABLE [Security].[RoleAccessLog](
        RoleAccessLogId  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RoleAccessLog PRIMARY KEY,
        RoleId           INT            NULL,
        UserId           BIGINT         NULL,          -- the user whose roles changed (USER_ROLES_SET)
        ActionCode       VARCHAR(20)    NOT NULL,      -- ROLE_CREATED / ROLE_CHANGED / ROLE_DELETED / USER_ROLES
        Detail           NVARCHAR(2000) NULL,
        ActionBy         BIGINT         NULL,
        ActionDate       DATETIME2(0)   NOT NULL CONSTRAINT DF_RoleAccessLog_Date DEFAULT (SYSUTCDATETIME()),
        Deleted          BIT            NOT NULL CONSTRAINT DF_Security_RoleAccessLog_Deleted DEFAULT (0),
        DeletedBy        BIGINT         NULL,
        DeletedDate      DATETIME2(7)   NULL
    );
    CREATE INDEX IX_RoleAccessLog_Role ON [Security].[RoleAccessLog](RoleId, ActionDate DESC);
END;
GO

/* ------------------------------------------------------------------
   2. Permission codes  +  3. one-time grants
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT, Action VARCHAR(30) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action) VALUES
    ('EMPLOYEE_VIEW', 'Employee', 'View'),
    ('EMPLOYEE_CREATE', 'Employee', 'Create'),
    ('EMPLOYEE_EDIT', 'Employee', 'Edit'),
    ('EMPLOYEE_DELETE', 'Employee', 'Delete'),
    ('EMPLOYEE_COMPLIANCE_VIEW', 'Employee', 'ComplianceView'),
    ('EMPLOYEE_COMPLIANCE_EDIT', 'Employee', 'ComplianceEdit'),
    ('EMPLOYEE_DEPENDENT_VIEW', 'Employee', 'DependentView'),
    ('EMPLOYEE_DEPENDENT_EDIT', 'Employee', 'DependentEdit'),
    ('EMPLOYEE_DEPENDENT_DELETE', 'Employee', 'DependentDelete'),
    ('EMPLOYEE_DOCUMENT_VIEW', 'Employee', 'DocumentView'),
    ('EMPLOYEE_DOCUMENT_UPLOAD', 'Employee', 'DocumentUpload'),
    ('EMPLOYEE_DOCUMENT_DELETE', 'Employee', 'DocumentDelete'),
    ('ORGANIZATION_VIEW', 'Organization', 'View'),
    ('ORGANIZATION_CREATE', 'Organization', 'Create'),
    ('ORGANIZATION_EDIT', 'Organization', 'Edit'),
    ('ORGANIZATION_DELETE', 'Organization', 'Delete'),
    ('ORGANIZATION_COMPANY_EDIT', 'Organization', 'CompanyEdit'),
    ('ORGANIZATION_COMPANY_DELETE', 'Organization', 'CompanyDelete'),
    ('PAYROLL_DASHBOARD_VIEW', 'PayrollDashboard', 'View'),
    ('PAYROLL_RUN_EXCLUDE', 'PayrollRun', 'Exclude'),
    ('PAYROLL_RUN_APPROVE_SELF', 'PayrollRun', 'ApproveSelf'),
    ('PAYROLL_CALENDAR_VIEW', 'PayrollCalendar', 'View'),
    ('PAYROLL_CALENDAR_EDIT', 'PayrollCalendar', 'Edit'),
    ('PAYROLL_CALENDAR_DELETE', 'PayrollCalendar', 'Delete'),
    ('PAYROLL_ITEM_APPROVE_L1', 'PayrollItem', 'ApproveL1'),
    ('PAYROLL_ITEM_APPROVE_L2', 'PayrollItem', 'ApproveL2'),
    ('PAYROLL_ITEM_APPROVE_SELF', 'PayrollItem', 'ApproveSelf'),
    ('PAYROLL_FS_APPROVE_L1', 'FinalSettlement', 'ApproveL1'),
    ('PAYROLL_FS_APPROVE_L2', 'FinalSettlement', 'ApproveL2'),
    ('PAYROLL_FS_APPROVE_SELF', 'FinalSettlement', 'ApproveSelf'),
    ('SECURITY_ROLE_VIEW', 'Security', 'RoleView'),
    ('SECURITY_ROLE_EDIT', 'Security', 'RoleEdit'),
    ('SECURITY_ROLE_DELETE', 'Security', 'RoleDelete'),
    ('SECURITY_USER_VIEW', 'Security', 'UserView'),
    ('SECURITY_USER_ASSIGN', 'Security', 'UserAssign');

UPDATE c SET IsNew = 1 FROM #Codes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #Codes c WHERE c.IsNew = 1;

/* grant @Code to every role holding any of @From (or every role when @From = '*'), once */
IF OBJECT_ID('tempdb..#Grant') IS NOT NULL DROP TABLE #Grant;
CREATE TABLE #Grant (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT, FromCode VARCHAR(60) COLLATE DATABASE_DEFAULT);
INSERT INTO #Grant (PermissionCode, FromCode) VALUES
    ('EMPLOYEE_VIEW', '*'), ('EMPLOYEE_CREATE', '*'), ('EMPLOYEE_EDIT', '*'), ('EMPLOYEE_DELETE', '*'),
    ('EMPLOYEE_COMPLIANCE_VIEW', '*'), ('EMPLOYEE_COMPLIANCE_EDIT', '*'),
    ('EMPLOYEE_DEPENDENT_VIEW', '*'), ('EMPLOYEE_DEPENDENT_EDIT', '*'), ('EMPLOYEE_DEPENDENT_DELETE', '*'),
    ('EMPLOYEE_DOCUMENT_VIEW', '*'), ('EMPLOYEE_DOCUMENT_UPLOAD', '*'), ('EMPLOYEE_DOCUMENT_DELETE', '*'),
    ('ORGANIZATION_COMPANY_EDIT', '*'), ('ORGANIZATION_COMPANY_DELETE', '*'),
    ('PAYROLL_DASHBOARD_VIEW', 'PAYROLL_RUN_VIEW'), ('PAYROLL_DASHBOARD_VIEW', 'PAYROLL_SETUP_VIEW'), ('PAYROLL_DASHBOARD_VIEW', 'PAYROLL_REPORT_VIEW'),
    ('PAYROLL_DASHBOARD_VIEW', 'PAYROLL_SLIP_VIEW'), ('PAYROLL_DASHBOARD_VIEW', 'PAYROLL_BANK_VIEW'), ('PAYROLL_DASHBOARD_VIEW', 'PAYROLL_GL_VIEW'),
    ('PAYROLL_RUN_EXCLUDE', 'PAYROLL_RUN_PROCESS'),
    ('PAYROLL_CALENDAR_VIEW', 'PAYROLL_SETUP_VIEW'), ('PAYROLL_CALENDAR_EDIT', 'PAYROLL_SETUP_EDIT'), ('PAYROLL_CALENDAR_EDIT', 'PAYROLL_SETUP_CREATE'),
    ('PAYROLL_CALENDAR_DELETE', 'PAYROLL_SETUP_DELETE'),
    ('PAYROLL_ITEM_APPROVE_L1', 'PAYROLL_RUN_APPROVE_HR'), ('PAYROLL_ITEM_APPROVE_L2', 'PAYROLL_RUN_APPROVE_FINANCE'),
    ('PAYROLL_FS_APPROVE_L1', 'PAYROLL_RUN_APPROVE_HR'), ('PAYROLL_FS_APPROVE_L2', 'PAYROLL_RUN_APPROVE_FINANCE');

/* Organization Setup had no check either: its old codes go to every role, the first time only */
IF EXISTS (SELECT 1 FROM #Codes WHERE PermissionCode = 'ORGANIZATION_COMPANY_EDIT' AND IsNew = 1)
    INSERT INTO #Grant (PermissionCode, FromCode) VALUES
        ('ORGANIZATION_VIEW', '*'), ('ORGANIZATION_CREATE', '*'), ('ORGANIZATION_EDIT', '*'), ('ORGANIZATION_DELETE', '*');

IF OBJECT_ID('tempdb..#Pairs') IS NOT NULL DROP TABLE #Pairs;
SELECT DISTINCT r.RoleId, p.PermissionId
INTO   #Pairs
FROM   #Grant AS g
JOIN   [Security].[Permissions] AS p ON p.PermissionCode = g.PermissionCode AND p.Deleted = 0
JOIN   [Security].[Roles] AS r ON r.Deleted = 0
WHERE  (EXISTS (SELECT 1 FROM #Codes c WHERE c.PermissionCode = g.PermissionCode AND c.IsNew = 1)
        OR g.PermissionCode IN ('ORGANIZATION_VIEW', 'ORGANIZATION_CREATE', 'ORGANIZATION_EDIT', 'ORGANIZATION_DELETE'))
  AND  (g.FromCode = '*'
        OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp
                   JOIN [Security].[Permissions] fp ON fp.PermissionId = rp.PermissionId AND fp.Deleted = 0
                   WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND fp.PermissionCode = g.FromCode));

/* System Administrator: every permission */
INSERT INTO #Pairs (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] r CROSS JOIN [Security].[Permissions] p
WHERE  r.RoleCode = N'SYSADMIN' AND r.Deleted = 0 AND p.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM #Pairs x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId);

UPDATE rp SET Deleted = 0, DeletedBy = NULL, DeletedDate = NULL
FROM   [Security].[RolePermissions] rp JOIN #Pairs x ON x.RoleId = rp.RoleId AND x.PermissionId = rp.PermissionId
WHERE  rp.Deleted = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT x.RoleId, x.PermissionId FROM #Pairs x
WHERE  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp WHERE rp.RoleId = x.RoleId AND rp.PermissionId = x.PermissionId);

DECLARE @Granted INT = @@ROWCOUNT, @Created INT = (SELECT COUNT(1) FROM #Codes WHERE IsNew = 1);
PRINT CONCAT(N'Security codes created: ', @Created, N', role rights granted: ', @Granted);
DROP TABLE #Pairs; DROP TABLE #Grant; DROP TABLE #Codes;
GO

/* ------------------------------------------------------------------
   4. Sign-in: skip soft-deleted role links (copy of db/27, two WHEREs)
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Security].[usp_Auth_Manage]
    @Action           VARCHAR(20),

    @UserId           BIGINT         = NULL,
    @Username         NVARCHAR(100)  = NULL,

    /* supplied by the application, never by the browser */
    @PasswordHash     NVARCHAR(500)  = NULL,
    /* db/27: plain-text copy, only sent when Authentication:SimplePassword = true */
    @PlainPassword    NVARCHAR(50)   = NULL,
    @IpAddress        NVARCHAR(64)   = NULL,
    @UserAgent        NVARCHAR(400)  = NULL,

    /* lockout policy, passed from configuration */
    @MaxFailedAttempts INT           = 5,
    @LockoutMinutes    INT           = 15,

    /* recorded against the audit row on a failed attempt */
    @Outcome          VARCHAR(30)    = NULL,

    /* outputs */
    @ResultCode       VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage    NVARCHAR(400)  = NULL OUTPUT,
    @LockoutEndUtc    DATETIME2(0)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'';

    IF @Action NOT IN ('LOGIN_LOOKUP', 'LOGIN_SUCCESS', 'LOGIN_FAILURE',
                       'GET_PERMISSIONS', 'GET_ROLES', 'CHANGE_PASSWORD', 'UNLOCK', 'SET_PLAIN')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @Username = NULLIF(LTRIM(RTRIM(ISNULL(@Username, N''))), N'');

    /* ==================== LOGIN_LOOKUP ============================ */
    /* Matches on username or email. Returns exactly one row, or none. */
    IF @Action = 'LOGIN_LOOKUP'
    BEGIN
        SELECT TOP (1)
                u.UserId,
                u.Username,
                u.Email,
                u.PasswordHash,
                u.[Password],
                u.IsActive,
                u.FailedLoginAttempts,
                u.LockoutEndUtc,
                u.MustChangePassword,
                u.TwoFactorEnabled,
                u.SecurityStamp,
                u.CompanyId,
                c.CompanyName,
                u.EmployeeId,
                CONCAT(e.FirstName, N' ', ISNULL(e.LastName, N'')) AS EmployeeName
        FROM        [Security].[Users]    AS u
        LEFT JOIN   [Core].[Companies]    AS c ON c.CompanyId  = u.CompanyId
        LEFT JOIN   [Employee].[Employees] AS e ON e.EmployeeId = u.EmployeeId
        WHERE       u.Username = @Username
                OR (u.Email IS NOT NULL AND u.Email = @Username)
        ORDER BY    CASE WHEN u.Username = @Username THEN 0 ELSE 1 END;

        RETURN;
    END;

    /* ==================== LOGIN_SUCCESS =========================== */
    IF @Action = 'LOGIN_SUCCESS'
    BEGIN
        UPDATE [Security].[Users]
           SET FailedLoginAttempts = 0,
               LockoutEndUtc       = NULL,
               LastLoginDate       = SYSUTCDATETIME(),
               LastLoginIp         = @IpAddress
         WHERE UserId = @UserId;

        INSERT INTO [Security].[UserLoginHistory]
            (UserId, UsernameAttempted, Outcome, IpAddress, UserAgent)
        VALUES
            (@UserId, ISNULL(@Username, N'(unknown)'), 'SUCCESS', @IpAddress, @UserAgent);

        RETURN;
    END;

    /* ==================== LOGIN_FAILURE =========================== */
    /* @UserId is null when the username did not resolve - the attempt is
       still audited so targeted guessing is visible in the history. */
    IF @Action = 'LOGIN_FAILURE'
    BEGIN
        SET @Outcome = CASE
                          WHEN @Outcome IN ('BAD_PASSWORD', 'UNKNOWN_USER', 'INACTIVE', 'LOCKED_OUT')
                          THEN @Outcome
                          ELSE 'BAD_PASSWORD'
                       END;

        IF @UserId IS NOT NULL AND @Outcome = 'BAD_PASSWORD'
        BEGIN
            UPDATE [Security].[Users]
               SET FailedLoginAttempts = FailedLoginAttempts + 1,
                   LockoutEndUtc       = CASE
                                            WHEN FailedLoginAttempts + 1 >= @MaxFailedAttempts
                                            THEN DATEADD(MINUTE, @LockoutMinutes, SYSUTCDATETIME())
                                            ELSE LockoutEndUtc
                                         END
             WHERE UserId = @UserId;

            SELECT @LockoutEndUtc = LockoutEndUtc
            FROM   [Security].[Users]
            WHERE  UserId = @UserId;

            IF @LockoutEndUtc IS NOT NULL AND @LockoutEndUtc > SYSUTCDATETIME()
            BEGIN
                SET @Outcome    = 'LOCKED_OUT';
                SET @ResultCode = 'LOCKED_OUT';
            END;
        END;

        INSERT INTO [Security].[UserLoginHistory]
            (UserId, UsernameAttempted, Outcome, IpAddress, UserAgent)
        VALUES
            (@UserId, ISNULL(@Username, N'(unknown)'), @Outcome, @IpAddress, @UserAgent);

        RETURN;
    END;

    /* ==================== GET_PERMISSIONS ========================= */
    IF @Action = 'GET_PERMISSIONS'
    BEGIN
        SELECT DISTINCT p.PermissionCode
        FROM        [Security].[UserRoles]       AS ur
        INNER JOIN  [Security].[Roles]           AS r  ON r.RoleId       = ur.RoleId
        INNER JOIN  [Security].[RolePermissions] AS rp ON rp.RoleId      = r.RoleId
        INNER JOIN  [Security].[Permissions]     AS p  ON p.PermissionId = rp.PermissionId
        WHERE       ur.UserId = @UserId
                AND r.IsActive = 1
                /* soft-deleted links (db/28 turns DELETE into Deleted = 1) grant nothing */
                AND ur.Deleted = 0 AND r.Deleted = 0 AND rp.Deleted = 0 AND p.Deleted = 0
        ORDER BY    p.PermissionCode;

        RETURN;
    END;

    /* ==================== GET_ROLES =============================== */
    IF @Action = 'GET_ROLES'
    BEGIN
        SELECT      r.RoleCode, r.RoleName
        FROM        [Security].[UserRoles] AS ur
        INNER JOIN  [Security].[Roles]     AS r ON r.RoleId = ur.RoleId
        WHERE       ur.UserId = @UserId
                AND r.IsActive = 1
                AND ur.Deleted = 0 AND r.Deleted = 0
        ORDER BY    r.RoleName;

        RETURN;
    END;

    /* ==================== CHANGE_PASSWORD ========================= */
    /* Rotating SecurityStamp signs the user out of every other session. */
    IF @Action = 'CHANGE_PASSWORD'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Security].[Users] WHERE UserId = @UserId)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That account no longer exists.';
            RETURN;
        END;

        /* The hash is always kept current, so SimplePassword can be switched
           off at any time. [Password] gets the plain text only in simple mode;
           in normal mode it is cleared, so no plain copy outlives a change. */
        UPDATE [Security].[Users]
           SET PasswordHash           = @PasswordHash,
               [Password]             = @PlainPassword,
               PasswordChangedDateUtc = SYSUTCDATETIME(),
               MustChangePassword     = 0,
               SecurityStamp          = NEWID(),
               FailedLoginAttempts    = 0,
               LockoutEndUtc          = NULL,
               ModifiedDate           = SYSUTCDATETIME()
         WHERE UserId = @UserId;

        SET @ResultMessage = N'Password changed successfully.';
        RETURN;
    END;

    /* ==================== SET_PLAIN (db/27) ======================= */
    /* Simple mode only: fills [Password] for an account that signed in with
       its hashed password before simple mode was turned on. Does not rotate
       the security stamp (the password itself has not changed). */
    IF @Action = 'SET_PLAIN'
    BEGIN
        UPDATE [Security].[Users]
           SET [Password]   = @PlainPassword,
               ModifiedDate = SYSUTCDATETIME()
         WHERE UserId = @UserId;
        RETURN;
    END;

    /* ==================== UNLOCK ================================== */
    IF @Action = 'UNLOCK'
    BEGIN
        UPDATE [Security].[Users]
           SET FailedLoginAttempts = 0,
               LockoutEndUtc       = NULL,
               ModifiedDate        = SYSUTCDATETIME()
         WHERE UserId = @UserId;

        SET @ResultMessage = N'Account unlocked.';
        RETURN;
    END;
END;
GO

/* ------------------------------------------------------------------
   5. Security administration
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Security].[usp_SecurityAdmin_Manage]
    @Action          VARCHAR(20),
    @CompanyId       INT             = NULL,     -- the caller's company when pinned (scope)
    @RoleId          INT             = NULL,
    @UserId          BIGINT          = NULL,     -- USER_ROLES_SET: the user whose roles change
    @RoleCode        NVARCHAR(50)    = NULL,
    @RoleName        NVARCHAR(100)   = NULL,
    @Description     NVARCHAR(500)   = NULL,
    @RoleCompanyId   INT             = NULL,     -- ROLE_SAVE: NULL = a global role
    @IsActive        BIT             = 1,
    @ManagedCodes    NVARCHAR(MAX)   = NULL,     -- CSV: every code the role screen manages
    @GrantedCodes    NVARCHAR(MAX)   = NULL,     -- CSV: the codes this role gets
    @RoleIds         NVARCHAR(MAX)   = NULL,     -- CSV: USER_ROLES_SET
    @Search          NVARCHAR(200)   = NULL,
    @RoleFilter      INT             = NULL,
    @PageNumber      INT             = 1,
    @PageSize        INT             = 25,
    @CallerIsSysAdmin BIT            = 0,
    @ActionBy        BIGINT          = NULL,

    @TotalCount      INT             = NULL OUTPUT,
    @NewId           BIGINT          = NULL OUTPUT,
    @ResultCode      VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage   NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@RoleId, 0), @TotalCount = 0;
    SET @Search      = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @RoleCode    = UPPER(NULLIF(LTRIM(RTRIM(@RoleCode)), N''));
    SET @RoleName    = NULLIF(LTRIM(RTRIM(@RoleName)), N'');
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');
    SET @PageNumber  = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize    = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @Action NOT IN ('ROLES', 'ROLE_GET', 'ROLE_CODES', 'ROLE_SAVE', 'ROLE_DELETE', 'USERS', 'USER_ROLES_SET')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* the roles the caller may see: global ones and their company's (all when not pinned) */
    DECLARE @Visible TABLE (RoleId INT PRIMARY KEY);
    INSERT INTO @Visible
    SELECT r.RoleId FROM [Security].[Roles] r
    WHERE  r.Deleted = 0 AND (@CompanyId IS NULL OR r.CompanyId IS NULL OR r.CompanyId = @CompanyId);

    /* ======================= ROLES / ROLE_GET ==================== */
    IF @Action IN ('ROLES', 'ROLE_GET')
    BEGIN
        SELECT  r.RoleId, r.RoleCode, r.RoleName, r.[Description], r.CompanyId, co.CompanyName, r.IsActive,
                CAST(CASE WHEN r.RoleCode = N'SYSADMIN' THEN 1 ELSE 0 END AS BIT) AS IsSystem,
                CAST(CASE WHEN @CompanyId IS NULL OR r.CompanyId = @CompanyId THEN 1 ELSE 0 END AS BIT) AS IsEditable,
                (SELECT COUNT(1) FROM [Security].[UserRoles] ur JOIN [Security].[Users] u ON u.UserId = ur.UserId
                  WHERE ur.RoleId = r.RoleId AND ur.Deleted = 0 AND u.Deleted = 0) AS UserCount,
                (SELECT COUNT(1) FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] p ON p.PermissionId = rp.PermissionId
                  WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND p.Deleted = 0) AS PermissionCount,
                r.ModifiedDate
        FROM    [Security].[Roles] r
        JOIN    @Visible v ON v.RoleId = r.RoleId
        LEFT JOIN [Core].[Companies] co ON co.CompanyId = r.CompanyId
        WHERE   (@Action = 'ROLES' AND (@Pattern IS NULL OR r.RoleName LIKE @Pattern ESCAPE '\' OR r.RoleCode LIKE @Pattern ESCAPE '\'))
             OR (@Action = 'ROLE_GET' AND r.RoleId = @RoleId)
        ORDER BY CASE WHEN r.RoleCode = N'SYSADMIN' THEN 0 ELSE 1 END, r.RoleName;
        RETURN;
    END;

    IF @Action = 'ROLE_CODES'
    BEGIN
        SELECT p.PermissionCode
        FROM   [Security].[RolePermissions] rp
        JOIN   [Security].[Permissions] p ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
        JOIN   @Visible v ON v.RoleId = rp.RoleId
        WHERE  rp.RoleId = @RoleId AND rp.Deleted = 0
        ORDER BY p.PermissionCode;
        RETURN;
    END;

    /* ======================= ROLE_SAVE ============================ */
    IF @Action = 'ROLE_SAVE'
    BEGIN
        DECLARE @eCode NVARCHAR(50), @eCompany INT;
        IF ISNULL(@RoleId, 0) > 0
        BEGIN
            SELECT @eCode = RoleCode, @eCompany = CompanyId FROM [Security].[Roles] WHERE RoleId = @RoleId AND Deleted = 0;
            IF @eCode IS NULL OR NOT EXISTS (SELECT 1 FROM @Visible WHERE RoleId = @RoleId)
            BEGIN
                SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That role no longer exists. Refresh and try again.';
                RETURN;
            END;
            IF @eCode = N'SYSADMIN'
            BEGIN
                SELECT @ResultCode = 'SYSTEM_ROLE', @ResultMessage = N'System Administrator is a system role - it always has every right.';
                RETURN;
            END;
            IF @CompanyId IS NOT NULL AND ISNULL(@eCompany, 0) <> @CompanyId
            BEGIN
                SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'Only a System Administrator can change a role shared by every company.';
                RETURN;
            END;
        END;

        IF @RoleCode IS NULL OR @RoleName IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the role code and name.';
            RETURN;
        END;
        IF @RoleCode = N'SYSADMIN' OR @RoleCode LIKE N'%[^A-Z0-9_]%'
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The role code may use letters, digits and _ only, and cannot be SYSADMIN.';
            RETURN;
        END;
        /* a pinned caller's roles always belong to their company */
        IF @CompanyId IS NOT NULL SET @RoleCompanyId = @CompanyId;

        IF EXISTS (SELECT 1 FROM [Security].[Roles] WHERE Deleted = 0 AND RoleCode = @RoleCode AND RoleId <> ISNULL(@RoleId, 0)
                     AND ISNULL(CompanyId, 0) = ISNULL(@RoleCompanyId, 0))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'Another role already uses this code.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            IF ISNULL(@RoleId, 0) = 0
            BEGIN
                INSERT INTO [Security].[Roles] (CompanyId, RoleCode, RoleName, [Description], IsActive, ModifiedBy, ModifiedDate)
                VALUES (@RoleCompanyId, @RoleCode, @RoleName, @Description, ISNULL(@IsActive, 1), @ActionBy, @Now);
                SET @NewId = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                UPDATE [Security].[Roles]
                   SET RoleCode = @RoleCode, RoleName = @RoleName, [Description] = @Description, IsActive = ISNULL(@IsActive, 1),
                       CompanyId = CASE WHEN @CompanyId IS NULL THEN @RoleCompanyId ELSE CompanyId END,
                       ModifiedBy = @ActionBy, ModifiedDate = @Now
                WHERE RoleId = @RoleId;
                SET @NewId = @RoleId;
            END;

            /* the rights: only the codes the screen manages are replaced */
            DECLARE @Managed TABLE (PermissionId INT PRIMARY KEY);
            INSERT INTO @Managed
            SELECT DISTINCT p.PermissionId FROM [Security].[Permissions] p
            WHERE p.Deleted = 0 AND p.PermissionCode IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(ISNULL(@ManagedCodes, N''), N','));

            DECLARE @Granted TABLE (PermissionId INT PRIMARY KEY);
            INSERT INTO @Granted
            SELECT DISTINCT p.PermissionId FROM [Security].[Permissions] p
            JOIN @Managed m ON m.PermissionId = p.PermissionId
            WHERE p.PermissionCode IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(ISNULL(@GrantedCodes, N''), N','));

            UPDATE rp SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now
            FROM   [Security].[RolePermissions] rp
            JOIN   @Managed m ON m.PermissionId = rp.PermissionId
            WHERE  rp.RoleId = @NewId AND rp.Deleted = 0
              AND  NOT EXISTS (SELECT 1 FROM @Granted g WHERE g.PermissionId = rp.PermissionId);

            UPDATE rp SET Deleted = 0, DeletedBy = NULL, DeletedDate = NULL
            FROM   [Security].[RolePermissions] rp
            JOIN   @Granted g ON g.PermissionId = rp.PermissionId
            WHERE  rp.RoleId = @NewId AND rp.Deleted = 1;

            INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
            SELECT @NewId, g.PermissionId FROM @Granted g
            WHERE NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp WHERE rp.RoleId = @NewId AND rp.PermissionId = g.PermissionId);

            INSERT INTO [Security].[RoleAccessLog] (RoleId, ActionCode, Detail, ActionBy)
            VALUES (@NewId, CASE WHEN ISNULL(@RoleId, 0) = 0 THEN 'ROLE_CREATED' ELSE 'ROLE_CHANGED' END,
                    LEFT(CONCAT(@RoleCode, N': ', (SELECT COUNT(1) FROM @Granted), N' rights'), 2000), @ActionBy);
        COMMIT TRANSACTION;

        SET @ResultMessage = CASE WHEN ISNULL(@RoleId, 0) = 0 THEN N'Role created.' ELSE N'Role saved.' END;
        RETURN;
    END;

    /* ======================= ROLE_DELETE ========================== */
    IF @Action = 'ROLE_DELETE'
    BEGIN
        DECLARE @dCode NVARCHAR(50), @dCompany INT;
        SELECT @dCode = RoleCode, @dCompany = CompanyId FROM [Security].[Roles] WHERE RoleId = @RoleId AND Deleted = 0;
        IF @dCode IS NULL OR NOT EXISTS (SELECT 1 FROM @Visible WHERE RoleId = @RoleId)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That role no longer exists. Refresh and try again.';
            RETURN;
        END;
        IF @dCode = N'SYSADMIN'
        BEGIN
            SELECT @ResultCode = 'SYSTEM_ROLE', @ResultMessage = N'System Administrator is a system role and cannot be deleted.';
            RETURN;
        END;
        IF @CompanyId IS NOT NULL AND ISNULL(@dCompany, 0) <> @CompanyId
        BEGIN
            SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'Only a System Administrator can delete a role shared by every company.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Security].[UserRoles] ur JOIN [Security].[Users] u ON u.UserId = ur.UserId
                   WHERE ur.RoleId = @RoleId AND ur.Deleted = 0 AND u.Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Users still have this role. Remove it from them on Assign Roles first.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE [Security].[Roles] SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now WHERE RoleId = @RoleId;
            INSERT INTO [Security].[RoleAccessLog] (RoleId, ActionCode, Detail, ActionBy) VALUES (@RoleId, 'ROLE_DELETED', @dCode, @ActionBy);
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Role deleted.';
        RETURN;
    END;

    /* ======================= USERS =============================== */
    IF @Action = 'USERS'
    BEGIN
        DECLARE @U TABLE (UserId BIGINT PRIMARY KEY, SortName NVARCHAR(300));
        INSERT INTO @U
        SELECT u.UserId, COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))), N''), u.Username)
        FROM   [Security].[Users] u
        LEFT JOIN [Employee].[Employees] e ON e.EmployeeId = u.EmployeeId
        WHERE  u.Deleted = 0
          AND  (@CompanyId IS NULL OR u.CompanyId = @CompanyId)
          AND  (@UserId IS NULL OR u.UserId = @UserId)         -- one user (Assign Roles popup)
          AND  (@Pattern IS NULL OR u.Username LIKE @Pattern ESCAPE '\' OR u.Email LIKE @Pattern ESCAPE '\'
                OR e.FirstName LIKE @Pattern ESCAPE '\' OR e.LastName LIKE @Pattern ESCAPE '\')
          AND  (@RoleFilter IS NULL OR EXISTS (SELECT 1 FROM [Security].[UserRoles] ur WHERE ur.UserId = u.UserId AND ur.RoleId = @RoleFilter AND ur.Deleted = 0)
                OR (@RoleFilter = 0 AND NOT EXISTS (SELECT 1 FROM [Security].[UserRoles] ur JOIN [Security].[Roles] r ON r.RoleId = ur.RoleId
                                                     WHERE ur.UserId = u.UserId AND ur.Deleted = 0 AND r.Deleted = 0)));

        SET @TotalCount = (SELECT COUNT(1) FROM @U);

        SELECT  u.UserId, u.Username, u.Email, x.SortName AS DisplayName, u.CompanyId, co.CompanyName, u.IsActive, u.LastLoginDate,
                e.EmployeeCode,
                (SELECT STRING_AGG(CAST(r.RoleId AS VARCHAR(12)), ',') FROM [Security].[UserRoles] ur
                   JOIN [Security].[Roles] r ON r.RoleId = ur.RoleId AND r.Deleted = 0
                  WHERE ur.UserId = u.UserId AND ur.Deleted = 0) AS RoleIds,
                (SELECT STRING_AGG(r.RoleName, N'|') WITHIN GROUP (ORDER BY r.RoleName) FROM [Security].[UserRoles] ur
                   JOIN [Security].[Roles] r ON r.RoleId = ur.RoleId AND r.Deleted = 0
                  WHERE ur.UserId = u.UserId AND ur.Deleted = 0) AS RoleNames
        FROM    @U x
        JOIN    [Security].[Users] u ON u.UserId = x.UserId
        LEFT JOIN [Employee].[Employees] e ON e.EmployeeId = u.EmployeeId
        LEFT JOIN [Core].[Companies] co ON co.CompanyId = u.CompanyId
        ORDER BY x.SortName, u.Username
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= USER_ROLES_SET ====================== */
    IF @Action = 'USER_ROLES_SET'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Security].[Users] WHERE UserId = @UserId AND Deleted = 0
                         AND (@CompanyId IS NULL OR CompanyId = @CompanyId))
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That user was not found.';
            RETURN;
        END;

        /* a user gets global roles and their own company's roles only */
        DECLARE @UserCompany INT = (SELECT CompanyId FROM [Security].[Users] WHERE UserId = @UserId);
        DECLARE @Want TABLE (RoleId INT PRIMARY KEY);
        INSERT INTO @Want
        SELECT DISTINCT v.RoleId FROM @Visible v
        JOIN [Security].[Roles] r ON r.RoleId = v.RoleId
        WHERE v.RoleId IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(ISNULL(@RoleIds, N''), N','))
          AND (r.CompanyId IS NULL OR @UserCompany IS NULL OR r.CompanyId = @UserCompany);

        DECLARE @SysRole INT = (SELECT TOP 1 RoleId FROM [Security].[Roles] WHERE RoleCode = N'SYSADMIN' AND Deleted = 0 ORDER BY CASE WHEN CompanyId IS NULL THEN 0 ELSE 1 END);
        DECLARE @HasSys BIT = CASE WHEN EXISTS (SELECT 1 FROM [Security].[UserRoles] WHERE UserId = @UserId AND RoleId = @SysRole AND Deleted = 0) THEN 1 ELSE 0 END;
        DECLARE @WantsSys BIT = CASE WHEN EXISTS (SELECT 1 FROM @Want WHERE RoleId = @SysRole) THEN 1 ELSE 0 END;

        IF @HasSys <> @WantsSys AND ISNULL(@CallerIsSysAdmin, 0) = 0
        BEGIN
            SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'Only a System Administrator can give or remove the System Administrator role.';
            RETURN;
        END;
        IF @HasSys = 1 AND @WantsSys = 0
           AND NOT EXISTS (SELECT 1 FROM [Security].[UserRoles] ur JOIN [Security].[Users] u ON u.UserId = ur.UserId
                           WHERE ur.RoleId = @SysRole AND ur.Deleted = 0 AND u.Deleted = 0 AND u.IsActive = 1 AND u.UserId <> @UserId)
        BEGIN
            SELECT @ResultCode = 'LAST_ADMIN', @ResultMessage = N'This is the last active System Administrator - give the role to another user first.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            /* only the roles the caller can see change; others the user holds stay */
            UPDATE ur SET Deleted = 1, DeletedBy = @ActionBy, DeletedDate = @Now
            FROM   [Security].[UserRoles] ur
            JOIN   @Visible v ON v.RoleId = ur.RoleId
            WHERE  ur.UserId = @UserId AND ur.Deleted = 0 AND NOT EXISTS (SELECT 1 FROM @Want w WHERE w.RoleId = ur.RoleId);

            UPDATE ur SET Deleted = 0, DeletedBy = NULL, DeletedDate = NULL
            FROM   [Security].[UserRoles] ur JOIN @Want w ON w.RoleId = ur.RoleId
            WHERE  ur.UserId = @UserId AND ur.Deleted = 1;

            INSERT INTO [Security].[UserRoles] (UserId, RoleId)
            SELECT @UserId, w.RoleId FROM @Want w
            WHERE NOT EXISTS (SELECT 1 FROM [Security].[UserRoles] ur WHERE ur.UserId = @UserId AND ur.RoleId = w.RoleId);

            INSERT INTO [Security].[RoleAccessLog] (UserId, ActionCode, Detail, ActionBy)
            VALUES (@UserId, 'USER_ROLES', LEFT(ISNULL(@RoleIds, N''), 2000), @ActionBy);
        COMMIT TRANSACTION;

        SET @ResultMessage = N'Roles saved. They apply to the user within a minute.';
        RETURN;
    END;
END;
GO
