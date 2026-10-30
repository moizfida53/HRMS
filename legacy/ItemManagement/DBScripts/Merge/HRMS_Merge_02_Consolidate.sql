/*==============================================================================
  HRMS_Merge_02_Consolidate.sql
  ------------------------------------------------------------------------------
  Run on HRMS_Kuwait, in SSMS, AFTER HRMS_Merge_ItemsManagement.sql (step 01).
  Moves the QR Menu masters onto the HRMS tables and rewrites the procedures
  that used them, so the QR Menu app keeps working unchanged.

    tblcompany            -> Core.Companies   (first company = the QR default company)
    tblUser               -> Security.Users   (+ DisplayName, DeletePassword, BrandID,
                                                 PosPasswordHash, PosPasswordSalt, IsQrMenuUser)
    tblRole +
    tblPOS_Role_Master    -> Security.Roles   (+ LegacyRoleId, MenuRoleName, IsPosRole)
                             Can* flags      -> Security.Permissions POS_* + RolePermissions
    tblUser.RoleID        -> Security.UserRoles
    tblPOS_AuditLog       -> Security.AuditLogs (+ UserName)
    tblLabelName          -> Core.UiLabels      (+ LegacyKey, Module = 'qrmenu')
    tblPrinter            -> removed (unused; tblPOS_Printer stays)
    tblbranch, tblSection, tblAudit, tblAuditDetails, AuditTrail,
    tblPOS_UserBranch_Map: unchanged (and every procedure that only uses them)

  IDs: QR user IDs are kept when they are free in Security.Users. If they
  clash, new IDs are issued and every Items Management column that stores a
  user ID is updated (listed in the Messages tab). Role IDs are always
  kept as LegacyRoleId, because the app and procedures compare them as numbers.

  Take a backup first. Section 2 (data) is one transaction; the rest is not.
==============================================================================*/
SET NOCOUNT ON;
SET NOEXEC OFF;
GO
/*------------------------------------------------------------------------------
  0. PRE-CHECKS
------------------------------------------------------------------------------*/
IF DB_NAME() <> N'HRMS_Kuwait'
BEGIN RAISERROR(N'STOPPED: run this on HRMS_Kuwait. Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1) WITH NOWAIT; SET NOEXEC ON; END;
GO
IF OBJECT_ID(N'dbo.tblUser', N'U') IS NULL
BEGIN RAISERROR(N'STOPPED: run HRMS_Merge_ItemsManagement.sql (step 01) first (it did not finish), or this script has already run. Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1) WITH NOWAIT; SET NOEXEC ON; END;
GO
IF COL_LENGTH(N'Security.Users', N'IsQrMenuUser') IS NOT NULL
BEGIN RAISERROR(N'STOPPED: Security.Users already has IsQrMenuUser - this script has already run (partly?). Restore the backup. Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1) WITH NOWAIT; SET NOEXEC ON; END;
GO
IF CONVERT(sysname, DATABASEPROPERTYEX(DB_NAME(), 'Collation')) NOT LIKE N'%[_]CI[_]%'
BEGIN RAISERROR(N'STOPPED: the database collation is case-sensitive; the rewritten procedures rely on case-insensitive column names. Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1) WITH NOWAIT; SET NOEXEC ON; END;
GO
PRINT N'Pre-checks passed.';
GO
/*------------------------------------------------------------------------------
  1. NEW COLUMNS, INDEXES AND PERMISSION CODES ON THE HRMS TABLES
------------------------------------------------------------------------------*/
ALTER TABLE Security.Users ADD
      DisplayName     NVARCHAR(100)  NULL   -- tblUser.NAME
    , DeletePassword  NVARCHAR(50)   NULL   -- manager password for deletes/cancels
    , BrandID         VARCHAR(50)    NULL   -- tblUser.BrandID, as it was
    , PosPasswordHash VARBINARY(64)  NULL   -- POS SHA2-512 hash
    , PosPasswordSalt VARBINARY(32)  NULL
    , IsQrMenuUser    BIT NOT NULL CONSTRAINT DF_Users_IsQrMenuUser DEFAULT (0);
GO
ALTER TABLE Security.Roles ADD
      LegacyRoleId INT          NULL        -- the role number the QR app uses
    , MenuRoleName NVARCHAR(50) NULL        -- name from tblRole (menu admin roles)
    , IsPosRole    BIT NOT NULL CONSTRAINT DF_Roles_IsPosRole DEFAULT (0);  -- was in tblPOS_Role_Master
GO
ALTER TABLE Security.AuditLogs ADD UserName NVARCHAR(100) NULL;
GO
ALTER TABLE Core.UiLabels ADD LegacyKey NVARCHAR(100) NULL;   -- tblLabelName.labelName, as the app looks it up
GO
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON;
SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
GO
CREATE UNIQUE INDEX UX_Roles_LegacyRoleId ON Security.Roles (LegacyRoleId) WHERE LegacyRoleId IS NOT NULL;
CREATE INDEX IX_UiLabels_LegacyKey ON Core.UiLabels (Module, LegacyKey) WHERE LegacyKey IS NOT NULL;
GO
INSERT INTO Security.Permissions (PermissionCode, Module, [Action])
SELECT v.Code, N'POS', v.Act
FROM (VALUES (N'POS_CHANGE_STATUS', N'ChangeStatus'), (N'POS_CANCEL', N'Cancel'), (N'POS_REFUND', N'Refund'),
             (N'POS_TRANSFER', N'Transfer'), (N'POS_TAKE_PAYMENT', N'TakePayment'), (N'POS_VIEW_REPORTS', N'ViewReports'),
             (N'POS_END_DAY', N'EndDay'), (N'POS_MANAGE_MASTERS', N'ManageMasters')) v (Code, Act)
WHERE NOT EXISTS (SELECT 1 FROM Security.Permissions p WHERE p.PermissionCode = v.Code);
GO
/*------------------------------------------------------------------------------
  2. MOVE THE DATA  (one transaction)
------------------------------------------------------------------------------*/
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;

DECLARE @sql NVARCHAR(MAX), @t sysname, @c sysname, @n INT;

/*---- 2a. companies ---------------------------------------------------------*/
DECLARE @CoMap TABLE (OldId INT PRIMARY KEY, NewId INT);
MERGE Core.Companies AS tgt
USING (SELECT id, companyName FROM dbo.tblcompany) AS src ON 1 = 0
WHEN NOT MATCHED THEN
    INSERT (CompanyCode, CompanyName, IsActive)
    VALUES (CONCAT(N'QR-', src.id), LEFT(ISNULL(NULLIF(LTRIM(RTRIM(src.companyName)), N''), CONCAT(N'Company ', src.id)), 200), 1)
OUTPUT src.id, inserted.CompanyId INTO @CoMap (OldId, NewId);

DECLARE @DefaultCompanyId INT = (SELECT TOP (1) NewId FROM @CoMap ORDER BY OldId);
IF @DefaultCompanyId IS NULL
    SET @DefaultCompanyId = (SELECT MIN(CompanyId) FROM Core.Companies WHERE Deleted = 0);
IF @DefaultCompanyId IS NULL
BEGIN
    INSERT INTO Core.Companies (CompanyCode, CompanyName, IsActive) VALUES (N'QR-1', N'QR Menu', 1);
    SET @DefaultCompanyId = SCOPE_IDENTITY();
END;
SET @n = (SELECT COUNT(*) FROM @CoMap);
PRINT CONCAT(N'Default company for QR Menu: CompanyId ', @DefaultCompanyId, N' (', @n, N' row(s) moved from tblcompany)');

SET @sql = N'CREATE OR ALTER FUNCTION dbo.fn_QR_DefaultCompanyId() RETURNS INT WITH SCHEMABINDING AS BEGIN RETURN '
         + CONVERT(NVARCHAR(20), @DefaultCompanyId) + N'; END;';
EXEC sys.sp_executesql @sql;

/*---- 2b. roles + POS permission flags ---------------------------------------*/
DECLARE @RoleMap TABLE (LegacyRoleId INT PRIMARY KEY, RoleId INT NOT NULL);
MERGE Security.Roles AS tgt
USING (
    SELECT LegacyRoleId = COALESCE(p.RoleID, m.Role_ID),
           PosName      = p.RoleName,
           MenuName     = m.RoleName
    FROM      dbo.tblPOS_Role_Master p
    FULL JOIN dbo.tblRole m ON m.Role_ID = p.RoleID
) AS src ON 1 = 0
WHEN NOT MATCHED THEN
    INSERT (CompanyId, RoleCode, RoleName, IsActive, LegacyRoleId, MenuRoleName, IsPosRole, [Description])
    VALUES (@DefaultCompanyId, CONCAT(N'QR_', src.LegacyRoleId), LEFT(COALESCE(src.PosName, src.MenuName), 100), 1,
            src.LegacyRoleId, src.MenuName, CASE WHEN src.PosName IS NOT NULL THEN 1 ELSE 0 END, N'QR Menu / POS role')
OUTPUT src.LegacyRoleId, inserted.RoleId INTO @RoleMap (LegacyRoleId, RoleId);

INSERT INTO Security.RolePermissions (RoleId, PermissionId)
SELECT rm.RoleId, pm.PermissionId
FROM dbo.tblPOS_Role_Master r
JOIN @RoleMap rm ON rm.LegacyRoleId = r.RoleID
CROSS APPLY (VALUES (N'POS_CHANGE_STATUS', r.CanChangeStatus), (N'POS_CANCEL', r.CanCancel), (N'POS_REFUND', r.CanRefund),
                    (N'POS_TRANSFER', r.CanTransfer), (N'POS_TAKE_PAYMENT', r.CanTakePayment), (N'POS_VIEW_REPORTS', r.CanViewReports),
                    (N'POS_END_DAY', r.CanEndDay), (N'POS_MANAGE_MASTERS', r.CanManageMasters)) f (Code, Flag)
JOIN Security.Permissions pm ON pm.PermissionCode = f.Code
WHERE f.Flag = 1;
SET @n = (SELECT COUNT(*) FROM @RoleMap);
PRINT CONCAT(N'Roles: ', @n, N' moved (legacy role numbers kept in LegacyRoleId).');

/*---- 2c. users -------------------------------------------------------------*/
DECLARE @U TABLE (OldId INT PRIMARY KEY, FinalUsername NVARCHAR(100) NOT NULL, Renamed BIT NOT NULL);
INSERT INTO @U (OldId, FinalUsername, Renamed)
SELECT x.ID,
       CASE WHEN x.Bad = 1 THEN LEFT(CONCAT(ISNULL(NULLIF(LTRIM(RTRIM(x.USERNAME)), N''), N'user'), N'_qr', x.ID), 100) ELSE x.USERNAME END,
       x.Bad
FROM (
    SELECT u.ID, u.USERNAME,
           Bad = CASE WHEN NULLIF(LTRIM(RTRIM(u.USERNAME)), N'') IS NULL
                        OR EXISTS (SELECT 1 FROM Security.Users su WHERE su.Username = u.USERNAME)
                        OR ROW_NUMBER() OVER (PARTITION BY u.USERNAME ORDER BY u.ID) > 1
                      THEN 1 ELSE 0 END
    FROM dbo.tblUser u
) x;
IF EXISTS (SELECT 1 FROM @U WHERE Renamed = 1)
BEGIN
    PRINT N'Usernames already taken in Security.Users (or blank/duplicate) - renamed:';
    DECLARE @rn NVARCHAR(MAX) = (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(N'   ', ISNULL(u.USERNAME, N'(blank)'), N' -> ', x.FinalUsername)), NCHAR(10))
                                 FROM @U x JOIN dbo.tblUser u ON u.ID = x.OldId WHERE x.Renamed = 1);
    PRINT @rn;
END;

DECLARE @UsMap TABLE (OldId INT PRIMARY KEY, NewId BIGINT NOT NULL);
IF NOT EXISTS (SELECT 1 FROM Security.Users su JOIN dbo.tblUser u ON u.ID = su.UserId)
BEGIN
    SET IDENTITY_INSERT Security.Users ON;
    INSERT INTO Security.Users (UserId, CompanyId, Username, [Password], DisplayName, DeletePassword, BrandID,
                                PosPasswordHash, PosPasswordSalt, IsQrMenuUser, IsActive)
    SELECT u.ID, @DefaultCompanyId, x.FinalUsername, u.[PASSWORD], u.NAME, u.DeletePassword, u.BrandID,
           u.PasswordHash, u.PasswordSalt, 1, 1
    FROM dbo.tblUser u JOIN @U x ON x.OldId = u.ID;
    SET IDENTITY_INSERT Security.Users OFF;
    INSERT INTO @UsMap (OldId, NewId) SELECT ID, ID FROM dbo.tblUser;
    PRINT CONCAT(N'Users: ', @@ROWCOUNT, N' moved, IDs kept.');
END
ELSE
BEGIN
    MERGE Security.Users AS tgt
    USING (SELECT u.*, x.FinalUsername FROM dbo.tblUser u JOIN @U x ON x.OldId = u.ID) AS src ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (CompanyId, Username, [Password], DisplayName, DeletePassword, BrandID, PosPasswordHash, PosPasswordSalt, IsQrMenuUser, IsActive)
        VALUES (@DefaultCompanyId, src.FinalUsername, src.[PASSWORD], src.NAME, src.DeletePassword, src.BrandID,
                src.PasswordHash, src.PasswordSalt, 1, 1)
    OUTPUT src.ID, inserted.UserId INTO @UsMap (OldId, NewId);
    SET @n = (SELECT COUNT(*) FROM @UsMap);
    PRINT CONCAT(N'Users: ', @n, N' moved with NEW IDs (old IDs were taken in Security.Users). Updating references:');

    DECLARE @UsCols TABLE (T sysname, C sysname);
    INSERT INTO @UsCols (T, C) VALUES
        (N'tblInvoice', N'WaiterID'),
        (N'tblInvoice', N'ModifiedBy'),
        (N'tblOrder', N'WaiterID'),
        (N'tblPOS_PaymentLink', N'CreatedBy'),
        (N'tblPOS_Printer', N'CreatedBy'),
        (N'tblPOS_Printer', N'ModifiedBy'),
        (N'tblPOS_UserBranch_Map', N'UserID'),
        (N'AuditTrail', N'Userid');
    SELECT * INTO #um FROM @UsMap;
    DECLARE cu CURSOR LOCAL FAST_FORWARD FOR SELECT T, C FROM @UsCols;
    OPEN cu; FETCH NEXT FROM cu INTO @t, @c;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'UPDATE x SET ' + QUOTENAME(@c) + N' = CAST(m.NewId AS INT) FROM dbo.' + QUOTENAME(@t) + N' x JOIN #um m ON m.OldId = x.' + QUOTENAME(@c) + N';';
        EXEC sys.sp_executesql @sql; SET @n = @@ROWCOUNT;
        PRINT CONCAT(N'   dbo.', @t, N'.', @c, N': ', @n, N' row(s)');
        FETCH NEXT FROM cu INTO @t, @c;
    END;
    CLOSE cu; DEALLOCATE cu;
    DROP TABLE #um;
    /* tblOrder.DeletePasswordUserID is text */
    UPDATE o SET DeletePasswordUserID = CONVERT(NVARCHAR(50), m.NewId)
    FROM dbo.tblOrder o JOIN @UsMap m ON CONVERT(NVARCHAR(50), m.OldId) = o.DeletePasswordUserID;
    PRINT CONCAT(N'   dbo.tblOrder.DeletePasswordUserID: ', @@ROWCOUNT, N' row(s)');
END;

INSERT INTO Security.UserRoles (UserId, RoleId)
SELECT m.NewId, rm.RoleId
FROM dbo.tblUser u
JOIN @UsMap   m  ON m.OldId = u.ID
JOIN @RoleMap rm ON rm.LegacyRoleId = u.RoleID;
PRINT CONCAT(N'User roles: ', @@ROWCOUNT, N' assigned.');

/*---- 2d. POS audit log -----------------------------------------------------*/
INSERT INTO Security.AuditLogs (CompanyId, UserId, UserName, EntityName, RecordId, [Action], NewValues, IPAddress, CreatedDate)
SELECT @DefaultCompanyId, m.NewId, a.UserName, a.EntityType, a.EntityID, a.[Action], a.Details, a.IPAddress, a.CreatedOn
FROM dbo.tblPOS_AuditLog a
LEFT JOIN @UsMap m ON m.OldId = a.UserID
ORDER BY a.AuditID;
PRINT CONCAT(N'Audit log: ', @@ROWCOUNT, N' row(s) moved.');

/*---- 2e. labels ------------------------------------------------------------*/
INSERT INTO Core.UiLabels (LabelKey, Module, EnglishText, ArabicText, LegacyKey, IsActive)
SELECT CONCAT('qrmenu.label', l.id), 'qrmenu',
       ISNULL(l.labelNameEng, ISNULL(l.labelName, N'')), l.labelNameArb, l.labelName, 1
FROM dbo.tblLabelName l;
PRINT CONCAT(N'Labels: ', @@ROWCOUNT, N' moved.');

COMMIT TRANSACTION;
PRINT N'Data moved and committed.';
GO
SET XACT_ABORT OFF;
GO
/*------------------------------------------------------------------------------
  3. HELPERS AND REWRITTEN PROCEDURES (31 procedures)
------------------------------------------------------------------------------*/

/*---- helper: the QR role a user holds (legacy role id kept for the app) ----*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER FUNCTION dbo.fn_QR_UserRole (@UserId BIGINT)
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) r.RoleId, r.LegacyRoleId, r.RoleName, r.MenuRoleName, r.IsPosRole
    FROM   Security.UserRoles ur
    JOIN   Security.Roles     r ON r.RoleId = ur.RoleId
    WHERE  ur.UserId = @UserId
      AND  ur.Deleted = 0 AND r.Deleted = 0
      AND  r.LegacyRoleId IS NOT NULL
    ORDER BY ur.UserRoleId DESC;
GO
/*---- helper: the 8 POS permission flags of a QR role, from RolePermissions ----*/
CREATE OR ALTER FUNCTION dbo.fn_QR_RoleFlags (@LegacyRoleId INT)
RETURNS TABLE
AS
RETURN
    SELECT r.RoleId, r.LegacyRoleId, r.RoleName
         , CanChangeStatus  = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_CHANGE_STATUS'  THEN 1 ELSE 0 END) AS BIT)
         , CanCancel        = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_CANCEL'         THEN 1 ELSE 0 END) AS BIT)
         , CanRefund        = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_REFUND'         THEN 1 ELSE 0 END) AS BIT)
         , CanTransfer      = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_TRANSFER'       THEN 1 ELSE 0 END) AS BIT)
         , CanTakePayment   = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_TAKE_PAYMENT'   THEN 1 ELSE 0 END) AS BIT)
         , CanViewReports   = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_VIEW_REPORTS'   THEN 1 ELSE 0 END) AS BIT)
         , CanEndDay        = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_END_DAY'        THEN 1 ELSE 0 END) AS BIT)
         , CanManageMasters = CAST(MAX(CASE WHEN p.PermissionCode = N'POS_MANAGE_MASTERS' THEN 1 ELSE 0 END) AS BIT)
    FROM      Security.Roles r
    LEFT JOIN Security.RolePermissions rp ON rp.RoleId = r.RoleId AND rp.Deleted = 0
    LEFT JOIN Security.Permissions     p  ON p.PermissionId = rp.PermissionId AND p.Deleted = 0
    WHERE     r.LegacyRoleId = @LegacyRoleId AND r.IsPosRole = 1 AND r.Deleted = 0
    GROUP BY  r.RoleId, r.LegacyRoleId, r.RoleName;
GO
/*---- helper: give a user one QR role (other QR roles are soft-deleted) ----*/
CREATE OR ALTER PROCEDURE dbo.usp_QR_SetUserRole
      @UserId       BIGINT
    , @LegacyRoleId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RoleId INT = (SELECT RoleId FROM Security.Roles WHERE LegacyRoleId = @LegacyRoleId AND Deleted = 0);

    UPDATE ur
       SET ur.Deleted = 1, ur.DeletedDate = SYSUTCDATETIME()
    FROM   Security.UserRoles ur
    JOIN   Security.Roles r ON r.RoleId = ur.RoleId
    WHERE  ur.UserId = @UserId AND ur.Deleted = 0
      AND  r.LegacyRoleId IS NOT NULL
      AND  (@RoleId IS NULL OR ur.RoleId <> @RoleId);

    IF @RoleId IS NULL RETURN;

    IF EXISTS (SELECT 1 FROM Security.UserRoles WHERE UserId = @UserId AND RoleId = @RoleId)
        UPDATE Security.UserRoles
           SET Deleted = 0, DeletedBy = NULL, DeletedDate = NULL
         WHERE UserId = @UserId AND RoleId = @RoleId AND Deleted = 1;
    ELSE
        INSERT INTO Security.UserRoles (UserId, RoleId) VALUES (@UserId, @RoleId);
END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[mvc_sp_AddWaiter]
@NAME nvarchar(max),
@USERNAME nvarchar(max),
@PASSWORD nvarchar(max),
@Role_ID int,
@BrandID nvarchar(max)=''
AS
BEGIN
 SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 insert into Security.Users (CompanyId, Username, [Password], DisplayName, BrandID, IsQrMenuUser, IsActive)
 values (dbo.fn_QR_DefaultCompanyId(), LEFT(@USERNAME, 100), LEFT(@PASSWORD, 50), LEFT(@NAME, 100), LEFT(@BrandID, 50), 1, 1)
 declare @NewUserId bigint = SCOPE_IDENTITY()
 exec dbo.usp_QR_SetUserRole @UserId = @NewUserId, @LegacyRoleId = @Role_ID
 COMMIT TRANSACTION;
END
GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[mvc_sp_GetRole]
AS
BEGIN
SELECT Role_ID  = LegacyRoleId,
       RoleName = MenuRoleName
FROM   Security.Roles
WHERE  MenuRoleName IS NOT NULL AND LegacyRoleId IS NOT NULL AND Deleted = 0
ORDER BY LegacyRoleId
END
GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[mvc_sp_GetWaiter]
AS
BEGIN
SELECT ID             = CAST(u.UserId AS int),
       NAME           = u.DisplayName,
       USERNAME       = u.Username,
       PASSWORD       = u.[Password],
       DeletePassword = u.DeletePassword,
       Role_ID        = qr.LegacyRoleId,
       RoleName       = qr.MenuRoleName,
       BrandID        = u.BrandID
FROM   Security.Users u
CROSS APPLY dbo.fn_QR_UserRole(u.UserId) qr
WHERE  u.IsQrMenuUser = 1 AND u.Deleted = 0
  AND  qr.MenuRoleName IS NOT NULL
END
GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[mvc_sp_Login]
@Username nvarchar(max)='',
@Password nvarchar(max)
AS
BEGIN
	SELECT ID          = CAST(u.UserId AS int),
	       UserName    = u.Username,
	       Name        = u.DisplayName,
	       BrandID     = u.BrandID,
	       Role_ID     = qr.LegacyRoleId,
	       RoleName    = qr.MenuRoleName,
	       isnull(b.FeedBack,0) as FeedBack,
	       isnull(b.MultipleBranch,0) as MultipleBranch,
	       isnull(b.IsCartVisible,0) as IsCartVisible
	FROM Security.Users u
	CROSS APPLY dbo.fn_QR_UserRole(u.UserId) qr
	left join tblBrand b on b.BrandID = TRY_CAST(u.BrandID AS int)
	WHERE u.[Password] = @Password and u.Username = @Username
	  and u.IsQrMenuUser = 1 and u.Deleted = 0 and u.IsActive = 1
	  and qr.MenuRoleName IS NOT NULL
END
GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[mvc_sp_UpdateWaiter]
@ID int,
@NAME nvarchar(max),
@USERNAME nvarchar(max),
@PASSWORD nvarchar(max)='',
@Role_ID int,
@BrandID nvarchar(max)=''
AS
BEGIN
 SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 if(@PASSWORD='')
 begin
update Security.Users set DisplayName=LEFT(@NAME,100),Username=LEFT(@USERNAME,100),BrandID=LEFT(@BrandID,50),ModifiedDate=SYSUTCDATETIME() where UserId=@ID
 end
 else
 begin
update Security.Users set DisplayName=LEFT(@NAME,100),Username=LEFT(@USERNAME,100),[Password]=LEFT(@PASSWORD,50),BrandID=LEFT(@BrandID,50),ModifiedDate=SYSUTCDATETIME() where UserId=@ID
end
 exec dbo.usp_QR_SetUserRole @UserId = @ID, @LegacyRoleId = @Role_ID
 COMMIT TRANSACTION;
END
GO
GO
/****** Object:  StoredProcedure [dbo].[sp_Dashbord_DeletedItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_Dashbord_DeletedItems]
      @FromDate  DATETIME       = NULL
    , @ToDate    DATETIME       = NULL
    , @BranchIds NVARCHAR(1000) = NULL
    , @Waste     BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   [Branch]     = ISNULL(b.branchName, N'-')
           , [Invoice No]  = i.InvoiceNo
           , [Item]        = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , [Qty]         = o.Quantity
           , [Amount]      = CAST(ISNULL(o.TotalAmount, 0) AS DECIMAL(18,3))
           , [Deleted On]  = FORMAT(o.DeletedDate, 'dd-MMM-yy hh:mm tt')
           , [Comment]     = o.DeleteOrderComment
           , [Approved By] = u.DisplayName
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblbranch b  WITH (NOLOCK) ON b.id = i.BranchID
    LEFT JOIN dbo.tblItems  it WITH (NOLOCK) ON it.ID = o.ItemID
    LEFT JOIN Security.Users u  WITH (NOLOCK) ON CAST(u.UserId AS NVARCHAR(50)) = o.DeletePasswordUserID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(o.Deleted, 0) = 1 AND ISNULL(o.IsSplit, 0) = 0
      AND    ISNULL(o.Waste, 0)   = @Waste
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    ORDER BY o.DeletedDate DESC;
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_GetBrands]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetBrands]
@WaiterID int
AS
BEGIN

declare @isAdmin bit

set @isAdmin=(select case when LegacyRoleId=1 then 1 else 0 end Role from dbo.fn_QR_UserRole(@WaiterID))

if(@isAdmin=1)
begin

	select b.BrandID,b.Theme,b.BrandImage,b.BrandName,b.BrandNameAra,b.BrandSeq,b.Russian,b.Mandarin,isnull(b.IsOtherLanguages,'') IsOtherLanguages
   ,t.ThemeName,b.url as brandUrl from tblBrand b inner join tblTheme t on t.ThemeID=b.Theme

end
else

begin
declare @BrandID nvarchar(50)

set @BrandID=(select BrandID from Security.Users where UserId=@WaiterID)

select b.BrandID,b.Theme,b.BrandImage,b.BrandName,b.BrandNameAra,b.BrandSeq,b.Russian,b.Mandarin,isnull(b.IsOtherLanguages,'') IsOtherLanguages
   ,t.ThemeName,b.url as brandUrl from tblBrand b inner join tblTheme t on t.ThemeID=b.Theme  where BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,','))

end

END


GO
GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategory]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetCategory]
@WaiterID int,
@BrandID int
AS
BEGIN

declare @isAdmin bit

set @isAdmin=(select case when LegacyRoleId=1 then 1 else 0 end Role from dbo.fn_QR_UserRole(@WaiterID))

if(@isAdmin=1 and @BrandID=0)
begin

	select distinct c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM,c.ShowInTablet,c.CAT_NAME_ARABIC,c.CatNameRus,c.CatNameMan
	,c.MainCategory, --a.BrandID 
	isnull(a.BrandID,0) BrandID
	,b.BrandName
	,1 as IsOtherLanguages

	,cl.chinese as CategoryName_chinese
	,cl.turkish as CategoryName_turkish
	,cl.hindi as CategoryName_hindi
	,cl.korean as CategoryName_korean
	,cl.spain as CategoryName_spain
	,cl.bangladeshi as CategoryName_bangladeshi
	,cl.srilanka as CategoryName_srilanka
	,cl.iranian as CategoryName_iranian
	,cl.italian as CategoryName_italian
	,cl.urdu as CategoryName_urdu
	,cl.philippines as CategoryName_philippines
	,cl.french as CategoryName_french
	,cl.germany as CategoryName_germany
	from tblCategory c 
	left join Assign_Cat a on c.CAT_NUM=a.CatNum 
	left join tblBrand b on a.BrandID= b.BrandID
	left join tblCategoryName_Languages cl on cl.CAT_NUM=c.CAT_NUM
	order by SEQ_NUM asc
	
end
else
set @BrandID= (select BrandID from Security.Users where UserId=@WaiterID)
begin

			if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
			begin
				select distinct c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM,c.ShowInTablet,c.CAT_NAME_ARABIC,c.CatNameRus,c.CatNameMan
				,c.MainCategory, isnull(a.BrandID,0) BrandID,b.BrandName
				,1 as IsOtherLanguages
				,cl.chinese as CategoryName_chinese
				,cl.turkish as CategoryName_turkish
				,cl.hindi as CategoryName_hindi
				,cl.korean as CategoryName_korean
				,cl.spain as CategoryName_spain
				,cl.bangladeshi as CategoryName_bangladeshi
				,cl.srilanka as CategoryName_srilanka
				,cl.iranian as CategoryName_iranian
				,cl.italian as CategoryName_italian
				,cl.urdu as CategoryName_urdu
				,cl.philippines as CategoryName_philippines
				,cl.french as CategoryName_french
				,cl.germany as CategoryName_germany
				
				from tblCategory  c 
				left join Assign_Cat a on c.CAT_NUM=a.CatNum 
				left join tblBrand b on a.BrandID= b.BrandID
				left join tblCategoryName_Languages cl on cl.CAT_NUM=c.CAT_NUM
				where a.BrandID=@BrandID or a.BrandID is null order by SEQ_NUM asc
			end
			else begin
				select distinct c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM,c.ShowInTablet,c.CAT_NAME_ARABIC,c.CatNameRus,c.CatNameMan
				,c.MainCategory, isnull(a.BrandID,0) BrandID,b.BrandName
				,0 as IsOtherLanguages
				,cl.chinese as CategoryName_chinese
				,cl.turkish as CategoryName_turkish
				,cl.hindi as CategoryName_hindi
				,cl.korean as CategoryName_korean
				,cl.spain as CategoryName_spain
				,cl.bangladeshi as CategoryName_bangladeshi
				,cl.srilanka as CategoryName_srilanka
				,cl.iranian as CategoryName_iranian
				,cl.italian as CategoryName_italian
				,cl.urdu as CategoryName_urdu
				,cl.philippines as CategoryName_philippines
				,cl.french as CategoryName_french
				,cl.germany as CategoryName_germany
				
				from tblCategory  c 
				left join Assign_Cat a on c.CAT_NUM=a.CatNum 
				left join tblBrand b on a.BrandID= b.BrandID
				left join tblCategoryName_Languages cl on cl.CAT_NUM=c.CAT_NUM
				where a.BrandID=@BrandID or a.BrandID is null order by SEQ_NUM asc
			
			end
	
end
END

GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetLangLabels]
@selectedLang nvarchar(10)='EN'
AS
BEGIN
	IF @selectedLang = 'EN'
	BEGIN
		select [id]        = UiLabelId
		      ,[labelName] = LegacyKey
		      ,EnglishText as LabelTest
		from Core.UiLabels
		where Module = 'qrmenu' and LegacyKey is not null and Deleted = 0
	END
	ELSE
	BEGIN
		select [id]        = UiLabelId
		      ,[labelName] = LegacyKey
		      ,ArabicText as LabelTest
		from Core.UiLabels
		where Module = 'qrmenu' and LegacyKey is not null and Deleted = 0
	END
END
GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_AddPayment]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_AddPayment]
      @InvoiceNo      BIGINT
    , @PaymentTypeID  INT
    , @Amount         DECIMAL(18,3)
    , @AmountTendered DECIMAL(18,3) = NULL
    , @ReferenceNo    NVARCHAR(100) = NULL
    , @IsRefund       BIT           = 0
    , @UserID         INT           = NULL
    , @UserName       NVARCHAR(100) = NULL
    , @Comments       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @Status INT, @BranchID INT, @Due DECIMAL(18,3), @Paid DECIMAL(18,3)
          , @Err NVARCHAR(500) = NULL, @Change DECIMAL(18,3) = NULL
          , @RequiresRef BIT = 0, @LegacyCol SYSNAME = NULL;

    SELECT @Status = i.OrderStatusID
         , @BranchID = i.BranchID
         , @Due = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
    FROM   dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    SELECT @RequiresRef = pt.RequiresReference, @LegacyCol = pt.LegacyColumn
    FROM   dbo.tblInvoicePaymentType pt WHERE pt.ID = @PaymentTypeID AND ISNULL(pt.IsDeleted,0) = 0;

    IF @Status IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @LegacyCol IS NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID AND ISNULL(IsDeleted,0)=0)
        SET @Err = N'Unknown payment type.';
    ELSE IF @Amount IS NULL OR @Amount <= 0
        SET @Err = N'Amount must be greater than zero.';
    ELSE IF @Status = 7 AND @IsRefund = 0
        SET @Err = N'Cannot take payment on a cancelled order.';
    ELSE IF @IsRefund = 0 AND (@Paid + @Amount) > @Due + 0.001
        -- Overpayment is almost always a keying error, and it silently breaks
        -- the cash-up. Change due is handled by AmountTendered, not by
        -- recording more money than the order is worth.
        SET @Err = CONCAT(N'Payment exceeds the amount due. Due ', @Due, N', already paid ', @Paid, N'.');
    ELSE IF @IsRefund = 1 AND @Amount > @Paid + 0.001
        SET @Err = CONCAT(N'Refund exceeds the amount paid (', @Paid, N').');
    ELSE IF @RequiresRef = 1 AND NULLIF(LTRIM(RTRIM(@ReferenceNo)),'') IS NULL
        SET @Err = N'A reference number is required for this payment type.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, AmountPaid=@Paid, AmountDue=@Due,
               ChangeGiven=CAST(NULL AS DECIMAL(18,3)), PaymentStatus=CAST(NULL AS VARCHAR(10)),
               ErrorMessage=@Err;
        RETURN;
    END

    IF @IsRefund = 0 AND @AmountTendered IS NOT NULL AND @AmountTendered > @Amount
        SET @Change = @AmountTendered - @Amount;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tblInvoicePayment
            (PaymentTypeID, InvoiceId, PaymentType, BranchId, Amount, AmountTendered, ChangeGiven,
             ReferenceNo, IsRefund, ReceivedBy, ReceivedOn, Comments, isdeleted)
        SELECT @PaymentTypeID, @InvoiceNo, pt.PaymentTypeName, @BranchID, @Amount, @AmountTendered, @Change,
               @ReferenceNo, @IsRefund, @UserID, @Now, @Comments, 0
        FROM   dbo.tblInvoicePaymentType pt WHERE pt.ID = @PaymentTypeID;

        SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
        FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

        UPDATE dbo.tblInvoice
           SET PaidDate   = CASE WHEN @Paid + 0.001 >= @Due THEN ISNULL(PaidDate, @Now) ELSE NULL END
             , ModifiedOn = @Now
             , ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        /*---- Recalculate the legacy per-method columns from the rows.
               Rebuilt rather than incremented, so a refund or a corrected row
               cannot leave the legacy totals drifting away from the truth. ----*/
        DECLARE @col SYSNAME, @sql NVARCHAR(MAX);
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT LegacyColumn FROM dbo.tblInvoicePaymentType WHERE LegacyColumn IS NOT NULL AND COL_LENGTH('dbo.tblInvoice', LegacyColumn) IS NOT NULL;
        OPEN c; FETCH NEXT FROM c INTO @col;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'
                UPDATE i SET ' + QUOTENAME(@col) + N' = ISNULL(x.Amt, 0)
                FROM dbo.tblInvoice i
                OUTER APPLY (
                    SELECT Amt = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                    FROM   dbo.tblInvoicePayment p
                    JOIN   dbo.tblInvoicePaymentType t ON t.ID = p.PaymentTypeID
                    WHERE  p.InvoiceId = @inv AND ISNULL(p.isdeleted,0) = 0 AND t.LegacyColumn = @c
                ) x
                WHERE i.InvoiceNo = @inv;';
            EXEC sp_executesql @sql, N'@inv BIGINT, @c SYSNAME', @inv = @InvoiceNo, @c = @col;
            FETCH NEXT FROM c INTO @col;
        END
        CLOSE c; DEALLOCATE c;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, CASE WHEN @IsRefund = 1 THEN 'Refund' ELSE 'Payment' END,
                @UserID, @UserName,
                CONCAT(N'Type=', @PaymentTypeID, N' Amount=', @Amount,
                       N' Ref=', ISNULL(@ReferenceNo, N''), N' PaidNow=', @Paid, N' Due=', @Due))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, AmountPaid=@Paid, AmountDue=@Due,
               ChangeGiven=CAST(NULL AS DECIMAL(18,3)), PaymentStatus=CAST(NULL AS VARCHAR(10)),
               ErrorMessage=ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message       = 'Success'
         , InvoiceNo     = @InvoiceNo
         , AmountPaid    = @Paid
         , AmountDue     = @Due
         , ChangeGiven   = @Change
         , PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid'
                                WHEN @Paid + 0.001 >= @Due THEN 'Paid' ELSE 'Partial' END
         , ErrorMessage  = CAST(NULL AS NVARCHAR(500));
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_CancelOrder]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_CancelOrder]
      @InvoiceNo     BIGINT
    , @CancelReasonID INT           = NULL
    , @Comments      NVARCHAR(1000)
    , @Disposition   TINYINT                    -- 1 = Waste, 2 = Reuse
    , @UserID        INT           = NULL
    , @UserName      NVARCHAR(100) = NULL
    , @RoleID        INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @From INT, @Paid DECIMAL(18,3), @Err NVARCHAR(500) = NULL;

    SELECT @From = i.OrderStatusID FROM dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    IF @From IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @From IN (7, 8)
        SET @Err = N'Order is already cancelled or refunded.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblPOS_OrderStatusTransition WHERE FromStatusID = @From AND ToStatusID = 7)
        SET @Err = N'An order in this status cannot be cancelled.';
    ELSE IF @Disposition NOT IN (1, 2)
        SET @Err = N'Select Waste or Reuse.';
    ELSE IF NULLIF(LTRIM(RTRIM(@Comments)), '') IS NULL
        SET @Err = N'A cancellation comment is required.';
    ELSE IF @Paid > 0
        -- Cancelling paid money without refunding it makes the cash drawer
        -- disagree with the system at end of day, and the difference is very
        -- hard to trace afterwards.
        SET @Err = N'This order has payments recorded. Refund it before cancelling.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET OrderStatusID     = 7
             , OrderStatus       = 7
             , CancelReasonID    = @CancelReasonID
             , CancelComments    = @Comments
             , CancelDisposition = @Disposition
             , Closed            = 1
             , ClosedDate        = @Now
             , ModifiedOn        = @Now
             , ModifiedBy        = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        -- Waste marks the lines; Reuse does not, because the stock goes back.
        UPDATE dbo.tblOrder
           SET Waste                = CASE WHEN @Disposition = 1 THEN 1 ELSE 0 END
             , DeleteOrderComment   = @Comments
             , DeletePasswordUserID = CAST(@UserID AS NVARCHAR(50))
             , DeletedDate          = @Now
         WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @From, 7, @UserID, @UserName, @Now,
                CONCAT(CASE WHEN @Disposition = 1 THEN N'[Waste] ' ELSE N'[Reuse] ' END, @Comments));

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, 'Cancel', @UserID, @UserName,
                CONCAT(N'Reason=', ISNULL(@CancelReasonID,0),
                       N' Disposition=', CASE WHEN @Disposition = 1 THEN N'Waste' ELSE N'Reuse' END,
                       N' Comments=', @Comments))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, ErrorMessage=ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message='Success', InvoiceNo=@InvoiceNo, ErrorMessage=CAST(NULL AS NVARCHAR(500));
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_CancelOrderReject]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_CancelOrderReject]
      @InvoiceNo  BIGINT
    , @Comments   NVARCHAR(500)
    , @Password   NVARCHAR(100)
    , @UserID     INT           = NULL        -- who is logged in at the counter
    , @UserName   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME = GETDATE();
    DECLARE @From INT, @Err NVARCHAR(500), @ApprovedByID INT, @ApprovedBy NVARCHAR(100);

    SET @Comments = NULLIF(LTRIM(RTRIM(ISNULL(@Comments, N''))), N'');

    SELECT @From = i.OrderStatusID
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceNo = @InvoiceNo AND ISNULL(i.Deleted,0) = 0;

    /*---- who does this password belong to? ------------------------------
      Looked up dynamically so a database without the column returns "no
      match" instead of stopping this procedure from being created at all.
      Blank passwords never match: a manager row with an empty deletePassword
      would otherwise let an empty box through.
    ---------------------------------------------------------------------*/
    IF COL_LENGTH('Security.Users', 'DeletePassword') IS NOT NULL
       AND NULLIF(LTRIM(RTRIM(ISNULL(@Password, N''))), N'') IS NOT NULL
    BEGIN
        DECLARE @sql NVARCHAR(MAX) = N'
            SELECT TOP (1) @pID = u.UserId, @pName = u.DisplayName
            FROM   Security.Users u
            CROSS APPLY dbo.fn_QR_UserRole(u.UserId) q
            WHERE  q.LegacyRoleId = 1
              AND  u.IsQrMenuUser = 1 AND u.Deleted = 0
              AND  NULLIF(LTRIM(RTRIM(ISNULL(u.deletePassword, N''''))), N'''') IS NOT NULL
              AND  LTRIM(RTRIM(u.deletePassword)) = LTRIM(RTRIM(@pPwd))
            ORDER BY u.UserId;';

        EXEC sp_executesql @sql,
             N'@pPwd NVARCHAR(100), @pID INT OUTPUT, @pName NVARCHAR(100) OUTPUT',
             @pPwd = @Password, @pID = @ApprovedByID OUTPUT, @pName = @ApprovedBy OUTPUT;
    END

    /*---- refuse, in the order the operator would hit them ---------------*/
    IF @From IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @From = 6
        SET @Err = N'This order is already cancelled.';
    ELSE IF @Comments IS NULL
        SET @Err = N'A reason is required.';
    ELSE IF @ApprovedByID IS NULL
        -- One message for a wrong password and for a password that belongs to
        -- someone who is not a manager. Telling them apart would say which
        -- accounts exist.
        SET @Err = N'That password is not recognised.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- The reason is APPENDED. Comments may already hold what the customer
        -- asked for ("no onions"), and overwriting that to record why staff
        -- rejected the order destroys the only copy of it.
        UPDATE dbo.tblInvoice
           SET Comments      = LEFT(
                                 CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(Comments, N''))), N'') IS NULL
                                      THEN N'[Cancelled] ' + @Comments
                                      ELSE Comments + N' | [Cancelled] ' + @Comments
                                 END, 500)
             , OrderStatusID = 6
             , OrderStatus   = 6
             , ModifiedOn    = @Now
             , ModifiedBy    = ISNULL(@UserID, @ApprovedByID)
         WHERE InvoiceNo = @InvoiceNo;

        -- Kept in step with the fuller cancel path in POS_09, so reports that
        -- read the cancellation columns see this one too.
        IF COL_LENGTH('dbo.tblInvoice', 'CancelComments') IS NOT NULL
            UPDATE dbo.tblInvoice SET CancelComments = @Comments WHERE InvoiceNo = @InvoiceNo;

        IF COL_LENGTH('dbo.tblInvoice', 'Closed') IS NOT NULL
            UPDATE dbo.tblInvoice SET Closed = 1, ClosedDate = @Now WHERE InvoiceNo = @InvoiceNo;

        -- Who approved it, on every line. DeletePasswordUserID is the existing
        -- column for exactly this.
        IF COL_LENGTH('dbo.tblOrder', 'DeletePasswordUserID') IS NOT NULL
            UPDATE dbo.tblOrder
               SET DeleteOrderComment   = @Comments
                 , DeletePasswordUserID = CAST(@ApprovedByID AS NVARCHAR(50))
                 , DeletedDate          = @Now
             WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_OrderStatusHistory
            (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @From, 6, ISNULL(@UserID, @ApprovedByID),
                ISNULL(@UserName, @ApprovedBy), @Now,
                CONCAT(N'[Cancelled] ', @Comments, N' (approved by ', @ApprovedBy, N')'));

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, 'Cancel', ISNULL(@UserID, @ApprovedByID),
                ISNULL(@UserName, @ApprovedBy),
                CONCAT(N'From=', @From, N' To=6 ApprovedByUserID=', @ApprovedByID,
                       N' Comments=', @Comments))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT   Message        = 'Success'
           , InvoiceNo      = @InvoiceNo
           , OrderStatusID  = 6
           , ApprovedByID   = @ApprovedByID
           , ApprovedBy     = @ApprovedBy
           , ErrorMessage   = CAST(NULL AS NVARCHAR(500));
