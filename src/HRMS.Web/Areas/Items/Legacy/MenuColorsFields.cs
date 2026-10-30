#nullable disable
// The tblMenuTheme field list from the old MenuColorsController (static part only),
// used by the customer menu to write the brand colours as CSS variables.
// The Menu Colors editor itself moves over with the Settings module.
namespace HRMS.Web.Areas.Items.Legacy
{
    public static class MenuColorsFields
    {
        // Ordered display list: { DB column, friendly label, section }.
        // Column names MUST match tbl_Menu_Colors columns / MenuColorsModel properties.
        private static readonly string[][] Fields = new string[][]
        {
            new[]{ "header_background_color",                          "Header background",                 "Header" },
            new[]{ "header_icon_color",                               "Header icon",                       "Header" },
            new[]{ "scroll_header_background_color",                  "Scrolled header background",        "Header" },
            new[]{ "scroll_header_icon_color",                        "Scrolled header icon",              "Header" },
            new[]{ "fixd_item_list_title_background_color",           "Fixed item-list title background",  "Header" },
            new[]{ "fixd_item_list_title_text_color",                 "Fixed item-list title text",        "Header" },
            new[]{ "category_page_background_color",                  "Page background",                   "Category page" },
            new[]{ "category_page_card_primary_background_color",     "Category card background",          "Category page" },
            new[]{ "category_page_categoryname_color",                "Category name",                     "Category page" },
            new[]{ "Design_1_selected_category_background_color",     "Selected category background",      "Category (Design 1)" },
            new[]{ "Design_1_selected_category_name_color",           "Selected category name",            "Category (Design 1)" },
            new[]{ "Design_1_plus_button_background_color",           "+ button background",               "Category (Design 1)" },
            new[]{ "Design_1_plus_button_icon_color",                 "+ button icon",                     "Category (Design 1)" },
            new[]{ "Design_1_item_card_background_color",             "Item card background",              "Items (Design 1)" },
            new[]{ "Design_1_item_name_color",                       "Item name text",                    "Items (Design 1)" },
            new[]{ "Design_1_item_description_color",                "Description text",                  "Items (Design 1)" },
            new[]{ "Design_1_item_price_color",                      "Price text",                        "Items (Design 1)" },
            new[]{ "item_page_background_color",                      "Page background",                   "Item page" },
            new[]{ "item_page_category_title_bg_color",               "Category title background",         "Item page" },
            new[]{ "item_page_category_title_font_color",             "Category title text",               "Item page" },
            new[]{ "item_page_item_background_color",                 "Item card background",              "Item page" },
            new[]{ "item_page_itemname_color",                       "Item name",                         "Item page" },
            new[]{ "item_page_price_color",                           "Price",                             "Item page" },
            new[]{ "item_page_plus_button_color",                     "Plus button",                       "Item page" },
            new[]{ "item_page_plus_button_icon_color",                "Plus button icon",                  "Item page" },
            new[]{ "product_details_title_bg_color",                  "Title background",                  "Product details" },
            new[]{ "product_details_title_font_color",                "Title text",                        "Product details" },
            new[]{ "product_details_background_color",                "Background",                        "Product details" },
            new[]{ "product_name",                                    "Product name",                      "Product details" },
            new[]{ "product_details_text",                            "Description text",                  "Product details" },
            new[]{ "product_details_price",                           "Price",                             "Product details" },
            new[]{ "product_details_price_text",                      "Price label text",                  "Product details" },
            new[]{ "product_details_price_background_color",          "Price background",                  "Product details" },
            new[]{ "product_details_plus_button_color",               "Plus button",                       "Product details" },
            new[]{ "product_details_plus_button_icon_color",          "Plus button icon",                  "Product details" },
            new[]{ "category_carousel_background_color",              "Related-items carousel background", "Product details" },
            new[]{ "Item_details_price_background_color",             "Price background",                  "Item details price" },
            new[]{ "item_details_price_text",                        "Price text",                        "Item details price" },
            new[]{ "item_details_price_total_price_background_color", "Total price background",            "Item details price" },
            new[]{ "item_details_price_total_price_text",             "Total price text",                  "Item details price" },
            new[]{ "item_details_extra_price_text_color",            "Extra price text",                  "Item details price" },
            // Item popup (modal) shown when an item is tapped in Design1 (also reused by
            // Design4 / waiter login). Section is shown in the editor only for Design1.
            new[]{ "popup_header_background_color",                   "Header background",                 "Item Popup (Design 1)" },
            new[]{ "popup_header_font_color",                        "Header title text",                 "Item Popup (Design 1)" },
            new[]{ "popup_close_button_color",                       "Close (x) button",                  "Item Popup (Design 1)" },
            new[]{ "popup_body_background_color",                    "Popup background",                  "Item Popup (Design 1)" },
            new[]{ "popup_description_background_color",             "Description background",            "Item Popup (Design 1)" },
            new[]{ "popup_description_text_color",                   "Description text",                  "Item Popup (Design 1)" },
            new[]{ "popup_price_background_color",                   "Price background",                  "Item Popup (Design 1)" },
            new[]{ "popup_price_color",                              "Price text",                        "Item Popup (Design 1)" },
            new[]{ "popup_addcart_button_background_color",          "Add-to-cart button",                "Item Popup (Design 1)" },
            new[]{ "popup_addcart_button_text_color",               "Add-to-cart text",                  "Item Popup (Design 1)" },
            new[]{ "popup_qty_pill_background_color",                "Quantity bar background",           "Item Popup (Design 1)" },
            new[]{ "popup_qty_button_background_color",              "Quantity +/- button",               "Item Popup (Design 1)" },
            new[]{ "popup_qty_button_icon_color",                   "Quantity +/- icon",                 "Item Popup (Design 1)" },
            new[]{ "popup_qty_count_text_color",                    "Quantity number",                   "Item Popup (Design 1)" },
            new[]{ "popup_choice_group_background_color",            "Choice/extra group background",     "Item Popup (Design 1)" },
            new[]{ "popup_choice_title_color",                      "Choice/extra group title",          "Item Popup (Design 1)" },
            new[]{ "popup_choice_item_text_color",                  "Choice/extra item text",            "Item Popup (Design 1)" },
            new[]{ "popup_carousel_background_color",                "Related-items carousel background", "Item Popup (Design 1)" },
            new[]{ "popup_carousel_item_background_color",           "Related item card",                 "Item Popup (Design 1)" },
            new[]{ "popup_carousel_item_text_color",                "Related item text",                 "Item Popup (Design 1)" },
            new[]{ "popup_allergen_menu_background_color",           "Allergen dropdown background",      "Item Popup (Design 1)" },
            new[]{ "popup_allergen_menu_text_color",                "Allergen dropdown text",            "Item Popup (Design 1)" },
            new[]{ "Design_4_MainCategory_Background_Color",          "Main category header background",   "Design 4" },
            new[]{ "Design_4_MainCategory_Internal_Background_Color", "Main category inner background",    "Design 4" },
            new[]{ "Design_4_MainCategory_Text_color",               "Main category text",                "Design 4" },
            new[]{ "Design_4_MainCategory_arrow_color",              "Main category arrow",               "Design 4" },
            new[]{ "Design_4_Item_background_color",                  "Item background",                   "Design 4" },
            new[]{ "Design_4_Item_Name_Color",                       "Item name",                         "Design 4" },
            new[]{ "Design_4_Item_details_Color",                    "Item description",                  "Design 4" },
            new[]{ "Design_4_Item_Price_Color",                      "Item price",                        "Design 4" },
            new[]{ "Design_4_SubCategory_Bg_Color",                  "Sub-category background",           "Design 4" },
            new[]{ "Design_4_SubCategory_text_color",                "Sub-category text",                 "Design 4" }
        };

