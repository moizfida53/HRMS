/**********************************************************************************
  POS_12_GridV2.sql
  ------------------------------------------------------------------------------
  Order List v2: brand / branch / invoice-type facets, and the columns the
  screen actually shows.

  Run after POS_09_ActionProcs.sql.

      sp_POS_GetOrders        + @BrandIDs, @InvoiceTypeIDs
                              + BrandName, InvoiceTypeName, DriverName, AreaName
      sp_POS_GetOrderFacets   counts per brand / branch / invoice type

  ON THE FACET COUNTS
  -------------------
  Each facet group is counted with every filter applied EXCEPT its own. That is
  what makes a filter panel usable: ticking "Take Away" must not collapse the
  Invoice Type counts to a single row, or you can never widen your selection
  again without clearing everything. Brand counts respect the branch filter,
  branch counts respect the brand filter, and so on.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  1. sp_POS_GetOrders  (v2)
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

    /* whitelisted sort - user input never reaches the SQL text */
    DECLARE @OrderBy NVARCHAR(200) =
        CASE UPPER(@SortCol)
            WHEN 'INVOICENO'    THEN 'i.InvoiceNo'
            WHEN 'INVOICETYPE'  THEN 'it.Name'
            WHEN 'CUSTOMERNAME' THEN 'i.CustomerName'
            WHEN 'MOBILE'       THEN 'i.MobileText'
            WHEN 'AREANAME'     THEN 'ar.AreaName'
            WHEN 'DELIVERYDATE' THEN 'ISNULL(i.DeliveryDate, i.InvoiceDate)'
            WHEN 'INVOICEDATE'  THEN 'i.InvoiceDate'
            WHEN 'AMOUNT'       THEN '(i.FinalAmount + ISNULL(i.DeliveryCharges,0))'
            WHEN 'DRIVERNAME'   THEN 'i.DriverName'
            WHEN 'BRANDNAME'    THEN 'br.BrandName'
            WHEN 'BRANCHNAME'   THEN 'b.branchName'
            WHEN 'ORDERSTATUS'  THEN 'i.OrderStatusID'
            ELSE 'i.InvoiceDate'
        END
      + CASE WHEN UPPER(ISNULL(@SortDir,'DESC')) = 'ASC' THEN ' ASC' ELSE ' DESC' END
      + ', i.InvoiceNo DESC';

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

    DECLARE @sql NVARCHAR(MAX) = N'
    SELECT
          TotalRows       = COUNT(*) OVER ()
        , i.InvoiceNo
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
    ORDER BY ' + @OrderBy + N'
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY
    OPTION (RECOMPILE);';

    EXEC sp_executesql @sql,
        N'@IncludeDeleted BIT, @AnyBrand BIT, @AnyBranch BIT, @AnyIType BIT, @AnyStatus BIT,
          @dFrom DATETIME, @dTo DATETIME, @OrderType INT, @PaymentTypeID INT, @SourceID INT, @DriverID INT,
          @MinAmount DECIMAL(18,3), @MaxAmount DECIMAL(18,3), @SearchLike NVARCHAR(102), @SearchNum BIGINT,
          @PaymentStatus VARCHAR(10), @Skip INT, @Take INT,
          @Brands dbo.TVP_POS_IntList READONLY, @Branches dbo.TVP_POS_IntList READONLY,
          @ITypes dbo.TVP_POS_IntList READONLY, @Statuses dbo.TVP_POS_IntList READONLY',
        @IncludeDeleted, @AnyBrand, @AnyBranch, @AnyIType, @AnyStatus,
        @dFrom, @dTo, @OrderType, @PaymentTypeID, @SourceID, @DriverID,
        @MinAmount, @MaxAmount, @SearchLike, @SearchNum, @PaymentStatus, @Skip, @Take,
        @Brands, @Branches, @ITypes, @Statuses;
END
GO


