/**********************************************************************************
  POS_38_DineIn_SplitFlag.sql
  ------------------------------------------------------------------------------
  Split bill, the new way.

  The cashier selects item rows on a table's bill and presses Split bill. The
  selected items go onto a NEW bill and that new bill is paid on the spot.

  What happens to the items on the original bill
  ----------------------------------------------
  They are not moved and not deleted. Each original line is kept for the audit
  trail and FLAGGED:   Deleted = 1,  IsSplit = 1,  SplitToInvoiceNo = <new bill>.
  A fresh copy of the line (with its extras) goes on the new bill.

    * Sales, item counts, stock, the Order Details view and the printed bill all
      skip Deleted = 1 lines, so a split item is counted ONCE (on the new bill)
      and never twice.
    * IsSplit = 1 tells the "deleted items" figures to ignore these lines, so a
      split item is not reported as deleted or wasted either: it only moved.

  Part 3 below patches the two dashboard procedures that count deleted lines
  (sp_DashbordSalesData: the reuse count, sp_Dashbord_DeletedItems: the drill-
  down) so they ignore IsSplit lines. It edits the procedures in place and is
  safe to re-run.

  If another report of yours lists tblOrder lines WHERE Deleted = 1, add
        AND ISNULL(o.IsSplit, 0) = 0
  to it.

  Run after POS_35 / POS_36 / POS_37. Safe to re-run.
**********************************************************************************/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  PART 1 - the flag columns on tblOrder
==============================================================================*/
IF COL_LENGTH('dbo.tblOrder', 'IsSplit') IS NULL
BEGIN
    ALTER TABLE dbo.tblOrder ADD IsSplit BIT NOT NULL CONSTRAINT DF_tblOrder_IsSplit DEFAULT (0);
    PRINT '1.1  tblOrder.IsSplit added';
END
GO
IF COL_LENGTH('dbo.tblOrder', 'SplitToInvoiceNo') IS NULL
BEGIN
    ALTER TABLE dbo.tblOrder ADD SplitToInvoiceNo BIGINT NULL;
    PRINT '1.2  tblOrder.SplitToInvoiceNo added';
END
GO
IF COL_LENGTH('dbo.tblOrder', 'SplitFromOrderID') IS NULL
BEGIN
    ALTER TABLE dbo.tblOrder ADD SplitFromOrderID BIGINT NULL;
    PRINT '1.3  tblOrder.SplitFromOrderID added';
END
GO

/*==============================================================================
  PART 2 - sp_POS_DineIn_SplitInvoice (replaces the POS_35 version)
  @Lines carries the chosen item rows (OrderID); a row always moves whole, the
  Quantity column is not used. The extras of a chosen item travel with it.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_DineIn_SplitInvoice') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_SplitInvoice;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_SplitInvoice
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInSplit', @UserID, @UserName,
                CONCAT(N'NewInvoice=', @NewNo, N'; OldBill=', @BillOld, N'; NewBill=', @BillNew));

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

/*==============================================================================
  PART 3 - "deleted" figures must ignore split lines
  The two procedures are read back from the database, the condition is added,
  and they are re-created in place. Nothing happens if a procedure is missing or
  already patched.
==============================================================================*/
DECLARE @procs TABLE (Nm SYSNAME);
INSERT INTO @procs VALUES (N'sp_DashbordSalesData'), (N'sp_Dashbord_DeletedItems');

DECLARE @nm SYSNAME, @def NVARCHAR(MAX), @pos INT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Nm FROM @procs;
OPEN c; FETCH NEXT FROM c INTO @nm;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @nm));

    IF @def IS NULL
        PRINT CONCAT(N'3.  ', @nm, N' not found - skipped');
    ELSE IF @def LIKE N'%IsSplit%'
        PRINT CONCAT(N'3.  ', @nm, N' already ignores split lines');
    ELSE
    BEGIN
        SET @def = REPLACE(@def, N'ISNULL(o.Deleted, 0) = 1', N'ISNULL(o.Deleted, 0) = 1 AND ISNULL(o.IsSplit, 0) = 0');
        IF @def NOT LIKE N'%IsSplit%'
            PRINT CONCAT(N'3.  ', @nm, N': the expected condition was not found - add AND ISNULL(o.IsSplit,0)=0 to its Deleted = 1 filter by hand');
        ELSE
        BEGIN
            SET @pos = CHARINDEX(N'CREATE', @def);
            SET @def = STUFF(@def, @pos, 6, N'ALTER');
            EXEC sys.sp_executesql @def;
            PRINT CONCAT(N'3.  ', @nm, N' patched');
        END
    END

    FETCH NEXT FROM c INTO @nm;
END
CLOSE c; DEALLOCATE c;
GO

PRINT 'POS_38_DineIn_SplitFlag.sql complete.';
