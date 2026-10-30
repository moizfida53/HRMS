/**********************************************************************************
  POS_33_UserManagement.sql   -   Admin-only User Management page (list / add /
  update / assign role / re-assign role) for the POS Area.

  Gate: the new UsersController requires POSPermission.ManageMasters, the same
  permission that already gates the "Settings" drawer link. Today only the
  Administrator role (RoleID 1) has CanManageMasters = 1, so this is
  functionally Admin-only, and it stays that way even if another role is later
  granted the same permission.

  >>> PASSWORD HASHING <<<
  This closes part of the gap flagged in POS_08_Auth.sql: tblUser.PASSWORD was
  plain text. From this script onward:
      - PasswordHash / PasswordSalt are added to tblUser (nullable).
      - Any password SET through the new Add/Update User screen is salted
        (CRYPT_GEN_RANDOM) and hashed (HASHBYTES('SHA2_512', salt + pwd)), and
        the legacy plain-text PASSWORD column is cleared for that user.
      - sp_POS_Login checks the hash first; if a user has no hash yet, it
        falls back to the old plain-text comparison, so nobody already using
        the system is locked out. That user is upgraded to a hash the next
        time their password is changed here.
      - Existing accounts left untouched keep working exactly as before -
        this script does not force a mass migration.

  Salted SHA2_512 is a solid improvement over plain text and is what fits
  cleanly inside a single stored procedure. A slow key-derivation function
  (PBKDF2 / bcrypt, computed in the C# layer) resists offline brute-forcing
  better and is worth doing later if that risk matters for this deployment.

  Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 1 - PasswordHash / PasswordSalt columns
==============================================================================*/
IF COL_LENGTH('dbo.tblUser', 'PasswordHash') IS NULL
    ALTER TABLE dbo.tblUser ADD PasswordHash VARBINARY(64) NULL;
IF COL_LENGTH('dbo.tblUser', 'PasswordSalt') IS NULL
    ALTER TABLE dbo.tblUser ADD PasswordSalt VARBINARY(32) NULL;
GO
PRINT '33.1  tblUser.PasswordHash / PasswordSalt present.';
GO


