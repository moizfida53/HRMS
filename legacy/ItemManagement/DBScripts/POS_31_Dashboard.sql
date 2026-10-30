/**********************************************************************************
  POS_31_Dashboard.sql
  ------------------------------------------------------------------------------
  The Dashboard page, ported from the Call Centre project onto THIS database.

  The two databases are not the same shape, and the differences are not cosmetic
  - the original procedures cannot run here at all. What follows is the port,
  with every decision stated where it was made. The full table-by-table
  comparison is in DASHBOARD_PORT_NOTES.md; the four that change the most:

  1. ONE DATABASE, NOT MANY
     The Call Centre keeps a database per branch (tblBranch.BranchDBName) and
     every procedure walks a cursor building dynamic SQL against
     [BranchDB].dbo.tblInvoice. Here all branches live in one database with a
     BranchID column, so the cursors and the dynamic SQL are gone. That also
     removes split_stringWithDelim, which does not exist here - STRING_SPLIT
     does the same job.

  2. THE INVOICE KEY
     Call Centre:  tblInvoice.id      <- tblOrder.InvoiceId
     Here:         tblInvoice.InvoiceNo <- tblOrder.InvoiceNo
     Every join in the original is written the first way. Left as-is it fails
     with "Invalid column name 'InvoiceId'".

  3. BRANCH COLUMNS
     Call Centre:  BranchID, BranchName, StoreID, BranchDBName
     Here:         id, branchName, brandId          (no StoreID, no DB name)
     StoreID was on the branch charts; branch id stands in for it.

  4. DATE SCOPING - the one that decides whether anything appears at all
     Every original query scopes by tblEndDay: an order counts when its
     EndDayID belongs to a session that started in range. That works when a
     till is cashed up nightly. Orders taken through this QR menu are written
     with EndDayID NULL and nothing ever sets it, so an end-of-day scope
     returns zero rows for every panel, on every date.

     So the scope here is i.InvoiceDate between @FromDate and @ToDate. When
     @EndDates is supplied the dashboard is asking for particular operating
     days, and those are matched against CAST(i.InvoiceDate AS DATE).

  MISSING TABLES
     tblWaste / tblWasteDetails     no equivalent. Standalone waste (thrown
                                    stock not attached to an order) is not
                                    recorded here, so the waste figures come
                                    from tblOrder.Waste alone.
     tblFranchise_GroupMaster       franchise groups do not exist. tblBrand is
                                    the equivalent grouping and is used instead.
     tbl_StatusDetails              per-branch status timings. The equivalent
                                    here is tblPOS_OrderStatusHistory, which is
                                    what the late-order timings are read from.

  PROCEDURES CREATED
     sp_DashboardFilter                    filter dropdowns
     sp_GetEndDatesForRptDashboard         operating-day list
     sp_DashbordSalesData                  the Sales tab (16 result sets)
     sp_DashbordPaymentTypesData           payment type drill-down
     sp_GetDashboardTopItemsSummaryData    top items drill-down
     sp_GetDashboardLateOrdersData         late orders drill-down
     sp_DashbordDiscountWiseItemsData      discount drill-down
     sp_DashbordDeletedReUseWiseItemsData  deleted / reuse drill-down
     sp_DashbordDeletedWasteWiseItemsData  deleted / waste drill-down

  @CountryId is accepted and ignored throughout: the JS sends it and there is
  one country here. Keeping the parameter means DashboardController.cs and
  Dashboard.js need no change on that account.

  Requires SQL Server 2016+ (STRING_SPLIT). Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  0. Preflight - what is actually here?

  Read this output before anything else. A missing table below is a panel that
  will read zero, not an error.
==============================================================================*/
PRINT '===== dashboard preflight =====';

SELECT   ObjectName = t.n
       , Status     = CASE WHEN OBJECT_ID('dbo.' + t.n) IS NULL THEN 'MISSING' ELSE 'ok' END
FROM   (VALUES ('tblInvoice'), ('tblOrder'), ('tblbranch'), ('tblBrand'),
               ('tblItems'), ('tblCategory'), ('tblInvoiceType_Master'),
               ('tblInvoicePaymentType'), ('tblInvoicePayment'),
               ('tblDiscount_Type'), ('tblPOS_OrderStatusHistory'),
               ('tblEndDay')) AS t(n);

SELECT   DiscountTypeNameColumn =
             CASE WHEN COL_LENGTH('dbo.tblDiscount_Type', 'DiscountTypeName') IS NOT NULL THEN 'DiscountTypeName'
                  WHEN COL_LENGTH('dbo.tblDiscount_Type', 'DiscountType')     IS NOT NULL THEN 'DiscountType'
                  WHEN COL_LENGTH('dbo.tblDiscount_Type', 'TypeName')         IS NOT NULL THEN 'TypeName'
                  WHEN COL_LENGTH('dbo.tblDiscount_Type', 'Name')             IS NOT NULL THEN 'Name'
                  ELSE 'NOT FOUND - discount names will be blank' END;

