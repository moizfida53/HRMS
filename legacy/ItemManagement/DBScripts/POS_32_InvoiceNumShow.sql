/**********************************************************************************
  POS_32_InvoiceNumShow.sql
  ------------------------------------------------------------------------------
  tblInvoice.InvoiceNumShow - the number printed on the customer's invoice.

      InvoiceNumShow = yyyy + MM + dd + InvoiceNo          e.g. 202608141042

  InvoiceNo stays exactly what it is: the primary key, the value every join,
  every URL and every POST uses. InvoiceNumShow is for DISPLAY only. Nothing in
  the application should look an order up by it.

  WHY IT IS A COMPUTED COLUMN

  You added it as an ordinary column. That works right up until the first row is
  written without it, or written with yesterday's date - and from then on the
  invoice on the customer's table disagrees with the invoice in the system,
  which is the one kind of bug nobody can argue their way out of at a counter.

  A PERSISTED computed column removes the question. It is stored like a normal
  column, so it reads fast and can be indexed, but SQL Server derives it from
  InvoiceDate and InvoiceNo on every insert. There is no code path that can
  forget to set it, no backfill to run, and no second copy of the formula in C#
  or JavaScript to drift out of step.

  SECTION 1 prints what you currently have.
  SECTION 2 converts the column.
  SECTION 3 re-emits the two procedures that feed the POS screens with the
            column added. Their bodies are otherwise unchanged from POS_24 and
            POS_14 - one extra column in each SELECT, nothing else.
  SECTION 4 adds sp_POS_GetInvoiceNumShow for the checkout confirmation.

  Run after POS_24_GridSortFix.sql and POS_14_DetailLines.sql. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 1 - what is there now
==============================================================================*/
PRINT '===== SECTION 1 : InvoiceNumShow as it stands =====';

IF COL_LENGTH('dbo.tblInvoice', 'InvoiceNumShow') IS NULL
    PRINT '  column does not exist yet - section 2 creates it';
ELSE IF EXISTS (SELECT 1 FROM sys.computed_columns
                WHERE object_id = OBJECT_ID('dbo.tblInvoice') AND name = 'InvoiceNumShow')
    PRINT '  already a computed column - section 2 leaves it alone';
ELSE
    PRINT '  present as a STORED column - section 2 converts it';

SELECT   ColumnName  = c.name
       , DataType    = TYPE_NAME(c.user_type_id)
       , IsComputed  = c.is_computed
       , Definition  = cc.definition
       , IsPersisted = cc.is_persisted
FROM     sys.columns c
LEFT JOIN sys.computed_columns cc
       ON cc.object_id = c.object_id AND cc.column_id = c.column_id
WHERE    c.object_id = OBJECT_ID('dbo.tblInvoice') AND c.name = 'InvoiceNumShow';
GO


/*==============================================================================
  SECTION 2 - make it computed and persisted

  CONVERT(CHAR(8), InvoiceDate, 112) is style 112, ISO yyyymmdd. Deliberately
  not FORMAT(): style 112 is culture-independent, so the number cannot change
  shape because the server language did, and it is roughly an order of
  magnitude cheaper - this is evaluated per row.

  The existing column is dropped and re-added. There is no ALTER that turns a
  stored column into a computed one, and every value is reproducible from data
  already in the row, so nothing is lost.
==============================================================================*/
IF NOT EXISTS (SELECT 1 FROM sys.computed_columns
               WHERE object_id = OBJECT_ID('dbo.tblInvoice') AND name = 'InvoiceNumShow')