/*==============================================================================
  SECTION 2 - sp_POS_Login, updated to check the hash first

  Unchanged for every user who has not been touched by the new screen: the
  plain-text branch (PasswordHash IS NULL) still runs exactly the old
  comparison.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_Login') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Login;
GO

CREATE PROCEDURE dbo.sp_POS_Login
      @Username NVARCHAR(50)
    , @Password NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
          UserID           = u.ID
        , UserName         = u.NAME
        , LoginName        = u.USERNAME
        , BrandID          = TRY_CAST(u.BrandID AS INT)
        , RoleID           = ISNULL(u.RoleID, 4)
        , RoleName         = ISNULL(r.RoleName, N'Cashier')
        , CanChangeStatus  = ISNULL(r.CanChangeStatus, 1)
        , CanCancel        = ISNULL(r.CanCancel, 0)
        , CanRefund        = ISNULL(r.CanRefund, 0)
        , CanTransfer      = ISNULL(r.CanTransfer, 0)
        , CanTakePayment   = ISNULL(r.CanTakePayment, 1)
        , CanViewReports   = ISNULL(r.CanViewReports, 0)
        , CanEndDay        = ISNULL(r.CanEndDay, 0)
        , CanManageMasters = ISNULL(r.CanManageMasters, 0)
    FROM      dbo.tblUser u
    LEFT JOIN dbo.tblPOS_Role_Master r ON r.RoleID = u.RoleID
    WHERE     u.USERNAME = @Username
      AND     (
                    (u.PasswordHash IS NOT NULL
                     AND u.PasswordHash = HASHBYTES('SHA2_512', u.PasswordSalt + CONVERT(VARBINARY(200), @Password)))
                 OR (u.PasswordHash IS NULL AND u.PASSWORD = @Password)
              );

    -- Deliberately no row on failure: the caller cannot tell "bad user" from
    -- "bad password", so the login form cannot be used to enumerate accounts.
END
GO
PRINT '33.2  sp_POS_Login updated (hash-first, plain-text fallback).';
GO


/*==============================================================================
  SECTION 3 - sp_POS_Role_List   (Role dropdown)
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_Role_List') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Role_List;
GO

CREATE PROCEDURE dbo.sp_POS_Role_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RoleID, RoleName
    FROM   dbo.tblPOS_Role_Master
    ORDER BY RoleID;
END
GO
PRINT '33.3  sp_POS_Role_List created.';
GO


/*==============================================================================
  SECTION 4 - sp_POS_User_List   (the grid)

  Never returns PASSWORD / PasswordHash / PasswordSalt - only whether a hash
  exists, so the admin screen can show "secure password set" without the
  value ever leaving the database.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_User_List') IS NOT NULL DROP PROCEDURE dbo.sp_POS_User_List;
GO

CREATE PROCEDURE dbo.sp_POS_User_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
          u.ID
        , u.NAME
        , u.USERNAME
        , BranchID          = TRY_CAST(u.BrandID AS INT)
        , BranchName        = b.branchName
        , u.RoleID
        , RoleName          = ISNULL(r.RoleName, N'(no role)')
        , CanManageMasters  = ISNULL(r.CanManageMasters, 0)
        , HasHashedPassword = CASE WHEN u.PasswordHash IS NOT NULL THEN 1 ELSE 0 END
    FROM      dbo.tblUser u
    LEFT JOIN dbo.tblPOS_Role_Master r ON r.RoleID = u.RoleID
    LEFT JOIN dbo.tblbranch          b ON b.id     = TRY_CAST(u.BrandID AS INT)
    ORDER BY  u.NAME;
END
GO
PRINT '33.4  sp_POS_User_List created.';
GO


/*==============================================================================
  SECTION 5 - sp_POS_User_Save   (Add User + Update User + role at either)

  @UserID NULL or 0  -> insert a new user (a password is required)
  @UserID > 0        -> update NAME / USERNAME / BranchID / RoleID; the
                        password is only touched when @NewPassword is
                        non-blank, so an edit that does not mention the
                        password leaves it exactly as it was.

  Refuses to move the LAST CanManageMasters-capable user off that role -
  otherwise a mistake here locks every admin out of this very screen.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_User_Save') IS NOT NULL DROP PROCEDURE dbo.sp_POS_User_Save;
GO

CREATE PROCEDURE dbo.sp_POS_User_Save
      @UserID         INT           = NULL
    , @Name           NVARCHAR(100)
    , @Username       NVARCHAR(50)
    , @NewPassword    NVARCHAR(50)  = NULL
    , @BranchID       INT           = NULL
    , @RoleID         INT
    , @ActorUserID    INT           = NULL
    , @ActorUserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Name     = NULLIF(LTRIM(RTRIM(ISNULL(@Name, N''))), N'');
    SET @Username = NULLIF(LTRIM(RTRIM(ISNULL(@Username, N''))), N'');
    SET @NewPassword = NULLIF(LTRIM(RTRIM(ISNULL(@NewPassword, N''))), N'');
    IF @UserID IS NOT NULL AND @UserID <= 0 SET @UserID = NULL;

    DECLARE @IsInsert BIT = CASE WHEN @UserID IS NULL THEN 1 ELSE 0 END;
    DECLARE @Err NVARCHAR(500) = NULL;
    DECLARE @OldRoleID INT;

    /*---- validation, in the order the admin would hit it ------------------*/
    IF @Name IS NULL
        SET @Err = N'Name is required.';
    ELSE IF @Username IS NULL
        SET @Err = N'Username is required.';
    ELSE IF @IsInsert = 1 AND @NewPassword IS NULL
        SET @Err = N'A password is required for a new user.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID)
        SET @Err = N'Unknown role.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.tblUser WHERE USERNAME = @Username AND ISNULL(ID,0) <> ISNULL(@UserID,0))
        SET @Err = N'That username is already in use.';
    ELSE IF @IsInsert = 0 AND NOT EXISTS (SELECT 1 FROM dbo.tblUser WHERE ID = @UserID)
        SET @Err = N'User not found.';

    IF @Err IS NULL AND @IsInsert = 0
    BEGIN
        SELECT @OldRoleID = RoleID FROM dbo.tblUser WHERE ID = @UserID;

        -- Would this update take the CanManageMasters permission away from
        -- the only user who currently has it?
        IF EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @OldRoleID AND CanManageMasters = 1)
           AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID AND CanManageMasters = 1)
           AND (SELECT COUNT(*) FROM dbo.tblUser u3
                JOIN dbo.tblPOS_Role_Master r3 ON r3.RoleID = u3.RoleID
                WHERE r3.CanManageMasters = 1) <= 1
            SET @Err = N'This is the only user who can manage Settings/User Management - assign another user that role first.';
    END

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = @Err;
        RETURN;
    END

    DECLARE @Salt VARBINARY(32), @Hash VARBINARY(64);
    IF @NewPassword IS NOT NULL
    BEGIN
        SET @Salt = CRYPT_GEN_RANDOM(16);
        SET @Hash = HASHBYTES('SHA2_512', @Salt + CONVERT(VARBINARY(200), @NewPassword));
    END

    BEGIN TRY
        IF @IsInsert = 1
        BEGIN
            INSERT INTO dbo.tblUser (NAME, USERNAME, PASSWORD, PasswordHash, PasswordSalt, BrandID, RoleID)
            VALUES (@Name, @Username, N'', @Hash, @Salt, @BranchID, @RoleID);

            SET @UserID = SCOPE_IDENTITY();

            INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
            VALUES ('User', @UserID, 'Create', @ActorUserID, @ActorUserName,
                    CONCAT(N'Username=', @Username, N' RoleID=', @RoleID));
        END
        ELSE
        BEGIN
            IF @NewPassword IS NOT NULL
            BEGIN
                UPDATE dbo.tblUser
                   SET NAME          = @Name
                     , USERNAME      = @Username
                     , BrandID       = @BranchID
                     , RoleID        = @RoleID
                     , PasswordHash  = @Hash
                     , PasswordSalt  = @Salt
                     , PASSWORD      = N''
                 WHERE ID = @UserID;
            END
            ELSE
            BEGIN
                UPDATE dbo.tblUser
                   SET NAME          = @Name
                     , USERNAME      = @Username
                     , BrandID       = @BranchID
                     , RoleID        = @RoleID
                 WHERE ID = @UserID;
            END

            INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
            VALUES ('User', @UserID, 'Update', @ActorUserID, @ActorUserName,
                    CONCAT(N'Username=', @Username,
                           N' RoleID ', ISNULL(@OldRoleID,0), N'->', @RoleID,
                           CASE WHEN @NewPassword IS NOT NULL THEN N' PasswordChanged' ELSE N'' END));
        END
    END TRY
    BEGIN CATCH
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', UserID = @UserID, ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
PRINT '33.5  sp_POS_User_Save created.';
GO