SELECT   ColumnOnTblOrder = c.n
       , Status = CASE WHEN COL_LENGTH('dbo.tblOrder', c.n) IS NULL THEN 'MISSING' ELSE 'ok' END
FROM   (VALUES ('InvoiceNo'), ('ItemID'), ('Quantity'), ('Price'), ('Discount'),
               ('TotalAmount'), ('Deleted'), ('Waste'), ('LineType'),
               ('DiscountTypeID'), ('BranchID'), ('ItemNameSnapshot'),
               ('DeleteOrderComment')) AS c(n);
GO


/*==============================================================================
  1. sp_DashboardFilter

  Same four result sets, same val/txt column names the JS binds to. Only the
  source columns change: tblbranch is id / branchName here, not BranchID /
  BranchName, and deleted or inactive rows are left out - a filter listing a
  branch that closed last year is a filter nobody trusts.
==============================================================================*/
IF OBJECT_ID('dbo.sp_DashboardFilter') IS NOT NULL DROP PROCEDURE dbo.sp_DashboardFilter;
GO

CREATE PROCEDURE dbo.sp_DashboardFilter
      @CountryId INT = NULL          -- accepted and ignored; one country here
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   val = b.id, txt = ISNULL(b.branchName, N'-')
    FROM     dbo.tblbranch b WITH (NOLOCK)
    WHERE    ISNULL(b.IsDeleted, 0) = 0
    ORDER BY ISNULL(b.SEQ_NUM, 9999), b.branchName;

    SELECT   val = it.ID, txt = ISNULL(it.Name, N'-')
    FROM     dbo.tblInvoiceType_Master it WITH (NOLOCK)
    ORDER BY it.ID;

    SELECT   val = pt.ID, txt = ISNULL(pt.PaymentTypeName, N'-')
    FROM     dbo.tblInvoicePaymentType pt WITH (NOLOCK)
    WHERE    ISNULL(pt.IsDeleted, 0) = 0
    ORDER BY ISNULL(pt.Seqnum, 9999), pt.ID;

    SELECT   val = br.BrandID, txt = ISNULL(br.BrandName, N'-')
    FROM     dbo.tblBrand br WITH (NOLOCK)
    ORDER BY ISNULL(br.BrandSeq, 9999), br.BrandName;
END
GO
PRINT 'sp_DashboardFilter created.';
GO


/*==============================================================================
  2. sp_GetEndDatesForRptDashboard

  The original walked every branch database collecting tblEndDay.StartDate.
  Here the "operating days" the dashboard can filter by are simply the days on
  which orders exist - which is also the only thing that produces a non-empty
  list, since EndDayID is never populated by the QR menu.

  Column names are unchanged (StartDate, StartDateName): the controller reads
  them by name into tmpclsEndDate.
==============================================================================*/
IF OBJECT_ID('dbo.sp_GetEndDatesForRptDashboard') IS NOT NULL DROP PROCEDURE dbo.sp_GetEndDatesForRptDashboard;
GO

CREATE PROCEDURE dbo.sp_GetEndDatesForRptDashboard
      @CountryId INT      = NULL
    , @FromDate  DATETIME = NULL
    , @ToDate    DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = DATEADD(DAY, -30, GETDATE());
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   StartDate     = d.Day
           , StartDateName = FORMAT(d.Day, 'dd-MMM-yy, ddd')
    FROM   (
        SELECT DISTINCT Day = CAST(i.InvoiceDate AS DATE)
        FROM   dbo.tblInvoice i WITH (NOLOCK)
        WHERE  ISNULL(i.Deleted, 0) = 0
          AND  i.InvoiceDate >= CAST(@FromDate AS DATE)
          AND  i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
    ) d
    ORDER BY d.Day DESC;
END
GO
PRINT 'sp_GetEndDatesForRptDashboard created.';
GO


/*==============================================================================
  3. sp_DashbordSalesData  -  the Sales tab

  This procedure was NOT in the file supplied. DashboardController.cs calls it
  and reads specific table INDEXES out of the result:

      0  TotalSales          TotalSales, OrderCount
      1  TotalDiscount       TotalDiscount, OrderCount
      2  PaymentTypes        Name, orders, Total
      3  SalesLineChart      BranchName, InvoiceDate, NetTotal, TotalCount
      4  SalesPivot          BranchName, keyName, KeyValue, InvoiceDate
      5  OrderTypes          Name, TotalOrders, TotalSales
      6  CancellationReUse   TotalDelItems, CountDelItems
      7  CancellationWaste   TotalWasteItems, CountWasteItems
      8  (unused)
      9  HourlyWiseSales     Name, HoursBreak, TotalSales, TotalCount
     10  TopItems            itemName, SoldItems, Total
     11  (unused)
     12  BranchSales         BranchName, OrderTotalAmt, OrderCount
     13  (unused)
     14  LateOrders          BranchName, LateOrderCount, TotalOrders
     15  CountryData         Currency

  The unused indexes are still returned, empty, because the controller reads by
  position: drop one and every table after it shifts and the page fills with
  the wrong numbers.

  TYPES MATTER. The controller does x.Field<int>("TotalCount") and
  x.Field<Decimal>("TotalSales") - a mismatch throws InvalidCastException
  rather than showing a wrong figure, so counts are CAST to INT and money to
  DECIMAL(18,3) everywhere.
==============================================================================*/
IF OBJECT_ID('dbo.sp_DashbordSalesData') IS NOT NULL DROP PROCEDURE dbo.sp_DashbordSalesData;
GO

