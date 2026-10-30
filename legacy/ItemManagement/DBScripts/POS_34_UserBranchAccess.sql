/**********************************************************************************
  POS_34_UserBranchAccess.sql   -   Per-user Branch access for the Order List
  and the Dashboard reports.

  Adds a many-to-many "which branches can this user see" mapping and wires it
  into login, the User Management screen, and both places that filter by
  branch today (Order List, Dashboard reports). No existing stored procedure
  that already filters by a branch-ID CSV had to change shape - the C# layer
  narrows the CSV it hands them before it ever reaches SQL, so this script
  only touches login, the User Management procs, and adds the new table.

  >>> POLICY, AS CONFIRMED <<<
    - A user with the "manage users/settings" permission (CanManageMasters -
      today that is the Administrator role) always sees every branch, in the
      Order List and in Dashboard reports, no matter what is or is not
      assigned to them here.
    - Every other user sees ONLY the branches assigned to them below. A user
      with ZERO branches assigned sees NOTHING in the Order List or Dashboard
      reports - this is deliberate, not a bug. Existing accounts (everyone
      except whoever already has CanManageMasters) will see zero orders and
      zero report data the moment this script runs, until an admin visits
      User Management and assigns branches to them.

  Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 1 - tblPOS_UserBranch_Map
==============================================================================*/
IF OBJECT_ID('dbo.tblPOS_UserBranch_Map') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_UserBranch_Map
    (
          ID       INT IDENTITY(1,1) NOT NULL
        , UserID   INT NOT NULL
        , BranchID INT NOT NULL
        , CONSTRAINT PK_tblPOS_UserBranch_Map PRIMARY KEY CLUSTERED (ID)
        , CONSTRAINT UQ_tblPOS_UserBranch_Map UNIQUE (UserID, BranchID)
    );
    CREATE INDEX IX_tblPOS_UserBranch_Map_UserID ON dbo.tblPOS_UserBranch_Map (UserID);
    PRINT '34.1  tblPOS_UserBranch_Map created.';
END
ELSE PRINT '34.1  tblPOS_UserBranch_Map already exists.';
GO


/*==============================================================================
  SECTION 2 - sp_POS_Login, now also returning the user's assigned branches

  Result set 0 is unchanged in shape. Result set 1 is new: one row per
  assigned BranchID, empty for a user with none (which, per policy above,
  means "sees nothing" once their role is not CanManageMasters).
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_Login') IS NOT NULL DROP PROCEDURE dbo.sp_POS_Login;
GO

CREATE PROCEDURE dbo.sp_POS_Login
      @Username NVARCHAR(50)
    , @Password NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MatchedUserID INT;

    SELECT @MatchedUserID = u.ID
    FROM   dbo.tblUser u
    WHERE  u.USERNAME = @Username
      AND  (
                (u.PasswordHash IS NOT NULL
                 AND u.PasswordHash = HASHBYTES('SHA2_512', u.PasswordSalt + CONVERT(VARBINARY(200), @Password)))
             OR (u.PasswordHash IS NULL AND u.PASSWORD = @Password)
           );

    -- result set 0: the user row - deliberately no row on failure, same as
    -- before, so the login form cannot be used to enumerate accounts.
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
    WHERE     u.ID = @MatchedUserID;

    -- result set 1: assigned branch IDs
    SELECT BranchID
    FROM   dbo.tblPOS_UserBranch_Map
    WHERE  UserID = @MatchedUserID;
END
GO
PRINT '34.2  sp_POS_Login now also returns assigned branch IDs.';
GO


/*==============================================================================
  SECTION 3 - sp_POS_User_List, now also returning every user's assigned
  branches in one extra result set (avoids one round trip per row in the
  grid, and prefills the edit form's branch checklist)
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_User_List') IS NOT NULL DROP PROCEDURE dbo.sp_POS_User_List;
GO

CREATE PROCEDURE dbo.sp_POS_User_List
AS
BEGIN
    SET NOCOUNT ON;

    -- result set 0: the grid, unchanged
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

    -- result set 1: every user's assigned branches (Order List / Dashboard
    -- access) - a different thing from BrandID above, which is unrelated.
    SELECT
          m.UserID
        , m.BranchID
        , BranchName = ISNULL(ab.branchName, N'?')
    FROM      dbo.tblPOS_UserBranch_Map m
    LEFT JOIN dbo.tblbranch ab ON ab.id = m.BranchID
    ORDER BY  m.UserID, ab.branchName;
END
GO
PRINT '34.3  sp_POS_User_List now also returns assigned Order List / Dashboard branches.';
GO


/*==============================================================================
  SECTION 4 - sp_POS_User_Save, now also replacing the assigned-branches set
  in the same transaction as the user row

  @BranchIDs is a CSV of dbo.tblbranch.id values, always taken as the COMPLETE
  desired set - an empty string means "assign no branches" (which, for a
  non-CanManageMasters user, means they will see nothing), not "leave
  unchanged". The edit form always submits the full checklist state, so this
  matches what the admin sees on screen.
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
    , @BranchIDs      NVARCHAR(1000) = NULL   -- CSV of dbo.tblbranch.id - Order List / Dashboard access
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
        BEGIN TRANSACTION;

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
            -- BrandID is deliberately NOT touched here - it is a separate,
            -- chain-level field (see sp_POS_GetLookups) that User Management
            -- does not manage. It is only ever set on INSERT, above, and is
            -- left exactly as it was on every UPDATE.
            IF @NewPassword IS NOT NULL
            BEGIN
                UPDATE dbo.tblUser
                   SET NAME          = @Name
                     , USERNAME      = @Username
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
                     , RoleID        = @RoleID
                 WHERE ID = @UserID;
            END

            INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
            VALUES ('User', @UserID, 'Update', @ActorUserID, @ActorUserName,
                    CONCAT(N'Username=', @Username,
                           N' RoleID ', ISNULL(@OldRoleID,0), N'->', @RoleID,
                           CASE WHEN @NewPassword IS NOT NULL THEN N' PasswordChanged' ELSE N'' END));
        END

        -- Order List / Dashboard branch access - always replaced with the
        -- complete set submitted, per the comment above the parameter list.
        DELETE FROM dbo.tblPOS_UserBranch_Map WHERE UserID = @UserID;

        INSERT INTO dbo.tblPOS_UserBranch_Map (UserID, BranchID)
        SELECT DISTINCT @UserID, TRY_CAST(value AS INT)
        FROM   STRING_SPLIT(ISNULL(@BranchIDs, N''), ',')
        WHERE  TRY_CAST(value AS INT) IS NOT NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', UserID = @UserID, ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
PRINT '34.4  sp_POS_User_Save now also saves Order List / Dashboard branch access.';
GO

PRINT 'POS_34_UserBranchAccess.sql complete.';
GO

/* Smoke test - replace values first:
   EXEC dbo.sp_POS_User_Save @UserID = <existing id>, @Name = N'Test User',
        @Username = N'testuser', @RoleID = 4, @BranchIDs = N'1,2';

   SELECT * FROM dbo.tblPOS_UserBranch_Map WHERE UserID = <existing id>;

   EXEC dbo.sp_POS_Login @Username = N'testuser', @Password = N'<whatever it is>';
   -> two result sets: the user row, then the assigned BranchID rows.
*/
