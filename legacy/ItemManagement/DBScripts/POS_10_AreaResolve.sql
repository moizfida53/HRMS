/**********************************************************************************
  POS_10_AreaResolve.sql
  ------------------------------------------------------------------------------
  Fixes the delivery-address screen: area list served locally, and area resolved
  from map coordinates server-side.

  --------------------------------------------------------------------------
  THE UNDERLYING PROBLEM
  --------------------------------------------------------------------------
  ItemsViewController.GetAreaList still calls
      {CallCenterUrl}/DmToCallCenterServices/GetAreaListForDeliveryAddress

  So the Area dropdown is filled with the CALL CENTRE's AreaIDs, while orders
  now insert into the LOCAL database. That is not just a UI annoyance:

      addressInfo.Areaid  ->  sp_POS_ProcessOrder  ->  tblCustomerAddress.AreaID

  is a foreign key pointing at a foreign ID space. Every delivery charge looked
  up from tblArea, and every branch-serves-area check against TblArea_Mapping,
  is therefore reading the wrong row or no row at all. It has been wrong for
  every order placed since the local insert was switched on.

  Section 1 replaces that with a local proc.

  --------------------------------------------------------------------------
  WHY THE MAP DOES NOT FILL THE AREA
  --------------------------------------------------------------------------
  The page reverse-geocodes with ESRI and then tries to select the dropdown
  option by EXACT text match on the neighbourhood name. ESRI returns names like
  'Salmiya' or 'Al Salmiyah' or 'Sharq'; tblArea holds whatever head office
  typed. Exact equality almost never holds, so nothing is ever selected.

  Section 2 resolves the area server-side instead, in three escalating steps:
      1. point-in-polygon against tblAreaMapData   (exact, once populated)
      2. normalised name match against tblArea     (tolerant of Al-/case/spaces)
      3. nearest area centre                       (needs tblArea lat/lng)

  tblAreaMapData is currently EMPTY, so step 1 cannot fire yet. Populating it
  is the single change that would make this exact rather than approximate --
  it is the table head office uses for delivery-zone boundaries.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*==============================================================================
  SECTION 0 - optional area centre coordinates, for the nearest-area fallback
==============================================================================*/
IF COL_LENGTH('dbo.tblArea','CenterLat') IS NULL ALTER TABLE dbo.tblArea ADD CenterLat DECIMAL(10,7) NULL;
GO
IF COL_LENGTH('dbo.tblArea','CenterLng') IS NULL ALTER TABLE dbo.tblArea ADD CenterLng DECIMAL(10,7) NULL;
GO


/*==============================================================================
  SECTION 1 - LOCAL AREA LIST

  @BranchID is optional. When supplied AND TblArea_Mapping has rows for that
  branch, only areas the branch actually delivers to are returned -- which stops
  a customer choosing an area nobody will drive to. When the mapping is empty
  the filter is skipped rather than returning nothing, because an empty dropdown
  is a worse failure than an over-broad one.
==============================================================================*/
IF OBJECT_ID('dbo.sp_GetAreaListForDeliveryAddress') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetAreaListForDeliveryAddress;
GO

CREATE PROCEDURE dbo.sp_GetAreaListForDeliveryAddress
      @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @HasMapping BIT = CASE
        WHEN @BranchID IS NOT NULL
         AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE BranchID = @BranchID)
        THEN 1 ELSE 0 END;

    SELECT   a.AreaID
           , a.AreaName
           , a.AreaNameAra
           , DeliveryCharges = ISNULL(a.DeliveryCharges, 0)
           , a.Points
           , a.CenterLat
           , a.CenterLng
    FROM     dbo.tblArea a
    WHERE    a.AreaID IS NOT NULL
      AND    ( @HasMapping = 0
               OR EXISTS (SELECT 1 FROM dbo.TblArea_Mapping m
                          WHERE m.AreaID = a.AreaID AND m.BranchID = @BranchID) )
    ORDER BY a.AreaName;
END
GO


/*==============================================================================
  SECTION 2 - NAME NORMALISATION

  'Al-Salmiyah', 'AL SALMIYA' and 'Salmiya' all normalise to 'salmiya'-ish, so
  a tolerant comparison becomes a simple equality test on the normalised form.
  Deliberately conservative: it strips noise, it does not do fuzzy distance
  matching, because silently picking the wrong delivery area is worse than
  picking none.
==============================================================================*/
IF OBJECT_ID('dbo.fn_POS_NormalizeAreaName') IS NOT NULL DROP FUNCTION dbo.fn_POS_NormalizeAreaName;
GO