END
GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_ChangeStatus]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_ChangeStatus]
      @InvoiceNos  dbo.TVP_POS_BigIntList READONLY
    , @ToStatusID  INT
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
    , @RoleID      INT           = NULL
    , @Comments    NVARCHAR(1000)= NULL
    , @DriverID    INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE();

    IF NOT EXISTS (SELECT 1 FROM dbo.tblOrderStatus WHERE OrderStatusID = @ToStatusID)
    BEGIN
        SELECT Message='Fail', Updated=0, ErrorMessage=N'Unknown target status.';
        SELECT TOP 0 InvoiceNo=CAST(NULL AS BIGINT), Reason=CAST(NULL AS NVARCHAR(200));
        RETURN;
    END

    -- Evaluate every candidate once, so the outcome per order is known up front.
    DECLARE @eval TABLE
    (
          InvoiceNo    BIGINT PRIMARY KEY
        , FromStatusID INT
        , OrderType    INT
        , BranchID     INT
        , Allowed      BIT
        , Reason       NVARCHAR(200)
    );

    INSERT INTO @eval (InvoiceNo, FromStatusID, OrderType, BranchID, Allowed, Reason)
    SELECT  i.InvoiceNo
          , i.OrderStatusID
          , i.OrderType
          , i.BranchID
          -- The move-forward sequence used to be enforced here: a target
          -- status had to have a matching row in tblPOS_OrderStatusTransition
          -- or the whole change was refused with "Not a permitted transition
          -- from X." That table now only gates a role requirement where one
          -- is configured - any FromStatus -> ToStatus pair is otherwise
          -- open, so the picker's "confirm before committing" step is the
          -- guard against a stray tap, not a hard-coded sequence.
          , Allowed = CASE
                        WHEN ISNULL(i.Deleted,0) = 1 THEN 0
                        WHEN i.OrderStatusID = @ToStatusID THEN 0
                        WHEN EXISTS (SELECT 1 FROM dbo.tblPOS_OrderStatusTransition t
                                     WHERE t.FromStatusID = i.OrderStatusID AND t.ToStatusID = @ToStatusID
                                       AND t.RequiresRole IS NOT NULL
                                       AND (@RoleID IS NULL OR @RoleID > t.RequiresRole)) THEN 0
                        WHEN (i.OrderType = 1 AND s.AppliesToPickup = 0)
                          OR (i.OrderType <> 1 AND s.AppliesToDelivery = 0) THEN 0
                        ELSE 1
                      END
          , Reason  = CASE
                        WHEN ISNULL(i.Deleted,0) = 1 THEN N'Order is deleted.'
                        WHEN i.OrderStatusID = @ToStatusID THEN N'Already in that status.'
                        WHEN EXISTS (SELECT 1 FROM dbo.tblPOS_OrderStatusTransition t
                                     WHERE t.FromStatusID = i.OrderStatusID AND t.ToStatusID = @ToStatusID
                                       AND t.RequiresRole IS NOT NULL
                                       AND (@RoleID IS NULL OR @RoleID > t.RequiresRole))
                             THEN N'Your role cannot make this change.'
                        WHEN (i.OrderType = 1 AND s.AppliesToPickup = 0)
                          OR (i.OrderType <> 1 AND s.AppliesToDelivery = 0)
                             THEN N'Status does not apply to this order type.'
                        ELSE NULL
                      END
    FROM      dbo.tblInvoice i
    JOIN      @InvoiceNos    n   ON n.Value = i.InvoiceNo
    JOIN      dbo.tblOrderStatus s   ON s.OrderStatusID = @ToStatusID
    LEFT JOIN dbo.tblOrderStatus cur ON cur.OrderStatusID = i.OrderStatusID;

    -- Handing to a driver without saying which driver leaves the dispatch board
    -- unusable and the delivery unattributable.
    IF @ToStatusID = 4 AND @DriverID IS NULL
        UPDATE @eval SET Allowed = 0, Reason = N'Select a driver first.' WHERE Allowed = 1;

    DECLARE @Updated INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE i
           SET i.OrderStatusID    = @ToStatusID
             , i.OrderStatus      = @ToStatusID          -- legacy column kept in step
             , i.Driver           = CASE WHEN @DriverID IS NOT NULL THEN @DriverID ELSE i.Driver END
             , i.DriverName       = CASE WHEN @DriverID IS NOT NULL
                                         THEN (SELECT TOP 1 d.DriverName FROM dbo.tblDriver d WHERE d.DriverID = @DriverID)
                                         ELSE i.DriverName END
             , i.DriverAssignDate = CASE WHEN @ToStatusID = 4 THEN @Now ELSE i.DriverAssignDate END
             , i.Closed           = CASE WHEN s.IsTerminal = 1 THEN 1 ELSE i.Closed END
             , i.ClosedDate       = CASE WHEN s.IsTerminal = 1 AND i.ClosedDate IS NULL THEN @Now ELSE i.ClosedDate END
             , i.ModifiedOn       = @Now
             , i.ModifiedBy       = @UserID
        FROM dbo.tblInvoice i
        JOIN @eval e ON e.InvoiceNo = i.InvoiceNo AND e.Allowed = 1
        JOIN dbo.tblOrderStatus s ON s.OrderStatusID = @ToStatusID;

        SET @Updated = @@ROWCOUNT;

        -- Delivered also means the food left the kitchen: keep tblOrder in step
        -- so kitchen and line-level reports agree with the header.
        IF @ToStatusID = 6
            UPDATE o SET o.Delivered = 1
            FROM dbo.tblOrder o
            JOIN @eval e ON e.InvoiceNo = o.InvoiceNo AND e.Allowed = 1;

        IF @ToStatusID = 2
            UPDATE o SET o.Prepared = 1
            FROM dbo.tblOrder o
            JOIN @eval e ON e.InvoiceNo = o.InvoiceNo AND e.Allowed = 1;

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments, DriverID)
        SELECT e.InvoiceNo, e.FromStatusID, @ToStatusID, @UserID, @UserName, @Now, @Comments, @DriverID
        FROM   @eval e WHERE e.Allowed = 1;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (SELECT 'Invoice', e.InvoiceNo, 'StatusChange', @UserID, @UserName,
               CONCAT(N'From=', e.FromStatusID, N' To=', @ToStatusID,
                      CASE WHEN @DriverID IS NOT NULL THEN CONCAT(N' Driver=', @DriverID) ELSE N'' END)
        FROM   @eval e WHERE e.Allowed = 1) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', Updated=0, ErrorMessage=ERROR_MESSAGE();
        SELECT TOP 0 InvoiceNo=CAST(NULL AS BIGINT), Reason=CAST(NULL AS NVARCHAR(200));
        RETURN;
    END CATCH

    SELECT Message = CASE WHEN @Updated = 0 THEN 'Fail' ELSE 'Success' END
         , Updated = @Updated
         , Skipped = (SELECT COUNT(*) FROM @eval WHERE Allowed = 0)
         , ErrorMessage = CAST(NULL AS NVARCHAR(500));

    -- Second result set: exactly which orders did not move, and why.
    SELECT InvoiceNo, Reason FROM @eval WHERE Allowed = 0 ORDER BY InvoiceNo;
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_ChangeToPickup]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_ChangeToPickup]
      @InvoiceNo   BIGINT
    , @BranchID    INT
    , @InvoiceType INT           = 3
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @Err NVARCHAR(500) = NULL, @Warning NVARCHAR(500) = NULL
          , @Status INT, @OrderType INT, @FromBranch INT
          , @OldCharge DECIMAL(18,3), @Bill DECIMAL(18,3), @Discount DECIMAL(18,3)
          , @Paid DECIMAL(18,3), @NewNet DECIMAL(18,3);

    SELECT @Status     = i.OrderStatusID
         , @OrderType  = i.OrderType
         , @FromBranch = i.BranchID
         , @OldCharge  = ISNULL(i.DeliveryCharges, 0)
         , @Bill       = ISNULL(i.BillAmount, 0)
         , @Discount   = ISNULL(i.Discount, 0)
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceNo = @InvoiceNo AND ISNULL(i.Deleted,0) = 0;

    IF @Status IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @Status IN (6, 7, 8)
        SET @Err = N'A cancelled or completed order cannot be changed to pickup.';
    ELSE IF @Status IN (4, 5)
        -- The food is already on a bike. Telling the system the customer is
        -- collecting it does not bring the driver back.
        SET @Err = N'Order is already with a driver - recall it first.';
    ELSE IF @OrderType = 1
        SET @Err = N'This order is already a pickup.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch
                        WHERE id = @BranchID AND ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1)
        SET @Err = N'Select a branch for the customer to collect from.';
    ELSE IF @InvoiceType IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoiceType_Master WHERE ID = @InvoiceType)
        SET @Err = CONCAT(N'Invoice type ', @InvoiceType, N' does not exist in tblInvoiceType_Master.');

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = @Err,
               Warning = CAST(NULL AS NVARCHAR(500)),
               NetPayable = CAST(NULL AS DECIMAL(18,3));
        RETURN;
    END

    SET @NewNet = (@Bill - @Discount);   -- delivery charge is now zero

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET InvoiceType     = @InvoiceType
             , OrderType       = 1
             , BranchID        = @BranchID
             , DeliveryCharges = 0
             , ModifiedOn      = @Now
             , ModifiedBy      = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        -- Line rows carry BranchID, and every branch-level item report reads it
        -- from there rather than from the header.
        UPDATE dbo.tblOrder SET BranchID = @BranchID WHERE InvoiceNo = @InvoiceNo;

        -- A move between branches is a transfer whichever way it was triggered,
        -- so it lands in the same table the transfer screen writes to.
        IF @FromBranch <> @BranchID
            INSERT INTO dbo.tblPOS_OrderTransfer (InvoiceNo, FromBranchID, ToBranchID, Reason, TransferredBy, TransferredOn)
            VALUES (@InvoiceNo, @FromBranch, @BranchID, N'Changed to pickup', @UserID, @Now);

        INSERT INTO dbo.tblPOS_OrderStatusHistory
            (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @Status, @Status, @UserID, @UserName, @Now,
                CONCAT(N'Changed to pickup at branch ', @BranchID,
                       CASE WHEN @OldCharge > 0
                            THEN CONCAT(N'; delivery charge ', @OldCharge, N' removed')
                            ELSE N'' END));

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, 'ChangeToPickup', @UserID, @UserName,
                CONCAT(N'Branch=', @FromBranch, N'->', @BranchID,
                       N' InvoiceType=', @InvoiceType,
                       N' OrderType=1 DeliveryCharges=', @OldCharge, N'->0'))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = ERROR_MESSAGE(),
               Warning = CAST(NULL AS NVARCHAR(500)), NetPayable = CAST(NULL AS DECIMAL(18,3));
        RETURN;
    END CATCH

    /*---- did removing the charge leave them overpaid? --------------------*/
    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p
    WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    IF @Paid > @NewNet + 0.001
        SET @Warning = CONCAT(N'The order is now overpaid by ',
                              CAST(@Paid - @NewNet AS DECIMAL(18,3)),
                              N' - the delivery charge has been removed. Refund the difference.');
    ELSE IF @OldCharge > 0
        SET @Warning = CONCAT(N'Delivery charge of ', @OldCharge, N' removed.');

    SELECT   Message      = 'Success'
           , InvoiceNo    = @InvoiceNo
           , BranchID     = @BranchID
           , InvoiceType  = @InvoiceType
           , NetPayable   = @NewNet
           , AmountPaid   = @Paid
           , Warning      = @Warning
           , ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_AddItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_DineIn_AddItems]
      @InvoiceNo          BIGINT
    , @DineInTableTypeID  INT           = 0
    , @UserID             INT           = NULL
    , @UserName           NVARCHAR(100) = NULL
    , @dtOrderItems       dbo.TVP_POS_OrderItem READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @Status INT, @BranchID INT, @WaiterID INT
          , @DiscountTypeID INT, @Discount DECIMAL(18,3), @Bill DECIMAL(18,3), @Added INT;

    SELECT @Status = OrderStatusID, @BranchID = BranchID, @WaiterID = WaiterID
         , @DiscountTypeID = DiscountTypeID, @Discount = ISNULL(Discount, 0)
    FROM   dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

    IF @Status IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Bill not found.'; RETURN;
    END
    IF @Status IN (6, 7, 8)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'This bill is cancelled or refunded.'; RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM @dtOrderItems)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Add at least one item.'; RETURN;
    END

    -- @DineInTableTypeID = -1 means a Take Away bill: new lines carry whatever
    -- the bill's first line already carries instead of the Dine-In type.
    DECLARE @LineTableType INT = @DineInTableTypeID;
    IF @DineInTableTypeID < 0
    BEGIN
        SET @LineTableType = NULL;
        SELECT TOP 1 @LineTableType = o.TableType FROM dbo.tblOrder o WHERE o.InvoiceNo = @InvoiceNo ORDER BY o.OrderID;
        SET @LineTableType = ISNULL(@LineTableType, 0);
    END

    DECLARE @lines TABLE
    (
          Seq INT IDENTITY(1,1) PRIMARY KEY, ResolvedItemID INT NULL, ItemName NVARCHAR(200) NULL
        , Quantity INT NOT NULL, UnitPrice DECIMAL(18,3) NOT NULL, LineType TINYINT NOT NULL
        , CartItemUniqID INT NULL, Comments NVARCHAR(MAX) NULL, Extra NVARCHAR(MAX) NULL
    );

    INSERT INTO @lines (ResolvedItemID, ItemName, Quantity, UnitPrice, LineType, CartItemUniqID, Comments, Extra)
    SELECT  it.ID, it.ITEM_NAME
          , CASE WHEN d.Quantity < 1 THEN 1 ELSE d.Quantity END
          , CAST(ISNULL(it.PRICE, 0) AS DECIMAL(18,3))
          , ISNULL(d.LineType, 1), d.CartItemUniqID, d.Comments, d.Extra
    FROM    @dtOrderItems d
    CROSS APPLY (SELECT TOP 1 t.ID, t.ITEM_NAME, t.PRICE FROM dbo.tblItems t
                 WHERE t.ID = d.ItemID OR (d.HID IS NOT NULL AND t.HID = d.HID)
                 ORDER BY CASE WHEN t.ID = d.ItemID THEN 0 ELSE 1 END) it;

    IF NOT EXISTS (SELECT 1 FROM @lines)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'None of those items could be found.'; RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT @InvoiceNo, l.ResolvedItemID, l.Quantity, l.UnitPrice, 0, l.Comments, l.Extra
             , ISNULL(@UserID, @WaiterID), 0, 0, 0, 0, 0
             , @Now, @LineTableType, 0, @DiscountTypeID, 0, @BranchID
             , l.CartItemUniqID, l.LineType, l.ItemName
        FROM @lines l ORDER BY l.Seq;
        SET @Added = @@ROWCOUNT;

        SELECT @Bill = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

        UPDATE dbo.tblInvoice
           SET BillAmount = @Bill, ModifiedOn = @Now, ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, 'DineInAddItems', @UserID, @UserName,
                CONCAT(N'Lines=', @Added, N'; NewBill=', @Bill))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300))
         , InvoiceNo = @InvoiceNo, LinesAdded = @Added, BillAmount = @Bill
         , NetPayable = @Bill - @Discount;
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_AttachInvoice]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_DineIn_AttachInvoice]
      @InvoiceNo          BIGINT
    , @TableID            INT
    , @DineInTableTypeID  INT           = 0
    , @UserID             INT           = NULL
    , @UserName           NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT, @Persons INT, @TableNo NVARCHAR(30);

    SELECT @SessionID = s.SessionID, @Persons = s.Persons
    FROM   dbo.tblPOS_TableSession s WHERE s.TableID = @TableID AND s.ClosedOn IS NULL;

    SELECT @TableNo = LTRIM(RTRIM(CAST(Table_No AS NVARCHAR(30)))) FROM dbo.tblTable WHERE TableID = @TableID;

    IF @SessionID IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'The table was freed before the order was saved.';
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET TableID = @TableID, TableSessionID = @SessionID, Person = ISNULL(@Persons, 1)
             , WaiterID = ISNULL(@UserID, WaiterID)
         WHERE InvoiceNo = @InvoiceNo;

        UPDATE dbo.tblOrder SET TableType = @DineInTableTypeID, WaiterID = ISNULL(@UserID, WaiterID)
         WHERE InvoiceNo = @InvoiceNo;

        UPDATE dbo.tblPOS_OrderStatusHistory
           SET Comments = N'Dine-In order, table ' + ISNULL(@TableNo, N'?')
             , ChangedBy = @UserID, ChangedByName = ISNULL(@UserName, ChangedByName)
         WHERE InvoiceNo = @InvoiceNo AND FromStatusID IS NULL;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, 'DineInAttach', @UserID, @UserName,
                CONCAT(N'TableID=', @TableID, N'; Table=', @TableNo, N'; Session=', @SessionID))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_SaveLayout]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_DineIn_SaveLayout]
      @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
    , @Positions  dbo.TVP_POS_TablePosition READONLY
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE t
       SET t.Xaxis = CASE WHEN p.Xaxis < 0 THEN 0 ELSE p.Xaxis END
         , t.Yaxis = CASE WHEN p.Yaxis < 0 THEN 0 ELSE p.Yaxis END
    FROM   dbo.tblTable t
    JOIN   @Positions p ON p.TableID = t.TableID;

    DECLARE @n INT = @@ROWCOUNT;

    INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
    SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Table', NULL, 'DineInLayout', @UserID, @UserName, CONCAT(N'TablesMoved=', @n))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

    SELECT Message = 'Success', Updated = @n;
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_SetLineTakeAway]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_DineIn_SetLineTakeAway]
      @InvoiceNo  BIGINT
    , @OrderID    BIGINT
    , @On         BIT
    , @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status INT, @Found BIT = 0, @c NVARCHAR(MAX);

    SELECT @Status = OrderStatusID FROM dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;
    IF @Status IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Bill not found.'; RETURN;
    END
    IF @Status IN (6, 7, 8)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'This bill is cancelled or refunded.'; RETURN;
    END

    SELECT @c = o.Comments, @Found = 1
    FROM   dbo.tblOrder o
    WHERE  o.OrderID = @OrderID AND o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0
      AND  o.ParentOrderID IS NULL;

    IF @Found = 0
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'That item is not on this bill any more.'; RETURN;
    END

    SET @c = LTRIM(RTRIM(ISNULL(@c, N'')));
    IF LEFT(@c, 9) = N'TAKE AWAY'
    BEGIN
        SET @c = LTRIM(SUBSTRING(@c, 10, 4000));
        IF LEFT(@c, 1) = N'-' SET @c = LTRIM(SUBSTRING(@c, 2, 4000));
    END
    IF @On = 1
        SET @c = N'TAKE AWAY' + CASE WHEN @c = N'' THEN N'' ELSE N' - ' + @c END;

    BEGIN TRY
        UPDATE dbo.tblOrder SET Comments = NULLIF(@c, N'')
        WHERE  OrderID = @OrderID AND InvoiceNo = @InvoiceNo;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, CASE WHEN @On = 1 THEN 'DineInMarkTakeAway' ELSE 'DineInUnmarkTakeAway' END,
                @UserID, @UserName, CONCAT(N'OrderID=', @OrderID))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;
    END TRY
    BEGIN CATCH
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE(); RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_SplitInvoice]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_DineIn_SplitInvoice]
      @InvoiceNo  BIGINT
    , @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
    , @Lines      dbo.TVP_POS_DineInSplitLine READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @Today DATE = CAST(GETDATE() AS DATE)
          , @Err NVARCHAR(300), @Status INT, @BranchID INT, @NewNo BIGINT, @Running INT
          , @Paid DECIMAL(18,3), @Remaining INT, @Discount DECIMAL(18,3)
          , @BillOld DECIMAL(18,3), @BillNew DECIMAL(18,3);

    SELECT @Status = OrderStatusID, @BranchID = BranchID, @Discount = ISNULL(Discount, 0)
    FROM   dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted, 0) = 0;

    -- the chosen item rows (whole rows only)
    DECLARE @req TABLE (OrderID BIGINT PRIMARY KEY);
    INSERT INTO @req (OrderID)
    SELECT DISTINCT o.OrderID
    FROM   @Lines l
    JOIN   dbo.tblOrder o ON o.OrderID = l.OrderID AND o.InvoiceNo = @InvoiceNo
                         AND ISNULL(o.Deleted, 0) = 0 AND ISNULL(o.LineType, 1) = 1
                         AND o.ParentOrderID IS NULL;

    SELECT @Remaining = COUNT(*)
    FROM   dbo.tblOrder o
    WHERE  o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0
      AND  ISNULL(o.LineType, 1) = 1 AND o.ParentOrderID IS NULL
      AND  NOT EXISTS (SELECT 1 FROM @req r WHERE r.OrderID = o.OrderID);

    IF @Status IS NULL                      SET @Err = N'Bill not found.';
    ELSE IF @Status IN (6, 7, 8)            SET @Err = N'This bill is cancelled or refunded.';
    ELSE IF @Paid > 0                       SET @Err = N'This bill already has a payment on it and cannot be split.';
    ELSE IF NOT EXISTS (SELECT 1 FROM @req) SET @Err = N'Select at least one item to split.';
    ELSE IF @Remaining <= 0                 SET @Err = N'Leave at least one item on the original bill. To pay everything, use Pay.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = @Err, NewInvoiceNo = CAST(NULL AS BIGINT); RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        /* new running number for the day, same counter sp_POS_ProcessOrder uses */
        UPDATE dbo.tblPOS_DailyCounter WITH (UPDLOCK, HOLDLOCK)
           SET @Running = LastNumber = LastNumber + 1
         WHERE BranchID = @BranchID AND CounterDate = @Today;
        IF @Running IS NULL
        BEGIN
            INSERT INTO dbo.tblPOS_DailyCounter (BranchID, CounterDate, LastNumber) VALUES (@BranchID, @Today, 1);
            SET @Running = 1;
        END

        /* header copied from the original */
        INSERT INTO dbo.tblInvoice
        (
              WaiterID, BillAmount, Discount, Comments, Person, Status
            , InvoiceDate, InvoiceTime, PaymentType, Printed, Mobile, MobileText
            , CustomerName, OrderStatus, CustomerId, OrderStatusID, Deleted
            , BranchID, AddressID, BrandID, DeliveryDate, InvoiceType
            , DiscountTypeID, DeliveryCharges, OrderType, TrackingCode
            , ClientOrderGuid, DiscountCode, SourceID, RunningOrder
            , PromisedTime, PrintCount, PaidDate, TableID, TableSessionID
        )
        SELECT  ISNULL(@UserID, i.WaiterID), 0, 0, N'Split from bill ' + CAST(i.InvoiceNo AS NVARCHAR(20)), 1, i.Status
              , @Now, @Now, i.PaymentType, 0, i.Mobile, i.MobileText
              , i.CustomerName, i.OrderStatus, i.CustomerId, i.OrderStatusID, 0
              , i.BranchID, i.AddressID, i.BrandID, i.DeliveryDate, i.InvoiceType
              , 0, 0, i.OrderType, NULL
              , NULL, NULL, i.SourceID, @Running
              , i.PromisedTime, 0, NULL, i.TableID, i.TableSessionID
        FROM    dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

        SET @NewNo = CAST(SCOPE_IDENTITY() AS BIGINT);

        DECLARE @seed BIGINT = @NewNo * 2654435761 % 456976;
        UPDATE dbo.tblInvoice
           SET TrackingCode = CHAR(65 + (@seed/17576)%26) + CHAR(65 + (@seed/676)%26)
                            + CHAR(65 + (@seed/26)%26)    + CHAR(65 + @seed%26)
                            + '-' + RIGHT('0000' + CAST(@NewNo % 10000 AS VARCHAR(4)), 4)
         WHERE InvoiceNo = @NewNo;

        /* copies of the chosen items go on the new bill.
           The identity column is handed out in the order of the SELECT ... ORDER BY,
           so the n-th copy belongs to the n-th original; that pairs a copy with its
           original so the extras can be attached to the right parent. */
        DECLARE @map TABLE (Rn INT IDENTITY(1,1) PRIMARY KEY, OldID BIGINT NOT NULL, NewID BIGINT NULL);
        INSERT INTO @map (OldID) SELECT OrderID FROM @req ORDER BY OrderID;

        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot, SplitFromOrderID
        )
        SELECT @NewNo, o.ItemID, o.Quantity, o.Price, o.SentToPrinter, o.Comments, o.Extra
             , o.WaiterID, o.Prepared, o.Combined, o.Delivered, o.Dispatcher, 0
             , o.OrderDate, o.TableType, 0, o.DiscountTypeID, ISNULL(o.Discount, 0), o.BranchID
             , o.CartItemUniqID, o.LineType, o.ItemNameSnapshot, o.OrderID
        FROM   dbo.tblOrder o
        JOIN   @map m ON m.OldID = o.OrderID
        ORDER BY m.Rn;

        ;WITH nn AS (SELECT OrderID, Rn = ROW_NUMBER() OVER (ORDER BY OrderID)
                     FROM   dbo.tblOrder WHERE InvoiceNo = @NewNo)
        UPDATE m SET m.NewID = nn.OrderID
        FROM   @map m JOIN nn ON nn.Rn = m.Rn;

        /* their extras / choices, attached to the new parent */
        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot, ParentOrderID, SplitFromOrderID
        )
        SELECT @NewNo, k.ItemID, k.Quantity, k.Price, k.SentToPrinter, k.Comments, k.Extra
             , k.WaiterID, k.Prepared, k.Combined, k.Delivered, k.Dispatcher, 0
             , k.OrderDate, k.TableType, 0, k.DiscountTypeID, ISNULL(k.Discount, 0), k.BranchID
             , k.CartItemUniqID, k.LineType, k.ItemNameSnapshot, m.NewID, k.OrderID
        FROM   dbo.tblOrder k
        JOIN   @map m ON m.OldID = k.ParentOrderID
        WHERE  ISNULL(k.Deleted, 0) = 0;

        /* the originals stay, flagged: not deleted, not wasted, not counted -
           they now live on the new bill */
        UPDATE o
           SET o.Deleted = 1, o.IsSplit = 1, o.SplitToInvoiceNo = @NewNo
        FROM   dbo.tblOrder o
        WHERE  o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0
          AND  (o.OrderID IN (SELECT OrderID FROM @req)
             OR o.ParentOrderID IN (SELECT OrderID FROM @req));

        /* re-total both bills from the lines that count */
        SELECT @BillOld = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;
        SELECT @BillNew = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @NewNo AND ISNULL(Deleted, 0) = 0;

        UPDATE dbo.tblInvoice
           SET BillAmount = @BillOld
             , Discount   = CASE WHEN @Discount > @BillOld THEN @BillOld ELSE @Discount END
             , ModifiedOn = @Now, ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;
        UPDATE dbo.tblInvoice SET BillAmount = @BillNew WHERE InvoiceNo = @NewNo;

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, Comments)
        SELECT @NewNo, NULL, OrderStatusID, @UserID, @UserName, N'Split from bill ' + CAST(@InvoiceNo AS NVARCHAR(20))
        FROM   dbo.tblInvoice WHERE InvoiceNo = @NewNo;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, 'DineInSplit', @UserID, @UserName,
                CONCAT(N'NewInvoice=', @NewNo, N'; OldBill=', @BillOld, N'; NewBill=', @BillNew))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE(), NewInvoiceNo = CAST(NULL AS BIGINT);
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300)), NewInvoiceNo = @NewNo
         , OldBill = @BillOld, NewBill = @BillNew;
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_TransferTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_DineIn_TransferTable]
      @FromTableID  INT
    , @ToTableID    INT
    , @UserID       INT           = NULL
    , @UserName     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT, @Err NVARCHAR(300);

    SELECT @SessionID = SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @FromTableID AND ClosedOn IS NULL;

    IF @FromTableID = @ToTableID
        SET @Err = N'Pick a different table.';
    ELSE IF @SessionID IS NULL
        SET @Err = N'There is nobody seated at this table.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblTable WHERE TableID = @ToTableID)
        SET @Err = N'Target table not found.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.fn_POS_DineIn_Tables() WHERE TableID = @ToTableID AND Status = 1)
        SET @Err = N'That table is occupied. Pick a vacant one.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = @Err; RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblPOS_TableSession SET TableID = @ToTableID WHERE SessionID = @SessionID;
        UPDATE dbo.tblInvoice SET TableID = @ToTableID WHERE TableSessionID = @SessionID;
        UPDATE dbo.tblTable SET Status = 0 WHERE TableID = @FromTableID;
        UPDATE dbo.tblTable SET Status = 1 WHERE TableID = @ToTableID;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('TableSession', @SessionID, 'DineInTransfer', @UserID, @UserName,
                CONCAT(N'FromTableID=', @FromTableID, N'; ToTableID=', @ToTableID))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail',
               ErrorMessage = CASE WHEN ERROR_NUMBER() IN (2601, 2627)
                                   THEN N'That table was just taken on another device.'
                                   ELSE ERROR_MESSAGE() END;
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_Login]
      @Username NVARCHAR(50)
    , @Password NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MatchedUserID INT;

    SELECT @MatchedUserID = u.UserId
    FROM   Security.Users u
    WHERE  u.Username = @Username
      AND  u.IsQrMenuUser = 1
      AND  u.Deleted = 0
      AND  u.IsActive = 1
      AND  (
                (u.PosPasswordHash IS NOT NULL
                 AND u.PosPasswordHash = HASHBYTES('SHA2_512', u.PosPasswordSalt + CONVERT(VARBINARY(200), @Password)))
             OR (u.PosPasswordHash IS NULL AND NULLIF(u.[Password], N'') IS NOT NULL AND u.[Password] = @Password)
           );

    -- result set 0: the user row - no row on failure, so the login form
    -- cannot be used to enumerate accounts.
    SELECT
          UserID           = CAST(u.UserId AS INT)
        , UserName         = u.DisplayName
        , LoginName        = u.Username
        , BrandID          = TRY_CAST(u.BrandID AS INT)
        , RoleID           = ISNULL(qr.LegacyRoleId, 4)
        , RoleName         = ISNULL(f.RoleName, N'Cashier')
        , CanChangeStatus  = ISNULL(f.CanChangeStatus, 1)
        , CanCancel        = ISNULL(f.CanCancel, 0)
        , CanRefund        = ISNULL(f.CanRefund, 0)
        , CanTransfer      = ISNULL(f.CanTransfer, 0)
        , CanTakePayment   = ISNULL(f.CanTakePayment, 1)
        , CanViewReports   = ISNULL(f.CanViewReports, 0)
        , CanEndDay        = ISNULL(f.CanEndDay, 0)
        , CanManageMasters = ISNULL(f.CanManageMasters, 0)
    FROM        Security.Users u
    OUTER APPLY dbo.fn_QR_UserRole(u.UserId)       qr
    OUTER APPLY dbo.fn_QR_RoleFlags(qr.LegacyRoleId) f
    WHERE       u.UserId = @MatchedUserID;

    -- result set 1: assigned branch IDs
    SELECT BranchID
    FROM   dbo.tblPOS_UserBranch_Map
    WHERE  UserID = @MatchedUserID;
