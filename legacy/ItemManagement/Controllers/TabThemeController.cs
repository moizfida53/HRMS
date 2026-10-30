using Jar.Helper;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Web;
using System.Web.Mvc;

namespace Jar.Controllers
{
    // Admin page (Role_ID = 4) to edit the tablet ("TAB") themes in tblTheme.
    // A dropdown selects which theme (ThemeID) to edit. 6 fields are images
    // (uploaded to ~/images, file name stored), the rest are colours.
    // All DB access is via stored procs (sp_GetTabThemes / sp_SaveTabTheme) -
    // no inline SQL.
    public class TabThemeController : Controller
    {
        // { column, friendly label } - images uploaded to ~/images (file name stored).
        private static readonly string[][] ImageFields = new string[][]
        {
            new[]{ "CategoryActive",   "Category active" },
            new[]{ "CategoryInActive", "Category inactive" },
            new[]{ "Setting",          "Setting" },
            new[]{ "SeperatorLine",    "Separator line" },
            new[]{ "HomeScreen",       "Home screen" },
            new[]{ "PopUpBackground",  "Pop-up background" }
        };

        // { column, friendly label } - colour pickers.
        private static readonly string[][] ColorFields = new string[][]
        {
            new[]{ "EnglishButton",       "Menu / Language button" },
            new[]{ "ArabicButton",        "Arabic button" },
            new[]{ "MandarinButton",      "Mandarin button" },
            new[]{ "RussianButton",       "Russian button" },
            new[]{ "CloseButton",         "Close button" },
            new[]{ "LeftArrow",           "Left arrow" },
            new[]{ "LeftTop",             "Left top" },
            new[]{ "LeftBottom",          "Left bottom" },
            new[]{ "RightArrow",          "Right arrow" },
            new[]{ "RightTop",            "Right top" },
            new[]{ "RightButton",         "Right button" },
            new[]{ "FontColor",           "Font colour" },
            new[]{ "FontColorItemName",   "Font colour – item name" },
            new[]{ "FontColorIngName",    "Font colour – ingredient name" },
            new[]{ "FontColorPrice",      "Font colour – price" },
            new[]{ "ItemBackgroundColor", "Item background colour" }
        };

