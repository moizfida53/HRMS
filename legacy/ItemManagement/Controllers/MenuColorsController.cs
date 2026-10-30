using Jar.Helper;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Web;
using System.Web.Mvc;

namespace Jar.Controllers
{
    // Admin page (Role_ID = 4) to view / edit the menu theme colours stored in
    // tbl_Menu_Colors. Colours are edited at brand level (BranchId = 0) for the
    // brand of the logged-in user (from the eCommerceCook cookie).
    public class MenuColorsController : Controller
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

        public ActionResult Index()
        {
            HttpCookie cookie = Request.Cookies["eCommerceCook"];
            if (cookie == null)
                return RedirectToAction("Index", "Login");

            int roleId = 0, brandId = 0;
            int.TryParse(cookie["RoleID"], out roleId);
            int.TryParse(cookie["BrandID"], out brandId);

            if (roleId != 4)
                return View("AccessDenied");

            // Current values from the DB (brand-level row, BranchId = 0).
            Dictionary<string, string> values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                // EAV: one row per field name in tblMenuTheme (brand-level, BranchID = 0).
                SqlParameter[] spTheme = {
                    new SqlParameter(){ ParameterName="@BrandId", SqlDbType=SqlDbType.Int, Value=brandId },
                    new SqlParameter(){ ParameterName="@BranchId", SqlDbType=SqlDbType.Int, Value=0 }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetMenuTheme", spTheme);
                if (ds != null && ds.Tables.Count > 0)
                {
                    foreach (DataRow row in ds.Tables[0].Rows)
                    {
                        string nm = Convert.ToString(row["Name"]).Trim();
                        // First row wins: sp_GetMenuTheme already orders branch-specific
                        // rows ahead of brand-level ones, so overwriting here would let the
                        // brand-level fallback mask the branch value.
                        if (string.IsNullOrEmpty(nm) || values.ContainsKey(nm)) continue;
                        values[nm] = Convert.ToString(row["Color"]).Trim();
                    }
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MenuColorsController", "Index", null);
            }

            List<ColorField> list = new List<ColorField>();
            foreach (string[] f in Fields)
            {
                // DB value if present, otherwise the standard-theme default (never blank).
                string val = values.ContainsKey(f[0]) ? values[f[0]] : "";
                if (string.IsNullOrEmpty(val) && Defaults.ContainsKey(f[0]))
                    val = Defaults[f[0]];

                list.Add(new ColorField
                {
                    Column = f[0],
                    Label = f[1],
                    Section = f[2],
                    Value = val,
                    Hidden = HiddenColumns.Contains(f[0])
                });
            }

            // Current layout (tbl_Brand via sp_GetBrandHomePageImage) to pre-select the radio.
            string currentLayout = "";
            try
            {
                string cfg = System.Configuration.ConfigurationManager.AppSettings["DesignTheme"];
                if (!string.IsNullOrEmpty(cfg)) currentLayout = cfg;
                SqlParameter[] spl = { new SqlParameter(){ ParameterName="@BrandId", SqlDbType=SqlDbType.Int, Value=brandId } };
                DataSet dsl = DB.ExecuteStoredProcDataSet("sp_GetBrandHomePageImage", spl);
                if (dsl != null && dsl.Tables.Count > 0 && dsl.Tables[0].Rows.Count > 0)
                {
                    string lay = Convert.ToString(dsl.Tables[0].Rows[0]["Layout"]).Trim();
                    if (!string.IsNullOrEmpty(lay)) currentLayout = lay;
                }
            }
            catch (Exception ex) { DB.AuditTrail(ex, "MenuColorsController", "Index-Layout", null); }
            if (string.IsNullOrEmpty(currentLayout)) currentLayout = "Design1";

            // Current brand images (for the thumbnails in the upload UI).
            ViewBag.BannerImage = "";
            ViewBag.DesktopImage = "";
            try
            {
                SqlParameter[] spImg = { new SqlParameter(){ ParameterName="@BrandId", SqlDbType=SqlDbType.Int, Value=brandId } };
                DataSet dsi = DB.ExecuteStoredProcDataSet("sp_GetBrandImages", spImg);
                if (dsi != null && dsi.Tables.Count > 0 && dsi.Tables[0].Rows.Count > 0)
                {
                    ViewBag.BannerImage = Convert.ToString(dsi.Tables[0].Rows[0]["BannerImage"]).Trim();
                    ViewBag.DesktopImage = Convert.ToString(dsi.Tables[0].Rows[0]["DesktopImage"]).Trim();
                }
            }
            catch (Exception ex) { DB.AuditTrail(ex, "MenuColorsController", "Index-Images", null); }

            ViewBag.CurrentLayout = currentLayout;
            ViewBag.BrandId = brandId;
            ViewBag.Fields = list;
            return View();
        }

        [HttpPost]
        public JsonResult Save(MenuColorsModel model, string menuLayout)
        {
            try
            {
                HttpCookie cookie = Request.Cookies["eCommerceCook"];
                if (cookie == null)
                    return Json(new { Message = "Unauthorized" });

                int roleId = 0, brandId = 0;
                int.TryParse(cookie["RoleID"], out roleId);
                int.TryParse(cookie["BrandID"], out brandId);
                if (roleId != 4)
                    return Json(new { Message = "Unauthorized" });

                if (model == null) model = new MenuColorsModel();

                // EAV: upsert the colour fields + bump the version row inside sp_SaveMenuTheme.
                // Colours go in as a table-valued parameter (no inline sql). BrandId/BranchId
                // come from the cookie.
                DataTable dtColors = new DataTable();
                dtColors.Columns.Add("Name", typeof(string));
                dtColors.Columns.Add("Color", typeof(string));
                foreach (var prop in typeof(MenuColorsModel).GetProperties())
                {
                    if (prop.PropertyType != typeof(string)) continue;
                    string color = Convert.ToString(prop.GetValue(model, null));
                    if (color == null) color = "";
                    color = color.Trim();
                    if (color.Length > 50) color = color.Substring(0, 50);
                    dtColors.Rows.Add(prop.Name, color);
                }
                SqlParameter[] spSave = {
                    new SqlParameter(){ ParameterName="@BrandId", SqlDbType=SqlDbType.Int, Value=brandId },
                    new SqlParameter(){ ParameterName="@BranchId", SqlDbType=SqlDbType.Int, Value=0 },
                    // Table-valued parameter: SqlDbType.Structured + TypeName are BOTH
                    // required for a DataTable to be sent as a TVP - without TypeName,
                    // SQL Server has no way to know which user-defined table type
                    // (dbo.MenuThemeTVP, created in DBScripts/MenuTheme_SPs.sql) the
                    // Name/Color columns correspond to, and the call throws (caught by
                    // this method's outer catch, which returns Message="Fail" - so
                    // every colour save, on every design, silently never reached the DB).
                    new SqlParameter("@Items", SqlDbType.Structured) { TypeName = "dbo.MenuThemeTVP", Value = dtColors }
                };
                DB.ExecuteStoredProcDataSet("sp_SaveMenuTheme", spSave);

                // Also persist the selected layout to tbl_Brand (best-effort; the
                // value is whitelisted to the 4 known designs before it hits SQL).
                if (!string.IsNullOrEmpty(menuLayout))
                {
                    try
                    {
                        string canonical = null;
                        foreach (string a in new[] { "Design1", "Design2", "Design3", "Design4" })
                            if (a.Equals(menuLayout, StringComparison.OrdinalIgnoreCase)) { canonical = a; break; }
                        if (canonical != null)
                        {
                            SqlParameter[] spLay = {
                                new SqlParameter(){ ParameterName="@BrandId", SqlDbType=SqlDbType.Int, Value=brandId },
                                new SqlParameter(){ ParameterName="@Layout", SqlDbType=SqlDbType.NVarChar, Value=canonical }
                            };
                            DB.ExecuteStoredProcDataSet("sp_UpdateBrandLayout", spLay);
                        }
                    }
                    catch (Exception exLay) { DB.AuditTrail(exLay, "MenuColorsController", "Save-Layout", null); }
                }

                return Json(new { Message = "Success" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MenuColorsController", "Save", null);
                return Json(new { Message = "Fail" });
            }
        }

        // Uploads a brand image to ~/images and updates tbl_Brand.
        //   type = "banner"  -> BannerImage (and MobileImage = same file)
        //   type = "desktop" -> DesktopImage
        [HttpPost]
        public JsonResult UploadBrandImage(HttpPostedFileBase file, string type)
        {
            try
            {
                HttpCookie cookie = Request.Cookies["eCommerceCook"];
                if (cookie == null) return Json(new { Message = "Unauthorized" });
                int roleId = 0, brandId = 0;
                int.TryParse(cookie["RoleID"], out roleId);
                int.TryParse(cookie["BrandID"], out brandId);
                if (roleId != 4) return Json(new { Message = "Unauthorized" });

                if (file == null || file.ContentLength <= 0) return Json(new { Message = "No file" });

                // Only allow known image types.
                string ext = (System.IO.Path.GetExtension(file.FileName) ?? "").ToLower();
                string[] okExt = { ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp" };
                if (System.Array.IndexOf(okExt, ext) < 0) return Json(new { Message = "Invalid file type" });

                // Sanitised, unique file name (only [a-z0-9_] + timestamp + safe ext).
                string baseName = System.IO.Path.GetFileNameWithoutExtension(file.FileName ?? "").ToLower();
                System.Text.StringBuilder sbn = new System.Text.StringBuilder();
                foreach (char ch in baseName) sbn.Append(char.IsLetterOrDigit(ch) ? ch : '_');
                baseName = sbn.ToString().Trim('_');
                if (string.IsNullOrEmpty(baseName)) baseName = "img";
                string filename = baseName + "_" + DateTime.Now.ToString("yyyyMMddHHmmssfff") + ext;

                string folder = Server.MapPath("~/images");
                if (!System.IO.Directory.Exists(folder)) System.IO.Directory.CreateDirectory(folder);
                file.SaveAs(System.IO.Path.Combine(folder, filename));

                SqlParameter[] spImg = {
                    new SqlParameter(){ ParameterName="@BrandId", SqlDbType=SqlDbType.Int, Value=brandId },
                    new SqlParameter(){ ParameterName="@Type", SqlDbType=SqlDbType.NVarChar, Value=(string.Equals(type, "desktop", StringComparison.OrdinalIgnoreCase) ? "desktop" : "banner") },
                    new SqlParameter(){ ParameterName="@FileName", SqlDbType=SqlDbType.NVarChar, Value=filename }
                };
                DB.ExecuteStoredProcDataSet("sp_UpdateBrandImage", spImg);

                return Json(new { Message = "Success", fileName = filename, url = "/images/" + filename });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MenuColorsController", "UploadBrandImage", null);
                return Json(new { Message = "Fail" });
            }
        }

        // Layout-less menu snapshot shown inside an iframe on the editor page.
        // The editor injects the live :root colours into it (load / on change).
        public ActionResult Preview()
        {
            HttpCookie cookie = Request.Cookies["eCommerceCook"];
            if (cookie == null)
                return RedirectToAction("Index", "Login");
            int roleId = 0;
            int.TryParse(cookie["RoleID"], out roleId);
            if (roleId != 4)
                return View("AccessDenied");
            return View();
        }
    }

    public class ColorField
    {
        public string Column { get; set; }
        public string Label { get; set; }
        public string Section { get; set; }
        public string Value { get; set; }
        public bool Hidden { get; set; }
    }

    // 33 colour columns from tbl_Menu_Colors. Property names must match the DB
    // column names and the sp_SaveMenuColors parameter names (case-insensitive).
    public class MenuColorsModel
    {
        public string header_background_color { get; set; }
        public string header_icon_color { get; set; }
        public string scroll_header_background_color { get; set; }
        public string scroll_header_icon_color { get; set; }
        public string fixd_item_list_title_background_color { get; set; }
        public string fixd_item_list_title_text_color { get; set; }
        public string category_page_background_color { get; set; }
        public string category_page_card_primary_background_color { get; set; }
        public string category_page_categoryname_color { get; set; }
        public string Design_1_selected_category_background_color { get; set; }
        public string Design_1_selected_category_name_color { get; set; }
        public string Design_1_plus_button_background_color { get; set; }
        public string Design_1_plus_button_icon_color { get; set; }
        public string Design_1_item_card_background_color { get; set; }
        public string Design_1_item_name_color { get; set; }
        public string Design_1_item_description_color { get; set; }
        public string Design_1_item_price_color { get; set; }
        public string item_page_background_color { get; set; }
        public string item_page_category_title_bg_color { get; set; }
        public string item_page_category_title_font_color { get; set; }
        public string item_page_item_background_color { get; set; }
        public string item_page_itemname_color { get; set; }
        public string item_page_price_color { get; set; }
        public string item_page_plus_button_color { get; set; }
        public string item_page_plus_button_icon_color { get; set; }
        public string product_details_title_bg_color { get; set; }
        public string product_details_title_font_color { get; set; }
        public string product_details_background_color { get; set; }
        public string product_name { get; set; }
        public string product_details_text { get; set; }
        public string product_details_price { get; set; }
        public string product_details_price_text { get; set; }
        public string product_details_price_background_color { get; set; }
        public string product_details_plus_button_color { get; set; }
        public string product_details_plus_button_icon_color { get; set; }
        public string category_carousel_background_color { get; set; }
        public string Item_details_price_background_color { get; set; }
        public string item_details_price_text { get; set; }
        public string item_details_price_total_price_background_color { get; set; }
        public string item_details_price_total_price_text { get; set; }
        public string item_details_extra_price_text_color { get; set; }
        // Item popup (modal) colours - Design1 (also reused by Design4 / waiter login).
        public string popup_header_background_color { get; set; }
        public string popup_header_font_color { get; set; }
        public string popup_close_button_color { get; set; }
        public string popup_body_background_color { get; set; }
        public string popup_description_background_color { get; set; }
        public string popup_description_text_color { get; set; }
        public string popup_price_background_color { get; set; }
        public string popup_price_color { get; set; }
        public string popup_addcart_button_background_color { get; set; }
        public string popup_addcart_button_text_color { get; set; }
        public string popup_qty_pill_background_color { get; set; }
        public string popup_qty_button_background_color { get; set; }
        public string popup_qty_button_icon_color { get; set; }
        public string popup_qty_count_text_color { get; set; }
        public string popup_choice_group_background_color { get; set; }
        public string popup_choice_title_color { get; set; }
        public string popup_choice_item_text_color { get; set; }
        public string popup_carousel_background_color { get; set; }
        public string popup_carousel_item_background_color { get; set; }
        public string popup_carousel_item_text_color { get; set; }
        public string popup_allergen_menu_background_color { get; set; }
        public string popup_allergen_menu_text_color { get; set; }
        public string Design_4_MainCategory_Background_Color { get; set; }
        public string Design_4_MainCategory_Internal_Background_Color { get; set; }
        public string Design_4_MainCategory_Text_color { get; set; }
        public string Design_4_MainCategory_arrow_color { get; set; }
        public string Design_4_Item_background_color { get; set; }
        public string Design_4_Item_Name_Color { get; set; }
        public string Design_4_Item_details_Color { get; set; }
        public string Design_4_Item_Price_Color { get; set; }
        public string Design_4_SubCategory_Bg_Color { get; set; }
        public string Design_4_SubCategory_text_color { get; set; }
    }
}