END
GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_MarkPrinted]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_MarkPrinted]
      @InvoiceNos dbo.TVP_POS_BigIntList READONLY
    , @DocType    VARCHAR(20)   = 'Invoice'      -- Invoice | Thermal | Kitchen
    , @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME = GETDATE();

    UPDATE i
       SET i.PrintCount    = ISNULL(i.PrintCount, 0) + 1
         , i.LastPrintedOn = @Now
         , i.Printed       = 1
    FROM dbo.tblInvoice i
    JOIN @InvoiceNos n ON n.Value = i.InvoiceNo;

    IF @DocType = 'Kitchen'
        UPDATE o SET o.SentToPrinter = 1
        FROM dbo.tblOrder o JOIN @InvoiceNos n ON n.Value = o.InvoiceNo;

    INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
    SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (SELECT 'Invoice', n.Value, 'Print', @UserID, @UserName,
           CONCAT(N'DocType=', @DocType, N' Count=',
                  (SELECT PrintCount FROM dbo.tblInvoice WHERE InvoiceNo = n.Value))
    FROM   @InvoiceNos n) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

    SELECT i.InvoiceNo, i.PrintCount, IsReprint = CASE WHEN i.PrintCount > 1 THEN 1 ELSE 0 END
    FROM   dbo.tblInvoice i JOIN @InvoiceNos n ON n.Value = i.InvoiceNo;
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_PaymentLink_Complete]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_PaymentLink_Complete]
      @CustomerReference VARCHAR(60)
    , @Success           BIT
    , @ProviderPaymentId VARCHAR(60)   = NULL
    , @PaidAmount        DECIMAL(18,3) = NULL
    , @FailureReason     NVARCHAR(500) = NULL
    , @RawResponse       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LinkID BIGINT, @InvoiceNo BIGINT, @Amount DECIMAL(18,3),
            @PaymentTypeID INT, @Now DATETIME = GETDATE();

    SELECT @LinkID = LinkID, @InvoiceNo = InvoiceNo, @Amount = Amount, @PaymentTypeID = PaymentTypeID
    FROM   dbo.tblPOS_PaymentLink WHERE CustomerReference = @CustomerReference;

    IF @LinkID IS NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT),
               ErrorMessage=N'Unknown payment reference.';
        RETURN;
    END

    /*---- failure: record it, credit nothing --------------------------------*/
    IF @Success = 0
    BEGIN
        UPDATE dbo.tblPOS_PaymentLink
           SET Status = 'Failed', FailureReason = @FailureReason,
               RawResponse = ISNULL(@RawResponse, RawResponse), CompletedOn = @Now
         WHERE LinkID = @LinkID AND Status = 'Pending';

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserName, NewValues)
        VALUES ('Invoice', @InvoiceNo, 'PaymentFailed', N'MyFatoorah',
                CONCAT(N'Ref=', @CustomerReference, N' Reason=', ISNULL(@FailureReason, N'')));

        SELECT Message='Failed', InvoiceNo=@InvoiceNo, ErrorMessage=@FailureReason;
        RETURN;
    END

    /*---- success: claim the attempt ---------------------------------------
      Only the caller whose UPDATE actually changes a row proceeds to book the
      payment. Anything arriving second sees @@ROWCOUNT = 0 and returns
      'Duplicate' without touching the ledger.
    ------------------------------------------------------------------------*/
    UPDATE dbo.tblPOS_PaymentLink
       SET Status            = 'Paid'
         , ProviderPaymentId = @ProviderPaymentId
         , PaidAmount        = ISNULL(@PaidAmount, Amount)
         , RawResponse       = ISNULL(@RawResponse, RawResponse)
         , CompletedOn       = @Now
     WHERE LinkID = @LinkID
       AND Status = 'Pending';          -- <= the guard

    IF @@ROWCOUNT = 0
    BEGIN
        SELECT Message='Duplicate', InvoiceNo=@InvoiceNo,
               ErrorMessage=CAST(NULL AS NVARCHAR(500));
        RETURN;
    END

    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType
        WHERE PaymentTypeName = N'MyFatoorah' AND ISNULL(IsDeleted,0) = 0;

    -- Reuse sp_POS_AddPayment rather than inserting directly, so the legacy
    -- per-method columns and PaidDate stay in step with everything else.
    EXEC dbo.sp_POS_AddPayment
          @InvoiceNo     = @InvoiceNo
        , @PaymentTypeID = @PaymentTypeID
        , @Amount        = @Amount
        , @ReferenceNo   = @ProviderPaymentId
        , @IsRefund      = 0
        , @UserName      = N'MyFatoorah'
        , @Comments      = @CustomerReference;

    -- A gateway that reports a different figure to the one requested is worth
    -- knowing about; it is logged rather than silently accepted.
    IF @PaidAmount IS NOT NULL AND ABS(@PaidAmount - @Amount) > 0.001
        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserName, NewValues)
        VALUES ('Invoice', @InvoiceNo, 'PaymentAmountMismatch', N'MyFatoorah',
                CONCAT(N'Ref=', @CustomerReference, N' Requested=', @Amount, N' Reported=', @PaidAmount));

    SELECT Message='Success', InvoiceNo=@InvoiceNo, ErrorMessage=CAST(NULL AS NVARCHAR(500));
