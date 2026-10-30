/* ============================================================================
   TAB Theme  -  Stored Procedures  (tblTheme)
   ----------------------------------------------------------------------------
   Backs the Role-4 "TAB Theme" editor page (TabThemeController).
     6 image columns  : CategoryActive, CategoryInActive, Setting,
                         SeperatorLine, HomeScreen, PopUpBackground  (file names)
     16 colour columns : EnglishButton, ArabicButton, MandarinButton,
                         RussianButton, CloseButton, LeftArrow, LeftBottom,
                         LeftTop, RightArrow, RightButton, RightTop, FontColor,
                         FontColorItemName, FontColorIngName, FontColorPrice,
                         ItemBackgroundColor
   Re-runnable (drops & recreates). No table schema changes.
   ============================================================================ */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   sp_GetTabThemes  -  all themes (for the dropdown + to populate the form).
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_GetTabThemes', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetTabThemes;
GO
CREATE PROCEDURE dbo.sp_GetTabThemes
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ThemeID, ThemeName,
            CategoryActive, CategoryInActive, Setting, SeperatorLine, HomeScreen, PopUpBackground,
            EnglishButton, ArabicButton, MandarinButton, RussianButton, CloseButton,
            LeftArrow, LeftBottom, LeftTop, RightArrow, RightButton, RightTop,
            FontColor, FontColorItemName, FontColorIngName, FontColorPrice, ItemBackgroundColor
    FROM    dbo.tblTheme
    ORDER BY ThemeID;
END
GO

/* ---------------------------------------------------------------------------
   sp_SaveTabTheme  -  update one theme (by ThemeID) with all editable fields.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.sp_SaveTabTheme', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SaveTabTheme;
GO
CREATE PROCEDURE dbo.sp_SaveTabTheme
    @ThemeID             INT,
    @ThemeName           NVARCHAR(255),
    -- images (file names saved in ~/images)
    @CategoryActive      NVARCHAR(255),
    @CategoryInActive    NVARCHAR(255),
    @Setting             NVARCHAR(255),
    @SeperatorLine       NVARCHAR(255),
    @HomeScreen          NVARCHAR(255),
    @PopUpBackground     NVARCHAR(255),
    -- colours
    @EnglishButton       NVARCHAR(50),
    @ArabicButton        NVARCHAR(50),
    @MandarinButton      NVARCHAR(50),
    @RussianButton       NVARCHAR(50),
    @CloseButton         NVARCHAR(50),
    @LeftArrow           NVARCHAR(50),
    @LeftBottom          NVARCHAR(50),
    @LeftTop             NVARCHAR(50),
    @RightArrow          NVARCHAR(50),
    @RightButton         NVARCHAR(50),
    @RightTop            NVARCHAR(50),
    @FontColor           NVARCHAR(50),
    @FontColorItemName   NVARCHAR(50),
    @FontColorIngName    NVARCHAR(50),
    @FontColorPrice      NVARCHAR(50),
    @ItemBackgroundColor NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.tblTheme
    SET ThemeName           = @ThemeName,
        CategoryActive      = @CategoryActive,
        CategoryInActive    = @CategoryInActive,
        Setting             = @Setting,
        SeperatorLine       = @SeperatorLine,
        HomeScreen          = @HomeScreen,
        PopUpBackground     = @PopUpBackground,
        EnglishButton       = @EnglishButton,
        ArabicButton        = @ArabicButton,
        MandarinButton      = @MandarinButton,
        RussianButton       = @RussianButton,
        CloseButton         = @CloseButton,
        LeftArrow           = @LeftArrow,
        LeftBottom          = @LeftBottom,
        LeftTop             = @LeftTop,
        RightArrow          = @RightArrow,
        RightButton         = @RightButton,
        RightTop            = @RightTop,
        FontColor           = @FontColor,
        FontColorItemName   = @FontColorItemName,
        FontColorIngName    = @FontColorIngName,
        FontColorPrice      = @FontColorPrice,
        ItemBackgroundColor = @ItemBackgroundColor
    WHERE ThemeID = @ThemeID;
END
GO