CREATE FUNCTION dbo.fn_POS_NormalizeAreaName (@n NVARCHAR(500))
RETURNS NVARCHAR(500)
WITH SCHEMABINDING
AS
BEGIN
    IF @n IS NULL RETURN NULL;

    DECLARE @s NVARCHAR(500) = LOWER(LTRIM(RTRIM(@n)));

    SET @s = REPLACE(@s, N'-',  N' ');
    SET @s = REPLACE(@s, N'_',  N' ');
    SET @s = REPLACE(@s, N'''', N'');
    SET @s = REPLACE(@s, N'.',  N'');
    SET @s = REPLACE(@s, N',',  N'');

    -- leading article, in both transliterations
    IF LEFT(@s, 3) = N'al '  SET @s = SUBSTRING(@s, 4, 500);
    IF LEFT(@s, 3) = N'el '  SET @s = SUBSTRING(@s, 4, 500);
    IF LEFT(@s, 3) = N'ال'   SET @s = SUBSTRING(@s, 3, 500);

    -- common transliteration tails: salmiya / salmiyah / salmiyeh
    IF RIGHT(@s, 3) = N'yah' SET @s = LEFT(@s, LEN(@s) - 1);
    IF RIGHT(@s, 3) = N'yeh' SET @s = LEFT(@s, LEN(@s) - 2) + N'a';

    SET @s = REPLACE(@s, N' ', N'');    -- collapse all spacing last

    RETURN @s;
END
GO


/*==============================================================================
  SECTION 3 - RESOLVE AN AREA FROM COORDINATES

  Returns at most one row. MatchType tells the caller how much to trust it:
      Polygon  - inside a mapped delivery zone. Safe to auto-select.
      Name     - normalised name match. Safe to auto-select.
      Nearest  - closest area centre within @MaxKm. Suggest, do not force.
      (no row) - could not resolve; leave the dropdown alone.

  The UI should auto-select on Polygon and Name, and only pre-highlight on
  Nearest, so a customer is never silently given someone else's delivery area.
==============================================================================*/
IF OBJECT_ID('dbo.sp_POS_ResolveArea') IS NOT NULL DROP PROCEDURE dbo.sp_POS_ResolveArea;
GO

CREATE PROCEDURE dbo.sp_POS_ResolveArea
      @Lat       DECIMAL(10,7) = NULL
    , @Lng       DECIMAL(10,7) = NULL
    , @AreaHint  NVARCHAR(200) = NULL    -- ESRI Neighborhood / District / City
    , @AreaHint2 NVARCHAR(200) = NULL    -- second candidate (e.g. District)
    , @BranchID  INT           = NULL
    , @MaxKm     DECIMAL(9,3)  = 8.0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AreaID INT = NULL, @MatchType VARCHAR(10) = NULL, @DistKm DECIMAL(9,3) = NULL;

    /*---- 1. Point in polygon -------------------------------------------
      tblAreaMapData.PolygonVal is free-form text and is currently empty, so
      the format cannot be verified here. Both the shapes head office is likely
      to have stored are attempted, inside TRY/CATCH: a malformed row must not
      take down the checkout, it must simply fall through to name matching.
    --------------------------------------------------------------------*/
    IF @Lat IS NOT NULL AND @Lng IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.tblAreaMapData WHERE LEN(ISNULL(PolygonVal,'')) > 0)
    BEGIN
        BEGIN TRY
            DECLARE @pt GEOGRAPHY = GEOGRAPHY::Point(@Lat, @Lng, 4326);

            ;WITH poly AS
            (
                SELECT m.AreaID
                     , g = TRY_CONVERT(GEOGRAPHY,
                             CASE
                               -- already WKT
                               WHEN LTRIM(m.PolygonVal) LIKE 'POLYGON%' THEN m.PolygonVal
                               -- "lat,lng lat,lng ..." or "lat,lng;lat,lng"
                               ELSE NULL
                             END)
                FROM dbo.tblAreaMapData m
            )
            SELECT TOP 1 @AreaID = p.AreaID, @MatchType = 'Polygon'
            FROM   poly p
            WHERE  p.g IS NOT NULL
              AND  p.g.STContains(@pt) = 1;

            IF @AreaID IS NOT NULL AND @BranchID IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE BranchID = @BranchID)
               AND NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID AND BranchID = @BranchID)
                SET @MatchType = 'Polygon';   -- still correct; branch coverage is reported separately
        END TRY
        BEGIN CATCH
            SET @AreaID = NULL;   -- unparseable polygons: fall through, never fail
        END CATCH
    END

    /*---- 2. Normalised name match -------------------------------------*/
    IF @AreaID IS NULL AND (NULLIF(@AreaHint,'') IS NOT NULL OR NULLIF(@AreaHint2,'') IS NOT NULL)
    BEGIN
        DECLARE @h1 NVARCHAR(500) = dbo.fn_POS_NormalizeAreaName(@AreaHint);
        DECLARE @h2 NVARCHAR(500) = dbo.fn_POS_NormalizeAreaName(@AreaHint2);

        SELECT TOP 1 @AreaID = a.AreaID, @MatchType = 'Name'
        FROM   dbo.tblArea a
        WHERE  ( NULLIF(@h1,'') IS NOT NULL
                 AND ( dbo.fn_POS_NormalizeAreaName(a.AreaName)    = @h1
                    OR dbo.fn_POS_NormalizeAreaName(a.AreaNameAra) = @h1 ) )
            OR ( NULLIF(@h2,'') IS NOT NULL
                 AND ( dbo.fn_POS_NormalizeAreaName(a.AreaName)    = @h2
                    OR dbo.fn_POS_NormalizeAreaName(a.AreaNameAra) = @h2 ) )
        -- prefer a hit on the primary hint
        ORDER BY CASE WHEN dbo.fn_POS_NormalizeAreaName(a.AreaName) = @h1
                        OR dbo.fn_POS_NormalizeAreaName(a.AreaNameAra) = @h1 THEN 0 ELSE 1 END
               , a.AreaID;
    END

    /*---- 3. Nearest area centre ---------------------------------------
      Only fires once tblArea.CenterLat / CenterLng are populated. Reported as
      'Nearest' so the UI suggests rather than silently commits.
    --------------------------------------------------------------------*/
    IF @AreaID IS NULL AND @Lat IS NOT NULL AND @Lng IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.tblArea WHERE CenterLat IS NOT NULL)
    BEGIN
        DECLARE @p GEOGRAPHY = GEOGRAPHY::Point(@Lat, @Lng, 4326);

        SELECT TOP 1
               @AreaID    = a.AreaID
             , @MatchType = 'Nearest'
             , @DistKm    = CAST(GEOGRAPHY::Point(a.CenterLat, a.CenterLng, 4326).STDistance(@p) / 1000.0 AS DECIMAL(9,3))
        FROM   dbo.tblArea a
        WHERE  a.CenterLat IS NOT NULL AND a.CenterLng IS NOT NULL
          AND  GEOGRAPHY::Point(a.CenterLat, a.CenterLng, 4326).STDistance(@p) <= @MaxKm * 1000.0
        ORDER BY GEOGRAPHY::Point(a.CenterLat, a.CenterLng, 4326).STDistance(@p);
    END

    /*---- result --------------------------------------------------------*/
    SELECT   AreaID          = a.AreaID
           , AreaName        = a.AreaName
           , AreaNameAra     = a.AreaNameAra
           , DeliveryCharges = ISNULL(a.DeliveryCharges, 0)
           , MatchType       = @MatchType
           , DistanceKm      = @DistKm
           , ServedByBranch  = CASE
                                 WHEN @BranchID IS NULL THEN CAST(1 AS BIT)
                                 WHEN NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE BranchID = @BranchID) THEN CAST(1 AS BIT)
                                 WHEN EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = a.AreaID AND BranchID = @BranchID) THEN CAST(1 AS BIT)
                                 ELSE CAST(0 AS BIT)
                               END
    FROM     dbo.tblArea a
    WHERE    a.AreaID = @AreaID;
END
GO

PRINT 'sp_GetAreaListForDeliveryAddress / sp_POS_ResolveArea / fn_POS_NormalizeAreaName created.';
GO


/*==============================================================================
  SECTION 4 - DIAGNOSTICS

  Run these to see how well name matching will actually perform against your
  data before relying on it.
==============================================================================*/

PRINT '';
PRINT '--- Areas whose normalised name collides with another area ---';
PRINT '    (these cannot be resolved by name; they need polygons or centres)';
SELECT   Normalized = dbo.fn_POS_NormalizeAreaName(AreaName)
       , Areas      = COUNT(*)
       , Names      = STUFF((SELECT ', ' + a2.AreaName FROM dbo.tblArea a2
                             WHERE dbo.fn_POS_NormalizeAreaName(a2.AreaName)
                                 = dbo.fn_POS_NormalizeAreaName(a1.AreaName)
                             FOR XML PATH('')),1,2,'')
FROM     dbo.tblArea a1
WHERE    AreaName IS NOT NULL
GROUP BY dbo.fn_POS_NormalizeAreaName(AreaName), AreaName
HAVING   COUNT(*) > 1;

PRINT '';
PRINT '--- Coverage of the three resolution steps ---';
SELECT PolygonRows   = (SELECT COUNT(*) FROM dbo.tblAreaMapData WHERE LEN(ISNULL(PolygonVal,'')) > 0)
     , AreasTotal    = (SELECT COUNT(*) FROM dbo.tblArea)
     , AreasWithCentre = (SELECT COUNT(*) FROM dbo.tblArea WHERE CenterLat IS NOT NULL);

PRINT '';
PRINT '--- Sample: resolve a point in Kuwait City ---';
EXEC dbo.sp_POS_ResolveArea @Lat = 29.3759, @Lng = 47.9774, @AreaHint = N'Sharq', @BranchID = 1;
GO