END

GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_ProcessOrder]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_ProcessOrder]
      @BranchID          INT
    , @BrandID           INT
    , @InvoiceTypeID     INT            = NULL        -- NULL = resolve 'QR Menu Online'
    , @OrderType         INT            = 2           -- 1 Pickup, 2 Delivery, 3 Dine-in
    , @SourceID          INT            = 1

    , @CustomerId        INT            = NULL
    , @CustomerName      NVARCHAR(200)  = NULL
    , @Mobile            NVARCHAR(30)   = NULL
    , @Mobile2           NVARCHAR(30)   = NULL
    , @Email             NVARCHAR(100)  = NULL
    , @CivilID           NVARCHAR(50)   = NULL

    , @AddressID         INT            = NULL
    , @AreaID            INT            = NULL
    , @Block             NVARCHAR(50)   = NULL
    , @Street            NVARCHAR(500)  = NULL
    , @Lane              NVARCHAR(100)  = NULL
    , @Building          NVARCHAR(50)   = NULL
    , @Floor             NVARCHAR(50)   = NULL
    , @Flat              NVARCHAR(50)   = NULL
    , @HouseNo           NVARCHAR(50)   = NULL
    , @PACI              NVARCHAR(50)   = NULL
    , @AddressRemark     NVARCHAR(500)  = NULL
    , @Lat               NVARCHAR(50)   = NULL
    , @Lng               NVARCHAR(50)   = NULL

    , @DeliveryDate      DATETIME       = NULL
    , @PaymentTypeID     INT            = NULL        -- NULL = resolve 'Cash on Delivery'
    , @IsPrepaid         BIT            = 0           -- 1 = money already taken online
    , @PaymentReference  NVARCHAR(100)  = NULL
    , @DiscountTypeID    INT            = 0
    , @InvoiceDiscount   DECIMAL(18,3)  = 0           -- fallback only; a code overrides it
    , @DiscountCode      NVARCHAR(50)   = NULL
    , @DeliveryCharges   DECIMAL(18,3)  = NULL        -- NULL = derive from tblArea
    , @WaiterID          INT            = 0
    , @Comments          NVARCHAR(500)  = NULL
    , @ClientOrderGuid   UNIQUEIDENTIFIER = NULL

    , @dtOrderItems      dbo.TVP_POS_OrderItem READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InvoiceNo     BIGINT
          , @TrackingCode  VARCHAR(12)
          , @RunningOrder  INT
          , @BillAmount    DECIMAL(18,3) = 0
          , @Discount      DECIMAL(18,3) = 0
          , @Today         DATE     = CAST(GETDATE() AS DATE)
          , @Now           DATETIME = GETDATE()
          , @Warning       NVARCHAR(500) = NULL
          , @PriceMismatch INT = 0
          , @LegacyCol     SYSNAME = NULL
          , @IsCOD         BIT = 0;

    /*----------------------------------------------------------------------
      Shared shape for every early return
    ----------------------------------------------------------------------*/
    DECLARE @FailMsg NVARCHAR(500);

    /*======================================================================
      0. VALIDATION
    ======================================================================*/
    IF NOT EXISTS (SELECT 1 FROM @dtOrderItems) SET @FailMsg = N'Cart is empty.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch WHERE id = @BranchID AND ISNULL(IsDeleted,0) = 0)
        SET @FailMsg = N'Invalid or inactive branch.';

    IF @FailMsg IS NOT NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=CAST(NULL AS INT), Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=@FailMsg;
        RETURN;
    END

    /*======================================================================
      1. RESOLVE LOOKUPS BY MEANING, NOT BY HARD-CODED ID

      The head-office tables use IDENTITY keys, so the actual IDs differ per
      deployment. Resolving by name here means the proc works against any
      seeded set without a code change.
    ======================================================================*/
    -- The real head-office channel list is:
    --   1 On Line Order | 2 Dine In | 3 Take Away | 4 Call Centre | 5 Talabat
    -- 'On Line Order' IS the QR menu channel.
    IF @InvoiceTypeID IS NULL
        SELECT TOP 1 @InvoiceTypeID = ID FROM dbo.tblInvoiceType_Master
        WHERE  Name IN (N'On Line Order', N'Online Order', N'QR Menu Online')
        ORDER BY ID;

    -- Deliberately NO fallback to Call Centre. Filing a QR order as a
    -- call-centre order is worse than leaving the channel unset: it is
    -- invisible, and it corrupts every channel report from that point on.

    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType WHERE IsCOD = 1 AND ISNULL(IsDeleted,0)=0;
    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType WHERE IsCash = 1 AND ISNULL(IsDeleted,0)=0;

    IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID AND ISNULL(IsDeleted,0)=0)
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=CAST(NULL AS INT), Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=N'Unknown payment type.';
        RETURN;
    END

    SELECT @LegacyCol = LegacyColumn, @IsCOD = IsCOD
    FROM   dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID;

    /*======================================================================
      2. IDEMPOTENCY
    ======================================================================*/
    IF @ClientOrderGuid IS NOT NULL
    BEGIN
        SELECT @InvoiceNo = InvoiceNo FROM dbo.tblInvoice WHERE ClientOrderGuid = @ClientOrderGuid;

        IF @InvoiceNo IS NOT NULL
        BEGIN
            SELECT Message='Duplicate', InvoiceNo=i.InvoiceNo, TrackingCode=i.TrackingCode,
                   RunningOrder=i.RunningOrder, BillAmount=i.BillAmount, Discount=i.Discount,
                   DeliveryCharges=ISNULL(i.DeliveryCharges,0),
                   FinalAmount=i.FinalAmount,
                   NetPayable=i.FinalAmount + ISNULL(i.DeliveryCharges,0),
                   CustomerId=i.CustomerId, AddressID=i.AddressID, PaymentTypeID=i.PaymentType,
                   Warning=CAST(NULL AS NVARCHAR(500)), ErrorMessage=CAST(NULL AS NVARCHAR(500))
            FROM dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;
            RETURN;
        END
    END

    /*======================================================================
      3. RE-PRICE FROM tblItems
    ======================================================================*/
    DECLARE @lines TABLE
    (
          Seq            INT IDENTITY(1,1) PRIMARY KEY
        , ResolvedItemID INT           NULL
        , ItemName       NVARCHAR(200) NULL
        , Quantity       INT           NOT NULL
        , UnitPrice      DECIMAL(18,3) NOT NULL
        , ClientPrice    DECIMAL(18,3) NULL
        , LineType       TINYINT       NOT NULL
        , ParentItemID   INT           NULL
        , CartItemUniqID INT           NULL
        , Comments       NVARCHAR(MAX) NULL
        , Extra          NVARCHAR(MAX) NULL
    );

    INSERT INTO @lines (ResolvedItemID, ItemName, Quantity, UnitPrice, ClientPrice, LineType, ParentItemID, CartItemUniqID, Comments, Extra)
    SELECT  it.ID, it.ITEM_NAME
          , CASE WHEN d.Quantity < 1 THEN 1 ELSE d.Quantity END
          , CAST(ISNULL(it.PRICE, ISNULL(d.Price,0)) AS DECIMAL(18,3))
          , d.Price, d.LineType, d.ParentItemID, d.CartItemUniqID, d.Comments, d.Extra
    FROM        @dtOrderItems d
    OUTER APPLY (
                    SELECT TOP 1 t.ID, t.ITEM_NAME, t.PRICE
                    FROM   dbo.tblItems t
                    WHERE  (d.ItemID IS NOT NULL AND t.ID  = d.ItemID)
                        OR (d.HID    IS NOT NULL AND t.HID = d.HID)
                        OR (d.ItemID IS NOT NULL AND t.HID = d.ItemID)
                    ORDER BY CASE WHEN t.ID = d.ItemID THEN 0 ELSE 1 END
                ) it;

    SELECT @PriceMismatch = COUNT(*) FROM @lines
    WHERE  ClientPrice IS NOT NULL AND ABS(ClientPrice - UnitPrice) > 0.001;

    SELECT @BillAmount = CAST(ISNULL(SUM(Quantity * UnitPrice),0) AS DECIMAL(18,3)) FROM @lines;

    IF @BillAmount <= 0
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=@PaymentTypeID, Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=N'No priceable items resolved from the cart.';
        RETURN;
    END

    /*======================================================================
      4. DISCOUNT - computed here, never trusted from the browser
    ======================================================================*/
    IF NULLIF(LTRIM(RTRIM(@DiscountCode)),'') IS NOT NULL
    BEGIN
        DECLARE @dtId INT, @dtPct INT, @dtIsPct BIT;

        SELECT TOP 1 @dtId = dt.Id, @dtPct = dt.DiscountPercentage, @dtIsPct = dt.isPercentage
        FROM   dbo.tblDiscountCode dc
        JOIN   dbo.tblDiscount_Type dt ON dt.Id = dc.DiscountTypeId
        WHERE  dc.DiscountCode = @DiscountCode
          AND  ISNULL(dc.Isactive,0) = 1
          AND  ISNULL(dt.IsActive,0) = 1
          AND  ISNULL(dt.IsDeleted,0) = 0;

        IF @dtId IS NULL
        BEGIN
            SET @Discount = 0;
            SET @Warning  = N'Discount code not valid - no discount applied.';
        END
        ELSE
        BEGIN
            SET @DiscountTypeID = @dtId;
            SET @Discount = CASE WHEN ISNULL(@dtIsPct,0) = 1
                                 THEN CAST(@BillAmount * ISNULL(@dtPct,0) / 100.0 AS DECIMAL(18,3))
                                 ELSE CAST(ISNULL(@dtPct,0) AS DECIMAL(18,3))
                            END;
        END
    END
    ELSE IF @DiscountTypeID > 0
    BEGIN
        SELECT TOP 1 @Discount = CASE WHEN ISNULL(dt.isPercentage,0) = 1
                                      THEN CAST(@BillAmount * ISNULL(dt.DiscountPercentage,0) / 100.0 AS DECIMAL(18,3))
                                      ELSE CAST(ISNULL(dt.DiscountPercentage,0) AS DECIMAL(18,3)) END
        FROM   dbo.tblDiscount_Type dt
        WHERE  dt.Id = @DiscountTypeID AND ISNULL(dt.IsActive,0)=1 AND ISNULL(dt.IsDeleted,0)=0;

        SET @Discount = ISNULL(@Discount, 0);
    END
    ELSE
        SET @Discount = ISNULL(@InvoiceDiscount, 0);   -- legacy fallback

    IF @Discount < 0 SET @Discount = 0;
    IF @Discount > @BillAmount SET @Discount = @BillAmount;

    /*======================================================================
      5. DELIVERY CHARGE + AREA / BRANCH VALIDATION
    ======================================================================*/
    IF @OrderType = 2
    BEGIN
        IF @DeliveryCharges IS NULL
            SELECT @DeliveryCharges = ISNULL(a.DeliveryCharges,0) FROM dbo.tblArea a WHERE a.AreaID = @AreaID;

        SET @DeliveryCharges = ISNULL(@DeliveryCharges, 0);

        -- Does this branch actually serve this area?
        IF @AreaID IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID)
           AND NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID AND BranchID = @BranchID)
        BEGIN
            SET @Warning = ISNULL(@Warning + N' ', N'')
                         + N'Branch does not serve this delivery area - review or transfer the order.';
        END
    END
    ELSE
        SET @DeliveryCharges = 0;

    /*======================================================================
      6. TRANSACTION
    ======================================================================*/
    BEGIN TRY
        BEGIN TRANSACTION;

        /*---- 6.1 Customer -----------------------------------------------*/
        IF @CustomerId IS NULL AND NULLIF(LTRIM(RTRIM(@Mobile)),'') IS NOT NULL
            SELECT TOP 1 @CustomerId = id FROM dbo.tblCustomer WITH (UPDLOCK, HOLDLOCK)
            WHERE mobile = @Mobile AND IsDeleted = 0;

        IF @CustomerId IS NULL
        BEGIN
            INSERT INTO dbo.tblCustomer (firstName, mobile, Mobile2, email, CivilID, areaId, block, street, building, flat, landmark, BrandID)
            VALUES (@CustomerName, @Mobile, @Mobile2, @Email, @CivilID, @AreaID, @Block, @Street, @Building, @Flat, @AddressRemark, @BrandID);
            SET @CustomerId = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
            UPDATE dbo.tblCustomer
               SET firstName  = COALESCE(NULLIF(@CustomerName,''), firstName)
                 , email      = COALESCE(NULLIF(@Email,''),        email)
                 , Mobile2    = COALESCE(NULLIF(@Mobile2,''),      Mobile2)
                 , ModifiedOn = @Now
             WHERE id = @CustomerId;

        /*---- 6.2 Address ------------------------------------------------*/
        IF @OrderType = 2 AND @AddressID IS NULL
           AND (@AreaID IS NOT NULL OR NULLIF(@Block,'') IS NOT NULL OR NULLIF(@Street,'') IS NOT NULL)
        BEGIN
            SELECT TOP 1 @AddressID = AddressID FROM dbo.tblCustomerAddress
            WHERE CustomerID = @CustomerId AND IsDeleted = 0
              AND ISNULL(AreaID,-1)   = ISNULL(@AreaID,-1)
              AND ISNULL(Block,'')    = ISNULL(@Block,'')
              AND ISNULL(Street,'')   = ISNULL(@Street,'')
              AND ISNULL(Building,'') = ISNULL(@Building,'')
              AND ISNULL(Flat,'')     = ISNULL(@Flat,'');

            IF @AddressID IS NULL
            BEGIN
                INSERT INTO dbo.tblCustomerAddress
                    (CustomerID, AreaID, Block, Street, Lane, Building, Floor, Flat, HouseNo, PACI, AddressRemark, Lat, Lng, Email)
                VALUES (@CustomerId, @AreaID, @Block, @Street, @Lane, @Building, @Floor, @Flat, @HouseNo, @PACI, @AddressRemark, @Lat, @Lng, @Email);
                SET @AddressID = CAST(SCOPE_IDENTITY() AS INT);
            END
        END

        /*---- 6.3 Daily per-branch number --------------------------------*/
        UPDATE dbo.tblPOS_DailyCounter WITH (UPDLOCK, HOLDLOCK)
           SET @RunningOrder = LastNumber = LastNumber + 1
         WHERE BranchID = @BranchID AND CounterDate = @Today;

        IF @RunningOrder IS NULL
        BEGIN
            INSERT INTO dbo.tblPOS_DailyCounter (BranchID, CounterDate, LastNumber) VALUES (@BranchID, @Today, 1);
            SET @RunningOrder = 1;
        END

        /*---- 6.4 Invoice header -----------------------------------------*/
        INSERT INTO dbo.tblInvoice
        (
              WaiterID, BillAmount, Discount, Comments, Person, Status
            , InvoiceDate, InvoiceTime, PaymentType, Printed, Mobile, MobileText
            , CustomerName, OrderStatus, CustomerId, OrderStatusID, Deleted
            , BranchID, AddressID, BrandID, DeliveryDate, InvoiceType
            , DiscountTypeID, DeliveryCharges, OrderType, TrackingCode
            , ClientOrderGuid, DiscountCode, SourceID, RunningOrder
            , PromisedTime, PrintCount, PaidDate
        )
        VALUES
        (
              @WaiterID, @BillAmount, @Discount, @Comments, 1, 0
            , @Now, @Now, @PaymentTypeID, 0
            , TRY_CAST(REPLACE(REPLACE(ISNULL(@Mobile,''),'+',''),' ','') AS BIGINT), @Mobile
            -- OrderStatus / OrderStatusID both start at 0 = New.
            --
            -- They used to be inserted as 1 (Received), which meant an order
            -- was recorded as acknowledged the instant it was saved - before
            -- anyone in the branch had seen it, let alone printed a ticket.
            -- The status only moves to 1 when the ticket is actually printed;
            -- sp_POS_MarkPrinted does that.
            , @CustomerName, 0, @CustomerId, 0, 0
            , @BranchID, @AddressID, @BrandID, @DeliveryDate, @InvoiceTypeID
            , @DiscountTypeID, @DeliveryCharges, @OrderType, NULL
            , @ClientOrderGuid, @DiscountCode, @SourceID, @RunningOrder
            , DATEADD(MINUTE, ISNULL((SELECT DefaultPrepMinutes FROM dbo.tblPOS_BranchSetting WHERE BranchID=@BranchID),20), @Now)
            , 0, CASE WHEN @IsPrepaid = 1 THEN @Now ELSE NULL END
        );

        SET @InvoiceNo = CAST(SCOPE_IDENTITY() AS BIGINT);

        /*---- 6.5 Tracking code ------------------------------------------*/
        DECLARE @seed BIGINT = @InvoiceNo * 2654435761 % 456976;
        SET @TrackingCode = CHAR(65 + (@seed/17576)%26) + CHAR(65 + (@seed/676)%26)
                          + CHAR(65 + (@seed/26)%26)    + CHAR(65 +  @seed%26)
                          + '-' + RIGHT('0000' + CAST(@InvoiceNo % 10000 AS VARCHAR(4)), 4);

        UPDATE dbo.tblInvoice SET TrackingCode = @TrackingCode WHERE InvoiceNo = @InvoiceNo;

        /*---- 6.6 Order lines --------------------------------------------*/
        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT @InvoiceNo, l.ResolvedItemID, l.Quantity, l.UnitPrice, 0, l.Comments, l.Extra
             , @WaiterID, 0, 0, 0, 0, 0
             , @Now, 0, 0, @DiscountTypeID, 0, @BranchID
             , l.CartItemUniqID, l.LineType, l.ItemName
        FROM @lines l ORDER BY l.Seq;

        /*---- 6.7 Prepaid payment ----------------------------------------
          Money already taken online is recorded now. Cash / COD stays unpaid
          until the POS Pay action collects it.
        -----------------------------------------------------------------*/
        IF @IsPrepaid = 1
        BEGIN
            DECLARE @Paid DECIMAL(18,3) = (@BillAmount - @Discount) + @DeliveryCharges;

            INSERT INTO dbo.tblInvoicePayment
                (PaymentTypeID, InvoiceId, PaymentType, BranchId, Amount, ReferenceNo, IsRefund, ReceivedOn, isdeleted)
            SELECT @PaymentTypeID, @InvoiceNo, pt.PaymentTypeName, @BranchID, @Paid, @PaymentReference, 0, @Now, 0
            FROM   dbo.tblInvoicePaymentType pt WHERE pt.ID = @PaymentTypeID;

            -- Mirror into the legacy per-method column so end-of-day reports still add up.
            IF @LegacyCol IS NOT NULL
            BEGIN
                DECLARE @sql NVARCHAR(MAX) =
                    N'UPDATE dbo.tblInvoice SET ' + QUOTENAME(@LegacyCol) + N' = @amt WHERE InvoiceNo = @inv;';
                EXEC sp_executesql @sql, N'@amt DECIMAL(18,3), @inv BIGINT', @amt = @Paid, @inv = @InvoiceNo;
            END
        END

        /*---- 6.8 Status history + audit ---------------------------------*/
        -- The order arrives AT status 0; there is no prior status, so FromStatusID
        -- is NULL rather than 0. Recording 0 -> 1 here claimed a transition that
        -- had not happened, and left the history disagreeing with the invoice.
        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, Comments)
        VALUES (@InvoiceNo, NULL, 0, NULL, N'System', N'Order placed from QR Menu');

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserName, NewValues)
        VALUES ('Invoice', @InvoiceNo, 'Create', N'QRMenu',
                CONCAT(N'Branch=', @BranchID, N'; Lines=', (SELECT COUNT(*) FROM @lines),
                       N'; Bill=', @BillAmount, N'; Disc=', @Discount,
                       N'; Deliv=', @DeliveryCharges,
                       N'; PriceMismatchLines=', @PriceMismatch,
                       N'; Warning=', ISNULL(@Warning,N'none')));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @err NVARCHAR(500) = ERROR_MESSAGE();

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserName, NewValues)
        VALUES ('Invoice', NULL, 'CreateFailed', N'QRMenu', @err);

        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=@PaymentTypeID, Warning=@Warning, ErrorMessage=@err;
        RETURN;
    END CATCH

    /*======================================================================
      7. RESULT
         FinalAmount = BillAmount - Discount        (matches the DB column)
         NetPayable  = FinalAmount + DeliveryCharges (what the customer pays)
    ======================================================================*/
    SELECT Message         = 'Success'
         , InvoiceNo       = @InvoiceNo
         , TrackingCode    = @TrackingCode
         , RunningOrder    = @RunningOrder
         , BillAmount      = @BillAmount
         , Discount        = @Discount
         , DeliveryCharges = @DeliveryCharges
         , FinalAmount     = @BillAmount - @Discount
         , NetPayable      = (@BillAmount - @Discount) + @DeliveryCharges
         , CustomerId      = @CustomerId
         , AddressID       = @AddressID
         , PaymentTypeID   = @PaymentTypeID
         , Warning         = @Warning
         , ErrorMessage    = CAST(NULL AS NVARCHAR(500));
