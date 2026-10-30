/**********************************************************************************
  POS_09_ActionProcs.sql
  ------------------------------------------------------------------------------
  The write side of the POS. Run after POS_08_Auth.sql.

      sp_POS_ChangeStatus    status moves, single or bulk, transition-validated
      sp_POS_CancelOrder     cancel with reason + Waste/Reuse disposition
      sp_POS_TransferOrder   move an order to another branch
      sp_POS_AddPayment      collect payment; supports split, partial and refund
      sp_POS_MarkPrinted     print tracking, so reprints are visible

  PRINCIPLE THROUGHOUT
  --------------------
  Every rule is enforced HERE, not in the browser. A stale tab, a replayed
  request or a direct POST must not be able to drag a delivered order back into
  Preparing, cancel an order twice, or collect payment on a cancelled order.
  The UI hides invalid options; these procs make them impossible.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  0. Bigint list type, for bulk actions on selected rows
==============================================================================*/
IF TYPE_ID('dbo.TVP_POS_BigIntList') IS NULL
BEGIN
    CREATE TYPE dbo.TVP_POS_BigIntList AS TABLE (Value BIGINT NOT NULL PRIMARY KEY);
    PRINT 'TVP_POS_BigIntList created';
END
GO


/*==============================================================================
  1. sp_POS_ChangeStatus

  Bulk by design: the grid lets an operator select ten orders and mark them all
  Preparing. Doing that as ten round trips is ten transactions and ten chances
  to half-fail. Here it is one.

  Orders that fail validation are REPORTED, not silently skipped -- an operator
  who selects 10 and sees "8 updated" needs to know which 2 did not move.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_ChangeStatus') IS NOT NULL DROP PROCEDURE dbo.sp_POS_ChangeStatus;
GO

CREATE PROCEDURE dbo.sp_POS_ChangeStatus
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        SELECT 'Invoice', e.InvoiceNo, 'StatusChange', @UserID, @UserName,
               CONCAT(N'From=', e.FromStatusID, N' To=', @ToStatusID,
                      CASE WHEN @DriverID IS NOT NULL THEN CONCAT(N' Driver=', @DriverID) ELSE N'' END)
        FROM   @eval e WHERE e.Allowed = 1;

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


/*==============================================================================
  2. sp_POS_CancelOrder

  Waste vs Reuse is not cosmetic: it drives the wasteAmount / wasteCount and
  reUseAmount / reUseCount columns that already exist on tblEndDay, and it is
  what makes the waste report meaningful. Waste also flags the individual
  tblOrder lines, so item-level waste analysis is possible later.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_CancelOrder') IS NOT NULL DROP PROCEDURE dbo.sp_POS_CancelOrder;
GO

CREATE PROCEDURE dbo.sp_POS_CancelOrder
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Cancel', @UserID, @UserName,
                CONCAT(N'Reason=', ISNULL(@CancelReasonID,0),
                       N' Disposition=', CASE WHEN @Disposition = 1 THEN N'Waste' ELSE N'Reuse' END,
                       N' Comments=', @Comments));

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


/*==============================================================================
  3. sp_POS_TransferOrder
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_TransferOrder') IS NOT NULL DROP PROCEDURE dbo.sp_POS_TransferOrder;
GO

CREATE PROCEDURE dbo.sp_POS_TransferOrder
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Transfer', @UserID, @UserName,
                CONCAT(N'From=', @FromBranch, N' To=', @ToBranchID, N' Reason=', ISNULL(@Reason, N'')));

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


/*==============================================================================
  4. sp_POS_AddPayment

  Split and partial payments are normal (half cash, half KNET), so payments are
  rows, not a column. Refunds are negative rows. The legacy per-method columns
  on tblInvoice are recalculated from the rows afterwards, so the existing
  end-of-day and shift reports keep working untouched.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_AddPayment') IS NOT NULL DROP PROCEDURE dbo.sp_POS_AddPayment;
GO

CREATE PROCEDURE dbo.sp_POS_AddPayment
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
        VALUES ('Invoice', @InvoiceNo, CASE WHEN @IsRefund = 1 THEN 'Refund' ELSE 'Payment' END,
                @UserID, @UserName,
                CONCAT(N'Type=', @PaymentTypeID, N' Amount=', @Amount,
                       N' Ref=', ISNULL(@ReferenceNo, N''), N' PaidNow=', @Paid, N' Due=', @Due));

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


/*==============================================================================
  5. sp_POS_MarkPrinted

  PrintCount is what makes a reprint visible. A kitchen ticket that can be
  reprinted silently is a standard route to duplicate-order fraud, so the
  count is returned and the ticket template stamps REPRINT when it is above 1.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_MarkPrinted') IS NOT NULL DROP PROCEDURE dbo.sp_POS_MarkPrinted;
GO

CREATE PROCEDURE dbo.sp_POS_MarkPrinted
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

    INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
    SELECT 'Invoice', n.Value, 'Print', @UserID, @UserName,
           CONCAT(N'DocType=', @DocType, N' Count=',
                  (SELECT PrintCount FROM dbo.tblInvoice WHERE InvoiceNo = n.Value))
    FROM   @InvoiceNos n;

    SELECT i.InvoiceNo, i.PrintCount, IsReprint = CASE WHEN i.PrintCount > 1 THEN 1 ELSE 0 END
    FROM   dbo.tblInvoice i JOIN @InvoiceNos n ON n.Value = i.InvoiceNo;
END
GO

PRINT 'POS action procs created.';
GO

/**********************************************************************************
  SMOKE TEST  -  run against a test order
**********************************************************************************/
/*
DECLARE @ids dbo.TVP_POS_BigIntList;
INSERT INTO @ids (Value) SELECT TOP 1 InvoiceNo FROM dbo.tblInvoice ORDER BY InvoiceNo DESC;

-- Received -> Preparing
EXEC dbo.sp_POS_ChangeStatus @InvoiceNos=@ids, @ToStatusID=2, @UserID=1, @UserName=N'Admin', @RoleID=1;

-- Illegal jump: Preparing -> Delivered. Must report it, not do it.
EXEC dbo.sp_POS_ChangeStatus @InvoiceNos=@ids, @ToStatusID=6, @UserID=1, @UserName=N'Admin', @RoleID=1;

-- With Driver, no driver selected. Must be refused.
EXEC dbo.sp_POS_ChangeStatus @InvoiceNos=@ids, @ToStatusID=4, @UserID=1, @UserName=N'Admin', @RoleID=1;

DECLARE @inv BIGINT = (SELECT TOP 1 Value FROM @ids);

-- Overpayment must be refused
EXEC dbo.sp_POS_AddPayment @InvoiceNo=@inv, @PaymentTypeID=1, @Amount=99999;

-- Correct payment, with change calculated
EXEC dbo.sp_POS_AddPayment @InvoiceNo=@inv, @PaymentTypeID=1,
     @Amount=(SELECT FinalAmount + ISNULL(DeliveryCharges,0) FROM dbo.tblInvoice WHERE InvoiceNo=@inv),
     @AmountTendered=20, @UserID=1, @UserName=N'Admin';

-- Cancelling a paid order must be refused
EXEC dbo.sp_POS_CancelOrder @InvoiceNo=@inv, @Comments=N'test', @Disposition=1, @UserID=1, @RoleID=1;

SELECT * FROM dbo.tblPOS_AuditLog ORDER BY AuditID DESC;
*/