CREATE PROCEDURE dbo.sp_DashbordSalesData
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();
    IF @GroupByFlag IS NULL SET @GroupByFlag = 1;

    DECLARE @dFrom DATETIME = CAST(@FromDate AS DATE)
          , @dTo   DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATE));

    /*---- filters ---------------------------------------------------------
      Empty or '0' means "all". The dashboard's All option posts 0, and the
      controller strips it for branch and brand but deliberately NOT for
      payment type, where 0 means cash - so a 0 here must not wipe the filter.
    ---------------------------------------------------------------------*/
    DECLARE @Branches TABLE (v INT PRIMARY KEY);
    DECLARE @Brands   TABLE (v INT PRIMARY KEY);
    DECLARE @ITypes   TABLE (v INT PRIMARY KEY);
    DECLARE @PTypes   TABLE (v INT PRIMARY KEY);
    DECLARE @Days     TABLE (d DATE PRIMARY KEY);

    IF NULLIF(LTRIM(RTRIM(@BranchIds)), '') IS NOT NULL
        INSERT INTO @Branches (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL AND TRY_CAST(value AS INT) > 0;

    IF NULLIF(LTRIM(RTRIM(@BrandIds)), '') IS NOT NULL
        INSERT INTO @Brands (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BrandIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL AND TRY_CAST(value AS INT) > 0;

    IF NULLIF(LTRIM(RTRIM(@InvoiceTypeIds)), '') IS NOT NULL
        INSERT INTO @ITypes (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@InvoiceTypeIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL AND TRY_CAST(value AS INT) > 0;

    IF NULLIF(LTRIM(RTRIM(@PaymentTypeIds)), '') IS NOT NULL
        INSERT INTO @PTypes (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@PaymentTypeIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL;

    -- Operating days, when the user picked specific ones. @IsDefaultLoad = 1
    -- means they have not touched that dropdown, so the date range rules.
    IF ISNULL(@IsDefaultLoad, 0) = 0 AND NULLIF(LTRIM(RTRIM(@EndDates)), '') IS NOT NULL
        INSERT INTO @Days (d)
        SELECT DISTINCT TRY_CAST(value AS DATE) FROM STRING_SPLIT(@EndDates, ',')
        WHERE TRY_CAST(value AS DATE) IS NOT NULL;

    DECLARE @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END
          , @AnyBrand  BIT = CASE WHEN EXISTS (SELECT 1 FROM @Brands)   THEN 0 ELSE 1 END
          , @AnyIType  BIT = CASE WHEN EXISTS (SELECT 1 FROM @ITypes)   THEN 0 ELSE 1 END
          , @AnyPType  BIT = CASE WHEN EXISTS (SELECT 1 FROM @PTypes)   THEN 0 ELSE 1 END
          , @AnyDay    BIT = CASE WHEN EXISTS (SELECT 1 FROM @Days)     THEN 0 ELSE 1 END;

    /*---- the invoices in scope, once --------------------------------------
      Every panel below reads this. Building it once rather than repeating the
      filter in nine queries is what keeps them agreeing with each other.
    ---------------------------------------------------------------------*/
    IF OBJECT_ID('tempdb..#inv') IS NOT NULL DROP TABLE #inv;

    SELECT   i.InvoiceNo
           , i.BranchID
           , i.BrandID
           , i.InvoiceType
           , i.PaymentType
           , i.InvoiceDate
           , i.OrderStatusID
           , NetTotal   = CAST(i.FinalAmount + ISNULL(i.DeliveryCharges, 0) AS DECIMAL(18,3))
           , Discount   = CAST(ISNULL(i.Discount, 0) AS DECIMAL(18,3))
           , BranchName = ISNULL(b.branchName, N'-')
    INTO     #inv
    FROM     dbo.tblInvoice i WITH (NOLOCK)
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    i.InvoiceDate >= @dFrom
      AND    i.InvoiceDate <  @dTo
      AND    (@AnyDay    = 1 OR CAST(i.InvoiceDate AS DATE) IN (SELECT d FROM @Days))
      AND    (@AnyBranch = 1 OR i.BranchID    IN (SELECT v FROM @Branches))
      AND    (@AnyBrand  = 1 OR i.BrandID     IN (SELECT v FROM @Brands))
      AND    (@AnyIType  = 1 OR i.InvoiceType IN (SELECT v FROM @ITypes))
      AND    (@AnyPType  = 1 OR ISNULL(i.PaymentType, 0) IN (SELECT v FROM @PTypes));

    CREATE CLUSTERED INDEX IX_inv ON #inv (InvoiceNo);

    /*======================================================================
      0 : Total sales
    ======================================================================*/
    SELECT   TotalSales = CAST(ISNULL(SUM(NetTotal), 0) AS DECIMAL(18,3))
           , OrderCount = CAST(COUNT(*) AS INT)
    FROM     #inv;

    /*======================================================================
      1 : Total discount. OrderCount counts orders that HAD a discount, not
          all orders - "12 discounts" beside a discount total reads correctly,
          "12 orders" beside it does not.
    ======================================================================*/
    SELECT   TotalDiscount = CAST(ISNULL(SUM(Discount), 0) AS DECIMAL(18,3))
           , OrderCount    = CAST(SUM(CASE WHEN Discount > 0 THEN 1 ELSE 0 END) AS INT)
    FROM     #inv;

    /*======================================================================
      2 : Payment types. Taken from the payment ROWS, so a split payment shows
          under both methods. Orders with no payment row are Unpaid.
    ======================================================================*/
    SELECT   Name   = x.Name
           , orders = CAST(COUNT(DISTINCT x.InvoiceNo) AS INT)
           , Total  = CAST(ISNULL(SUM(x.Amount), 0) AS DECIMAL(18,3))
    FROM   (
        SELECT   v.InvoiceNo
               , Name   = ISNULL(pt.PaymentTypeName, ISNULL(p.PaymentType, N'Unknown'))
               , Amount = CAST(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END AS DECIMAL(18,3))
        FROM     #inv v
        JOIN     dbo.tblInvoicePayment p WITH (NOLOCK) ON p.InvoiceId = v.InvoiceNo
        LEFT JOIN dbo.tblInvoicePaymentType pt WITH (NOLOCK) ON pt.ID = p.PaymentTypeID
        WHERE    ISNULL(p.isdeleted, 0) = 0

        UNION ALL

        SELECT   v.InvoiceNo, N'Unpaid', v.NetTotal
        FROM     #inv v
        WHERE    NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePayment p WITH (NOLOCK)
                             WHERE p.InvoiceId = v.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0)
    ) x
    GROUP BY x.Name
    ORDER BY Total DESC;

    /*======================================================================
      3 : Sales line chart, one series per branch.
          InvoiceDate must be a real DATETIME - the controller reads it with
          Field<DateTime> and formats it itself.
    ======================================================================*/
    SELECT   BranchName = v.BranchName
           , InvoiceDate = CAST(CAST(v.InvoiceDate AS DATE) AS DATETIME)
           , NetTotal    = CAST(ISNULL(SUM(v.NetTotal), 0) AS DECIMAL(18,3))
           , TotalCount  = CAST(COUNT(*) AS INT)
    FROM     #inv v
    GROUP BY v.BranchName, CAST(v.InvoiceDate AS DATE)
    ORDER BY v.BranchName, CAST(CAST(v.InvoiceDate AS DATE) AS DATETIME);

    /*======================================================================
      4 : Sales pivot. One row per branch per day per measure; the view turns
          keyName / KeyValue into columns. Measures are Sales / Orders / Avg
          Per cheque (Discount dropped - the "Sales Data" drill-down grid
          does not show it); InvoiceDate is emitted as yyyy-MM-dd (style 23)
          so SalesPivotBuilder.FormatDate() in DashboardModels.cs can
          TryParseExact it, and so plain-text sort order matches chronological
          order without needing to parse first.
    ======================================================================*/
    SELECT   BranchName = v.BranchName
           , keyName    = k.keyName
           , KeyValue   = CAST(k.KeyValue AS DECIMAL(18,3))
           , InvoiceDate = CONVERT(VARCHAR(10), CAST(v.InvoiceDate AS DATE), 23)
    FROM   (
        SELECT   BranchName, Day = CAST(InvoiceDate AS DATE)
               , Sales = SUM(NetTotal), Cnt = COUNT(*)
        FROM     #inv GROUP BY BranchName, CAST(InvoiceDate AS DATE)
    ) g
    CROSS APPLY (VALUES ('Sales', g.Sales), ('Orders', CAST(g.Cnt AS DECIMAL(18,3))),
                         ('AvgPerCheque', CASE WHEN g.Cnt = 0 THEN 0 ELSE g.Sales / g.Cnt END)) k(keyName, KeyValue)
    JOIN     #inv v ON v.BranchName = g.BranchName AND CAST(v.InvoiceDate AS DATE) = g.Day
    GROUP BY v.BranchName, k.keyName, k.KeyValue, CAST(v.InvoiceDate AS DATE)
    ORDER BY v.BranchName, CAST(v.InvoiceDate AS DATE);

    /*======================================================================
      5 : Order types. The original sorted a literal 'zzzzzTotal' to the bottom
          and the JS renames it - kept, so that code still works.
    ======================================================================*/
    SELECT   Name        = x.Name
           , TotalOrders = CAST(x.TotalOrders AS INT)
           , TotalSales  = CAST(x.TotalSales AS DECIMAL(18,3))
    FROM   (
        SELECT   Name = ISNULL(it.Name, N'Unknown')
               , TotalOrders = COUNT(*)
               , TotalSales  = ISNULL(SUM(v.NetTotal), 0)
               , Ord = 1
        FROM     #inv v
        LEFT JOIN dbo.tblInvoiceType_Master it WITH (NOLOCK) ON it.ID = v.InvoiceType
        GROUP BY ISNULL(it.Name, N'Unknown')

        UNION ALL

        SELECT N'zzzzzTotal', COUNT(*), ISNULL(SUM(v.NetTotal), 0), 2 FROM #inv v
    ) x
    ORDER BY x.Ord, x.TotalSales DESC;

    /*======================================================================
      6 : Cancellations, reuse. Deleted lines whose stock went back.
    ======================================================================*/
    SELECT   TotalDelItems = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
           , CountDelItems = CAST(COUNT(*) AS INT)
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     #inv v ON v.InvoiceNo = o.InvoiceNo
    WHERE    ISNULL(o.Deleted, 0) = 1 AND ISNULL(o.Waste, 0) = 0;

    /*======================================================================
      7 : Cancellations, waste. Made and thrown away.

          The original added tblWaste / tblWasteDetails here - standalone waste
          not attached to an order. Neither table exists in this database, so
          this is order-line waste only.
    ======================================================================*/
    SELECT   TotalWasteItems = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
           , CountWasteItems = CAST(COUNT(*) AS INT)
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     #inv v ON v.InvoiceNo = o.InvoiceNo
    WHERE    ISNULL(o.Waste, 0) = 1;

    /*======================================================================
      8 : placeholder - the controller does not read Tables[8], but the ones
          after it are read by index, so it has to exist.
    ======================================================================*/
    SELECT TOP 0 Placeholder = CAST(NULL AS INT);

    /*======================================================================
      9 : Hourly breakdown.
          GroupByFlag 1 = per branch, 2 = per invoice type, anything else = all
          branches together. HoursBreak is the label the chart plots along the
          x axis, so it is zero-padded - '09-10' sorts before '10-11', '9-10'
          does not.
    ======================================================================*/
    SELECT   Name       = CASE WHEN @GroupByFlag = 2 THEN ISNULL(it.Name, N'Unknown')
                               WHEN @GroupByFlag = 1 THEN v.BranchName
                               ELSE N'All' END
           , HoursBreak = RIGHT('0' + CAST(DATEPART(HOUR, v.InvoiceDate) AS VARCHAR(2)), 2) + '-'
                        + RIGHT('0' + CAST((DATEPART(HOUR, v.InvoiceDate) + 1) % 24 AS VARCHAR(2)), 2)
           , TotalSales = CAST(ISNULL(SUM(v.NetTotal), 0) AS DECIMAL(18,3))
           , TotalCount = CAST(COUNT(*) AS INT)
    FROM     #inv v
    LEFT JOIN dbo.tblInvoiceType_Master it WITH (NOLOCK) ON it.ID = v.InvoiceType
    GROUP BY CASE WHEN @GroupByFlag = 2 THEN ISNULL(it.Name, N'Unknown')
                  WHEN @GroupByFlag = 1 THEN v.BranchName
                  ELSE N'All' END
           , DATEPART(HOUR, v.InvoiceDate)
    ORDER BY 1, DATEPART(HOUR, v.InvoiceDate);

    /*======================================================================
     10 : Top items. Sold lines only - a deleted line is not a sale.
          ItemNameSnapshot is the name AS SOLD; falling back to the live name
          means a renamed item does not rewrite last month's chart.
    ======================================================================*/
    SELECT TOP (20)
             itemName  = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , SoldItems = CAST(SUM(o.Quantity) AS INT)
           , Total     = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     #inv v ON v.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems it WITH (NOLOCK) ON it.ID = o.ItemID
    WHERE    ISNULL(o.Deleted, 0) = 0
    GROUP BY ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
    ORDER BY SoldItems DESC;

    /*====================================================================== 11 */
    SELECT TOP 0 Placeholder = CAST(NULL AS INT);

    /*======================================================================
     12 : Branch sales chart.
    ======================================================================*/
    SELECT   BranchName    = v.BranchName
           , OrderTotalAmt = CAST(ISNULL(SUM(v.NetTotal), 0) AS DECIMAL(18,3))
           , OrderCount    = CAST(COUNT(*) AS INT)
    FROM     #inv v
    GROUP BY v.BranchName
    ORDER BY OrderTotalAmt DESC;

    /*====================================================================== 13 */
    SELECT TOP 0 Placeholder = CAST(NULL AS INT);

    /*======================================================================
     14 : Late orders per branch.

          The original read per-branch tbl_StatusDetails. Here the timings are
          in tblPOS_OrderStatusHistory: an order is late when the gap between
          the invoice and the row that closed it exceeds @LateMinDuration.
          Orders still open are not late - they are not finished.
    ======================================================================*/
    SELECT   BranchName     = v.BranchName
           , LateOrderCount = CAST(SUM(CASE WHEN x.Mins >= @LateMinDuration THEN 1 ELSE 0 END) AS INT)
           , TotalOrders    = CAST(COUNT(*) AS INT)
    FROM     #inv v
    OUTER APPLY (
        SELECT Mins = DATEDIFF(MINUTE, v.InvoiceDate, MAX(h.ChangedOn))
        FROM   dbo.tblPOS_OrderStatusHistory h WITH (NOLOCK)
        JOIN   dbo.tblOrderStatus s WITH (NOLOCK) ON s.OrderStatusID = h.ToStatusID
        WHERE  h.InvoiceNo = v.InvoiceNo AND ISNULL(s.IsTerminal, 0) = 1
    ) x
    GROUP BY v.BranchName
    ORDER BY LateOrderCount DESC;

    /*======================================================================
     15 : Currency. The Call Centre served two countries and read this from a
          country table. There is one here, so it comes from Web.config's
          currency by way of a constant - change the literal if the brand
          trades in something other than KD.
    ======================================================================*/
    SELECT Currency = N'KD';

    DROP TABLE #inv;
END
GO
PRINT 'sp_DashbordSalesData created.';
GO


/*==============================================================================
  4. The drill-down grids

  All five return ONE table, which the JS renders into a DataTable by reading
  whatever columns come back - so the column names here are the column headings
  the user sees.
==============================================================================*/

/*---- 4.1 payment types -----------------------------------------------------*/
IF OBJECT_ID('dbo.sp_DashbordPaymentTypesData') IS NOT NULL DROP PROCEDURE dbo.sp_DashbordPaymentTypesData;
GO

CREATE PROCEDURE dbo.sp_DashbordPaymentTypesData
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   [Branch]        = ISNULL(b.branchName, N'-')
           , [Payment Type]  = ISNULL(pt.PaymentTypeName, ISNULL(p.PaymentType, N'Unknown'))
           , [Orders]        = COUNT(DISTINCT i.InvoiceNo)
           , [Amount]        = CAST(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END) AS DECIMAL(18,3))
    FROM     dbo.tblInvoicePayment p WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = p.InvoiceId
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    LEFT JOIN dbo.tblInvoicePaymentType pt WITH (NOLOCK) ON pt.ID = p.PaymentTypeID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(p.isdeleted, 0) = 0
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    GROUP BY ISNULL(b.branchName, N'-'), ISNULL(pt.PaymentTypeName, ISNULL(p.PaymentType, N'Unknown'))
    ORDER BY [Branch], [Amount] DESC;
END
GO

/*---- 4.2 top items ---------------------------------------------------------
  The original built this by cursor across branch databases and joined
  tblcategory on c.cat_num = i.cat_num. Same shape, one database.
----------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_GetDashboardTopItemsSummaryData') IS NOT NULL DROP PROCEDURE dbo.sp_GetDashboardTopItemsSummaryData;
GO

CREATE PROCEDURE dbo.sp_GetDashboardTopItemsSummaryData
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   Ranks      = ROW_NUMBER() OVER (ORDER BY SUM(o.Quantity) DESC)
           , itemID     = o.ItemID
           , itemName   = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , BrandName  = ISNULL(br.BrandName, N'-')
           , CategoryName = ISNULL(c.CAT_NAME, N'-')
           , UnitPrice  = CAST(MAX(o.Price) AS DECIMAL(18,3))
           , SoldItems  = CAST(SUM(o.Quantity) AS INT)
           , Total      = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems    it WITH (NOLOCK) ON it.ID      = o.ItemID
    LEFT JOIN dbo.tblCategory c  WITH (NOLOCK) ON c.CAT_NUM  = it.CAT_NUM
    LEFT JOIN dbo.tblBrand    br WITH (NOLOCK) ON br.BrandID = i.BrandID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(o.Deleted, 0) = 0
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
      AND    (NULLIF(@BrandIds, '') IS NULL
              OR i.BrandID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BrandIds, ',')))
    GROUP BY o.ItemID, ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-')),
             ISNULL(br.BrandName, N'-'), ISNULL(c.CAT_NAME, N'-')
    ORDER BY SoldItems DESC;
END
GO

/*---- 4.3 late orders -------------------------------------------------------
  The original read tbl_StatusDetails in each branch database, with hard-coded
  status IDs 2..6 for Kitchen / Ready / Dispatched / Collected / Delivered.
  Those IDs are per-installation here and have been renamed, so each step is
  found by its position in tblOrderStatus.SortOrder instead - the workflow
  order, which is what the columns actually mean.
----------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_GetDashboardLateOrdersData') IS NOT NULL DROP PROCEDURE dbo.sp_GetDashboardLateOrdersData;
GO

CREATE PROCEDURE dbo.sp_GetDashboardLateOrdersData
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();
    IF @LateMinDuration IS NULL SET @LateMinDuration = 70;

    DECLARE @MaxDuration INT = 1440;   -- a day. Beyond that it is bad data.

    ;WITH steps AS (
        SELECT   h.InvoiceNo
               , Step = DENSE_RANK() OVER (PARTITION BY h.InvoiceNo ORDER BY ISNULL(s.SortOrder, h.ToStatusID))
               , h.ChangedOn
               , s.OrderStatusName
               , IsTerminal = ISNULL(s.IsTerminal, 0)
        FROM     dbo.tblPOS_OrderStatusHistory h WITH (NOLOCK)
        LEFT JOIN dbo.tblOrderStatus s WITH (NOLOCK) ON s.OrderStatusID = h.ToStatusID
    )
    SELECT   BranchName        = ISNULL(b.branchName, N'-')
           , [Invoice No]      = i.InvoiceNo
           , [Bill Amount]     = CAST(i.FinalAmount + ISNULL(i.DeliveryCharges,0) AS DECIMAL(18,3))
           , [Order Received]  = FORMAT(i.InvoiceDate, 'dd-MMM-yy hh:mm tt')
           , [In Kitchen]      = FORMAT(k.ChangedOn, 'hh:mm tt')
           , [Ready]           = FORMAT(r.ChangedOn, 'hh:mm tt')
           , [Closed]          = FORMAT(f.ChangedOn, 'hh:mm tt')
           , [Closed Status]   = f.OrderStatusName
           , [Total Minutes]   = DATEDIFF(MINUTE, i.InvoiceDate, f.ChangedOn)
    FROM     dbo.tblInvoice i WITH (NOLOCK)
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    OUTER APPLY (SELECT TOP 1 ChangedOn FROM steps WHERE InvoiceNo = i.InvoiceNo AND Step = 2 ORDER BY ChangedOn) k
    OUTER APPLY (SELECT TOP 1 ChangedOn FROM steps WHERE InvoiceNo = i.InvoiceNo AND Step = 3 ORDER BY ChangedOn) r
    OUTER APPLY (SELECT TOP 1 ChangedOn, OrderStatusName FROM steps
                 WHERE InvoiceNo = i.InvoiceNo AND IsTerminal = 1 ORDER BY ChangedOn DESC) f
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    f.ChangedOn IS NOT NULL
      AND    DATEDIFF(MINUTE, i.InvoiceDate, f.ChangedOn) >= @LateMinDuration
      AND    DATEDIFF(MINUTE, i.InvoiceDate, f.ChangedOn) <= @MaxDuration
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    ORDER BY [Total Minutes] DESC, i.InvoiceNo DESC;
END
GO

/*---- 4.4 discount wise items ----------------------------------------------*/
IF OBJECT_ID('dbo.sp_DashbordDiscountWiseItemsData') IS NOT NULL DROP PROCEDURE dbo.sp_DashbordDiscountWiseItemsData;
GO

CREATE PROCEDURE dbo.sp_DashbordDiscountWiseItemsData
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    /*---- what is the name column called? --------------------------------
      The original reads tblDiscount_Type.DiscountTypeName. Nothing else in
      this project references that table by name, so the column is unverified -
      and a wrong column name here would stop this procedure being CREATED at
      all rather than failing at run time. It is resolved instead, and an
      unrecognised table just leaves the names blank.
    ---------------------------------------------------------------------*/
    IF OBJECT_ID('tempdb..#dt') IS NOT NULL DROP TABLE #dt;
    CREATE TABLE #dt (Id INT PRIMARY KEY, DiscountTypeName NVARCHAR(200) NULL);

    DECLARE @nameCol SYSNAME =
        CASE WHEN COL_LENGTH('dbo.tblDiscount_Type', 'DiscountTypeName') IS NOT NULL THEN 'DiscountTypeName'
             WHEN COL_LENGTH('dbo.tblDiscount_Type', 'DiscountType')     IS NOT NULL THEN 'DiscountType'
             WHEN COL_LENGTH('dbo.tblDiscount_Type', 'TypeName')         IS NOT NULL THEN 'TypeName'
             WHEN COL_LENGTH('dbo.tblDiscount_Type', 'Name')             IS NOT NULL THEN 'Name'
             ELSE NULL END;

    IF @nameCol IS NOT NULL AND OBJECT_ID('dbo.tblDiscount_Type') IS NOT NULL
    BEGIN
        DECLARE @sql NVARCHAR(MAX) =
            N'INSERT INTO #dt (Id, DiscountTypeName) SELECT Id, ' + QUOTENAME(@nameCol)
          + N' FROM dbo.tblDiscount_Type WITH (NOLOCK);';
        EXEC sp_executesql @sql;
    END

    -- The line's own discount type when it has one, otherwise the invoice's.
    -- Same rule as the original, written once instead of in a CASE per column.
    SELECT   [Discount Type] = ISNULL(dt.DiscountTypeName, N'(none)')
           , [Branch]        = ISNULL(b.branchName, N'-')
           , [Item]          = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , [Qty]           = CAST(SUM(o.Quantity) AS INT)
           , [Discount]      = CAST(SUM(ISNULL(o.Discount, 0)) AS DECIMAL(18,3))
           , [Line Total]    = CAST(SUM(ISNULL(o.TotalAmount, 0)) AS DECIMAL(18,3))
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    LEFT JOIN dbo.tblItems it WITH (NOLOCK) ON it.ID = o.ItemID
    LEFT JOIN #dt dt
           ON dt.Id = CASE WHEN ISNULL(o.DiscountTypeID, 0) > 0 THEN o.DiscountTypeID ELSE i.DiscountTypeID END
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(o.Deleted, 0) = 0
      AND    (ISNULL(o.Discount, 0) > 0 OR ISNULL(i.Discount, 0) > 0)
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    GROUP BY ISNULL(dt.DiscountTypeName, N'(none)'), ISNULL(b.branchName, N'-'),
             ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
    ORDER BY [Discount] DESC;

    DROP TABLE #dt;
END
GO

/*---- 4.5 deleted / reuse and deleted / waste -------------------------------
  Two procedures, one query, one flag: Waste = 0 is stock that went back,
  Waste = 1 is stock that was thrown. Kept as two names because the controller
  calls them by name from two different tabs.
----------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.sp_DashbordDeletedReUseWiseItemsData') IS NOT NULL DROP PROCEDURE dbo.sp_DashbordDeletedReUseWiseItemsData;
GO

CREATE PROCEDURE dbo.sp_DashbordDeletedReUseWiseItemsData
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_Dashbord_DeletedItems @FromDate = @FromDate, @ToDate = @ToDate,
                                      @BranchIds = @BranchIds, @Waste = 0;
END
GO

IF OBJECT_ID('dbo.sp_DashbordDeletedWasteWiseItemsData') IS NOT NULL DROP PROCEDURE dbo.sp_DashbordDeletedWasteWiseItemsData;
GO

CREATE PROCEDURE dbo.sp_DashbordDeletedWasteWiseItemsData
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_Dashbord_DeletedItems @FromDate = @FromDate, @ToDate = @ToDate,
                                      @BranchIds = @BranchIds, @Waste = 1;
END
GO

IF OBJECT_ID('dbo.sp_Dashbord_DeletedItems') IS NOT NULL DROP PROCEDURE dbo.sp_Dashbord_DeletedItems;
GO

CREATE PROCEDURE dbo.sp_Dashbord_DeletedItems
      @FromDate  DATETIME       = NULL
    , @ToDate    DATETIME       = NULL
    , @BranchIds NVARCHAR(1000) = NULL
    , @Waste     BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   [Branch]     = ISNULL(b.branchName, N'-')
           , [Invoice No]  = i.InvoiceNo
           , [Item]        = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , [Qty]         = o.Quantity
           , [Amount]      = CAST(ISNULL(o.TotalAmount, 0) AS DECIMAL(18,3))
           , [Deleted On]  = FORMAT(o.DeletedDate, 'dd-MMM-yy hh:mm tt')
           , [Comment]     = o.DeleteOrderComment
           , [Approved By] = u.NAME
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblbranch b  WITH (NOLOCK) ON b.id = i.BranchID
    LEFT JOIN dbo.tblItems  it WITH (NOLOCK) ON it.ID = o.ItemID
    LEFT JOIN dbo.tblUser   u  WITH (NOLOCK) ON CAST(u.ID AS NVARCHAR(50)) = o.DeletePasswordUserID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(o.Deleted, 0) = 1
      AND    ISNULL(o.Waste, 0)   = @Waste
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    ORDER BY o.DeletedDate DESC;
END
GO

PRINT 'Dashboard drill-down procs created.';
GO


/*==============================================================================
  SMOKE TEST - today, no filters. Sixteen result sets from the first one.
==============================================================================*/
EXEC dbo.sp_DashboardFilter @CountryId = 1;
EXEC dbo.sp_DashbordSalesData @FromDate = NULL, @ToDate = NULL, @IsDefaultLoad = 1;
GO
