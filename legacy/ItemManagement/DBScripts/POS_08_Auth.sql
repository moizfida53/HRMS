/**********************************************************************************
  POS_08_Auth.sql   -   sp_POS_Login + branch/lookup bootstrap for the POS Area

  >>> SECURITY NOTE, PLEASE READ <<<
  tblUser.PASSWORD is varchar(50) holding the password in PLAIN TEXT. Anyone
  with read access to the database - or to a backup file, or to a stray .bak on
  a USB stick - has every POS login. This proc does not make that worse, but it
  does not fix it either, and it should be fixed before the POS is exposed to
  more than a couple of trusted users.

  The migration is small and self-contained:
      1. ALTER TABLE dbo.tblUser ADD PasswordHash VARBINARY(64), PasswordSalt VARBINARY(32);
      2. On next successful plain-text login, compute and store the hash.
      3. Once every active user has a hash, drop the PASSWORD column.
  Use HASHBYTES('SHA2_512', @salt + @pwd) at minimum; PBKDF2 via
  System.Security.Cryptography.Rfc2898DeriveBytes in C# is better.

  Ask when you want this done - it is roughly an hour of work and it is the
  single largest security gap in the current schema.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

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
      AND     u.PASSWORD = @Password;

    -- Deliberately no row on failure: the caller cannot tell "bad user" from
    -- "bad password", so the login form cannot be used to enumerate accounts.
END
GO


/*==============================================================================
  Bootstrap data for the POS shell: branches, statuses, payment types,
  cancel reasons, channels. One round trip on page load, cached client-side.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetLookups') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetLookups;
GO

CREATE PROCEDURE dbo.sp_POS_GetLookups
      @BrandID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 0: branches
    SELECT   BranchID = id, BranchName = branchName, BranchNameAra = branchNameAra, BrandID = brandId
    FROM     dbo.tblbranch
    WHERE    ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1
      AND    (@BrandID IS NULL OR brandId = @BrandID)
    ORDER BY ISNULL(SEQ_NUM, 9999), branchName;

    -- 1: statuses
    SELECT   OrderStatusID, OrderStatusName, OrderStatusNameAra, SortOrder, ColorHex,
             IsTerminal, AppliesToPickup, AppliesToDelivery
    FROM     dbo.tblOrderStatus
    WHERE    ISNULL(IsActive,1) = 1
    ORDER BY SortOrder;

    -- 2: payment types
    SELECT   PaymentTypeID = ID, PaymentTypeName, PaymentTypeNameArb,
             IsCash, IsOnline, IsCOD, RequiresReference
    FROM     dbo.tblInvoicePaymentType
    WHERE    ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1
    ORDER BY Seqnum, ID;

    -- 3: cancellation reasons
    SELECT   CancelReasonID, ReasonName, ReasonNameAra, DefaultDisposition
    FROM     dbo.tblPOS_CancelReason_Master
    WHERE    IsActive = 1
    ORDER BY CancelReasonID;

    -- 4: channels
    SELECT   InvoiceTypeID = ID, Name, ShowInCallCentre
    FROM     dbo.tblInvoiceType_Master ORDER BY ID;

    -- 5: cash denominations for the tender pad
    SELECT   id, DenominationType, DenominationValue
    FROM     dbo.tblDenomination ORDER BY DenominationValue DESC;
END
GO

PRINT 'sp_POS_Login / sp_POS_GetLookups created.';
GO

/* Smoke test:
   EXEC dbo.sp_POS_Login @Username = N'admin', @Password = N'<the admin password>';
   EXEC dbo.sp_POS_GetLookups;
*/
