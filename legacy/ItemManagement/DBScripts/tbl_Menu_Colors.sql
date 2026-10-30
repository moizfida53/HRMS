/* ============================================================================
   tbl_Menu_Colors  -  per-brand (optionally per-branch) menu theme colours
   ----------------------------------------------------------------------------
   These are the colours that used to live as CSS :root variables in the brand
   css file (e.g. cssNew/OraBlu.css). The app now reads them from this table on
   page load (ItemsViewNewController) and injects them as a <style> override,
   so the brand css still supplies every OTHER variable and acts as a fallback.

   Column names below are EXACTLY the field names supplied. A few of the CSS
   variables use dashes even though the DB columns use underscores; that
   mapping is handled in C# (ItemsViewNewController.LoadMenuColors), e.g.
     DB  fixd_item_list_title_background_color
     CSS --fixd_item-list-title_background_color
     DB  item_details_extra_price_text_color
     CSS --item-details-extra-price-text-color
   ============================================================================ */

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* ------------------------------------------------------------------ TABLE -- */
IF OBJECT_ID(N'dbo.tbl_Menu_Colors', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_Menu_Colors
    (
        MenuColorId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_Menu_Colors PRIMARY KEY,
        BrandId     INT NOT NULL,
        BranchId    INT NOT NULL CONSTRAINT DF_tbl_Menu_Colors_BranchId DEFAULT (0), -- 0 = brand-level default

        header_background_color                         NVARCHAR(50) NULL,
        header_icon_color                               NVARCHAR(50) NULL,
        scroll_header_background_color                  NVARCHAR(50) NULL,
        scroll_header_icon_color                        NVARCHAR(50) NULL,
        fixd_item_list_title_background_color           NVARCHAR(50) NULL,
        fixd_item_list_title_text_color                 NVARCHAR(50) NULL,
        category_page_background_color                  NVARCHAR(50) NULL,
        category_page_card_primary_background_color     NVARCHAR(50) NULL,
        category_page_categoryname_color                NVARCHAR(50) NULL,
        item_page_background_color                      NVARCHAR(50) NULL,
        item_page_category_title_bg_color               NVARCHAR(50) NULL,
        item_page_category_title_font_color             NVARCHAR(50) NULL,
        item_page_item_background_color                 NVARCHAR(50) NULL,
        item_page_itemname_color                        NVARCHAR(50) NULL,
        item_page_price_color                           NVARCHAR(50) NULL,
        item_page_plus_button_color                     NVARCHAR(50) NULL,
        item_page_plus_button_icon_color                NVARCHAR(50) NULL,
        product_details_title_bg_color                  NVARCHAR(50) NULL,
        product_details_title_font_color                NVARCHAR(50) NULL,
        product_details_background_color                NVARCHAR(50) NULL,
        product_name                                    NVARCHAR(50) NULL,
        product_details_text                            NVARCHAR(50) NULL,
        product_details_price                           NVARCHAR(50) NULL,
        product_details_price_text                      NVARCHAR(50) NULL,
        product_details_price_background_color          NVARCHAR(50) NULL,
        product_details_plus_button_color               NVARCHAR(50) NULL,
        product_details_plus_button_icon_color          NVARCHAR(50) NULL,
        category_carousel_background_color              NVARCHAR(50) NULL,
        Item_details_price_background_color             NVARCHAR(50) NULL,
        item_details_price_text                         NVARCHAR(50) NULL,
        item_details_price_total_price_background_color  NVARCHAR(50) NULL,
        item_details_price_total_price_text             NVARCHAR(50) NULL,
        item_details_extra_price_text_color             NVARCHAR(50) NULL
    );

    /* one colour set per brand/branch */
    CREATE UNIQUE INDEX UX_tbl_Menu_Colors_Brand_Branch
        ON dbo.tbl_Menu_Colors (BrandId, BranchId);
END
GO

/* --------------------------------------------------------------- PROCEDURE -- */
/* Returns the colour row for a brand/branch. Prefers a branch-specific row,
   otherwise falls back to the brand-level row (BranchId = 0).                  */
IF OBJECT_ID(N'dbo.sp_GetMenuColors', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetMenuColors
GO
CREATE PROCEDURE dbo.sp_GetMenuColors
    @BrandId  INT,
    @BranchId INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1) *
    FROM   dbo.tbl_Menu_Colors
    WHERE  BrandId = @BrandId
      AND (BranchId = @BranchId OR BranchId = 0)
    ORDER BY CASE WHEN BranchId = @BranchId THEN 0 ELSE 1 END;  -- branch-specific first
END
GO

/* -------------------------------------------------------------------- SEED -- */
/* ORA BLU colours (copied from cssNew/OraBlu.css).
   >>> Set @BrandId below to the ORA BLU BrandId in YOUR database, then run. <<<
   (product_details_price_background_color was 'a1bba4' in the css - missing the
    leading '#', which made it invalid; seeded here as '#a1bba4'.)             */
DECLARE @BrandId INT = 0;   -- TODO: replace 0 with the ORA BLU BrandId

IF @BrandId <> 0
   AND NOT EXISTS (SELECT 1 FROM dbo.tbl_Menu_Colors WHERE BrandId = @BrandId AND BranchId = 0)
BEGIN
    INSERT INTO dbo.tbl_Menu_Colors
        (BrandId, BranchId,
         header_background_color, header_icon_color, scroll_header_background_color, scroll_header_icon_color,
         fixd_item_list_title_background_color, fixd_item_list_title_text_color,
         category_page_background_color, category_page_card_primary_background_color, category_page_categoryname_color,
         item_page_background_color, item_page_category_title_bg_color, item_page_category_title_font_color,
         item_page_item_background_color, item_page_itemname_color, item_page_price_color,
         item_page_plus_button_color, item_page_plus_button_icon_color,
         product_details_title_bg_color, product_details_title_font_color, product_details_background_color,
         product_name, product_details_text, product_details_price, product_details_price_text,
         product_details_price_background_color, product_details_plus_button_color, product_details_plus_button_icon_color,
         category_carousel_background_color,
         Item_details_price_background_color, item_details_price_text,
         item_details_price_total_price_background_color, item_details_price_total_price_text,
         item_details_extra_price_text_color)
    VALUES
        (@BrandId, 0,
         '#08203e', '#fff', '#08203e', '#FFF',
         '#08203e', '#fff',
         '#08203e', '#fff', '#fff',
         '#08203e', '#08203e', '#fff',
         '#fff', '#000', '#000',
         '#08203e', '#fff',
         '#faf7f1', '#08203e', '#faf7f1',
         '#000', '#5c5c5c', '#08203e', '#7f7f7f',
         '#a1bba4', '#08203e', '#08203e',
         '#08203e',
         '#f5f2f0', '#304633',
         '#f5f2f0', '#000',
         '#2eca42');
END
GO

/* --------------------------------------------------------- SAVE PROCEDURE -- */
/* Upsert used by the admin "Menu Colors" page (MenuColorsController.Save):
   updates the brand/branch colour row if it exists, else inserts a new one.   */
IF OBJECT_ID(N'dbo.sp_SaveMenuColors', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SaveMenuColors
GO
CREATE PROCEDURE dbo.sp_SaveMenuColors
    @BrandId  INT,
    @BranchId INT = 0,
    @header_background_color                         NVARCHAR(50) = NULL,
    @header_icon_color                               NVARCHAR(50) = NULL,
    @scroll_header_background_color                  NVARCHAR(50) = NULL,
    @scroll_header_icon_color                        NVARCHAR(50) = NULL,
    @fixd_item_list_title_background_color           NVARCHAR(50) = NULL,
    @fixd_item_list_title_text_color                 NVARCHAR(50) = NULL,
    @category_page_background_color                  NVARCHAR(50) = NULL,
    @category_page_card_primary_background_color     NVARCHAR(50) = NULL,
    @category_page_categoryname_color                NVARCHAR(50) = NULL,
    @item_page_background_color                      NVARCHAR(50) = NULL,
    @item_page_category_title_bg_color               NVARCHAR(50) = NULL,
    @item_page_category_title_font_color             NVARCHAR(50) = NULL,
    @item_page_item_background_color                 NVARCHAR(50) = NULL,
    @item_page_itemname_color                        NVARCHAR(50) = NULL,
    @item_page_price_color                           NVARCHAR(50) = NULL,
    @item_page_plus_button_color                     NVARCHAR(50) = NULL,
    @item_page_plus_button_icon_color                NVARCHAR(50) = NULL,
    @product_details_title_bg_color                  NVARCHAR(50) = NULL,
    @product_details_title_font_color                NVARCHAR(50) = NULL,
    @product_details_background_color                NVARCHAR(50) = NULL,
    @product_name                                    NVARCHAR(50) = NULL,
    @product_details_text                            NVARCHAR(50) = NULL,
    @product_details_price                           NVARCHAR(50) = NULL,
    @product_details_price_text                      NVARCHAR(50) = NULL,
    @product_details_price_background_color          NVARCHAR(50) = NULL,
    @product_details_plus_button_color               NVARCHAR(50) = NULL,
    @product_details_plus_button_icon_color          NVARCHAR(50) = NULL,
    @category_carousel_background_color              NVARCHAR(50) = NULL,
    @Item_details_price_background_color             NVARCHAR(50) = NULL,
    @item_details_price_text                         NVARCHAR(50) = NULL,
    @item_details_price_total_price_background_color  NVARCHAR(50) = NULL,
    @item_details_price_total_price_text             NVARCHAR(50) = NULL,
    @item_details_extra_price_text_color            NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.tbl_Menu_Colors WHERE BrandId = @BrandId AND BranchId = @BranchId)
    BEGIN
        UPDATE dbo.tbl_Menu_Colors SET
            header_background_color                         = @header_background_color,
            header_icon_color                               = @header_icon_color,
            scroll_header_background_color                  = @scroll_header_background_color,
            scroll_header_icon_color                        = @scroll_header_icon_color,
            fixd_item_list_title_background_color           = @fixd_item_list_title_background_color,
            fixd_item_list_title_text_color                 = @fixd_item_list_title_text_color,
            category_page_background_color                  = @category_page_background_color,
            category_page_card_primary_background_color     = @category_page_card_primary_background_color,
            category_page_categoryname_color                = @category_page_categoryname_color,
            item_page_background_color                      = @item_page_background_color,
            item_page_category_title_bg_color               = @item_page_category_title_bg_color,
            item_page_category_title_font_color             = @item_page_category_title_font_color,
            item_page_item_background_color                 = @item_page_item_background_color,
            item_page_itemname_color                        = @item_page_itemname_color,
            item_page_price_color                           = @item_page_price_color,
            item_page_plus_button_color                     = @item_page_plus_button_color,
            item_page_plus_button_icon_color                = @item_page_plus_button_icon_color,
            product_details_title_bg_color                  = @product_details_title_bg_color,
            product_details_title_font_color                = @product_details_title_font_color,
            product_details_background_color                = @product_details_background_color,
            product_name                                    = @product_name,
            product_details_text                            = @product_details_text,
            product_details_price                           = @product_details_price,
            product_details_price_text                      = @product_details_price_text,
            product_details_price_background_color          = @product_details_price_background_color,
            product_details_plus_button_color               = @product_details_plus_button_color,
            product_details_plus_button_icon_color          = @product_details_plus_button_icon_color,
            category_carousel_background_color              = @category_carousel_background_color,
            Item_details_price_background_color             = @Item_details_price_background_color,
            item_details_price_text                         = @item_details_price_text,
            item_details_price_total_price_background_color  = @item_details_price_total_price_background_color,
            item_details_price_total_price_text             = @item_details_price_total_price_text,
            item_details_extra_price_text_color            = @item_details_extra_price_text_color
        WHERE BrandId = @BrandId AND BranchId = @BranchId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.tbl_Menu_Colors
            (BrandId, BranchId,
             header_background_color, header_icon_color, scroll_header_background_color, scroll_header_icon_color,
             fixd_item_list_title_background_color, fixd_item_list_title_text_color,
             category_page_background_color, category_page_card_primary_background_color, category_page_categoryname_color,
             item_page_background_color, item_page_category_title_bg_color, item_page_category_title_font_color,
             item_page_item_background_color, item_page_itemname_color, item_page_price_color,
             item_page_plus_button_color, item_page_plus_button_icon_color,
             product_details_title_bg_color, product_details_title_font_color, product_details_background_color,
             product_name, product_details_text, product_details_price, product_details_price_text,
             product_details_price_background_color, product_details_plus_button_color, product_details_plus_button_icon_color,
             category_carousel_background_color,
             Item_details_price_background_color, item_details_price_text,
             item_details_price_total_price_background_color, item_details_price_total_price_text,
             item_details_extra_price_text_color)
        VALUES
            (@BrandId, @BranchId,
             @header_background_color, @header_icon_color, @scroll_header_background_color, @scroll_header_icon_color,
             @fixd_item_list_title_background_color, @fixd_item_list_title_text_color,
             @category_page_background_color, @category_page_card_primary_background_color, @category_page_categoryname_color,
             @item_page_background_color, @item_page_category_title_bg_color, @item_page_category_title_font_color,
             @item_page_item_background_color, @item_page_itemname_color, @item_page_price_color,
             @item_page_plus_button_color, @item_page_plus_button_icon_color,
             @product_details_title_bg_color, @product_details_title_font_color, @product_details_background_color,
             @product_name, @product_details_text, @product_details_price, @product_details_price_text,
             @product_details_price_background_color, @product_details_plus_button_color, @product_details_plus_button_icon_color,
             @category_carousel_background_color,
             @Item_details_price_background_color, @item_details_price_text,
             @item_details_price_total_price_background_color, @item_details_price_total_price_text,
             @item_details_extra_price_text_color);
    END

    SELECT 'Success' AS Result;
END
GO