BEGIN
    -- Anything built on the old column comes off first, or the drop fails with
    -- a dependency error that says nothing useful.
    DECLARE @drop NVARCHAR(MAX) = N'';

    SELECT @drop = @drop + N'ALTER TABLE dbo.tblInvoice DROP CONSTRAINT ' + QUOTENAME(dc.name) + N';' + CHAR(10)
    FROM   sys.default_constraints dc
    JOIN   sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
    WHERE  dc.parent_object_id = OBJECT_ID('dbo.tblInvoice') AND c.name = 'InvoiceNumShow';

    SELECT @drop = @drop + N'DROP INDEX ' + QUOTENAME(i.name) + N' ON dbo.tblInvoice;' + CHAR(10)
    FROM   sys.indexes i
    JOIN   sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN   sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE  i.object_id = OBJECT_ID('dbo.tblInvoice') AND c.name = 'InvoiceNumShow' AND i.is_primary_key = 0;

    IF LEN(@drop) > 0 EXEC sp_executesql @drop;

    IF COL_LENGTH('dbo.tblInvoice', 'InvoiceNumShow') IS NOT NULL
    BEGIN
        ALTER TABLE dbo.tblInvoice DROP COLUMN InvoiceNumShow;
        PRINT '2.1  stored column dropped';
    END

    ALTER TABLE dbo.tblInvoice
        ADD InvoiceNumShow AS (CONVERT(CHAR(8), InvoiceDate, 112)
                             + CAST(InvoiceNo AS VARCHAR(20))) PERSISTED;

    PRINT '2.2  InvoiceNumShow added as a PERSISTED computed column';
END
ELSE PRINT '2.1  InvoiceNumShow is already computed - nothing to do';
GO

-- Searching by the printed number is the obvious next request, and without an
-- index it scans the whole invoice table every time someone types one in.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tblInvoice_InvoiceNumShow')
    CREATE NONCLUSTERED INDEX IX_tblInvoice_InvoiceNumShow
        ON dbo.tblInvoice (InvoiceNumShow) INCLUDE (InvoiceNo, InvoiceDate);
GO

SELECT TOP (5) InvoiceNo, InvoiceDate, InvoiceNumShow
FROM   dbo.tblInvoice ORDER BY InvoiceNo DESC;
GO


