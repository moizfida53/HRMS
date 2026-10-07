/* ================================================================
   HRMS Kuwait - Module 1: authentication schema additions
   ----------------------------------------------------------------
   Run AFTER script 05.

   PURELY ADDITIVE. Adds the columns a real sign-in flow needs to
   Security.Users, creates a login audit trail, and seeds one
   administrator account so you can get into the application.

   Nothing existing is altered or dropped.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   1. Security.Users - columns required for lockout and password policy
   ----------------------------------------------------------------
   Without these there is no brute-force protection, which is the
   first thing a penetration test will exercise against a login form.
================================================================ */

IF COL_LENGTH('Security.Users', 'FailedLoginAttempts') IS NULL
    ALTER TABLE [Security].[Users]
        ADD FailedLoginAttempts INT NOT NULL
            CONSTRAINT DF_Users_FailedLoginAttempts DEFAULT(0);
GO

IF COL_LENGTH('Security.Users', 'LockoutEndUtc') IS NULL
    ALTER TABLE [Security].[Users] ADD LockoutEndUtc DATETIME2(0) NULL;
GO

IF COL_LENGTH('Security.Users', 'PasswordChangedDateUtc') IS NULL
    ALTER TABLE [Security].[Users] ADD PasswordChangedDateUtc DATETIME2(0) NULL;
GO

IF COL_LENGTH('Security.Users', 'MustChangePassword') IS NULL
    ALTER TABLE [Security].[Users]
        ADD MustChangePassword BIT NOT NULL
            CONSTRAINT DF_Users_MustChangePassword DEFAULT(0);
GO

IF COL_LENGTH('Security.Users', 'TwoFactorEnabled') IS NULL
    ALTER TABLE [Security].[Users]
        ADD TwoFactorEnabled BIT NOT NULL
            CONSTRAINT DF_Users_TwoFactorEnabled DEFAULT(0);
GO

/* Rotating this value invalidates every existing sign-in cookie for the
   user. Used on password change, role change, and forced sign-out. */
IF COL_LENGTH('Security.Users', 'SecurityStamp') IS NULL
    ALTER TABLE [Security].[Users]
        ADD SecurityStamp UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_Users_SecurityStamp DEFAULT(NEWID());
GO

IF COL_LENGTH('Security.Users', 'LastLoginIp') IS NULL
    ALTER TABLE [Security].[Users] ADD LastLoginIp NVARCHAR(64) NULL;
GO

IF COL_LENGTH('Security.Users', 'ModifiedDate') IS NULL
    ALTER TABLE [Security].[Users] ADD ModifiedDate DATETIME2(0) NULL;
GO

/* Sign-in looks users up by username OR email; index both. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Users_Email' AND object_id = OBJECT_ID(N'Security.Users'))
    CREATE INDEX IX_Users_Email ON [Security].[Users](Email) WHERE Email IS NOT NULL;
GO

/* ================================================================
   2. Security.UserLoginHistory - the audit trail
   ----------------------------------------------------------------
   Every attempt is recorded, successful or not, including attempts
   against usernames that do not exist. This is what lets you answer
   "was this account targeted?" during an incident review.
================================================================ */
IF OBJECT_ID(N'[Security].[UserLoginHistory]', N'U') IS NULL
BEGIN
    CREATE TABLE [Security].[UserLoginHistory](
        LoginHistoryId    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UserLoginHistory PRIMARY KEY,
        UserId            BIGINT NULL,
        UsernameAttempted NVARCHAR(100) NOT NULL,
        Outcome           VARCHAR(30) NOT NULL,
        IpAddress         NVARCHAR(64) NULL,
        UserAgent         NVARCHAR(400) NULL,
        AttemptedUtc      DATETIME2(0) NOT NULL
            CONSTRAINT DF_UserLoginHistory_AttemptedUtc DEFAULT(SYSUTCDATETIME()),
        CONSTRAINT FK_UserLoginHistory_User FOREIGN KEY(UserId) REFERENCES [Security].[Users](UserId),
        CONSTRAINT CK_UserLoginHistory_Outcome CHECK(Outcome IN
            ('SUCCESS', 'BAD_PASSWORD', 'UNKNOWN_USER', 'INACTIVE', 'LOCKED_OUT'))
    );

    CREATE INDEX IX_UserLoginHistory_User
        ON [Security].[UserLoginHistory](UserId, AttemptedUtc DESC);

    CREATE INDEX IX_UserLoginHistory_Username
        ON [Security].[UserLoginHistory](UsernameAttempted, AttemptedUtc DESC);