        // Fallback shown when the DB has no value yet (matches the standard theme /
        // the seed in DBScripts\tbl_Menu_Colors.sql) so the editor is never blank.
        private static readonly Dictionary<string, string> Defaults = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "header_background_color", "#08203e" },
            { "header_icon_color", "#fff" },
            { "scroll_header_background_color", "#08203e" },
            { "scroll_header_icon_color", "#FFF" },
            { "fixd_item_list_title_background_color", "#08203e" },
            { "fixd_item_list_title_text_color", "#fff" },
            { "category_page_background_color", "#08203e" },
            { "category_page_card_primary_background_color", "#fff" },
            { "category_page_categoryname_color", "#fff" },
            { "Design_1_selected_category_background_color", "#3b4f67" },
            { "Design_1_selected_category_name_color", "#ffffff" },
            { "Design_1_plus_button_background_color", "#08203e" },
            { "Design_1_plus_button_icon_color", "#ffffff" },
            { "Design_1_item_card_background_color", "#ffffff" },
            { "Design_1_item_name_color", "#08203e" },
            { "Design_1_item_description_color", "#5c5c5c" },
            { "Design_1_item_price_color", "#08203e" },
            { "item_page_background_color", "#08203e" },
            { "item_page_category_title_bg_color", "#08203e" },
            { "item_page_category_title_font_color", "#fff" },
            { "item_page_item_background_color", "#fff" },
            { "item_page_itemname_color", "#000" },
            { "item_page_price_color", "#000" },
            { "item_page_plus_button_color", "#08203e" },
            { "item_page_plus_button_icon_color", "#fff" },
            { "product_details_title_bg_color", "#faf7f1" },
            { "product_details_title_font_color", "#08203e" },
            { "product_details_background_color", "#faf7f1" },
            { "product_name", "#000" },
            { "product_details_text", "#5c5c5c" },
            { "product_details_price", "#08203e" },
            { "product_details_price_text", "#7f7f7f" },
            { "product_details_price_background_color", "#a1bba4" },
            { "product_details_plus_button_color", "#08203e" },
            { "product_details_plus_button_icon_color", "#08203e" },
            { "category_carousel_background_color", "#08203e" },
            { "Item_details_price_background_color", "#f5f2f0" },
            { "item_details_price_text", "#304633" },
            { "item_details_price_total_price_background_color", "#f5f2f0" },
            { "item_details_price_total_price_text", "#000" },
            { "item_details_extra_price_text_color", "#2eca42" },
            { "popup_header_background_color", "#ffffff" },
            { "popup_header_font_color", "#000000" },
            { "popup_close_button_color", "#000000" },
            { "popup_body_background_color", "#ffffff" },
            { "popup_description_background_color", "#ffffff" },
            { "popup_description_text_color", "#5c5c5c" },
            { "popup_price_background_color", "#ffffff" },
            { "popup_price_color", "#08203e" },
            { "popup_addcart_button_background_color", "#08203e" },
            { "popup_addcart_button_text_color", "#ffffff" },
            { "popup_qty_pill_background_color", "#a1bba4" },
            { "popup_qty_button_background_color", "#08203e" },
            { "popup_qty_button_icon_color", "#ffffff" },
            { "popup_qty_count_text_color", "#000000" },
            { "popup_choice_group_background_color", "#ffffff" },
            { "popup_choice_title_color", "#08203e" },
            { "popup_choice_item_text_color", "#333333" },
            { "popup_carousel_background_color", "#08203e" },
            { "popup_carousel_item_background_color", "#ffffff" },
            { "popup_carousel_item_text_color", "#000000" },
            { "popup_allergen_menu_background_color", "#ffffff" },
            { "popup_allergen_menu_text_color", "#333333" },
            { "Design_4_MainCategory_Background_Color", "#08203e" },
            { "Design_4_MainCategory_Internal_Background_Color", "#faf7f1" },
            { "Design_4_MainCategory_Text_color", "#ffffff" },
            { "Design_4_MainCategory_arrow_color", "#ffffff" },
            { "Design_4_Item_background_color", "#ffffff" },
            { "Design_4_Item_Name_Color", "#000000" },
            { "Design_4_Item_details_Color", "#5c5c5c" },
            { "Design_4_Item_Price_Color", "#08203e" },
            { "Design_4_SubCategory_Bg_Color", "#08203e" },
            { "Design_4_SubCategory_text_color", "#ffffff" }
        };

        // Columns kept in the DB but hidden from the editor UI. Their current
        // value is preserved on save (posted as hidden inputs), not wiped.
        private static readonly HashSet<string> HiddenColumns = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "scroll_header_background_color",
            "scroll_header_icon_color",
            "fixd_item_list_title_background_color",
            "fixd_item_list_title_text_color"
        };

        // Canonical (case-correct) field names, looked up case-insensitively.
        // CSS custom properties ARE case-sensitive: --Design_1_selected_category_name_color
        // and --design_1_selected_category_name_color are two different variables. SQL
        // Server collation is case-INsensitive, so a tblMenuTheme row seeded with different
        // casing saves and reads back fine but is emitted as a variable the stylesheets
        // never reference — the colour appears not to save. ItemsViewNewController
        // .LoadMenuColors runs every DB name through here before building the :root block.
        private static readonly Dictionary<string, string> CanonicalNames = BuildCanonicalNames();

        private static Dictionary<string, string> BuildCanonicalNames()
        {
            Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (string[] f in Fields)
                map[f[0]] = f[0];
            return map;
        }

        // Returns the canonical casing for a tblMenuTheme row name, or the name
        // unchanged when it isn't one of the known fields.
        public static string CanonicalFieldName(string name)
        {
            if (string.IsNullOrEmpty(name)) return name;
            string canonical;
            return CanonicalNames.TryGetValue(name.Trim(), out canonical) ? canonical : name.Trim();
        }
    }
}
