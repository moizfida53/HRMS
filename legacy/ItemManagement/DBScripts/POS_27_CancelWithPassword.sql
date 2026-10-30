/**********************************************************************************
  POS_27_CancelWithPassword.sql
  ------------------------------------------------------------------------------
  sp_POS_CancelOrderReject

  Cancelling from the Order List asks for two things and accepts nothing less:

      a reason    saved to tblInvoice.Comments
      a password  checked against tblUser.deletePassword for a RoleID = 1 user

  The password is the authorisation. Whoever is logged in at the counter does
  not need the cancel permission on their own account - a manager types the
  delete password over their shoulder - so the check is on the password, not on
  the session. The user whose password matched is recorded, which is the whole
  point of asking for it.

  This is deliberately separate from sp_POS_CancelOrder (POS_09), which is the
  fuller flow: a cancel reason from the master list, a waste/reuse disposition,
  a refund check, and status 7. This one is the counter's quick reject and lands
  on status 6, as specified.

  Run after POS_09_ActionProcs.sql. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 1 - the column this depends on

  tblUser.deletePassword is head-office's column, not one this project creates.
  If it is missing, say so here rather than letting CREATE PROCEDURE fail with
  "Invalid column name" three screens further down.
==============================================================================*/
IF COL_LENGTH('dbo.tblUser', 'deletePassword') IS NULL
    PRINT '!! tblUser.deletePassword does NOT exist - the proc below will reject every password.';
ELSE
    PRINT '   tblUser.deletePassword found.';

IF NOT EXISTS (SELECT 1 FROM dbo.tblUser WHERE ISNULL(RoleID,0) = 1)
    PRINT '!! No tblUser row with RoleID = 1 - nobody can authorise a cancellation.';
ELSE
    SELECT ManagersWithADeletePassword = COUNT(*)
    FROM   dbo.tblUser
    WHERE  ISNULL(RoleID,0) = 1;
GO


/*==============================================================================
  SECTION 2 - sp_POS_CancelOrderReject
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_CancelOrderReject') IS NOT NULL DROP PROCEDURE dbo.sp_POS_CancelOrderReject;
GO

CREATE PROCEDURE dbo.sp_POS_CancelOrderReject
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
    IF COL_LENGTH('dbo.tblUser', 'deletePassword') IS NOT NULL
       AND NULLIF(LTRIM(RTRIM(ISNULL(@Password, N''))), N'') IS NOT NULL
    BEGIN
        DECLARE @sql NVARCHAR(MAX) = N'
            SELECT TOP (1) @pID = u.ID, @pName = u.NAME
            FROM   dbo.tblUser u
            WHERE  ISNULL(u.RoleID, 0) = 1
              AND  NULLIF(LTRIM(RTRIM(ISNULL(u.deletePassword, N''''))), N'''') IS NOT NULL
              AND  LTRIM(RTRIM(u.deletePassword)) = LTRIM(RTRIM(@pPwd))
            ORDER BY u.ID;';

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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Cancel', ISNULL(@UserID, @ApprovedByID),
                ISNULL(@UserName, @ApprovedBy),
                CONCAT(N'From=', @From, N' To=6 ApprovedByUserID=', @ApprovedByID,
                       N' Comments=', @Comments));

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

PRINT 'sp_POS_CancelOrderReject created.';
GO

/*==============================================================================
  Smoke test - replace the invoice number and password first.

  EXEC dbo.sp_POS_CancelOrderReject
        @InvoiceNo = 1001, @Comments = N'Customer changed their mind',
        @Password  = N'wrong', @UserID = 1, @UserName = N'Counter';
      -> Fail, "That password is not recognised."
==============================================================================*/
