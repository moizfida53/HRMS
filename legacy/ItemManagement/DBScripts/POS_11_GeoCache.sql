/**********************************************************************************
  POS_11_GeoCache.sql
  ------------------------------------------------------------------------------
  Cache for reverse-geocode lookups used by the delivery-address screen.

  WHY A CACHE IS NOT OPTIONAL HERE
  --------------------------------
  OpenStreetMap's Nominatim is free but rate limited, and its usage policy
  expects roughly one request per second with an identifying User-Agent. A busy
  lunch service tapping a map would blow straight past that and get the site's
  IP blocked -- taking the feature down for every customer at once.

  Coordinates are rounded to 4 decimal places (about 11 metres) before lookup,
  so repeated taps on the same building collapse onto one cache row instead of
  one row per pixel.
**********************************************************************************/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.tblPOS_GeoCache') IS NULL
BEGIN
    CREATE TABLE dbo.tblPOS_GeoCache
    (
          Lat           DECIMAL(10,4)  NOT NULL
        , Lng           DECIMAL(10,4)  NOT NULL
        , Block         NVARCHAR(50)   NULL
        , Neighbourhood NVARCHAR(200)  NULL
        , RawJson       NVARCHAR(MAX)  NULL
        , CreatedOn     DATETIME       NOT NULL CONSTRAINT DF_tblPOS_GeoCache_CreatedOn DEFAULT (GETDATE())
        , HitCount      INT            NOT NULL CONSTRAINT DF_tblPOS_GeoCache_HitCount  DEFAULT (0)
        , CONSTRAINT PK_tblPOS_GeoCache PRIMARY KEY CLUSTERED (Lat, Lng)
    );
    PRINT 'tblPOS_GeoCache created';
END
ELSE PRINT 'tblPOS_GeoCache already exists';
GO


IF OBJECT_ID('dbo.sp_POS_GeoCacheGet') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GeoCacheGet;
GO
CREATE PROCEDURE dbo.sp_POS_GeoCacheGet
      @Lat DECIMAL(10,4)
    , @Lng DECIMAL(10,4)
AS
BEGIN
    SET NOCOUNT ON;

    -- A miss is a row that was never found, not a row that was found empty:
    -- caching "no block here" is correct and stops us asking Nominatim the
    -- same unanswerable question forever.
    UPDATE dbo.tblPOS_GeoCache
       SET HitCount = HitCount + 1
     WHERE Lat = @Lat AND Lng = @Lng;

    SELECT Block, Neighbourhood
    FROM   dbo.tblPOS_GeoCache
    WHERE  Lat = @Lat AND Lng = @Lng
      AND  CreatedOn > DATEADD(DAY, -180, GETDATE());   -- refresh twice a year
END
GO


IF OBJECT_ID('dbo.sp_POS_GeoCacheSet') IS NOT NULL DROP PROCEDURE dbo.sp_POS_GeoCacheSet;
GO
CREATE PROCEDURE dbo.sp_POS_GeoCacheSet
      @Lat           DECIMAL(10,4)
    , @Lng           DECIMAL(10,4)
    , @Block         NVARCHAR(50)  = NULL
    , @Neighbourhood NVARCHAR(200) = NULL
    , @RawJson       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Two customers can tap the same spot at the same moment, so this has to
    -- tolerate a concurrent insert rather than throwing a duplicate key.
    BEGIN TRY
        MERGE dbo.tblPOS_GeoCache WITH (HOLDLOCK) AS t
        USING (SELECT @Lat AS Lat, @Lng AS Lng) AS s
           ON t.Lat = s.Lat AND t.Lng = s.Lng
        WHEN MATCHED THEN
            UPDATE SET Block = @Block, Neighbourhood = @Neighbourhood,
                       RawJson = @RawJson, CreatedOn = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (Lat, Lng, Block, Neighbourhood, RawJson)
            VALUES (@Lat, @Lng, @Block, @Neighbourhood, @RawJson);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;   -- ignore a lost race only
    END CATCH
END
GO

PRINT 'sp_POS_GeoCacheGet / sp_POS_GeoCacheSet created.';
GO

/* Useful later:
   -- how well is the cache working?
   SELECT Rows = COUNT(*), Hits = SUM(HitCount),
          WithBlock = SUM(CASE WHEN Block IS NOT NULL THEN 1 ELSE 0 END)
   FROM dbo.tblPOS_GeoCache;

   -- what did OSM actually return for a spot? (confirms field mapping)
   SELECT TOP 10 Lat, Lng, Block, Neighbourhood, RawJson
   FROM dbo.tblPOS_GeoCache ORDER BY CreatedOn DESC;
*/
