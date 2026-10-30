/**********************************************************************************
  POS_06_GridProcs.sql
  ------------------------------------------------------------------------------
  Data layer for the POS orders grid. Run after POS_05_FixAndSeed.sql.

      sp_POS_GetOrders        server-side paging / sorting / filtering
      sp_POS_GetOrderChanges  delta polling - only what changed since last poll
      sp_POS_GetOrderDetails  the slide-over details panel

  PERFORMANCE NOTES
  -----------------
  * Sorting uses whitelisted dynamic SQL rather than a CASE expression in
    ORDER BY. A CASE-based sort is unsortable by an index, so SQL Server has to
    materialise and sort the whole filtered set on every page. With dynamic SQL
    the covering index IX_tblInvoice_POSGrid satisfies the common sorts
    outright. The whitelist means no user input ever reaches the SQL text.

  * The row count is returned as a windowed COUNT(*) OVER () on the same pass,
    not as a second query over the same predicate. One scan, not two.

  * Payment status is derived from tblInvoicePayment with a correlated
    aggregate rather than a join, so unpaid orders (the majority) cost nothing.

  * Filters are written so that an unsupplied filter is a constant-true test the
    optimiser can discard, instead of the classic
    "col = ISNULL(@p, col)" pattern that defeats index seeks.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  0. Shared integer-list table type

  Needed because sp_POS_GetOrders builds its ORDER BY dynamically. A plain
  DECLARE @t TABLE cannot be passed to sp_executesql - only a declared TABLE
  TYPE can cross that boundary as a READONLY parameter.
==============================================================================*/
IF TYPE_ID('dbo.TVP_POS_IntList') IS NULL
BEGIN
    CREATE TYPE dbo.TVP_POS_IntList AS TABLE (Value INT NOT NULL PRIMARY KEY);
    PRINT 'TVP_POS_IntList created';
END
GO