/*==============================================================================
  SECTION 6 - sp_POS_User_ChangeRole   (the quick Assign/Re-Assign control on
  the grid row - same guardrail against locking out the last admin)
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_User_ChangeRole') IS NOT NULL DROP PROCEDURE dbo.sp_POS_User_ChangeRole;
GO

CREATE PROCEDURE dbo.sp_POS_User_ChangeRole
      @UserID         INT
    , @RoleID         INT
    , @ActorUserID    INT           = NULL
    , @ActorUserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Err NVARCHAR(500) = NULL, @OldRoleID INT;

    SELECT @OldRoleID = RoleID FROM dbo.tblUser WHERE ID = @UserID;

    IF @OldRoleID IS NULL
        SET @Err = N'User not found.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID)
        SET @Err = N'Unknown role.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @OldRoleID AND CanManageMasters = 1)
        AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID AND CanManageMasters = 1)
        AND (SELECT COUNT(*) FROM dbo.tblUser u3
             JOIN dbo.tblPOS_Role_Master r3 ON r3.RoleID = u3.RoleID
             WHERE r3.CanManageMasters = 1) <= 1
        SET @Err = N'This is the only user who can manage Settings/User Management - assign another user that role first.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        UPDATE dbo.tblUser SET RoleID = @RoleID WHERE ID = @UserID;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('User', @UserID, 'ChangeRole', @ActorUserID, @ActorUserName,
                CONCAT(N'RoleID ', ISNULL(@OldRoleID,0), N'->', @RoleID));
    END TRY
    BEGIN CATCH
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', UserID = @UserID, RoleID = @RoleID, ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
PRINT '33.6  sp_POS_User_ChangeRole created.';
GO

PRINT 'POS_33_UserManagement.sql complete.';
GO

/* Smoke test - replace values first:
   EXEC dbo.sp_POS_Role_List;
   EXEC dbo.sp_POS_User_List;
   EXEC dbo.sp_POS_User_Save @Name = N'Test User', @Username = N'testuser',
        @NewPassword = N'ChangeMe123', @BranchID = NULL, @RoleID = 4,
        @ActorUserID = 1, @ActorUserName = N'admin';
   EXEC dbo.sp_POS_User_ChangeRole @UserID = <the new ID above>, @RoleID = 3,
        @ActorUserID = 1, @ActorUserName = N'admin';
*/