END
GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_Role_List]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RoleID = LegacyRoleId, RoleName
    FROM   Security.Roles
    WHERE  IsPosRole = 1 AND LegacyRoleId IS NOT NULL AND Deleted = 0
    ORDER BY LegacyRoleId;
END
GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_TakePaymentSplit]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_TakePaymentSplit]
      @InvoiceNo   BIGINT
    , @Lines       dbo.TVP_POS_PaymentLine READONLY
    , @ReferenceNo NVARCHAR(100) = NULL
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
    , @Comments    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @Status INT, @BranchID INT, @Total DECIMAL(18,3), @Paid DECIMAL(18,3)
          , @Due DECIMAL(18,3), @Tendered DECIMAL(18,3), @Change DECIMAL(18,3) = 0
          , @Err NVARCHAR(500) = NULL;

    SELECT @Status   = i.OrderStatusID
         , @BranchID = i.BranchID
         , @Total    = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceNo = @InvoiceNo AND ISNULL(i.Deleted,0) = 0;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p
    WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    SET @Due      = @Total - ISNULL(@Paid, 0);
    SELECT @Tendered = ISNULL(SUM(Amount), 0) FROM @Lines WHERE Amount > 0;

    /*---- refuse ---------------------------------------------------------*/
    IF @Status IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @Status IN (6, 7, 8)
        -- 6 is this installation's cancelled status (POS_27), 7 and 8 are the
        -- seeded Cancelled / Refunded. Money must not be taken against any.
        SET @Err = N'This order is cancelled or refunded.';
    ELSE IF @Tendered <= 0
        SET @Err = N'Enter an amount against at least one payment type.';
    ELSE IF @Due <= 0.001
        SET @Err = N'This order is already paid in full.';
    ELSE IF EXISTS (SELECT 1 FROM @Lines l WHERE l.Amount < 0)
        SET @Err = N'A payment amount cannot be negative. Use a refund instead.';
    ELSE IF EXISTS (SELECT 1 FROM @Lines l
                    WHERE NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType t
                                      WHERE t.ID = l.PaymentTypeID AND ISNULL(t.IsDeleted,0) = 0))
        SET @Err = N'One of the payment types is not recognised.';
    ELSE IF EXISTS (SELECT 1 FROM @Lines l
                    JOIN dbo.tblInvoicePaymentType t ON t.ID = l.PaymentTypeID
                    WHERE l.Amount > 0 AND t.RequiresReference = 1
                      AND NULLIF(LTRIM(RTRIM(ISNULL(@ReferenceNo, N''))), N'') IS NULL)
        SET @Err = N'A reference number is required for one of the selected payment types.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, AmountDue = @Due,
               AmountPaid = @Paid, ChangeGiven = CAST(NULL AS DECIMAL(18,3)),
               PaymentStatus = CAST(NULL AS VARCHAR(10)), ErrorMessage = @Err;
        RETURN;
    END

    /*---- allocate --------------------------------------------------------
      Applied in payment-type sequence. Running total against the balance:
      everything before the crossing point is recorded in full, the crossing
      line is recorded at the remainder and carries the tendered amount and the
      change, and anything after it is not a payment at all.
    ---------------------------------------------------------------------*/
    IF @Tendered > @Due + 0.001 SET @Change = @Tendered - @Due;

    DECLARE @alloc TABLE
    (
          Seq           INT IDENTITY(1,1)
        , PaymentTypeID INT
        , Tendered      DECIMAL(18,3)
        , Applied       DECIMAL(18,3)
        , Change        DECIMAL(18,3)
    );

    INSERT INTO @alloc (PaymentTypeID, Tendered, Applied, Change)
    SELECT   l.PaymentTypeID
           , l.Amount
           -- Running total BEFORE this line tells us how much of the balance is
           -- still open when it is applied.
           , CASE
                WHEN @Due - ISNULL(SUM(l.Amount) OVER (ORDER BY ISNULL(t.Seqnum, 9999), t.ID
                                                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) <= 0
                     THEN 0
                WHEN l.Amount <= @Due - ISNULL(SUM(l.Amount) OVER (ORDER BY ISNULL(t.Seqnum, 9999), t.ID
                                                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
                     THEN l.Amount
                ELSE @Due - ISNULL(SUM(l.Amount) OVER (ORDER BY ISNULL(t.Seqnum, 9999), t.ID
                                                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
             END
           , 0
    FROM     @Lines l
    JOIN     dbo.tblInvoicePaymentType t ON t.ID = l.PaymentTypeID
    WHERE    l.Amount > 0
    ORDER BY ISNULL(t.Seqnum, 9999), t.ID;

    -- Drop lines that turned out to be entirely change.
    DELETE FROM @alloc WHERE Applied <= 0;

    IF NOT EXISTS (SELECT 1 FROM @alloc)
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, AmountDue = @Due,
               AmountPaid = @Paid, ChangeGiven = CAST(NULL AS DECIMAL(18,3)),
               PaymentStatus = CAST(NULL AS VARCHAR(10)),
               ErrorMessage = N'Nothing to apply against this order.';
        RETURN;
    END

    -- The change belongs to the last line that was actually applied - the one
    -- the customer overpaid on.
    UPDATE @alloc
       SET Change = @Change
     WHERE Seq = (SELECT MAX(Seq) FROM @alloc);

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tblInvoicePayment
            (PaymentTypeID, InvoiceId, PaymentType, BranchId, Amount, AmountTendered,
             ChangeGiven, ReferenceNo, IsRefund, ReceivedBy, ReceivedOn, Comments, isdeleted)
        SELECT   a.PaymentTypeID, @InvoiceNo, t.PaymentTypeName, @BranchID
               , a.Applied
               , a.Tendered
               , NULLIF(a.Change, 0)
               , @ReferenceNo, 0, @UserID, @Now, @Comments, 0
        FROM     @alloc a
        JOIN     dbo.tblInvoicePaymentType t ON t.ID = a.PaymentTypeID
        ORDER BY a.Seq;

        SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
        FROM   dbo.tblInvoicePayment p
        WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

        UPDATE dbo.tblInvoice
           SET PaidDate   = CASE WHEN @Paid + 0.001 >= @Total THEN ISNULL(PaidDate, @Now) ELSE NULL END
             , ModifiedOn = @Now
             , ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        /*---- Legacy per-method columns, rebuilt from the rows.
               Same treatment as sp_POS_AddPayment: recalculated rather than
               incremented, so a corrected or refunded row cannot leave the old
               end-of-day reports drifting. ----*/
        DECLARE @col SYSNAME, @sql NVARCHAR(MAX);
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT LegacyColumn FROM dbo.tblInvoicePaymentType WHERE LegacyColumn IS NOT NULL AND COL_LENGTH('dbo.tblInvoice', LegacyColumn) IS NOT NULL;
        OPEN c; FETCH NEXT FROM c INTO @col;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'
                UPDATE i SET ' + QUOTENAME(@col) + N' = ISNULL(x.Amt, 0)
                FROM dbo.tblInvoice i
                OUTER APPLY (
                    SELECT Amt = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                    FROM   dbo.tblInvoicePayment p
                    JOIN   dbo.tblInvoicePaymentType t ON t.ID = p.PaymentTypeID
                    WHERE  p.InvoiceId = @inv AND ISNULL(p.isdeleted,0) = 0 AND t.LegacyColumn = @c
                ) x
                WHERE i.InvoiceNo = @inv;';
            EXEC sp_executesql @sql, N'@inv BIGINT, @c SYSNAME', @inv = @InvoiceNo, @c = @col;
            FETCH NEXT FROM c INTO @col;
        END
        CLOSE c; DEALLOCATE c;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (SELECT 'Invoice', @InvoiceNo, 'Payment', @UserID, @UserName,
               CONCAT(N'Split=', (SELECT COUNT(*) FROM @alloc),
                      N' Tendered=', @Tendered, N' Applied=', (SELECT SUM(Applied) FROM @alloc),
                      N' Change=', @Change, N' PaidNow=', @Paid, N' Total=', @Total)) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, AmountDue = @Due,
               AmountPaid = @Paid, ChangeGiven = CAST(NULL AS DECIMAL(18,3)),
               PaymentStatus = CAST(NULL AS VARCHAR(10)), ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT   Message       = 'Success'
           , InvoiceNo     = @InvoiceNo
           , AmountDue     = @Total
           , AmountPaid    = @Paid
           , ChangeGiven   = @Change
           , PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid'
                                  WHEN @Paid + 0.001 >= @Total THEN 'Paid' ELSE 'Partial' END
           , ErrorMessage  = CAST(NULL AS NVARCHAR(500));
END
GO
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_TransferOrder]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_TransferOrder]
      @InvoiceNo   BIGINT
    , @ToBranchID  INT
    , @Reason      NVARCHAR(500) = NULL
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @FromBranch INT, @Status INT, @AreaID INT
          , @Err NVARCHAR(500) = NULL, @Warning NVARCHAR(500) = NULL;

    SELECT @FromBranch = i.BranchID, @Status = i.OrderStatusID, @AreaID = ca.AreaID
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblCustomerAddress ca ON ca.AddressID = i.AddressID
    WHERE     i.InvoiceNo = @InvoiceNo;

    IF @FromBranch IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @Status IN (6, 7, 8)
        SET @Err = N'A completed, cancelled or refunded order cannot be transferred.';
    ELSE IF @Status IN (4, 5)
        -- Once a driver has the food, moving the order to another branch means
        -- the branch that will actually deliver it is not the one on record.
        SET @Err = N'Order is already with a driver - recall it first.';
    ELSE IF @ToBranchID = @FromBranch
        SET @Err = N'Order is already at that branch.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch WHERE id = @ToBranchID AND ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1)
        SET @Err = N'Target branch is invalid or inactive.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, ErrorMessage=@Err, Warning=CAST(NULL AS NVARCHAR(500));
        RETURN;
    END

    -- Coverage is advisory, not blocking: a manager moving an order to a branch
    -- that is not mapped usually knows something the mapping does not.
    IF @AreaID IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID)
       AND NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID AND BranchID = @ToBranchID)
        SET @Warning = N'Target branch is not mapped to this delivery area.';

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET BranchID   = @ToBranchID
             , ModifiedOn = @Now
             , ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        -- Line rows carry BranchID too; leaving them behind would make every
        -- branch-level item report disagree with the header.
        UPDATE dbo.tblOrder SET BranchID = @ToBranchID WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_OrderTransfer (InvoiceNo, FromBranchID, ToBranchID, Reason, TransferredBy, TransferredOn)
        VALUES (@InvoiceNo, @FromBranch, @ToBranchID, @Reason, @UserID, @Now);

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @Status, @Status, @UserID, @UserName, @Now,
                CONCAT(N'Transferred from branch ', @FromBranch, N' to ', @ToBranchID,
                       CASE WHEN @Reason IS NULL THEN N'' ELSE N': ' + @Reason END));

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        SELECT a.EntityType, a.EntityID, a.Action, su.UserId, a.UserName, a.Details
        FROM (VALUES ('Invoice', @InvoiceNo, 'Transfer', @UserID, @UserName,
                CONCAT(N'From=', @FromBranch, N' To=', @ToBranchID, N' Reason=', ISNULL(@Reason, N'')))) AS a (EntityType, EntityID, Action, UserID, UserName, Details)
        LEFT JOIN Security.Users su ON su.UserId = a.UserID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, ErrorMessage=ERROR_MESSAGE(), Warning=CAST(NULL AS NVARCHAR(500));
        RETURN;
    END CATCH

    SELECT Message='Success', InvoiceNo=@InvoiceNo, ErrorMessage=CAST(NULL AS NVARCHAR(500)), Warning=@Warning;
