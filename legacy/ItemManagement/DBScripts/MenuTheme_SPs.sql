/* ============================================================================
   Menu Theme  -  Stored Procedures
   ----------------------------------------------------------------------------
   Replaces the inline SQL used by the theme editor / customer menu:
     tblMenuTheme  : EAV rows (Name, Color, BrandID, BranchID) + one row Name='Version'
     tblbrand      : Layout, BannerImage, MobileImage, DesktopImage

   Run this whole script once on the database. It is re-runnable (drops &
   recreates each object). No table schema changes are made here.
   ============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   Table type used to pass the colour rows into sp_SaveMenuTheme in one call.
   (Drop the proc that depends on it first so the type can be recreated.)
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_SaveMenuTheme', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SaveMenuTheme;
GO
IF TYPE_ID(N'dbo.MenuThemeTVP') IS NOT NULL
    DROP TYPE dbo.MenuThemeTVP;
GO
CREATE TYPE dbo.MenuThemeTVP AS TABLE
(
    Name  NVARCHAR(100) NOT NULL,
    Color NVARCHAR(50)  NULL
);
GO

/* ---------------------------------------------------------------------------
   sp_GetMenuTheme  -  read the colour rows for a brand/branch.
   Branch-specific rows are preferred, falling back to brand-level (BranchID=0).
   Used by ItemsViewNewController.LoadMenuColors and MenuColorsController.Index.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_GetMenuTheme', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetMenuTheme;
GO
CREATE PROCEDURE dbo.sp_GetMenuTheme
    @BrandId  INT,
    @BranchId INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  Name, Color
    FROM    dbo.tblMenuTheme
    WHERE   BrandID = @BrandId
      AND  (BranchID = @BranchId OR BranchID = 0)
    ORDER BY CASE WHEN BranchID = @BranchId THEN 0 ELSE 1 END;
END
GO

/* ---------------------------------------------------------------------------
   sp_GetMenuThemeVersion  -  read the theme version (Color of the Name='Version'
   row) used as the CSS cache-buster. Used by LoadMenuColors.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_GetMenuThemeVersion', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetMenuThemeVersion;
GO
CREATE PROCEDURE dbo.sp_GetMenuThemeVersion
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1) Color
    FROM   dbo.tblMenuTheme
    WHERE  Name = 'Version';
END
GO

/* ---------------------------------------------------------------------------
   sp_SaveMenuTheme  -  upsert the colour fields for a brand/branch and bump the
   version row by 1. UPDATEs existing rows, INSERTs only the ones that are
   missing (no delete/re-insert churn -> IDs stay stable).
   Used by MenuColorsController.Save.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_SaveMenuTheme', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SaveMenuTheme;
GO
CREATE PROCEDURE dbo.sp_SaveMenuTheme
    @BrandId  INT,
    @BranchId INT = 0,
    @Items    dbo.MenuThemeTVP READONLY
AS
BEGIN
    SET NOCOUNT ON;

    -- update the fields that already have a row
    UPDATE  t
    SET     t.Color = s.Color
    FROM    dbo.tblMenuTheme t
    INNER JOIN @Items s
        ON  t.Name = s.Name
    WHERE   t.BrandID = @BrandId
      AND   t.BranchID = @BranchId;

    -- insert the fields that don't have a row yet (first save)
    INSERT INTO dbo.tblMenuTheme (Name, Color, BrandID, BranchID)
    SELECT  s.Name, s.Color, @BrandId, @BranchId
    FROM    @Items s
    WHERE   NOT EXISTS (
                SELECT 1 FROM dbo.tblMenuTheme t
                WHERE  t.BrandID = @BrandId
                  AND  t.BranchID = @BranchId
                  AND  t.Name = s.Name
            );

    -- The theme editor (/MenuColors) only ever writes brand-level rows
    -- (@BranchId = 0), but sp_GetMenuTheme PREFERS branch-specific rows. A leftover
    -- BranchID <> 0 row therefore shadows a brand-level edit: the editor and its
    -- preview (which load branch 0) show the new colour while the real menu at
    -- /?id=<brand>,<branch> keeps the old one, so the save looks like it was ignored.
    -- Drop the branch-level copies of the fields being saved so the brand-level
    -- value is the single source of truth.
    IF @BranchId = 0
        DELETE  t
        FROM    dbo.tblMenuTheme t
        INNER JOIN @Items s
            ON  t.Name = s.Name
        WHERE   t.BrandID = @BrandId
          AND   t.BranchID <> 0;

    -- bump the single version row (its Color holds the number)
    UPDATE  dbo.tblMenuTheme
    SET     Color = CAST(ISNULL(TRY_CONVERT(INT, Color), 0) + 1 AS NVARCHAR(50))
    WHERE   Name = 'Version';
END
GO

/* ---------------------------------------------------------------------------
   sp_UpdateBrandLayout  -  save the selected layout to tblbrand.
   Used by MenuColorsController.Save.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_UpdateBrandLayout', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_UpdateBrandLayout;
GO
CREATE PROCEDURE dbo.sp_UpdateBrandLayout
    @BrandId INT,
    @Layout  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.tblbrand
    SET    Layout = @Layout
    WHERE  BrandID = @BrandId;
END
GO

/* ---------------------------------------------------------------------------
   sp_GetBrandImages  -  read the brand banner + desktop image file names
   (for the thumbnails in the editor). Used by MenuColorsController.Index.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_GetBrandImages', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetBrandImages;
GO
CREATE PROCEDURE dbo.sp_GetBrandImages
    @BrandId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT BannerImage, DesktopImage
    FROM   dbo.tblbrand
    WHERE  BrandID = @BrandId;
END
GO

/* ---------------------------------------------------------------------------
   sp_UpdateBrandImage  -  update a brand image file name after an upload.
     @Type = 'desktop' -> DesktopImage
     @Type = 'banner'  -> BannerImage AND MobileImage (they share the file)
   Used by MenuColorsController.UploadBrandImage.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_UpdateBrandImage', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_UpdateBrandImage;
GO
CREATE PROCEDURE dbo.sp_UpdateBrandImage
    @BrandId  INT,
    @Type     NVARCHAR(20),
    @FileName NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Type = 'desktop'
        UPDATE dbo.tblbrand SET DesktopImage = @FileName WHERE BrandID = @BrandId;
    ELSE
        UPDATE dbo.tblbrand SET BannerImage = @FileName, MobileImage = @FileName WHERE BrandID = @BrandId;
END
GO
