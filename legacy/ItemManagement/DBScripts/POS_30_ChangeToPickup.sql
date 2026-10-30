/**********************************************************************************
  POS_30_ChangeToPickup.sql
  ------------------------------------------------------------------------------
  sp_POS_ChangeToPickup - turn a delivery into a collection from a branch.

  The customer is coming to get it. That is four changes to the invoice, and
  they only make sense together:

      InvoiceType     -> 3    the channel this order is now counted under
      OrderType       -> 1    Pickup. The status rules read this: a status
                              flagged AppliesToPickup = 0 stops being offered
                              the moment the order becomes a collection
      BranchID        -> the branch they are collecting from, lines included
      DeliveryCharges -> 0    nobody is driving anywhere

  Dropping the delivery charge moves the money. FinalAmount is BillAmount less
  Discount and never included the charge, so the total the customer owes -
  NetPayable - falls by exactly the charge that was removed. If they have
  already paid, that leaves the order overpaid, and this says so rather than
  quietly leaving a difference for the cash-up to find.

  The address is deliberately left on the invoice. It is how the order was
  taken and how the customer is identified on the phone; blanking it to reflect
  that no one is driving there destroys the record of what was agreed.

  Run after POS_09_ActionProcs.sql. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_POS_ChangeToPickup') IS NOT NULL DROP PROCEDURE dbo.sp_POS_ChangeToPickup;
GO

CREATE PROCEDURE dbo.sp_POS_ChangeToPickup
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'ChangeToPickup', @UserID, @UserName,
                CONCAT(N'Branch=', @FromBranch, N'->', @BranchID,
                       N' InvoiceType=', @InvoiceType,
                       N' OrderType=1 DeliveryCharges=', @OldCharge, N'->0'));

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

PRINT 'sp_POS_ChangeToPickup created.';
GO