/*==============================================================================
  1. sp_POS_GetOrders
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetOrders') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrders;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrders
      @BranchIDs      VARCHAR(200)  = NULL   -- CSV, NULL = all
    , @StatusIDs      VARCHAR(200)  = NULL   -- CSV, NULL = all
    , @DateMode       VARCHAR(10)   = 'Today'-- Today | Future | Past | Range | All
    , @FromDate       DATE          = NULL   -- used when @DateMode = 'Range'
    , @ToDate         DATE          = NULL
    , @Search         NVARCHAR(100) = NULL   -- invoice no / tracking / name / mobile
    , @OrderType      INT           = NULL
    , @PaymentTypeID  INT           = NULL
    , @PaymentStatus  VARCHAR(10)   = NULL   -- Paid | Unpaid | Partial
    , @SourceID       INT           = NULL
    , @DriverID       INT           = NULL
    , @MinAmount      DECIMAL(18,3) = NULL
    , @MaxAmount      DECIMAL(18,3) = NULL
    , @IncludeDeleted BIT           = 0
    , @Skip           INT           = 0
    , @Take           INT           = 50
    , @SortCol        VARCHAR(30)   = 'InvoiceDate'
    , @SortDir        VARCHAR(4)    = 'DESC'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Take IS NULL OR @Take <= 0  SET @Take = 50;
    IF @Take > 500                  SET @Take = 500;   -- hard cap: nobody reads 5000 rows
    IF @Skip IS NULL OR @Skip < 0   SET @Skip = 0;

    /*---- whitelist the sort: user input never reaches the SQL text --------*/
    DECLARE @OrderBy NVARCHAR(200) =
        CASE UPPER(@SortCol)
            WHEN 'INVOICENO'    THEN 'i.InvoiceNo'
            WHEN 'INVOICEDATE'  THEN 'i.InvoiceDate'
            WHEN 'RUNNINGORDER' THEN 'i.RunningOrder'
            WHEN 'CUSTOMERNAME' THEN 'i.CustomerName'
            WHEN 'MOBILE'       THEN 'i.MobileText'
            WHEN 'BILLAMOUNT'   THEN 'i.BillAmount'
            WHEN 'NETPAYABLE'   THEN '(i.FinalAmount + ISNULL(i.DeliveryCharges,0))'
            WHEN 'ORDERSTATUS'  THEN 'i.OrderStatusID'
            WHEN 'BRANCH'       THEN 'i.BranchID'
            WHEN 'TRACKINGCODE' THEN 'i.TrackingCode'
            WHEN 'PROMISEDTIME' THEN 'i.PromisedTime'
            ELSE 'i.InvoiceDate'
        END
      + CASE WHEN UPPER(ISNULL(@SortDir,'DESC')) = 'ASC' THEN ' ASC' ELSE ' DESC' END
      + ', i.InvoiceNo DESC';   -- tie-break keeps paging stable

    /*---- date window ------------------------------------------------------*/
    DECLARE @dFrom DATETIME, @dTo DATETIME, @Today DATE = CAST(GETDATE() AS DATE);

    IF    @DateMode = 'Today'  BEGIN SET @dFrom = @Today;                    SET @dTo = DATEADD(DAY,1,@Today); END
    ELSE IF @DateMode = 'Future' BEGIN SET @dFrom = DATEADD(DAY,1,@Today);   SET @dTo = NULL; END
    ELSE IF @DateMode = 'Past'   BEGIN SET @dFrom = NULL;                    SET @dTo = @Today; END
    ELSE IF @DateMode = 'Range'  BEGIN SET @dFrom = @FromDate;               SET @dTo = DATEADD(DAY,1,@ToDate); END
    -- 'All' leaves both NULL

    /*---- CSV filters into table-typed variables so the plan can seek ------*/
    DECLARE @Branches dbo.TVP_POS_IntList;
    DECLARE @Statuses dbo.TVP_POS_IntList;

    IF NULLIF(LTRIM(RTRIM(@BranchIDs)),'') IS NOT NULL
        INSERT INTO @Branches (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIDs, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL;

    IF NULLIF(LTRIM(RTRIM(@StatusIDs)),'') IS NOT NULL
        INSERT INTO @Statuses (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@StatusIDs, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END;
    DECLARE @AnyStatus BIT = CASE WHEN EXISTS (SELECT 1 FROM @Statuses) THEN 0 ELSE 1 END;

    -- Numeric search terms can hit the indexed keys directly
    DECLARE @SearchNum BIGINT = TRY_CAST(REPLACE(REPLACE(ISNULL(@Search,''),'+',''),' ','') AS BIGINT);
    DECLARE @SearchLike NVARCHAR(102) = CASE WHEN NULLIF(@Search,'') IS NULL THEN NULL ELSE '%' + @Search + '%' END;

    DECLARE @sql NVARCHAR(MAX) = N'
    SELECT
          TotalRows       = COUNT(*) OVER ()
        , i.InvoiceNo
        , i.TrackingCode
        , i.RunningOrder
        , i.InvoiceDate
        , i.PromisedTime
        , AgeMinutes      = DATEDIFF(MINUTE, i.InvoiceDate, GETDATE())
        , IsLate          = CASE WHEN i.PromisedTime IS NOT NULL
                                  AND GETDATE() > i.PromisedTime
                                  AND ISNULL(st.IsTerminal,0) = 0 THEN 1 ELSE 0 END
        , i.CustomerName
        , Mobile          = i.MobileText
        , i.CustomerId
        , i.BranchID
        , BranchName      = b.branchName
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN ''Pickup'' WHEN 2 THEN ''Delivery'' WHEN 3 THEN ''Dine In'' ELSE ''Other'' END
        , i.OrderStatusID
        , OrderStatusName = st.OrderStatusName
        , StatusColor     = st.ColorHex
        , IsTerminal      = ISNULL(st.IsTerminal,0)
        , i.BillAmount
        , i.Discount
        , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
        , i.FinalAmount
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PaymentType
        , PaymentTypeName = pt.PaymentTypeName
        , IsCOD           = ISNULL(pt.IsCOD,0)
        , AmountPaid      = ISNULL(pay.Paid, 0)
        , PaymentStatus   = CASE WHEN ISNULL(pay.Paid,0) <= 0 THEN ''Unpaid''
                                 WHEN ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0) THEN ''Paid''
                                 ELSE ''Partial'' END
        , i.SourceID
        , i.Driver
        , i.DriverName
        , AreaName        = ar.AreaName
        , i.PrintCount
        , i.Deleted
        , ItemCount       = ISNULL(li.Cnt, 0)
    FROM        dbo.tblInvoice i
    LEFT JOIN   dbo.tblOrderStatus        st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN   dbo.tblbranch             b  ON b.id             = i.BranchID
    LEFT JOIN   dbo.tblInvoicePaymentType pt ON pt.ID            = i.PaymentType
    LEFT JOIN   dbo.tblCustomerAddress    ca ON ca.AddressID     = i.AddressID
    LEFT JOIN   dbo.tblArea               ar ON ar.AreaID        = ca.AreaID
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0) pay
    OUTER APPLY (SELECT Cnt = COUNT(*)
                 FROM   dbo.tblOrder o
                 WHERE  o.InvoiceNo = i.InvoiceNo AND ISNULL(o.Deleted,0) = 0 AND o.LineType = 1) li
    WHERE  (@IncludeDeleted = 1 OR ISNULL(i.Deleted,0) = 0)
      AND  (@AnyBranch = 1 OR i.BranchID IN (SELECT Value FROM @Branches))
      AND  (@AnyStatus = 1 OR i.OrderStatusID IN (SELECT Value FROM @Statuses))
      AND  (@dFrom IS NULL OR i.InvoiceDate >= @dFrom)
      AND  (@dTo   IS NULL OR i.InvoiceDate <  @dTo)
      AND  (@OrderType     IS NULL OR i.OrderType   = @OrderType)
      AND  (@PaymentTypeID IS NULL OR i.PaymentType = @PaymentTypeID)
      AND  (@SourceID      IS NULL OR i.SourceID    = @SourceID)
      AND  (@DriverID      IS NULL OR i.Driver      = @DriverID)
      AND  (@MinAmount     IS NULL OR i.FinalAmount + ISNULL(i.DeliveryCharges,0) >= @MinAmount)
      AND  (@MaxAmount     IS NULL OR i.FinalAmount + ISNULL(i.DeliveryCharges,0) <= @MaxAmount)
      AND  (@SearchLike IS NULL
            OR i.TrackingCode  LIKE @SearchLike
            OR i.CustomerName  LIKE @SearchLike
            OR i.MobileText    LIKE @SearchLike
            OR (@SearchNum IS NOT NULL AND (i.InvoiceNo = @SearchNum OR i.Mobile = @SearchNum OR i.RunningOrder = @SearchNum)))
      AND  (@PaymentStatus IS NULL
            OR (@PaymentStatus = ''Unpaid''  AND ISNULL(pay.Paid,0) <= 0)
            OR (@PaymentStatus = ''Paid''    AND ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0))
            OR (@PaymentStatus = ''Partial'' AND ISNULL(pay.Paid,0) > 0
                                            AND ISNULL(pay.Paid,0) + 0.001 < i.FinalAmount + ISNULL(i.DeliveryCharges,0)))
    ORDER BY ' + @OrderBy + N'
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY
    OPTION (RECOMPILE);';   -- filters vary wildly between users; a cached plan
                            -- for "today, one branch" is wrong for "all, 90 days"

    EXEC sp_executesql @sql,
        N'@IncludeDeleted BIT, @AnyBranch BIT, @AnyStatus BIT, @dFrom DATETIME, @dTo DATETIME,
          @OrderType INT, @PaymentTypeID INT, @SourceID INT, @DriverID INT,
          @MinAmount DECIMAL(18,3), @MaxAmount DECIMAL(18,3),
          @SearchLike NVARCHAR(102), @SearchNum BIGINT, @PaymentStatus VARCHAR(10),
          @Skip INT, @Take INT,
          @Branches AS dbo.TVP_POS_IntList READONLY, @Statuses AS dbo.TVP_POS_IntList READONLY',
        @IncludeDeleted, @AnyBranch, @AnyStatus, @dFrom, @dTo,
        @OrderType, @PaymentTypeID, @SourceID, @DriverID,
        @MinAmount, @MaxAmount, @SearchLike, @SearchNum, @PaymentStatus,
        @Skip, @Take, @Branches, @Statuses;