/*==============================================================================
  2. sp_POS_GetOrderFacets

  Three result sets: brands, branches, invoice types - each with a live count.

  Every group EXCLUDES ITS OWN filter, so a tick never hides the other options
  in the same group. Tick "Take Away" and the Invoice Type list still shows
  Dine-In and Call Centre with their counts, ready to be added.

  Rows with zero are still returned, so the panel keeps a stable shape instead
  of items appearing and vanishing as filters change.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_GetOrderFacets') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GetOrderFacets;
GO

CREATE PROCEDURE dbo.sp_POS_GetOrderFacets
      @BrandIDs       VARCHAR(200)  = NULL
    , @BranchIDs      VARCHAR(200)  = NULL
    , @InvoiceTypeIDs VARCHAR(200)  = NULL
    , @StatusIDs      VARCHAR(200)  = NULL
    , @DateMode       VARCHAR(10)   = 'Today'
    , @FromDate       DATE          = NULL
    , @ToDate         DATE          = NULL
    , @Search         NVARCHAR(100) = NULL
    , @PaymentStatus  VARCHAR(10)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @dFrom DATETIME, @dTo DATETIME, @Today DATE = CAST(GETDATE() AS DATE);
    IF      @DateMode = 'Today'  BEGIN SET @dFrom = @Today;                SET @dTo = DATEADD(DAY,1,@Today); END
    ELSE IF @DateMode = 'Future' BEGIN SET @dFrom = DATEADD(DAY,1,@Today); SET @dTo = NULL; END
    ELSE IF @DateMode = 'Past'   BEGIN SET @dFrom = NULL;                  SET @dTo = @Today; END
    ELSE IF @DateMode = 'Range'  BEGIN SET @dFrom = @FromDate;             SET @dTo = DATEADD(DAY,1,@ToDate); END

    DECLARE @Brands dbo.TVP_POS_IntList, @Branches dbo.TVP_POS_IntList,
            @ITypes dbo.TVP_POS_IntList, @Statuses dbo.TVP_POS_IntList;

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

    /* everything except the brand / branch / type filters */
    ;WITH base AS
    (
        SELECT i.InvoiceNo, i.BrandID, i.BranchID, i.InvoiceType,
               Paid = ISNULL((SELECT SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                              FROM dbo.tblInvoicePayment p
                              WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0), 0),
               Due  = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        FROM      dbo.tblInvoice i
        LEFT JOIN dbo.tblCustomerAddress ca ON ca.AddressID = i.AddressID
        LEFT JOIN dbo.tblArea            ar ON ar.AreaID    = ca.AreaID
        WHERE  ISNULL(i.Deleted,0) = 0
          AND  (@AnyStatus = 1 OR i.OrderStatusID IN (SELECT Value FROM @Statuses))
          AND  (@dFrom IS NULL OR i.InvoiceDate >= @dFrom)
          AND  (@dTo   IS NULL OR i.InvoiceDate <  @dTo)
          AND  (@SearchLike IS NULL
                OR i.TrackingCode LIKE @SearchLike
                OR i.CustomerName LIKE @SearchLike
                OR i.MobileText   LIKE @SearchLike
                OR ar.AreaName    LIKE @SearchLike
                OR (@SearchNum IS NOT NULL AND (i.InvoiceNo = @SearchNum OR i.Mobile = @SearchNum OR i.RunningOrder = @SearchNum)))
    ),
    scoped AS
    (
        SELECT * FROM base
        WHERE (@PaymentStatus IS NULL
               OR (@PaymentStatus = 'Unpaid'  AND Paid <= 0)
               OR (@PaymentStatus = 'Paid'    AND Paid + 0.001 >= Due)
               OR (@PaymentStatus = 'Partial' AND Paid > 0 AND Paid + 0.001 < Due))
    )

    -- 0: brands  (respects branch + type, not brand)
    SELECT   BrandID   = br.BrandID
           , BrandName = br.BrandName
           , Cnt       = (SELECT COUNT(*) FROM scoped s
                          WHERE s.BrandID = br.BrandID
                            AND (@AnyBranch = 1 OR s.BranchID    IN (SELECT Value FROM @Branches))
                            AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes)))
    FROM     dbo.tblBrand br
    ORDER BY br.BrandSeq, br.BrandName;

    -- 1: branches  (respects brand + type, not branch)
    SELECT   BranchID   = b.id
           , BranchName = b.branchName
           , BrandID    = b.brandId
           , Cnt        = (SELECT COUNT(*) FROM scoped s
                           WHERE s.BranchID = b.id
                             AND (@AnyBrand = 1 OR s.BrandID     IN (SELECT Value FROM @Brands))
                             AND (@AnyIType = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes)))
    FROM     dbo.tblbranch b
    WHERE    ISNULL(b.IsDeleted,0) = 0
    ORDER BY ISNULL(b.SEQ_NUM, 9999), b.branchName;

    -- 2: invoice types  (respects brand + branch, not type)
    SELECT   InvoiceTypeID   = it.ID
           , InvoiceTypeName = it.Name
           , Cnt             = (SELECT COUNT(*) FROM scoped s
                                WHERE s.InvoiceType = it.ID
                                  AND (@AnyBrand  = 1 OR s.BrandID  IN (SELECT Value FROM @Brands))
                                  AND (@AnyBranch = 1 OR s.BranchID IN (SELECT Value FROM @Branches)))
    FROM     dbo.tblInvoiceType_Master it
    ORDER BY it.ID;
END
GO

PRINT 'sp_POS_GetOrders (v2) / sp_POS_GetOrderFacets created.';
GO

/* Smoke test:
   EXEC dbo.sp_POS_GetOrders   @DateMode='All', @Take=25;
   EXEC dbo.sp_POS_GetOrderFacets @DateMode='All';
   EXEC dbo.sp_POS_GetOrders   @DateMode='All', @InvoiceTypeIDs='1', @BranchIDs='1';
*/