        public ActionResult Index()
        {
            HttpCookie cookie = Request.Cookies["eCommerceCook"];
            if (cookie == null)
                return RedirectToAction("Index", "Login");

            int roleId = 0;
            int.TryParse(cookie["RoleID"], out roleId);
            if (roleId != 4)
                return View("AccessDenied");

            List<TabThemeModel> themes = new List<TabThemeModel>();
            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetTabThemes");
                if (ds != null && ds.Tables.Count > 0)
                {
                    foreach (DataRow r in ds.Tables[0].Rows)
                    {
                        themes.Add(new TabThemeModel
                        {
                            ThemeID = ToInt(r, "ThemeID"),
                            ThemeName = S(r, "ThemeName"),
                            CategoryActive = S(r, "CategoryActive"),
                            CategoryInActive = S(r, "CategoryInActive"),
                            Setting = S(r, "Setting"),
                            SeperatorLine = S(r, "SeperatorLine"),
                            HomeScreen = S(r, "HomeScreen"),
                            PopUpBackground = S(r, "PopUpBackground"),
                            EnglishButton = S(r, "EnglishButton"),
                            ArabicButton = S(r, "ArabicButton"),
                            MandarinButton = S(r, "MandarinButton"),
                            RussianButton = S(r, "RussianButton"),
                            CloseButton = S(r, "CloseButton"),
                            LeftArrow = S(r, "LeftArrow"),
                            LeftBottom = S(r, "LeftBottom"),
                            LeftTop = S(r, "LeftTop"),
                            RightArrow = S(r, "RightArrow"),
                            RightButton = S(r, "RightButton"),
                            RightTop = S(r, "RightTop"),
                            FontColor = S(r, "FontColor"),
                            FontColorItemName = S(r, "FontColorItemName"),
                            FontColorIngName = S(r, "FontColorIngName"),
                            FontColorPrice = S(r, "FontColorPrice"),
                            ItemBackgroundColor = S(r, "ItemBackgroundColor")
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "TabThemeController", "Index", null);
            }

            ViewBag.ThemesJson = new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(themes);
            ViewBag.ImageFields = ImageFields;
            ViewBag.ColorFields = ColorFields;
            return View();
        }

        [HttpPost]
        public JsonResult Save(TabThemeModel model)
        {
            try
            {
                HttpCookie cookie = Request.Cookies["eCommerceCook"];
                if (cookie == null)
                    return Json(new { Message = "Unauthorized" });

                int roleId = 0;
                int.TryParse(cookie["RoleID"], out roleId);
                if (roleId != 4)
                    return Json(new { Message = "Unauthorized" });

                if (model == null || model.ThemeID <= 0)
                    return Json(new { Message = "Fail" });

                SqlParameter[] spa =
                {
                    new SqlParameter(){ ParameterName="@ThemeID", SqlDbType=SqlDbType.Int, Value=model.ThemeID },
                    P("@ThemeName", model.ThemeName),
                    P("@CategoryActive", model.CategoryActive),
                    P("@CategoryInActive", model.CategoryInActive),
                    P("@Setting", model.Setting),
                    P("@SeperatorLine", model.SeperatorLine),
                    P("@HomeScreen", model.HomeScreen),
                    P("@PopUpBackground", model.PopUpBackground),
                    P("@EnglishButton", model.EnglishButton),
                    P("@ArabicButton", model.ArabicButton),
                    P("@MandarinButton", model.MandarinButton),
                    P("@RussianButton", model.RussianButton),
                    P("@CloseButton", model.CloseButton),
                    P("@LeftArrow", model.LeftArrow),
                    P("@LeftBottom", model.LeftBottom),
                    P("@LeftTop", model.LeftTop),
                    P("@RightArrow", model.RightArrow),
                    P("@RightButton", model.RightButton),
                    P("@RightTop", model.RightTop),
                    P("@FontColor", model.FontColor),
                    P("@FontColorItemName", model.FontColorItemName),
                    P("@FontColorIngName", model.FontColorIngName),
                    P("@FontColorPrice", model.FontColorPrice),
                    P("@ItemBackgroundColor", model.ItemBackgroundColor)
                };
                DB.ExecuteStoredProcDataSet("sp_SaveTabTheme", spa);

                return Json(new { Message = "Success" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "TabThemeController", "Save", null);
                return Json(new { Message = "Fail" });
            }
        }

        [HttpPost]
        public JsonResult UploadThemeImage(HttpPostedFileBase file)
        {
            try
            {
                HttpCookie cookie = Request.Cookies["eCommerceCook"];
                if (cookie == null)
                    return Json(new { Message = "Unauthorized" });

                int roleId = 0;
                int.TryParse(cookie["RoleID"], out roleId);
                if (roleId != 4)
                    return Json(new { Message = "Unauthorized" });

                if (file == null || file.ContentLength <= 0)
                    return Json(new { Message = "No file selected." });

                string ext = System.IO.Path.GetExtension(file.FileName ?? "").ToLower();
                HashSet<string> allowed = new HashSet<string> { ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg" };
                if (!allowed.Contains(ext))
                    return Json(new { Message = "Unsupported file type." });

                // Sanitised, unique file name (only [a-z0-9] + timestamp + safe ext).
                string baseName = System.IO.Path.GetFileNameWithoutExtension(file.FileName ?? "").ToLower();
                System.Text.StringBuilder sbn = new System.Text.StringBuilder();
                foreach (char ch in baseName) sbn.Append(char.IsLetterOrDigit(ch) ? ch : '_');
                baseName = sbn.ToString().Trim('_');
                if (string.IsNullOrEmpty(baseName)) baseName = "img";
                string filename = baseName + "_" + DateTime.Now.ToString("yyyyMMddHHmmssfff") + ext;

                string folder = Server.MapPath("~/images");
                if (!System.IO.Directory.Exists(folder)) System.IO.Directory.CreateDirectory(folder);
                file.SaveAs(System.IO.Path.Combine(folder, filename));

                return Json(new { Message = "Success", fileName = filename, url = "/images/" + filename });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "TabThemeController", "UploadThemeImage", null);
                return Json(new { Message = "Fail" });
            }
        }

        // ---- helpers ----
        private static string S(DataRow r, string col)
        {
            if (!r.Table.Columns.Contains(col) || r[col] == DBNull.Value) return "";
            return Convert.ToString(r[col]).Trim();
        }

        private static int ToInt(DataRow r, string col)
        {
            int v = 0;
            if (r.Table.Columns.Contains(col)) int.TryParse(Convert.ToString(r[col]), out v);
            return v;
        }

        private static SqlParameter P(string name, string value)
        {
            return new SqlParameter() { ParameterName = name, SqlDbType = SqlDbType.NVarChar, Value = (object)(value ?? "") };
        }
    }

    // tblTheme editable columns. Property names match the DB columns and the
    // sp_SaveTabTheme parameter names (case-insensitive).
    public class TabThemeModel
    {
        public int ThemeID { get; set; }
        public string ThemeName { get; set; }
        // images (file names)
        public string CategoryActive { get; set; }
        public string CategoryInActive { get; set; }
        public string Setting { get; set; }
        public string SeperatorLine { get; set; }
        public string HomeScreen { get; set; }
        public string PopUpBackground { get; set; }
        // colours
        public string EnglishButton { get; set; }
        public string ArabicButton { get; set; }
        public string MandarinButton { get; set; }
        public string RussianButton { get; set; }
        public string CloseButton { get; set; }
        public string LeftArrow { get; set; }
        public string LeftBottom { get; set; }
        public string LeftTop { get; set; }
        public string RightArrow { get; set; }
        public string RightButton { get; set; }
        public string RightTop { get; set; }
        public string FontColor { get; set; }
        public string FontColorItemName { get; set; }
        public string FontColorIngName { get; set; }
        public string FontColorPrice { get; set; }
        public string ItemBackgroundColor { get; set; }
    }
}