END

GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_User_ChangeRole]
      @UserID         INT
    , @RoleID         INT
    , @ActorUserID    INT           = NULL
    , @ActorUserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Err NVARCHAR(500) = NULL, @OldRoleID INT, @Exists BIT = 0;

    IF EXISTS (SELECT 1 FROM Security.Users WHERE UserId = @UserID AND IsQrMenuUser = 1 AND Deleted = 0)
        SET @Exists = 1;
    SELECT @OldRoleID = LegacyRoleId FROM dbo.fn_QR_UserRole(@UserID);

    IF @Exists = 0
        SET @Err = N'User not found.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Security.Roles WHERE LegacyRoleId = @RoleID AND IsPosRole = 1 AND Deleted = 0)
        SET @Err = N'Unknown role.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.fn_QR_RoleFlags(@OldRoleID) WHERE CanManageMasters = 1)
        AND NOT EXISTS (SELECT 1 FROM dbo.fn_QR_RoleFlags(@RoleID) WHERE CanManageMasters = 1)
        AND (SELECT COUNT(*)
             FROM   Security.Users u3
             CROSS APPLY dbo.fn_QR_UserRole(u3.UserId)         q3
             CROSS APPLY dbo.fn_QR_RoleFlags(q3.LegacyRoleId) f3
             WHERE  u3.IsQrMenuUser = 1 AND u3.Deleted = 0 AND f3.CanManageMasters = 1) <= 1
        SET @Err = N'This is the only user who can manage Settings/User Management - assign another user that role first.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_QR_SetUserRole @UserId = @UserID, @LegacyRoleId = @RoleID;

        INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
        VALUES ('User', @UserID, 'ChangeRole', (SELECT su.UserId FROM Security.Users su WHERE su.UserId = @ActorUserID), @ActorUserName,
                CONCAT(N'RoleID ', ISNULL(@OldRoleID,0), N'->', @RoleID));
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', UserID = @UserID, RoleID = @RoleID, ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_User_List]
AS
BEGIN
    SET NOCOUNT ON;

    -- result set 0: the grid, unchanged columns
    SELECT
          ID                = CAST(u.UserId AS INT)
        , NAME              = u.DisplayName
        , USERNAME          = u.Username
        , BranchID          = TRY_CAST(u.BrandID AS INT)
        , BranchName        = b.branchName
        , RoleID            = qr.LegacyRoleId
        , RoleName          = ISNULL(f.RoleName, N'(no role)')
        , CanManageMasters  = ISNULL(f.CanManageMasters, 0)
        , HasHashedPassword = CASE WHEN u.PosPasswordHash IS NOT NULL THEN 1 ELSE 0 END
    FROM        Security.Users u
    OUTER APPLY dbo.fn_QR_UserRole(u.UserId)         qr
    OUTER APPLY dbo.fn_QR_RoleFlags(qr.LegacyRoleId) f
    LEFT JOIN   dbo.tblbranch b ON b.id = TRY_CAST(u.BrandID AS INT)
    WHERE       u.IsQrMenuUser = 1 AND u.Deleted = 0
    ORDER BY    u.DisplayName;

    -- result set 1: every user's assigned branches (Order List / Dashboard access)
    SELECT
          m.UserID
        , m.BranchID
        , BranchName = ISNULL(ab.branchName, N'?')
    FROM      dbo.tblPOS_UserBranch_Map m
    LEFT JOIN dbo.tblbranch ab ON ab.id = m.BranchID
    ORDER BY  m.UserID, ab.branchName;
