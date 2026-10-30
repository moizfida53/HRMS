/**********************************************************************************
  POS_28_TakePayment.sql
  ------------------------------------------------------------------------------
  sp_POS_TakePaymentSplit - settle an order across several payment types in one
  transaction, with change.

  The counter dialog shows every row in tblInvoicePaymentType with an amount box
  against each, so a KD 12 order can be settled as KD 5 KNET + KD 10 cash. That
  is three separate things the database has to get right:

    SPLIT     more than one payment type on one order. Payments are already
              rows in tblInvoicePayment, so this is natural - but they have to
              be written together. Two round trips means an order can end up
              half-settled if the second one fails.

    CHANGE    the boxes hold what was TENDERED, not what is owed. KD 10 cash
              against a KD 7 balance is a KD 7 payment and KD 3 change - not a
              KD 10 payment, which would overstate takings and break the cash-up.

    ORDER     lines are applied in payment-type sequence, and the one that
              crosses the balance is the one that carries the change. Cash last
              in the list is the usual setup and gives the expected result.

  sp_POS_AddPayment (POS_09) stays as it is: it is the single-payment path and
  refuses overpayment outright, which is right when only one amount is offered.

  Run after POS_09_ActionProcs.sql. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  1. The line type
==============================================================================*/
IF TYPE_ID('dbo.TVP_POS_PaymentLine') IS NULL
BEGIN
    CREATE TYPE dbo.TVP_POS_PaymentLine AS TABLE
    (
          PaymentTypeID INT           NOT NULL PRIMARY KEY
        , Amount        DECIMAL(18,3) NOT NULL
    );
    PRINT '1.1  TVP_POS_PaymentLine created';
END
ELSE PRINT '1.1  TVP_POS_PaymentLine already exists';
GO


/*==============================================================================
  2. sp_POS_TakePaymentSplit
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_TakePaymentSplit') IS NOT NULL DROP PROCEDURE dbo.sp_POS_TakePaymentSplit;
GO

CREATE PROCEDURE dbo.sp_POS_TakePaymentSplit
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
            SELECT DISTINCT LegacyColumn FROM dbo.tblInvoicePaymentType WHERE LegacyColumn IS NOT NULL;
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        SELECT 'Invoice', @InvoiceNo, 'Payment', @UserID, @UserName,
               CONCAT(N'Split=', (SELECT COUNT(*) FROM @alloc),
                      N' Tendered=', @Tendered, N' Applied=', (SELECT SUM(Applied) FROM @alloc),
                      N' Change=', @Change, N' PaidNow=', @Paid, N' Total=', @Total);

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

PRINT 'sp_POS_TakePaymentSplit created.';
GO

/*==============================================================================
  Smoke test - KD 12 order, paid with KNET 5 and cash 10.
  Expect: two rows, applied 5 and 7, change 3, status Paid.

  DECLARE @l dbo.TVP_POS_PaymentLine;
  INSERT INTO @l VALUES (2, 5.000), (1, 10.000);
  EXEC dbo.sp_POS_TakePaymentSplit @InvoiceNo = 1001, @Lines = @l,
       @UserID = 1, @UserName = N'Counter';
==============================================================================*/