/*==============================================================================
  SECTION 3 - the two procedures that feed the POS screens
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetOrders') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrders;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrders
      @BrandIDs       VARCHAR(200)  = NULL   -- CSV, NULL = all
    , @BranchIDs      VARCHAR(200)  = NULL
    , @InvoiceTypeIDs VARCHAR(200)  = NULL
    , @StatusIDs      VARCHAR(200)  = NULL
    , @DateMode       VARCHAR(10)   = 'Today'
    , @FromDate       DATE          = NULL
    , @ToDate         DATE          = NULL
    , @Search         NVARCHAR(100) = NULL
    , @OrderType      INT           = NULL
    , @PaymentTypeID  INT           = NULL
    , @PaymentStatus  VARCHAR(10)   = NULL
    , @SourceID       INT           = NULL
    , @DriverID       INT           = NULL
    , @MinAmount      DECIMAL(18,3) = NULL
    , @MaxAmount      DECIMAL(18,3) = NULL
    , @IncludeDeleted BIT           = 0
    , @ScheduledOnly  BIT           = 0    -- 1 = only orders whose DeliveryDate is a later calendar day than InvoiceDate
    , @Skip           INT           = 0
    , @Take           INT           = 50
    , @SortCol        VARCHAR(30)   = 'InvoiceDate'
    , @SortDir        VARCHAR(4)    = 'DESC'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Take IS NULL OR @Take <= 0 SET @Take = 50;
    IF @Take > 500                 SET @Take = 500;
    IF @Skip IS NULL OR @Skip < 0  SET @Skip = 0;

    /* Whitelisted sort - user input never reaches the SQL text.

       The grid sends the DataTables column key, which is the alias in the
       SELECT below (InvoiceTypeName, OrderStatusName), not the underlying
       column. Both spellings are accepted so a column header sorts by what it
       displays instead of silently falling back to the invoice date. */
    DECLARE @SortExpr NVARCHAR(200) =
        CASE UPPER(@SortCol)
            WHEN 'INVOICENO'       THEN 'i.InvoiceNo'
            WHEN 'TRACKINGCODE'    THEN 'i.TrackingCode'
            WHEN 'INVOICETYPE'     THEN 'it.Name'
            WHEN 'INVOICETYPENAME' THEN 'it.Name'
            WHEN 'CUSTOMERNAME'    THEN 'i.CustomerName'
            WHEN 'MOBILE'          THEN 'i.MobileText'
            WHEN 'AREANAME'        THEN 'ar.AreaName'
            WHEN 'DELIVERYDATE'    THEN 'ISNULL(i.DeliveryDate, i.InvoiceDate)'
            WHEN 'INVOICEDATE'     THEN 'i.InvoiceDate'
            WHEN 'AMOUNT'          THEN '(i.FinalAmount + ISNULL(i.DeliveryCharges,0))'
            WHEN 'DRIVERNAME'      THEN 'i.DriverName'
            WHEN 'BRANDNAME'       THEN 'br.BrandName'
            WHEN 'BRANCHNAME'      THEN 'b.branchName'
            WHEN 'ORDERSTATUS'     THEN 'st.SortOrder'
            WHEN 'ORDERSTATUSNAME' THEN 'st.SortOrder'
            ELSE 'i.InvoiceDate'
        END;

    /* InvoiceNo is appended as a tiebreaker so equal values - two orders in the
       same minute - keep a stable order across pages. Without it, row 50 can
       come back as row 51 on the next page.

       It is NOT appended when the user is already sorting by InvoiceNo. SQL
       Server rejects a column listed twice in ORDER BY:

           Msg 169 - A column has been specified more than once in the order by
                     list. Columns in the order by list must be unique.

       The dynamic SQL then fails and the browser shows it as the DataTables
       "Query failed" warning, which is exactly what clicking the Invoice No
       header produced. */
    DECLARE @OrderBy NVARCHAR(300) =
        @SortExpr
      + CASE WHEN UPPER(ISNULL(@SortDir,'DESC')) = 'ASC' THEN ' ASC' ELSE ' DESC' END
      + CASE WHEN @SortExpr = 'i.InvoiceNo' THEN N'' ELSE N', i.InvoiceNo DESC' END;

    DECLARE @dFrom DATETIME, @dTo DATETIME, @Today DATE = CAST(GETDATE() AS DATE);
    IF      @DateMode = 'Today'  BEGIN SET @dFrom = @Today;                  SET @dTo = DATEADD(DAY,1,@Today); END
    ELSE IF @DateMode = 'Future' BEGIN SET @dFrom = DATEADD(DAY,1,@Today);   SET @dTo = NULL; END
    ELSE IF @DateMode = 'Past'   BEGIN SET @dFrom = NULL;                    SET @dTo = @Today; END
    ELSE IF @DateMode = 'Range'  BEGIN SET @dFrom = @FromDate;               SET @dTo = DATEADD(DAY,1,@ToDate); END

    DECLARE @Brands   dbo.TVP_POS_IntList, @Branches dbo.TVP_POS_IntList,
            @ITypes   dbo.TVP_POS_IntList, @Statuses dbo.TVP_POS_IntList;

    IF NULLIF(LTRIM(RTRIM(@BrandIDs)),'')       IS NOT NULL INSERT INTO @Brands   (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BrandIDs,',')       WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@BranchIDs)),'')      IS NOT NULL INSERT INTO @Branches (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIDs,',')      WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@InvoiceTypeIDs)),'') IS NOT NULL INSERT INTO @ITypes   (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@InvoiceTypeIDs,',') WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@StatusIDs)),'')      IS NOT NULL INSERT INTO @Statuses (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@StatusIDs,',')      WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @AnyBrand  BIT = CASE WHEN EXISTS (SELECT 1 FROM @Brands)   THEN 0 ELSE 1 END
          , @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END
          , @AnyIType  BIT = CASE WHEN EXISTS (SELECT 1 FROM @ITypes)   THEN 0 ELSE 1 END
          , @AnyStatus BIT = CASE WHEN EXISTS (SELECT 1 FROM @Statuses) THEN 0 ELSE 1 END;

    DECLARE @SearchNum  BIGINT        = TRY_CAST(REPLACE(REPLACE(ISNULL(@Search,''),'+',''),' ','') AS BIGINT);
    DECLARE @SearchLike NVARCHAR(102) = CASE WHEN NULLIF(@Search,'') IS NULL THEN NULL ELSE '%' + @Search + '%' END;

    /* InvoiceNumShow is the number printed on the invoice the customer holds -
       a real column on tblInvoice, not assembled here, so there is one formula
       in one place. It is added to the SELECT below.

       NOTE FOR ANYONE EDITING THE STATEMENT BELOW: it is a STRING. An
       apostrophe anywhere inside it - including in a comment - closes the
       literal, and the rest of the procedure is then parsed as SQL. That
       produces a pile of "Incorrect syntax near ..." errors pointing at lines
       that are perfectly fine, ending in "Unclosed quotation mark". Write
       comments about this statement out here, not in there. */
    DECLARE @sql NVARCHAR(MAX) = N'
    SELECT
          TotalRows       = COUNT(*) OVER ()
        , i.InvoiceNo
        , i.InvoiceNumShow
        , i.TrackingCode
        , i.RunningOrder
        , InvoiceTypeID   = i.InvoiceType
        , InvoiceTypeName = ISNULL(it.Name, N''-'')
        , i.CustomerName
        , Mobile          = i.MobileText
        , i.CustomerId
        , AreaID          = ca.AreaID
        , AreaName        = ar.AreaName
        , DeliveryDate    = ISNULL(i.DeliveryDate, i.InvoiceDate)
        , i.InvoiceDate
        , AgeMinutes      = DATEDIFF(MINUTE, i.InvoiceDate, GETDATE())
        , IsLate          = CASE WHEN i.PromisedTime IS NOT NULL AND GETDATE() > i.PromisedTime
                                  AND ISNULL(st.IsTerminal,0) = 0 THEN 1 ELSE 0 END
        -- Amount = bill - discount + delivery. FinalAmount is a computed column
        -- that EXCLUDES DeliveryCharges, so it is added back here.
        , Amount          = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.BillAmount
        , i.Discount
        , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
        , DriverID        = i.Driver
        , DriverName      = ISNULL(NULLIF(i.DriverName,N''''), dr.DriverName)
        , BrandID         = i.BrandID
        , BrandName       = ISNULL(br.BrandName, N''-'')
        , i.BranchID
        , BranchName      = ISNULL(b.branchName, N''-'')
        , i.OrderStatusID
        , OrderStatusName = st.OrderStatusName
        , StatusColor     = st.ColorHex
        , IsTerminal      = ISNULL(st.IsTerminal,0)
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN ''Pickup'' WHEN 2 THEN ''Delivery'' WHEN 3 THEN ''Dine In'' ELSE ''Other'' END
        , PaymentTypeID   = i.PaymentType
        , PaymentTypeName = pt.PaymentTypeName
        , IsCOD           = ISNULL(pt.IsCOD,0)
        , AmountPaid      = ISNULL(pay.Paid,0)
        , PaymentStatus   = CASE WHEN ISNULL(pay.Paid,0) <= 0 THEN ''Unpaid''
                                 WHEN ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0) THEN ''Paid''
                                 ELSE ''Partial'' END
        , i.PrintCount
        , i.Deleted
    FROM        dbo.tblInvoice i
    LEFT JOIN   dbo.tblOrderStatus         st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN   dbo.tblbranch              b  ON b.id             = i.BranchID
    LEFT JOIN   dbo.tblBrand               br ON br.BrandID       = i.BrandID
    LEFT JOIN   dbo.tblInvoiceType_Master  it ON it.ID            = i.InvoiceType
    LEFT JOIN   dbo.tblInvoicePaymentType  pt ON pt.ID            = i.PaymentType
    LEFT JOIN   dbo.tblCustomerAddress     ca ON ca.AddressID     = i.AddressID
    LEFT JOIN   dbo.tblArea                ar ON ar.AreaID        = ca.AreaID
    LEFT JOIN   dbo.tblDriver              dr ON dr.DriverID      = i.Driver
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM dbo.tblInvoicePayment p
                 WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0) pay
    WHERE  (@IncludeDeleted = 1 OR ISNULL(i.Deleted,0) = 0)
      AND  (@AnyBrand  = 1 OR i.BrandID       IN (SELECT Value FROM @Brands))
      AND  (@AnyBranch = 1 OR i.BranchID      IN (SELECT Value FROM @Branches))
      AND  (@AnyIType  = 1 OR i.InvoiceType   IN (SELECT Value FROM @ITypes))
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
            OR i.TrackingCode LIKE @SearchLike
            OR i.CustomerName LIKE @SearchLike
            OR i.MobileText   LIKE @SearchLike
            OR ar.AreaName    LIKE @SearchLike
            OR (@SearchNum IS NOT NULL AND (i.InvoiceNo = @SearchNum OR i.Mobile = @SearchNum OR i.RunningOrder = @SearchNum)))
      AND  (@PaymentStatus IS NULL
            OR (@PaymentStatus = ''Unpaid''  AND ISNULL(pay.Paid,0) <= 0)
            OR (@PaymentStatus = ''Paid''    AND ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0))
            OR (@PaymentStatus = ''Partial'' AND ISNULL(pay.Paid,0) > 0
                                            AND ISNULL(pay.Paid,0) + 0.001 < i.FinalAmount + ISNULL(i.DeliveryCharges,0)))
      -- "Scheduled" = the customer picked a delivery date past the day the
      -- order was placed, not just a later time slot the same day. Raw
      -- i.DeliveryDate, not the ISNULL(...,InvoiceDate) fallback used in the
      -- SELECT above - a NULL DeliveryDate was never scheduled, and NULL >
      -- anything is unknown rather than true, so it is excluded either way.
      AND  (@ScheduledOnly = 0 OR CAST(i.DeliveryDate AS DATE) > CAST(i.InvoiceDate AS DATE))
    ORDER BY ' + @OrderBy + N'
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY
    OPTION (RECOMPILE);';

    EXEC sp_executesql @sql,
        N'@IncludeDeleted BIT, @AnyBrand BIT, @AnyBranch BIT, @AnyIType BIT, @AnyStatus BIT,
          @dFrom DATETIME, @dTo DATETIME, @OrderType INT, @PaymentTypeID INT, @SourceID INT, @DriverID INT,
          @MinAmount DECIMAL(18,3), @MaxAmount DECIMAL(18,3), @SearchLike NVARCHAR(102), @SearchNum BIGINT,
          @PaymentStatus VARCHAR(10), @ScheduledOnly BIT, @Skip INT, @Take INT,
          @Brands dbo.TVP_POS_IntList READONLY, @Branches dbo.TVP_POS_IntList READONLY,
          @ITypes dbo.TVP_POS_IntList READONLY, @Statuses dbo.TVP_POS_IntList READONLY',
        @IncludeDeleted, @AnyBrand, @AnyBranch, @AnyIType, @AnyStatus,
        @dFrom, @dTo, @OrderType, @PaymentTypeID, @SourceID, @DriverID,
        @MinAmount, @MaxAmount, @SearchLike, @SearchNum, @PaymentStatus, @ScheduledOnly, @Skip, @Take,
        @Brands, @Branches, @ITypes, @Statuses;
END
GO

PRINT 'sp_POS_GetOrders updated - InvoiceNumShow added, ScheduledOnly filter added.';
GO

IF OBJECT_ID('dbo.sp_POS_GetOrderDetails') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrderDetails;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrderDetails
      @InvoiceNo BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- 0: header
    SELECT
          i.InvoiceNo, i.InvoiceNumShow, i.TrackingCode, i.RunningOrder, i.InvoiceDate, i.PromisedTime
        , i.DeliveryDate, i.CustomerName, Mobile = i.MobileText, i.CustomerId
        , i.BranchID, BranchName = b.branchName, i.BrandID, BrandName = br.BrandName
        , InvoiceTypeID   = i.InvoiceType
        , InvoiceTypeName = it.Name
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN 'Pickup' WHEN 2 THEN 'Delivery' WHEN 3 THEN 'Dine In' ELSE 'Other' END
        , i.OrderStatusID, OrderStatusName = st.OrderStatusName, StatusColor = st.ColorHex
        , IsTerminal      = ISNULL(st.IsTerminal,0)
        , i.BillAmount, i.Discount, i.DiscountCode
        , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
        , i.FinalAmount
        -- FinalAmount is a computed column that EXCLUDES DeliveryCharges.
        -- NetPayable is what the customer actually pays.
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PaymentType, PaymentTypeName = pt.PaymentTypeName, IsCOD = ISNULL(pt.IsCOD,0)
        , AmountPaid      = ISNULL((SELECT SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                                    FROM dbo.tblInvoicePayment p
                                    WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0), 0)
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
    LEFT JOIN dbo.tblBrand              br ON br.BrandID       = i.BrandID
    LEFT JOIN dbo.tblInvoiceType_Master it ON it.ID            = i.InvoiceType
    LEFT JOIN dbo.tblInvoicePaymentType pt ON pt.ID            = i.PaymentType
    LEFT JOIN dbo.tblCustomerAddress    ca ON ca.AddressID     = i.AddressID
    LEFT JOIN dbo.tblArea               ar ON ar.AreaID        = ca.AreaID
    WHERE     i.InvoiceNo = @InvoiceNo;

    -- 1: lines.  ItemNameSnapshot is the name as sold, so a reprint months
    --    later still shows what the customer actually bought.
    SELECT
          o.OrderID, o.ItemID, o.LineType, o.ParentOrderID, o.CartItemUniqID
        , ItemName    = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
        , ItemNameAra = it.ITEM_NAME_ARABIC
        , o.Quantity, o.Price
        , Discount    = ISNULL(o.Discount, 0)
        , o.TotalAmount
        , OrderTime   = o.OrderDate
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

    -- 5: allowed next statuses, so the UI can never offer an invalid move
    SELECT    tr.ToStatusID, s.OrderStatusName, s.ColorHex, tr.RequiresRole
    FROM      dbo.tblPOS_OrderStatusTransition tr
    JOIN      dbo.tblOrderStatus s ON s.OrderStatusID = tr.ToStatusID
    JOIN      dbo.tblInvoice     i ON i.InvoiceNo     = @InvoiceNo
    WHERE     tr.FromStatusID = i.OrderStatusID
      AND     ((i.OrderType = 1 AND s.AppliesToPickup = 1) OR (i.OrderType <> 1 AND s.AppliesToDelivery = 1))
    ORDER BY  s.SortOrder;
END
GO

PRINT 'sp_POS_GetOrderDetails updated - InvoiceNumShow added.';
GO


/*==============================================================================
  SECTION 4 - sp_POS_GetInvoiceNumShow

  The customer checkout gets an invoice number back from sp_POS_ProcessOrder and
  puts it straight on the confirmation screen. Rather than recreating that whole
  procedure to return one more column, the number is fetched here.

  Read from the table, never rebuilt in C#. A second copy of the formula is a
  second thing to keep in step, and the one that gets forgotten is always the
  one the customer is holding.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetInvoiceNumShow') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetInvoiceNumShow;
GO

CREATE PROCEDURE dbo.sp_POS_GetInvoiceNumShow
      @InvoiceNo BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   InvoiceNo
           , InvoiceNumShow
           , TrackingCode
    FROM     dbo.tblInvoice
    WHERE    InvoiceNo = @InvoiceNo;
END
GO

PRINT 'sp_POS_GetInvoiceNumShow created.';
GO


/*==============================================================================
  THE REST OF THE DATABASE SIDE

  1. Procedures that return an invoice number to a screen should carry
     InvoiceNumShow. Where each one stands:

        sp_POS_GetOrders               done here
        sp_POS_GetOrderDetails         done here   (grid, drawer, printed receipt)
        sp_POS_GetOrderChanges         not needed - the delta poll patches rows
                                       that already exist, and the display value
                                       of an existing row never changes
        sp_POS_ProcessOrder            not changed - checkout calls
                                       sp_POS_GetInvoiceNumShow instead
        sp_POS_MarkPrinted             not needed - the print view reads the
                                       details proc
        sp_DashbordSalesData           not needed - aggregates only
        sp_GetDashboardLateOrdersData  add it if you want the printed number in
                                       that grid; same one-column change

  2. To FIND an order by the printed number, search InvoiceNumShow directly -
     the index above covers it. Do not parse the number apart: the InvoiceNo
     tail has no fixed length, so the first eight characters are the date and
     the rest is the key, and only in that direction.

  3. The formula assumes InvoiceDate never changes once the row is written. It
     does not today. If that ever changes, a reprint would carry a different
     number from the one the customer already has - at which point this should
     become a stored column stamped once at insert, not a computed one.
==============================================================================*/