END
GO
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_POS_User_Save]
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
    ELSE IF NOT EXISTS (SELECT 1 FROM Security.Roles WHERE LegacyRoleId = @RoleID AND IsPosRole = 1 AND Deleted = 0)
        SET @Err = N'Unknown role.';
    ELSE IF EXISTS (SELECT 1 FROM Security.Users WHERE Username = @Username AND UserId <> ISNULL(@UserID, 0))
        SET @Err = N'That username is already in use.';
    ELSE IF @IsInsert = 0 AND NOT EXISTS (SELECT 1 FROM Security.Users WHERE UserId = @UserID AND IsQrMenuUser = 1 AND Deleted = 0)
        SET @Err = N'User not found.';

    IF @Err IS NULL AND @IsInsert = 0
    BEGIN
        SELECT @OldRoleID = LegacyRoleId FROM dbo.fn_QR_UserRole(@UserID);

        -- Would this update take the CanManageMasters permission away from
        -- the only user who currently has it?
        IF EXISTS (SELECT 1 FROM dbo.fn_QR_RoleFlags(@OldRoleID) WHERE CanManageMasters = 1)
           AND NOT EXISTS (SELECT 1 FROM dbo.fn_QR_RoleFlags(@RoleID) WHERE CanManageMasters = 1)
           AND (SELECT COUNT(*)
                FROM   Security.Users u3
                CROSS APPLY dbo.fn_QR_UserRole(u3.UserId)         q3
                CROSS APPLY dbo.fn_QR_RoleFlags(q3.LegacyRoleId) f3
                WHERE  u3.IsQrMenuUser = 1 AND u3.Deleted = 0 AND f3.CanManageMasters = 1) <= 1
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
            INSERT INTO Security.Users (CompanyId, Username, [Password], PosPasswordHash, PosPasswordSalt, DisplayName, BrandID, IsQrMenuUser, IsActive)
            VALUES (dbo.fn_QR_DefaultCompanyId(), @Username, N'', @Hash, @Salt, @Name, @BranchID, 1, 1);
            SET @UserID = SCOPE_IDENTITY();

            EXEC dbo.usp_QR_SetUserRole @UserId = @UserID, @LegacyRoleId = @RoleID;

            INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
            VALUES ('User', @UserID, 'Create', (SELECT su.UserId FROM Security.Users su WHERE su.UserId = @ActorUserID), @ActorUserName,
                    CONCAT(N'Username=', @Username, N' RoleID=', @RoleID));
        END
        ELSE
        BEGIN
            -- BrandID is deliberately NOT touched here - it is only ever set
            -- on INSERT, above, and is left exactly as it was on every UPDATE.
            IF @NewPassword IS NOT NULL
            BEGIN
                UPDATE Security.Users
                   SET DisplayName     = @Name
                     , Username        = @Username
                     , PosPasswordHash = @Hash
                     , PosPasswordSalt = @Salt
                     , [Password]      = N''
                     , PasswordChangedDateUtc = SYSUTCDATETIME()
                     , ModifiedDate    = SYSUTCDATETIME()
                 WHERE UserId = @UserID;
            END
            ELSE
            BEGIN
                UPDATE Security.Users
                   SET DisplayName  = @Name
                     , Username     = @Username
                     , ModifiedDate = SYSUTCDATETIME()
                 WHERE UserId = @UserID;
            END

            EXEC dbo.usp_QR_SetUserRole @UserId = @UserID, @LegacyRoleId = @RoleID;

            INSERT INTO Security.AuditLogs (EntityName, RecordId, Action, UserId, UserName, NewValues)
            VALUES ('User', @UserID, 'Update', (SELECT su.UserId FROM Security.Users su WHERE su.UserId = @ActorUserID), @ActorUserName,
                    CONCAT(N'Username=', @Username,
                           N' RoleID ', ISNULL(@OldRoleID,0), N'->', @RoleID,
                           CASE WHEN @NewPassword IS NOT NULL THEN N' PasswordChanged' ELSE N'' END));
        END

        -- Order List / Dashboard branch access - always replaced with the
        -- complete set submitted.
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
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_changePassword]
	@UserId Int = 0,
	@OldPassword Varchar(50) = '',
	@NewPassword Varchar(50) = ''
