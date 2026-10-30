/**********************************************************************************
  POS_13_FacetsFix.sql
  ------------------------------------------------------------------------------
  Fixes sp_POS_GetOrderFacets, which returned nothing and left the Brands /
  Branches / Invoice Types panel empty.

  THE BUG
  -------
  POS_12 built the working set as a common table expression and then ran THREE
  SELECTs against it:

      ;WITH base AS (...), scoped AS (...)
      SELECT ... FROM scoped ...;     -- brands      <- only this one is legal
      SELECT ... FROM scoped ...;     -- branches    <- "Invalid object name"
      SELECT ... FROM scoped ...;     -- types       <- "Invalid object name"

  A CTE is scoped to the SINGLE statement that follows it. The second and third
  SELECTs referenced a name that no longer existed, so the proc threw at
  runtime. Deferred name resolution meant CREATE PROCEDURE succeeded without
  complaint, so the mistake only surfaced as an empty filter panel.

  THE FIX
  -------
  Materialise the working set into a #temp table once, then read it three
  times. This is also faster: three correlated subqueries over a CTE would have
  re-evaluated the whole expression on every pass, whereas the temp table is
  built once and indexed.
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

    /*---- working set: every filter EXCEPT brand / branch / type ---------*/
    IF OBJECT_ID('tempdb..#scoped') IS NOT NULL DROP TABLE #scoped;

    CREATE TABLE #scoped
    (
          InvoiceNo   BIGINT PRIMARY KEY
        , BrandID     INT NULL
        , BranchID    INT NULL
        , InvoiceType INT NULL
    );

    INSERT INTO #scoped (InvoiceNo, BrandID, BranchID, InvoiceType)
    SELECT     i.InvoiceNo, i.BrandID, i.BranchID, i.InvoiceType
    FROM       dbo.tblInvoice i
    LEFT JOIN  dbo.tblCustomerAddress ca ON ca.AddressID = i.AddressID
    LEFT JOIN  dbo.tblArea            ar ON ar.AreaID    = ca.AreaID
    OUTER APPLY (SELECT Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0) pay
    WHERE   ISNULL(i.Deleted,0) = 0
      AND   (@AnyStatus = 1 OR i.OrderStatusID IN (SELECT Value FROM @Statuses))
      AND   (@dFrom IS NULL OR i.InvoiceDate >= @dFrom)
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
                                           AND ISNULL(pay.Paid,0) + 0.001 < i.FinalAmount + ISNULL(i.DeliveryCharges,0)));

    CREATE NONCLUSTERED INDEX IX_scoped ON #scoped (BrandID, BranchID, InvoiceType);

    /*======================================================================
      Each group is counted with every filter applied EXCEPT ITS OWN, so a
      tick never hides the other options in the same group. Rows with a zero
      count are still returned: the panel keeps a stable shape instead of
      items appearing and vanishing as filters change.

      LEFT JOIN, not INNER: a brand with no orders today must still be listed.
    ======================================================================*/

    -- 0: brands (respects branch + type)
    SELECT   BrandID   = br.BrandID
           , BrandName = ISNULL(br.BrandName, N'-')
           , Cnt       = COUNT(s.InvoiceNo)
    FROM     dbo.tblBrand br
    LEFT JOIN #scoped s
           ON s.BrandID = br.BrandID
          AND (@AnyBranch = 1 OR s.BranchID    IN (SELECT Value FROM @Branches))
          AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
    GROUP BY br.BrandID, br.BrandName, br.BrandSeq
    ORDER BY ISNULL(br.BrandSeq, 9999), br.BrandName;

    -- 1: branches (respects brand + type)
    SELECT   BranchID   = b.id
           , BranchName = ISNULL(b.branchName, N'-')
           , BrandID    = b.brandId
           , Cnt        = COUNT(s.InvoiceNo)
    FROM     dbo.tblbranch b
    LEFT JOIN #scoped s
           ON s.BranchID = b.id
          AND (@AnyBrand = 1 OR s.BrandID     IN (SELECT Value FROM @Brands))
          AND (@AnyIType = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
    WHERE    ISNULL(b.IsDeleted,0) = 0
    GROUP BY b.id, b.branchName, b.brandId, b.SEQ_NUM
    ORDER BY ISNULL(b.SEQ_NUM, 9999), b.branchName;

    -- 2: invoice types (respects brand + branch)
    SELECT   InvoiceTypeID   = it.ID
           , InvoiceTypeName = ISNULL(it.Name, N'-')
           , Cnt             = COUNT(s.InvoiceNo)
    FROM     dbo.tblInvoiceType_Master it
    LEFT JOIN #scoped s
           ON s.InvoiceType = it.ID
          AND (@AnyBrand  = 1 OR s.BrandID  IN (SELECT Value FROM @Brands))
          AND (@AnyBranch = 1 OR s.BranchID IN (SELECT Value FROM @Branches))
    GROUP BY it.ID, it.Name
    ORDER BY it.ID;

    DROP TABLE #scoped;
END
GO

PRINT 'sp_POS_GetOrderFacets fixed.';
GO

/**********************************************************************************
  VERIFY - all three result sets must come back, with rows even when the counts
  are zero. Before the fix, sets 1 and 2 threw "Invalid object name 'scoped'".
**********************************************************************************/
EXEC dbo.sp_POS_GetOrderFacets @DateMode = 'All';
GO

PRINT '';
PRINT 'Source data behind the panel (if these are empty, the panel will be too):';
SELECT Brands = (SELECT COUNT(*) FROM dbo.tblBrand)
     , Branches = (SELECT COUNT(*) FROM dbo.tblbranch WHERE ISNULL(IsDeleted,0) = 0)
     , InvoiceTypes = (SELECT COUNT(*) FROM dbo.tblInvoiceType_Master)
     , Invoices = (SELECT COUNT(*) FROM dbo.tblInvoice WHERE ISNULL(Deleted,0) = 0);
GO