END
GO

/* ================================================================
   3. Permissions for the Organization Setup module
================================================================ */
INSERT INTO [Security].[Permissions](PermissionCode, Module, Action)
SELECT v.PermissionCode, v.Module, v.Action
FROM (VALUES
    ('ORGANIZATION_VIEW',   'Organization', 'View'),
    ('ORGANIZATION_CREATE', 'Organization', 'Create'),
    ('ORGANIZATION_EDIT',   'Organization', 'Edit'),
    ('ORGANIZATION_DELETE', 'Organization', 'Delete')
) v(PermissionCode, Module, Action)
WHERE NOT EXISTS (
    SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = v.PermissionCode);
GO

/* ================================================================
   4. System Administrator role, holding every permission
================================================================ */
IF NOT EXISTS (SELECT 1 FROM [Security].[Roles] WHERE RoleCode = N'SYSADMIN' AND CompanyId IS NULL)
    INSERT INTO [Security].[Roles](CompanyId, RoleCode, RoleName)
    VALUES(NULL, N'SYSADMIN', N'System Administrator');
GO

DECLARE @SysAdminRoleId INT =
    (SELECT TOP 1 RoleId FROM [Security].[Roles] WHERE RoleCode = N'SYSADMIN' AND CompanyId IS NULL);

INSERT INTO [Security].[RolePermissions](RoleId, PermissionId)
SELECT @SysAdminRoleId, p.PermissionId
FROM [Security].[Permissions] AS p
WHERE NOT EXISTS (
    SELECT 1 FROM [Security].[RolePermissions] rp
    WHERE rp.RoleId = @SysAdminRoleId AND rp.PermissionId = p.PermissionId);
GO

/* ================================================================
   5. Seed administrator account
   ----------------------------------------------------------------
   Username : administrator
   Password : Admin@12345

   >>> CHANGE THIS PASSWORD IMMEDIATELY AFTER YOUR FIRST SIGN-IN. <<<

   The stored value is PBKDF2-HMAC-SHA256, 210,000 iterations, with a
   random 16-byte salt and a 32-byte subkey, in the format the
   application's hasher produces and verifies:

       byte 0      format marker (0x01)
       bytes 1-4   iteration count, big-endian
       bytes 5-20  salt
       bytes 21-52 derived subkey

   MustChangePassword is set to 1, so the application will keep
   prompting until the password is changed.
================================================================ */
IF NOT EXISTS (SELECT 1 FROM [Security].[Users] WHERE Username = N'administrator')
BEGIN
    INSERT INTO [Security].[Users]
        (CompanyId, EmployeeId, Username, Email, PasswordHash, IsActive, MustChangePassword)
    VALUES
        (NULL, NULL, N'administrator', NULL,
         N'AQADNFAgrf6oGiAWo9PO5BtyjWe2sZZqxtIylZk3jNmtjkmGcBOsi3QMFuy0vZD8NRPDSGU=',
         1, 1);

    PRINT 'Seed account created -> username: administrator  password: Admin@12345';
    PRINT 'CHANGE THIS PASSWORD AFTER YOUR FIRST SIGN-IN.';
END
ELSE
    PRINT 'User [administrator] already exists - left unchanged.';
GO

DECLARE @AdminUserId    BIGINT = (SELECT TOP 1 UserId FROM [Security].[Users] WHERE Username = N'administrator');
DECLARE @SysAdminRoleId INT    = (SELECT TOP 1 RoleId FROM [Security].[Roles]  WHERE RoleCode = N'SYSADMIN' AND CompanyId IS NULL);

IF @AdminUserId IS NOT NULL AND @SysAdminRoleId IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM [Security].[UserRoles]
                   WHERE UserId = @AdminUserId AND RoleId = @SysAdminRoleId)
BEGIN
    INSERT INTO [Security].[UserRoles](UserId, RoleId) VALUES(@AdminUserId, @SysAdminRoleId);
END
GO

PRINT 'Authentication schema additions applied.';
GO