AS
BEGIN
	SET NOCOUNT ON;
	If Not Exists (Select 1 From Security.Users Where [Password] = @OldPassword And UserId = @UserId And Deleted = 0)
	Begin
		Select 'Wrong Password' As Msg
	End
	Else
	Begin
		Update Security.Users Set [Password] = @NewPassword, PasswordChangedDateUtc = SYSUTCDATETIME(), ModifiedDate = SYSUTCDATETIME() Where UserId = @UserId
	End
END
GO
GO

/*------------------------------------------------------------------------------
  4. DROP THE OLD TABLES  (only if nothing still depends on them)
------------------------------------------------------------------------------*/
DECLARE @deps NVARCHAR(MAX) =
    (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT(OBJECT_SCHEMA_NAME(d.referencing_id), N'.', OBJECT_NAME(d.referencing_id), N' -> ', d.referenced_entity_name)), N', ')
     FROM sys.sql_expression_dependencies d
     WHERE d.referenced_entity_name IN (N'tblcompany', N'tblUser', N'tblRole', N'tblPOS_Role_Master', N'tblPOS_AuditLog', N'tblLabelName', N'tblPrinter')
       AND d.referenced_database_name IS NULL
       /* old HRMS procedure for a different, non-existent tblRole (ID, Role_Name) - not related */
       AND OBJECT_NAME(d.referencing_id) NOT IN (N'sp_Get_DelegateRoleList'));
IF @deps IS NOT NULL
BEGIN
    DECLARE @m NVARCHAR(1800) = LEFT(@deps, 1800);
    RAISERROR(N'Old tables NOT dropped - still referenced by: %s', 16, 1, @m) WITH NOWAIT;
END
ELSE
BEGIN
    DROP TABLE dbo.tblPOS_AuditLog, dbo.tblLabelName, dbo.tblPrinter,
               dbo.tblUser, dbo.tblRole, dbo.tblPOS_Role_Master,
               dbo.tblcompany;
    PRINT N'Old tables dropped: tblcompany, tblUser, tblRole, tblPOS_Role_Master, tblPOS_AuditLog, tblLabelName, tblPrinter.';
END;
GO
/*------------------------------------------------------------------------------
  5. PERMISSIONS + CHECK
------------------------------------------------------------------------------*/
IF DATABASE_PRINCIPAL_ID(N'hrms_app_role') IS NOT NULL
BEGIN
    GRANT EXECUTE ON OBJECT::dbo.usp_QR_SetUserRole      TO [hrms_app_role];
    GRANT EXECUTE ON OBJECT::dbo.fn_QR_DefaultCompanyId  TO [hrms_app_role];
    GRANT SELECT  ON OBJECT::dbo.fn_QR_UserRole          TO [hrms_app_role];
    GRANT SELECT  ON OBJECT::dbo.fn_QR_RoleFlags         TO [hrms_app_role];
END;
GO
SELECT Item = N'QR users in Security.Users', Cnt = (SELECT COUNT(*) FROM Security.Users WHERE IsQrMenuUser = 1)
UNION ALL SELECT N'QR roles in Security.Roles',  (SELECT COUNT(*) FROM Security.Roles WHERE LegacyRoleId IS NOT NULL)
UNION ALL SELECT N'QR user-role links',          (SELECT COUNT(*) FROM Security.UserRoles ur JOIN Security.Roles r ON r.RoleId = ur.RoleId WHERE r.LegacyRoleId IS NOT NULL AND ur.Deleted = 0)
UNION ALL SELECT N'POS audit rows',              (SELECT COUNT(*) FROM Security.AuditLogs WHERE UserName IS NOT NULL OR EntityName IN (N'Invoice', N'User', N'Table', N'TableSession'))
UNION ALL SELECT N'QR labels in Core.UiLabels',  (SELECT COUNT(*) FROM Core.UiLabels WHERE Module = 'qrmenu');
PRINT N'Step 02 finished.';
GO
SET NOEXEC OFF;
GO
