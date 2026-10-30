/**********************************************************************************
  POS_29_DeleteOrderLine.sql
  ------------------------------------------------------------------------------
  sp_POS_DeleteOrderLine - void one line off an order and re-total the invoice.

  Asked for exactly like a cancellation: waste or reuse, a comment, and the
  delete password of a RoleID = 1 user. The password is the authorisation, not
  the session - a cashier runs it while a manager types.

  Three things happen together, so they happen in one transaction:

    1. The line is marked Deleted = 1. Nothing is removed from tblOrder: a
       kitchen ticket has already gone out with that item on it, and an order
       whose history quietly rewrites itself cannot be argued with at the end
       of the day.

    2. Its children go with it. Extras and choices hang off the line by
       ParentOrderID and are priced rows in their own right - leaving them
       behind would keep charging for the cheese on a burger that is no longer
       on the order.

    3. tblInvoice.BillAmount is rebuilt from the lines that remain, which is
       how FinalAmount moves: it is a computed column, BillAmount - Discount.
       Rebuilt rather than decremented, so a second void or a correction can
       never leave the invoice drifting from its own lines.

  Run after POS_09_ActionProcs.sql. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_POS_DeleteOrderLine') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DeleteOrderLine;
GO

CREATE PROCEDURE dbo.sp_POS_DeleteOrderLine
      @InvoiceNo    BIGINT
    , @OrderID      BIGINT
    , @Disposition  TINYINT               -- 1 = Waste, 2 = Reuse
    , @Comments     NVARCHAR(500)
    , @Password     NVARCHAR(100)
    , @UserID       INT           = NULL
    , @UserName     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME = GETDATE();
    DECLARE @Err NVARCHAR(500), @Status INT, @LineExists BIT = 0
          , @ApprovedByID INT, @ApprovedBy NVARCHAR(100)
          , @Live INT, @Killing INT
          , @BillAmount DECIMAL(18,3), @Discount DECIMAL(18,3)
          , @DeliveryCharges DECIMAL(18,3), @Paid DECIMAL(18,3)
          , @Warning NVARCHAR(300) = NULL;

    SET @Comments = NULLIF(LTRIM(RTRIM(ISNULL(@Comments, N''))), N'');

    SELECT @Status = i.OrderStatusID
         , @Discount = ISNULL(i.Discount, 0)
         , @DeliveryCharges = ISNULL(i.DeliveryCharges, 0)
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceNo = @InvoiceNo AND ISNULL(i.Deleted,0) = 0;

    IF EXISTS (SELECT 1 FROM dbo.tblOrder
               WHERE OrderID = @OrderID AND InvoiceNo = @InvoiceNo AND ISNULL(Deleted,0) = 0)
        SET @LineExists = 1;

    /*---- the line and everything hanging off it -------------------------*/
    DECLARE @kill TABLE (OrderID BIGINT PRIMARY KEY);

    INSERT INTO @kill (OrderID)
    SELECT o.OrderID
    FROM   dbo.tblOrder o
    WHERE  o.InvoiceNo = @InvoiceNo
      AND  ISNULL(o.Deleted,0) = 0
      AND  (o.OrderID = @OrderID OR o.ParentOrderID = @OrderID);

    SELECT @Killing = COUNT(*) FROM @kill;

    SELECT @Live = COUNT(*)
    FROM   dbo.tblOrder o
    WHERE  o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted,0) = 0 AND ISNULL(o.LineType,1) = 1;

    /*---- whose password is this? ----------------------------------------
      Same rule and same dynamic lookup as sp_POS_CancelOrderReject: the
      column belongs to head office, so a database without it reports "not
      recognised" instead of stopping this procedure being created.
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

    /*---- refuse ---------------------------------------------------------*/
    IF @Status IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @Status IN (6, 7, 8)
        SET @Err = N'This order is cancelled or refunded.';
    ELSE IF @LineExists = 0
        SET @Err = N'That item is not on this order, or has already been deleted.';
    ELSE IF @Disposition NOT IN (1, 2)
        SET @Err = N'Select Waste or Reuse.';
    ELSE IF @Comments IS NULL
        SET @Err = N'A delete comment is required.';
    ELSE IF @ApprovedByID IS NULL
        SET @Err = N'That password is not recognised.';
    ELSE IF @Live <= 1 AND EXISTS (SELECT 1 FROM @kill k
                                   JOIN dbo.tblOrder o ON o.OrderID = k.OrderID
                                   WHERE ISNULL(o.LineType,1) = 1)
        -- An order with nothing on it is not an order. Emptying it this way
        -- would leave an invoice with a zero total sitting in the day's takings
        -- as though it were live.
        SET @Err = N'This is the last item on the order. Cancel the order instead.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, OrderID = @OrderID,
               ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE o
           SET o.Deleted              = 1
             , o.Waste                = CASE WHEN @Disposition = 1 THEN 1 ELSE 0 END
             , o.DeleteOrderComment   = @Comments
             , o.DeletePasswordUserID = CAST(@ApprovedByID AS NVARCHAR(50))
             , o.DeletedDate          = @Now
        FROM dbo.tblOrder o
        JOIN @kill k ON k.OrderID = o.OrderID;

        /*---- re-total ----------------------------------------------------
          Quantity * Price over what is left, which is how BillAmount was
          built when the order was placed (sp_POS_ProcessOrder). Line-level
          Discount is not subtracted here for the same reason: it was not
          subtracted there either.
        ---------------------------------------------------------------------*/
        SELECT @BillAmount = CAST(ISNULL(SUM(o.Quantity * o.Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder o
        WHERE  o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted,0) = 0;

        -- The invoice discount was worked out against the original bill. It is
        -- left as it stands but capped, because a discount larger than the bill
        -- would make FinalAmount negative.
        IF @Discount > @BillAmount
        BEGIN
            SET @Warning = CONCAT(N'Discount reduced from ', @Discount, N' to ', @BillAmount,
                                  N' - it was larger than what is left on the order.');
            SET @Discount = @BillAmount;
        END

        UPDATE dbo.tblInvoice
           SET BillAmount = @BillAmount
             , Discount   = @Discount
             , ModifiedOn = @Now
             , ModifiedBy = ISNULL(@UserID, @ApprovedByID)
         WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DeleteLine', ISNULL(@UserID, @ApprovedByID),
                ISNULL(@UserName, @ApprovedBy),
                CONCAT(N'OrderID=', @OrderID, N' Rows=', @Killing,
                       N' Disposition=', CASE WHEN @Disposition = 1 THEN N'Waste' ELSE N'Reuse' END,
                       N' ApprovedByUserID=', @ApprovedByID,
                       N' NewBill=', @BillAmount,
                       N' Comments=', @Comments));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, OrderID = @OrderID,
               ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    /*---- has this left the order overpaid? ------------------------------*/
    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p
    WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    IF @Paid > (@BillAmount - @Discount) + @DeliveryCharges + 0.001
        SET @Warning = ISNULL(@Warning + N' ', N'')
                     + CONCAT(N'The order is now overpaid by ',
                              CAST(@Paid - ((@BillAmount - @Discount) + @DeliveryCharges) AS DECIMAL(18,3)),
                              N'. Refund the difference.');

    SELECT   Message        = 'Success'
           , InvoiceNo      = @InvoiceNo
           , OrderID        = @OrderID
           , LinesDeleted   = @Killing
           , BillAmount     = @BillAmount
           , Discount       = @Discount
           , NetPayable     = (@BillAmount - @Discount) + @DeliveryCharges
           , AmountPaid     = @Paid
           , ApprovedBy     = @ApprovedBy
           , Warning        = @Warning
           , ErrorMessage   = CAST(NULL AS NVARCHAR(500));
END
GO

PRINT 'sp_POS_DeleteOrderLine created.';
GO