END
GO


/*==============================================================================
  2. sp_POS_GetOrderChanges  - delta polling

  The grid polls this every few seconds with the highest RowVer it has seen.
  Only genuinely changed rows come back, so a busy branch costs a few rows per
  poll instead of a full page re-fetch.

  MIN_ACTIVE_ROWVERSION() is the upper bound rather than @@DBTS: a transaction
  that has stamped a row but not yet committed would otherwise be skipped and
  never seen again.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetOrderChanges') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrderChanges;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrderChanges
      @SinceRowVer BINARY(8)   = NULL
    , @BranchIDs   VARCHAR(200) = NULL
    , @MaxRows     INT          = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Upper BINARY(8) = MIN_ACTIVE_ROWVERSION();

    IF @SinceRowVer IS NULL
    BEGIN
        -- First poll: hand back the watermark only, no rows.
        SELECT CurrentRowVer = @Upper;
        SELECT TOP 0 InvoiceNo = CAST(NULL AS BIGINT);
        RETURN;
    END

    DECLARE @Branches TABLE (BranchID INT PRIMARY KEY);
    IF NULLIF(LTRIM(RTRIM(@BranchIDs)),'') IS NOT NULL
        INSERT INTO @Branches SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIDs, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END;

    SELECT CurrentRowVer = @Upper;

    SELECT TOP (@MaxRows)
          i.InvoiceNo
        , i.RowVer
        , i.TrackingCode
        , i.RunningOrder
        , i.OrderStatusID
        , OrderStatusName = st.OrderStatusName
        , StatusColor     = st.ColorHex
        , i.CustomerName
        , Mobile          = i.MobileText
        , i.BranchID
        , i.OrderType
        , i.BillAmount
        , i.FinalAmount
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PrintCount
        , i.Deleted
        , i.InvoiceDate
        , IsNewOrder      = CASE WHEN i.InvoiceDate > DATEADD(MINUTE,-2,GETDATE()) THEN 1 ELSE 0 END
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblOrderStatus st ON st.OrderStatusID = i.OrderStatusID
    WHERE     i.RowVer > @SinceRowVer
      AND     i.RowVer < @Upper
      AND     (@AnyBranch = 1 OR i.BranchID IN (SELECT BranchID FROM @Branches))
    ORDER BY  i.RowVer;
END
GO


/*==============================================================================
  3. sp_POS_GetOrderDetails - one round trip for the whole slide-over panel
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetOrderDetails') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrderDetails;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrderDetails
      @InvoiceNo BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- 0: header
    SELECT
          i.InvoiceNo, i.TrackingCode, i.RunningOrder, i.InvoiceDate, i.PromisedTime
        , i.DeliveryDate, i.CustomerName, Mobile = i.MobileText, i.CustomerId
        , i.BranchID, BranchName = b.branchName, i.BrandID
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN 'Pickup' WHEN 2 THEN 'Delivery' WHEN 3 THEN 'Dine In' ELSE 'Other' END
        , i.OrderStatusID, OrderStatusName = st.OrderStatusName, StatusColor = st.ColorHex
        , i.BillAmount, i.Discount, i.DiscountCode
        , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
        , i.FinalAmount
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PaymentType, PaymentTypeName = pt.PaymentTypeName, IsCOD = ISNULL(pt.IsCOD,0)
        , AmountPaid      = ISNULL((SELECT SUM(CASE WHEN p.IsRefund=1 THEN -p.Amount ELSE p.Amount END)
                                    FROM dbo.tblInvoicePayment p
                                    WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0)=0), 0)
        , i.Comments, i.Complaints
        , i.CancelReasonID, i.CancelComments, i.CancelDisposition
        , i.Driver, i.DriverName, i.DriverAssignDate
        , i.PrintCount, i.LastPrintedOn, i.SourceID, i.Deleted
        , AddressID = ca.AddressID, ca.Block, ca.Street, ca.Lane, ca.Building
        , ca.Floor, ca.Flat, ca.HouseNo, ca.PACI, ca.AddressRemark, ca.Lat, ca.Lng
        , AreaID = ca.AreaID, AreaName = ar.AreaName, AreaNameAra = ar.AreaNameAra
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblOrderStatus        st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN dbo.tblbranch             b  ON b.id             = i.BranchID
    LEFT JOIN dbo.tblInvoicePaymentType pt ON pt.ID            = i.PaymentType
    LEFT JOIN dbo.tblCustomerAddress    ca ON ca.AddressID     = i.AddressID
    LEFT JOIN dbo.tblArea               ar ON ar.AreaID        = ca.AreaID
    WHERE     i.InvoiceNo = @InvoiceNo;

    -- 1: lines (ItemNameSnapshot is the name as sold, so reprints never drift)
    SELECT
          o.OrderID, o.ItemID, o.LineType, o.ParentOrderID, o.CartItemUniqID
        , ItemName    = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
        , ItemNameAra = it.ITEM_NAME_ARABIC
        , o.Quantity, o.Price, o.TotalAmount, o.Discount
        , o.Comments, o.Extra, o.Prepared, o.Delivered, o.Deleted, o.Waste
    FROM      dbo.tblOrder o
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE     o.InvoiceNo = @InvoiceNo
    ORDER BY  o.OrderID;

    -- 2: status timeline
    SELECT    h.HistoryID, h.FromStatusID, h.ToStatusID
            , FromStatusName = sf.OrderStatusName
            , ToStatusName   = stt.OrderStatusName
            , StatusColor    = stt.ColorHex
            , h.ChangedBy, h.ChangedByName, h.ChangedOn, h.Comments, h.DriverID
    FROM      dbo.tblPOS_OrderStatusHistory h
    LEFT JOIN dbo.tblOrderStatus sf  ON sf.OrderStatusID  = h.FromStatusID
    LEFT JOIN dbo.tblOrderStatus stt ON stt.OrderStatusID = h.ToStatusID
    WHERE     h.InvoiceNo = @InvoiceNo
    ORDER BY  h.HistoryID;

    -- 3: payments
    SELECT    p.id AS PaymentID, p.PaymentTypeID, p.PaymentType, p.Amount
            , p.AmountTendered, p.ChangeGiven, p.ReferenceNo, p.IsRefund
            , p.ReceivedBy, p.ReceivedOn, p.Comments
    FROM      dbo.tblInvoicePayment p
    WHERE     p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0
    ORDER BY  p.id;

    -- 4: transfers
    SELECT    t.TransferID, t.FromBranchID, FromBranch = bf.branchName
            , t.ToBranchID, ToBranch = bt.branchName
            , t.Reason, t.TransferredBy, t.TransferredOn
    FROM      dbo.tblPOS_OrderTransfer t
    LEFT JOIN dbo.tblbranch bf ON bf.id = t.FromBranchID
    LEFT JOIN dbo.tblbranch bt ON bt.id = t.ToBranchID
    WHERE     t.InvoiceNo = @InvoiceNo
    ORDER BY  t.TransferID;

    -- 5: allowed next statuses, so the UI never offers an invalid move
    SELECT    tr.ToStatusID, s.OrderStatusName, s.ColorHex, tr.RequiresRole
    FROM      dbo.tblPOS_OrderStatusTransition tr
    JOIN      dbo.tblOrderStatus s ON s.OrderStatusID = tr.ToStatusID
    JOIN      dbo.tblInvoice     i ON i.InvoiceNo     = @InvoiceNo
    WHERE     tr.FromStatusID = i.OrderStatusID
      AND     ((i.OrderType = 1 AND s.AppliesToPickup = 1) OR (i.OrderType <> 1 AND s.AppliesToDelivery = 1))
    ORDER BY  s.SortOrder;
END
GO

PRINT 'sp_POS_GetOrders / sp_POS_GetOrderChanges / sp_POS_GetOrderDetails created.';
GO

/**********************************************************************************
  SMOKE TEST
**********************************************************************************/
/*
EXEC dbo.sp_POS_GetOrders @DateMode='All', @Take=50;
EXEC dbo.sp_POS_GetOrders @DateMode='Today', @BranchIDs='1', @StatusIDs='1,2,3', @SortCol='InvoiceDate', @SortDir='DESC';
EXEC dbo.sp_POS_GetOrders @DateMode='All', @Search='96560770626';
EXEC dbo.sp_POS_GetOrderChanges @SinceRowVer = NULL;
EXEC dbo.sp_POS_GetOrderDetails @InvoiceNo = 1;

-- Confirm the covering index is actually being used (look for an Index Seek
-- on IX_tblInvoice_POSGrid, not a Clustered Index Scan):
SET STATISTICS IO ON;
EXEC dbo.sp_POS_GetOrders @DateMode='Today', @BranchIDs='1';
SET STATISTICS IO OFF;
*/
