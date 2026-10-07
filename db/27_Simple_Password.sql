/* ================================================================
   HRMS Kuwait - "SimplePassword" mode (appsettings Authentication:SimplePassword)
   ----------------------------------------------------------------
   SimplePassword = false (default): unchanged - PBKDF2 hash only.
   SimplePassword = true:
     * sign-in compares the typed password with Security.Users.[Password]
       (plain text). An account whose [Password] is still empty signs in
       with its hashed password once, and [Password] is filled then.
     * Change Password saves the new password as-is in [Password] AND
       keeps PasswordHash current, so the setting can be switched back
       to false at any time without resetting anyone's password.
   An administrator can also set a password directly:
       UPDATE Security.Users SET [Password] = N'...' WHERE Username = N'...';
   (simple mode only - in normal mode [Password] is ignored).

   SECURITY: in simple mode every password is readable by anyone with
   SELECT on Security.Users, and in every database backup.

   Adds   Security.Users.[Password] NVARCHAR(50) NULL
   Re-creates Security.usp_Auth_Manage (db/07 + [Password]):
     LOGIN_LOOKUP     also returns [Password]
     CHANGE_PASSWORD  new @PlainPassword (NULL in normal mode clears it)
     SET_PLAIN        new - fills [Password] on first simple-mode sign-in

   Run AFTER 07. Safe to re-run.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('Security.Users', 'Password') IS NULL
    ALTER TABLE [Security].[Users] ADD [Password] NVARCHAR(50) NULL;
GO

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

PRINT N'db/27 applied: Security.Users.[Password] + usp_Auth_Manage SimplePassword support.';
GO
