/**********************************************************************************
  POS_23_StatusFacetCounts.sql
  ------------------------------------------------------------------------------
  Adds a fourth result set to sp_POS_GetOrderFacets: how many orders sit in each
  order status.

  The status panel is now drawn as an icon list with a count beside each entry,
  the way the brand / branch / invoice-type panels already are. Those counts had
  no source - the status list came from Lookups, which returns names and colours
  and nothing else - so the number had to come from here.

  Two things change in the working set, and both matter:

    1. The status filter is no longer applied when #scoped is built. It is
       applied per group instead. That is the same rule the other three groups
       already follow: a group is counted with every filter EXCEPT its own, so
       ticking "In Kitchen" does not reduce every other status to zero. The
       brand / branch / type counts are unchanged - they now carry the status
       condition on their own joins.

    2. Deleted orders stay in the working set, flagged. The other three groups
       exclude them exactly as before, but the status counts include them -
       otherwise the "Deleted" status permanently reads 0, which looks like a
       fault rather than a filter.

  Run after POS_13_FacetsFix.sql. Safe to re-run.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

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
    , @ScheduledOnly  BIT           = 0    -- 1 = only orders whose DeliveryDate is a later calendar day than InvoiceDate
AS
BEGIN
    SET NOCOUNT ON;

    /*---- date window ----------------------------------------------------*/
    DECLARE @dFrom DATETIME, @dTo DATETIME, @Today DATE = CAST(GETDATE() AS DATE);
    IF      @DateMode = 'Today'  BEGIN SET @dFrom = @Today;                SET @dTo = DATEADD(DAY,1,@Today); END
    ELSE IF @DateMode = 'Future' BEGIN SET @dFrom = DATEADD(DAY,1,@Today); SET @dTo = NULL; END
    ELSE IF @DateMode = 'Past'   BEGIN SET @dFrom = NULL;                  SET @dTo = @Today; END
    ELSE IF @DateMode = 'Range'  BEGIN SET @dFrom = @FromDate;             SET @dTo = DATEADD(DAY,1,@ToDate); END
    -- 'All' leaves both NULL

    /*---- CSV filters ----------------------------------------------------*/
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

    /*---- working set: date + search + payment only ----------------------
      Status is NOT applied here any more (each group applies it, except the
      status group itself), and deleted rows are kept but flagged.
    ---------------------------------------------------------------------*/
    IF OBJECT_ID('tempdb..#scoped') IS NOT NULL DROP TABLE #scoped;

    CREATE TABLE #scoped
    (
          InvoiceNo   BIGINT PRIMARY KEY
        , BrandID     INT NULL
        , BranchID    INT NULL
        , InvoiceType INT NULL
        , StatusID    INT NULL
        , IsDeleted   BIT NOT NULL
    );

    INSERT INTO #scoped (InvoiceNo, BrandID, BranchID, InvoiceType, StatusID, IsDeleted)
    SELECT     i.InvoiceNo, i.BrandID, i.BranchID, i.InvoiceType
             , i.OrderStatusID, CAST(ISNULL(i.Deleted,0) AS BIT)
    FROM       dbo.tblInvoice i
    LEFT JOIN  dbo.tblCustomerAddress ca ON ca.AddressID = i.AddressID
    LEFT JOIN  dbo.tblArea            ar ON ar.AreaID    = ca.AreaID
    OUTER APPLY (SELECT Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0) pay
    WHERE   (@dFrom IS NULL OR i.InvoiceDate >= @dFrom)
      AND   (@dTo   IS NULL OR i.InvoiceDate <  @dTo)
      AND   (@SearchLike IS NULL
             OR i.TrackingCode LIKE @SearchLike
             OR i.CustomerName LIKE @SearchLike
             OR i.MobileText   LIKE @SearchLike
             OR ar.AreaName    LIKE @SearchLike
             OR (@SearchNum IS NOT NULL AND (i.InvoiceNo = @SearchNum OR i.Mobile = @SearchNum OR i.RunningOrder = @SearchNum)))
      AND   (@PaymentStatus IS NULL
             OR (@PaymentStatus = 'Unpaid'  AND ISNULL(pay.Paid,0) <= 0)
             OR (@PaymentStatus = 'Paid'    AND ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0))
             OR (@PaymentStatus = 'Partial' AND ISNULL(pay.Paid,0) > 0
                                           AND ISNULL(pay.Paid,0) + 0.001 < i.FinalAmount + ISNULL(i.DeliveryCharges,0)))
      -- Same rule as sp_POS_GetOrders: a later calendar day, not just a later
      -- time slot the same day. Raw i.DeliveryDate - NULL is never scheduled.
      AND   (@ScheduledOnly = 0 OR CAST(i.DeliveryDate AS DATE) > CAST(i.InvoiceDate AS DATE));

    CREATE NONCLUSTERED INDEX IX_scoped ON #scoped (BrandID, BranchID, InvoiceType, StatusID);

    /*======================================================================
      Each group is counted with every filter applied EXCEPT ITS OWN, so a
      tick never hides the other options in the same group. Rows with a zero
      count are still returned: the panel keeps a stable shape instead of
      items appearing and vanishing as filters change.

      LEFT JOIN, not INNER: a brand with no orders today must still be listed.
    ======================================================================*/

    -- 0: brands (respects branch + type + status)
    SELECT   BrandID   = br.BrandID
           , BrandName = ISNULL(br.BrandName, N'-')
           , Cnt       = COUNT(s.InvoiceNo)
    FROM     dbo.tblBrand br
    LEFT JOIN #scoped s
           ON s.BrandID = br.BrandID
          AND s.IsDeleted = 0
          AND (@AnyBranch = 1 OR s.BranchID    IN (SELECT Value FROM @Branches))
          AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
          AND (@AnyStatus = 1 OR s.StatusID    IN (SELECT Value FROM @Statuses))
    GROUP BY br.BrandID, br.BrandName, br.BrandSeq
    ORDER BY ISNULL(br.BrandSeq, 9999), br.BrandName;

    -- 1: branches (respects brand + type + status)
    SELECT   BranchID   = b.id
           , BranchName = ISNULL(b.branchName, N'-')
           , BrandID    = b.brandId
           , Cnt        = COUNT(s.InvoiceNo)
    FROM     dbo.tblbranch b
    LEFT JOIN #scoped s
           ON s.BranchID = b.id
          AND s.IsDeleted = 0
          AND (@AnyBrand  = 1 OR s.BrandID     IN (SELECT Value FROM @Brands))
          AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
          AND (@AnyStatus = 1 OR s.StatusID    IN (SELECT Value FROM @Statuses))
    WHERE    ISNULL(b.IsDeleted,0) = 0
    GROUP BY b.id, b.branchName, b.brandId, b.SEQ_NUM
    ORDER BY ISNULL(b.SEQ_NUM, 9999), b.branchName;

    -- 2: invoice types (respects brand + branch + status)
    SELECT   InvoiceTypeID   = it.ID
           , InvoiceTypeName = ISNULL(it.Name, N'-')
           , Cnt             = COUNT(s.InvoiceNo)
    FROM     dbo.tblInvoiceType_Master it
    LEFT JOIN #scoped s
           ON s.InvoiceType = it.ID
          AND s.IsDeleted = 0
          AND (@AnyBrand  = 1 OR s.BrandID  IN (SELECT Value FROM @Brands))
          AND (@AnyBranch = 1 OR s.BranchID IN (SELECT Value FROM @Branches))
          AND (@AnyStatus = 1 OR s.StatusID IN (SELECT Value FROM @Statuses))
    GROUP BY it.ID, it.Name
    ORDER BY it.ID;

    -- 3: order statuses (respects brand + branch + type, NOT status)
    --
    -- Deleted rows are counted here so the "Deleted" entry shows a real
    -- number. Every status row in the table is returned, ticked or not, in the
    -- same order the panel lists them.
    SELECT   OrderStatusID   = os.OrderStatusID
           , OrderStatusName = ISNULL(os.OrderStatusName, N'-')
           , Cnt             = COUNT(s.InvoiceNo)
    FROM     dbo.tblOrderStatus os
    LEFT JOIN #scoped s
           ON s.StatusID = os.OrderStatusID
          AND (@AnyBrand  = 1 OR s.BrandID     IN (SELECT Value FROM @Brands))
          AND (@AnyBranch = 1 OR s.BranchID    IN (SELECT Value FROM @Branches))
          AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
    GROUP BY os.OrderStatusID, os.OrderStatusName, os.SortOrder
    ORDER BY ISNULL(os.SortOrder, 9999), os.OrderStatusID;

    DROP TABLE #scoped;
END
GO

PRINT 'sp_POS_GetOrderFacets updated - status counts added as result set 3.';
GO

/*==============================================================================
  Smoke test. Four result sets: brands, branches, invoice types, statuses.
==============================================================================*/
EXEC dbo.sp_POS_GetOrderFacets @DateMode = 'All';
GO
