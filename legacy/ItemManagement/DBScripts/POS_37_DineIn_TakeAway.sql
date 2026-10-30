/**********************************************************************************
  POS_37_DineIn_TakeAway.sql
  ------------------------------------------------------------------------------
  Take Away tab and the per-item "Take away" mark.

    sp_POS_DineIn_TakeAwayList     Take Away bills + their lines (the Take Away tab)
    sp_POS_DineIn_SetLineTakeAway  mark / unmark one item as Take Away
    sp_POS_DineIn_GetTable         re-created: every line now says IsTakeAway
    sp_POS_DineIn_AddItems         re-created: also works on a Take Away bill
                                   (pass @DineInTableTypeID = -1)

  The Take Away mark is the text 'TAKE AWAY' at the start of the item's Comments,
  which the kitchen ticket already prints. No new column, nothing else changes.

  Run after POS_35 / POS_36. Safe to re-run.
**********************************************************************************/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*---- 3.2 one table: header, bills, lines -------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_GetTable') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_GetTable;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_GetTable
    @TableID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT =
        (SELECT SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL);

    -- 0: the table
    SELECT f.*, AreaName = a.AreaName
    FROM   dbo.fn_POS_DineIn_Tables() f
    LEFT JOIN dbo.tblPOS_TableArea a ON a.TableType = f.TableType
    WHERE  f.TableID = @TableID;

    -- 1: live bills of this seating, oldest first
    SELECT  i.InvoiceNo
          , InvoiceNumShow = CAST(i.InvoiceNumShow AS NVARCHAR(30))
          , i.RunningOrder
          , i.InvoiceDate
          , i.BillAmount
          , Discount    = ISNULL(i.Discount, 0)
          , NetPayable  = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
          , AmountPaid  = ISNULL(pp.Paid, 0)
          , i.OrderStatusID
          , i.PrintCount
    FROM    dbo.tblInvoice i
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
    WHERE   @SessionID IS NOT NULL
      AND   i.TableSessionID = @SessionID
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
    ORDER BY i.InvoiceNo;

    -- 2: lines of those bills
    SELECT  o.InvoiceNo
          , o.OrderID
          , o.ItemID
          , o.ParentOrderID
          , LineType  = ISNULL(o.LineType, 1)
          , ItemName  = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
          , o.Quantity
          , o.Price
          , LineTotal = CAST(o.Quantity * o.Price AS DECIMAL(18,3))
          , o.Comments
          , IsTakeAway = CAST(CASE WHEN LEFT(LTRIM(ISNULL(o.Comments, N'')), 9) = N'TAKE AWAY' THEN 1 ELSE 0 END AS BIT)
          , o.OrderDate
    FROM    dbo.tblOrder o
    JOIN    dbo.tblInvoice i ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE   @SessionID IS NOT NULL
      AND   i.TableSessionID = @SessionID
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
      AND   ISNULL(o.Deleted, 0) = 0
    ORDER BY o.InvoiceNo, o.OrderID;
END
GO

/*---- 3.9 append items to an open bill ----------------------------------------
  Same pricing rule as sp_POS_ProcessOrder: the price comes from tblItems, never
  from the browser. BillAmount is rebuilt from the lines (FinalAmount is the
  computed BillAmount - Discount).
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_AddItems') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_AddItems;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_AddItems
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInAddItems', @UserID, @UserName,
                CONCAT(N'Lines=', @Added, N'; NewBill=', @Bill));

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


/*---- Take Away list: today's bills + any older bill still unpaid -------------
  Result 0: bills (newest first).  Result 1: their lines.  Same column shapes as
  sp_POS_DineIn_GetTable so the page renders both with the same code.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_TakeAwayList') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_TakeAwayList;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_TakeAwayList
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TA INT
          , @Today DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME);

    SELECT TOP 1 @TA = ID FROM dbo.tblInvoiceType_Master
    WHERE  REPLACE(REPLACE(Name, N'-', N''), N' ', N'') IN (N'TakeAway', N'Takeaway') ORDER BY ID;

    SELECT  i.InvoiceNo
          , InvoiceNumShow = CAST(i.InvoiceNumShow AS NVARCHAR(30))
          , i.RunningOrder
          , i.InvoiceDate
          , CustomerName   = NULLIF(LTRIM(RTRIM(CAST(i.CustomerName AS NVARCHAR(200)))), N'')
          , Mobile         = NULLIF(LTRIM(RTRIM(CAST(i.Mobile AS NVARCHAR(30)))), N'')
          , i.BillAmount
          , Discount       = ISNULL(i.Discount, 0)
          , NetPayable     = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
          , AmountPaid     = ISNULL(pp.Paid, 0)
          , i.OrderStatusID
          , i.PrintCount
    INTO    #b
    FROM    dbo.tblInvoice i
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
    WHERE   @TA IS NOT NULL
      AND   i.InvoiceType = @TA
      AND   i.TableSessionID IS NULL
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
      AND   (@BranchID IS NULL OR i.BranchID = @BranchID)
      AND   (   i.InvoiceDate >= @Today
             OR (    i.InvoiceDate >= DATEADD(DAY, -7, @Today)
                 AND (i.FinalAmount + ISNULL(i.DeliveryCharges, 0)) - ISNULL(pp.Paid, 0) > 0.0005));

    SELECT * FROM #b ORDER BY InvoiceNo DESC;

    SELECT  o.InvoiceNo
          , o.OrderID
          , o.ItemID
          , o.ParentOrderID
          , LineType  = ISNULL(o.LineType, 1)
          , ItemName  = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
          , o.Quantity
          , o.Price
          , LineTotal = CAST(o.Quantity * o.Price AS DECIMAL(18,3))
          , o.Comments
          , IsTakeAway = CAST(0 AS BIT)
          , o.OrderDate
    FROM    dbo.tblOrder o
    JOIN    #b b ON b.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE   ISNULL(o.Deleted, 0) = 0
    ORDER BY o.InvoiceNo, o.OrderID;
END
GO

/*---- Mark / unmark one line as Take Away -------------------------------------
  The mark is the text 'TAKE AWAY' at the start of the line's Comments. That is
  what the kitchen ticket (Orders/Print, doc=Kitchen) already prints under the
  item, so the kitchen sees it with no change to the ticket layout, and the
  Order List shows it too. Any comment the cashier typed is kept after it.
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_POS_DineIn_SetLineTakeAway') IS NOT NULL DROP PROCEDURE dbo.sp_POS_DineIn_SetLineTakeAway;
GO
CREATE PROCEDURE dbo.sp_POS_DineIn_SetLineTakeAway
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

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, CASE WHEN @On = 1 THEN 'DineInMarkTakeAway' ELSE 'DineInUnmarkTakeAway' END,
                @UserID, @UserName, CONCAT(N'OrderID=', @OrderID));
    END TRY
    BEGIN CATCH
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE(); RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END
GO

PRINT 'POS_37_DineIn_TakeAway.sql complete.';
