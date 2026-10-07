/* ================================================================
   HRMS Kuwait - Module 1: authentication stored procedures
   ----------------------------------------------------------------
   One multi-action procedure for the whole sign-in flow, following the
   same consolidation rule as the Organization module.

   Actions:
     LOGIN_LOOKUP     resolve a username or email to the credential row
     LOGIN_SUCCESS    clear the failure counter, stamp the login
     LOGIN_FAILURE    increment the counter, lock the account at threshold
     GET_PERMISSIONS  permission codes granted through the user's roles
     GET_ROLES        role codes held by the user
     CHANGE_PASSWORD  set a new hash and rotate the security stamp
     UNLOCK           clear a lockout (administrative action)

   Security notes:
     * LOGIN_LOOKUP never decides anything. It returns the stored hash
       and account state; the application compares the hash and applies
       the policy. The database is not asked to compare passwords, so a
       password never travels to SQL Server in any form.
     * The lockout window and threshold are parameters, not literals, so
       policy lives in configuration rather than in a redeployed procedure.
     * Every attempt is written to Security.UserLoginHistory, including
       attempts against usernames that do not exist.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [Security].[usp_Auth_Manage]
    @Action           VARCHAR(20),

    @UserId           BIGINT         = NULL,
    @Username         NVARCHAR(100)  = NULL,

    /* supplied by the application, never by the browser */
    @PasswordHash     NVARCHAR(500)  = NULL,
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
                       'GET_PERMISSIONS', 'GET_ROLES', 'CHANGE_PASSWORD', 'UNLOCK')
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

        UPDATE [Security].[Users]
           SET PasswordHash           = @PasswordHash,
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

PRINT 'Authentication stored procedure created: Security.usp_Auth_Manage.';
GO
