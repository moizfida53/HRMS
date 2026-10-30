#nullable disable
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
using HRMS.Web.Areas.Items.Legacy.Hesabe;
using HRMS.Web.Areas.Items.Models;
using HRMS.Web.Areas.Items.Legacy;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Linq;
using System.Net;
using System.Net.Mail;
using System.Threading.Tasks;

namespace HRMS.Web.Areas.Items.Controllers
{
    // The customer-facing QR menu: open to everyone, no HRMS sign-in.
    [Microsoft.AspNetCore.Authorization.AllowAnonymous, IgnoreAntiforgeryToken]
    public class ItemsViewNewController : LegacyController
    {
        public ActionResult Index(string id, string to, string previewLayout = null)
        {
            int BrandId = 0;
            ViewBag.BrandId = 0;
            ViewBag.Branchid = 0;
            ViewBag.BannerImage = "";
            ViewBag.MobileImage = "";
            ViewBag.DesktopImage = "";
            ViewBag.BrandCssFileName = "root.css";

            var cookie = QrCookie;
            var IswaiterLogin = "";
            if (cookie != null && !string.IsNullOrEmpty(cookie["IsWaiterLogin"]))
            {
                IswaiterLogin = cookie["IsWaiterLogin"].ToString();
            }
            if (!string.IsNullOrEmpty(IswaiterLogin))
            {
                ViewBag.IsFromWaiterLogin = IswaiterLogin;
                ViewBag.WaiterName = cookie["Name"].ToString();
            }
            else
            {
                ViewBag.IsFromWaiterLogin = "false";
                ViewBag.WaiterName = "";
            }

            // ?id=<BrandId>,<BranchId>  e.g. ?id=1,2 => Brand 1, Branch 2.
            // These URL values are authoritative: the branding lookup below may only
            // FILL IN missing ids, it must never overwrite what the URL asked for.
            int BranchId = 0;
            bool brandIdFromUrl = false;
            bool branchIdFromUrl = false;

            if (!string.IsNullOrEmpty(id))
            {
                try
                {
                    List<int> TagIds = id.Split(',')
                                         .Select(x => x.Trim())
                                         .Where(x => !string.IsNullOrEmpty(x))
                                         .Select(int.Parse)
                                         .ToList();
                    if (TagIds.Count() > 0)
                    {
                        ViewBag.BrandId = TagIds[0];
                        BrandId = TagIds[0];
                        brandIdFromUrl = BrandId > 0;
                        if (TagIds.Count() > 1)
                        {
                            BranchId = TagIds[1];
                            ViewBag.Branchid = BranchId;
                            branchIdFromUrl = BranchId > 0;
                        }
                        else
                        {
                            BranchId = 0;
                            ViewBag.Branchid = 0;
                        }
                    }
                }
                catch
                {
                }
            }
            //if (ViewBag.BrandId == 0 || ViewBag.BrandId == null)
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                               ParameterName="@brandName",
                                               SqlDbType=SqlDbType.VarChar,
                                               Value=""
                                            },
                                            new SqlParameter(){
                                               ParameterName="@branchName",
                                               SqlDbType=SqlDbType.VarChar,
                                               Value=""
                                            },
                                            new SqlParameter(){
                                               ParameterName="@branchId",
                                               SqlDbType=SqlDbType.Int,
                                               Value=BranchId
                                            }
                                        };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBrandBranchDetails", spa);
                if (ds != null && ds.Tables.Count > 0)
                {
                    if (ds.Tables[0].Rows.Count > 0)
                    {
                        // Only adopt the ids returned by the proc when the URL did not
                        // supply them, otherwise ?id=1,2 gets silently replaced by the
                        // proc's default (first) brand/branch row.
                        if (!brandIdFromUrl)
                        {
                            BrandId = Convert.ToInt32(ds.Tables[0].Rows[0]["Brandid"].ToString());
                            ViewBag.BrandId = BrandId;
                        }
                        if (!branchIdFromUrl)
                        {
                            int.TryParse(Convert.ToString(ds.Tables[0].Rows[0]["BranchId"]), out BranchId);
                            ViewBag.Branchid = BranchId;
                        }
                        ViewBag.BannerImage = ds.Tables[0].Rows[0]["BannerImage"].ToString();
                        ViewBag.MobileImage = ds.Tables[0].Rows[0]["MobileImage"].ToString();
                        ViewBag.DesktopImage = ds.Tables[0].Rows[0]["DesktopImage"].ToString();
                        ViewBag.BrandCssFileName = ds.Tables[0].Rows[0]["Css"].ToString();
                        ViewBag.IsItemDetailsBackToCategory = "False";
                        try
                        {
                            if(ds.Tables[0].Rows[0]["IsItemDetailsBackToCategory"].ToString() == "True")
                            {
                                ViewBag.IsItemDetailsBackToCategory = "True";
                            }
                        }
                        catch { }

                    }
                }
            }

            if (!string.IsNullOrEmpty(to))
            {
                ViewBag.ToformRedirect = to;
            }
            else
            {
                ViewBag.ToformRedirect = "";
            }
            ItemsViewController objitemview = new ItemsViewController();
            ViewBag.IsCartVisible = Convert.ToBoolean(ConfigurationManager.AppSettings["IsCartVisible"]);
            GetBrandHomePaggeImage(BrandId);
            setViewBagFromSettings();
            LoadMenuColors(BrandId, BranchId);

            if (IswaiterLogin=="true" && ViewBag.WaiterLayout !="")
            {
                ViewBag.DesignTheme = ViewBag.WaiterLayout;
            }

            ViewBag.LoginUser = "Customer";
            ViewBag.CallcWebServiceUrl = ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
            ViewBag.KNETPublicKey = ConfigurationManager.AppSettings["KNETPublicKey"].ToString();
            ViewBag.KNETMerchantId = ConfigurationManager.AppSettings["KNETMerchantId"].ToString();

            // Preview override from the Menu Theme editor: ?previewLayout=DesignX
            // renders the menu in the chosen layout without changing tbl_Brand.
            if (!string.IsNullOrEmpty(previewLayout))
            {
                ViewBag.DesignTheme = previewLayout;
                ViewBag.WaiterLayout = previewLayout;
            }
            // Named explicitly: brand() delegates to this method, and in that case the
            // route's action name is "brand", so a parameterless View() would look for
            // Views/ItemsViewNew/brand.cshtml and fail.
            return View("Index");
        }
        public ActionResult brand(string name, string to, string id = null, string previewLayout = null)
        {
            // The "Default" route maps the site root to this action with an empty {name},
            // so "/?id=1,2" lands here rather than on Index — and this action only knows how
            // to resolve a brand/branch by NAME, so the id pair was being dropped and the
            // proc fell back to the default brand/branch. Hand those requests to Index,
            // which understands ?id=<BrandId>,<BranchId>.
            if (string.IsNullOrEmpty(name) && !string.IsNullOrEmpty(id))
            {
                return Index(id, to, previewLayout);
            }

            if (name != "favicon.ico")
            {
                int BrandId = 0;
                ViewBag.BrandId = 0;
                ViewBag.Branchid = 0;
                ViewBag.BannerImage = "";
                ViewBag.MobileImage = "";
                ViewBag.DesktopImage = "";
                ViewBag.BrandCssFileName = "root.css";
                //if (!string.IsNullOrEmpty(name))
                //{
                try
                {
                    var cookie = QrCookie;
                    var IswaiterLogin = "";
                    if (cookie!=null)
                    {
                        if(!string.IsNullOrEmpty(cookie["IsWaiterLogin"]))
                        {
                            IswaiterLogin = cookie["IsWaiterLogin"].ToString();
                        }
                    }
                    if (!string.IsNullOrEmpty(IswaiterLogin))
                    {
                        ViewBag.IsFromWaiterLogin = IswaiterLogin;
                        ViewBag.WaiterName = cookie["Name"].ToString();
                    }
                    else
                    {
                        ViewBag.IsFromWaiterLogin = "false";
                        ViewBag.WaiterName = "";
                    }


                    string[] values = name != null ? name.Split(',') : "".Split(',');
                    string brandName = "";
                    string branchName = "";
                    if (!string.IsNullOrEmpty(values[0]))
                    {
                        brandName = values[0];
                    }
                    if (values.Count() > 1)
                    {
                        if (!string.IsNullOrEmpty(values[1]))
                        {
                            branchName = values[1];
                        }
                    }

                    SqlParameter[] spa ={ new SqlParameter(){
                                               ParameterName="@brandName",
                                               SqlDbType=SqlDbType.VarChar,
                                               Value=brandName
                                            },
                                            new SqlParameter(){
                                               ParameterName="@branchName",
                                               SqlDbType=SqlDbType.VarChar,
                                               Value=branchName
                                            },
                                            new SqlParameter(){
                                               ParameterName="@branchId",
                                               SqlDbType=SqlDbType.Int,
                                               Value=ViewBag.Branchid
                                            }
                                        };
                    DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBrandBranchDetails", spa);
                    if (ds != null && ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            BrandId = Convert.ToInt32(ds.Tables[0].Rows[0]["Brandid"].ToString());
                            ViewBag.BrandId = ds.Tables[0].Rows[0]["Brandid"].ToString();
                            ViewBag.Branchid = ds.Tables[0].Rows[0]["BranchId"].ToString();
                            ViewBag.BannerImage = ds.Tables[0].Rows[0]["BannerImage"].ToString();
                            ViewBag.MobileImage = ds.Tables[0].Rows[0]["MobileImage"].ToString();
                            ViewBag.DesktopImage = ds.Tables[0].Rows[0]["DesktopImage"].ToString();
                            ViewBag.BrandCssFileName = ds.Tables[0].Rows[0]["Css"].ToString();
                            ViewBag.IsItemDetailsBackToCategory = "False";
                            try
                            {
                                if (ds.Tables[0].Rows[0]["IsItemDetailsBackToCategory"].ToString() == "True")
                                {
                                    ViewBag.IsItemDetailsBackToCategory = "True";
                                }
                            }
                            catch { }
                        }
                    }
                }
                catch
                {
                }
                //}

                if (!string.IsNullOrEmpty(to))
                {
                    ViewBag.ToformRedirect = to;
                }
                else
                {
                    ViewBag.ToformRedirect = "";
                }
                ItemsViewController objitemview = new ItemsViewController();
                ViewBag.IsCartVisible = Convert.ToBoolean(ConfigurationManager.AppSettings["IsCartVisible"]);
                GetBrandHomePaggeImage(BrandId);
                setViewBagFromSettings();
                {
                    int branchIdForColors = 0;
                    int.TryParse(Convert.ToString(ViewBag.Branchid), out branchIdForColors);
                    LoadMenuColors(BrandId, branchIdForColors);
                }
                ViewBag.LoginUser = "Customer";
                ViewBag.CallcWebServiceUrl = ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                ViewBag.KNETPublicKey = ConfigurationManager.AppSettings["KNETPublicKey"].ToString();
                ViewBag.KNETMerchantId = ConfigurationManager.AppSettings["KNETMerchantId"].ToString();
                return View("Index");
            }
            return null;
        }

        public ActionResult TestLanding(string id, string to)
        {
            if (!string.IsNullOrEmpty(id))
            {
                List<int> TagIds = id.Split(',').Select(int.Parse).ToList();
                if (TagIds.Count() > 0)
                {
                    ViewBag.BrandId = TagIds[0];
                    if (TagIds.Count() > 1)
                    {
                        ViewBag.Branchid = TagIds[1];
                    }
                    else
                    {
                        ViewBag.Branchid = 0;
                    }
                }
            }
            else
            {
                ViewBag.BrandId = 0;
                ViewBag.Branchid = 0;
            }

            if (!string.IsNullOrEmpty(to))
            {
                ViewBag.ToformRedirect = to;
            }
            else
            {
                ViewBag.ToformRedirect = "";
            }
            ItemsViewController objitemview = new ItemsViewController();
            ViewBag.IsCartVisible = Convert.ToBoolean(ConfigurationManager.AppSettings["IsCartVisible"]);
            GetBrandHomePaggeImage(ViewBag.BrandId);
            setViewBagFromSettings();
            return View();
        }
        public void setViewBagFromSettings()
        {
            try
            {
                //SqlParameter[] spa ={ new SqlParameter(){
                //                       ParameterName="@BrandId",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=BrandId
                //                    }
                //};
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetSettings");
                if (ds != null && ds.Tables.Count > 0)
                {
                    ViewBag.isReservation = Convert.ToBoolean(ds.Tables[0].Rows[0]["isReservation"]);
                }
                else
                {
                    ViewBag.isReservation = false;
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "setViewBagFromSettings", null);
                ViewBag.isReservation = false;
            }

        }

        public ActionResult UserInfoAndOrderConfirm(int BrandId, int BranchId)
        {
            //if (!string.IsNullOrEmpty(id))
            //{
            //    List<int> TagIds = id.Split(',').Select(int.Parse).ToList();
            //    if (TagIds.Count() > 0)
            //    {
            //        ViewBag.BrandId = TagIds[0];
            //        if (TagIds.Count() > 1)
            //        {
            //            ViewBag.Branchid = TagIds[1];
            //        }
            //        else
            //        {
            //            ViewBag.Branchid = 0;
            //        }
            //    }
            //}
            //else
            //{
            //    ViewBag.BrandId = 0;
            //    ViewBag.Branchid = 0;
            //}

            ViewBag.BrandId = BrandId;
            ViewBag.Branchid = BranchId;
            ViewBag.IsCartVisible = Convert.ToBoolean(ConfigurationManager.AppSettings["IsCartVisible"]);
            GetBrandHomePaggeImage(ViewBag.BrandId);
            setViewBagFromSettings();
            return View();
        }

        public void GetBrandHomePaggeImage(int? BrandId)
        {
            try
            {
                string ImageName = "";
                string facebookUrl = "";
                string instagramUrl = "";
                string whatsAppUrl = "";
                string CurrencyENG = "";
                string CurrencyArab = "";
                string DesignTheme = ConfigurationManager.AppSettings["DesignTheme"].ToString();
                string WaiterLayout = ConfigurationManager.AppSettings["DesignTheme"].ToString();
                string BrandIsExpired = "0";
                string BrandAlert = "";
                int IsCartVisible = 0;
                string PopupBannerImage = "";
                string IsFeedBack = "False";
                int IsShowAllergen = 0;
                int DecimalPlaces = 0;
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBrandHomePageImage", spa);
                if (ds != null && ds.Tables.Count > 0)
                {
                    if (ds.Tables[0].Rows.Count > 0)
                    {
                        ImageName = ds.Tables[0].Rows[0]["BrandHomePageImage"].ToString();
                        facebookUrl = ds.Tables[0].Rows[0]["Facebook"].ToString();
                        instagramUrl = ds.Tables[0].Rows[0]["Instagram"].ToString();
                        whatsAppUrl = ds.Tables[0].Rows[0]["WhatsAppURL"].ToString();
                        CurrencyENG = ds.Tables[0].Rows[0]["Currency"].ToString();
                        CurrencyArab = ds.Tables[0].Rows[0]["CurrencyArabic"].ToString();
                        DesignTheme = !string.IsNullOrEmpty(ds.Tables[0].Rows[0]["Layout"].ToString()) ?
                            ds.Tables[0].Rows[0]["Layout"].ToString().Trim() : DesignTheme;
                        WaiterLayout = !string.IsNullOrEmpty(ds.Tables[0].Rows[0]["WaiterLayout"].ToString()) ?
                            ds.Tables[0].Rows[0]["WaiterLayout"].ToString().Trim() : WaiterLayout;
                        BrandIsExpired = ds.Tables[0].Rows[0]["IsExpired"].ToString();
                        BrandAlert = ds.Tables[0].Rows[0]["Alert"].ToString();
                        IsCartVisible = Convert.ToInt32(ds.Tables[0].Rows[0]["IsCartVisible"]);
                        PopupBannerImage = ds.Tables[0].Rows[0]["PopupBannerImage"].ToString().Trim();
                        IsFeedBack = ds.Tables[0].Rows[0]["IsFeedBack"].ToString();
                        IsShowAllergen = Convert.ToInt32(ds.Tables[0].Rows[0]["IsShowAllergen"]);
                        DecimalPlaces= Convert.ToInt32(ds.Tables[0].Rows[0]["DecimalPlaces"]);
                    }
                }
                ViewBag.BrandHomePageImage = ImageName;
                ViewBag.facebookUrl = facebookUrl;
                ViewBag.instagramUrl = instagramUrl;
                ViewBag.whatsAppUrl = whatsAppUrl;
                ViewBag.CurrencyENG = CurrencyENG;
                ViewBag.CurrencyArab = CurrencyArab;
                ViewBag.DesignTheme = DesignTheme;
                ViewBag.WaiterLayout = WaiterLayout;
                ViewBag.BrandIsExpired = BrandIsExpired;
                ViewBag.BrandAlert = BrandAlert;
                ViewBag.IsCrtVisible = IsCartVisible;
                ViewBag.PopupBannerImage = PopupBannerImage;
                ViewBag.IsFeedBack = IsFeedBack;
                ViewBag.IsShowAllergen = IsShowAllergen;
                ViewBag.DecimalPlaces = DecimalPlaces;

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "GetBrandHomePaggeImage", null);
            }
        }

        // Loads the per-brand menu theme colours from tblMenuTheme (Name/Color rows) and builds a
        // :root{...} CSS override that Index.cshtml injects into <head>. If the table
        // or proc isn't set up yet (or there's no row), ViewBag.MenuColorsCss stays
        // empty and the static brand css continues to supply the colours.
        private void LoadMenuColors(int brandId, int branchId)
        {
            ViewBag.MenuColorsCss = "";
            ViewBag.CssVersion = 0;
            try
            {
                // EAV: read Name/Color rows from tblMenuTheme (branch-specific preferred, else brand-level 0).
                Dictionary<string, string> vals = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                SqlParameter[] spTheme = {
                    new SqlParameter(){ ParameterName="@BrandId", SqlDbType=SqlDbType.Int, Value=brandId },
                    new SqlParameter(){ ParameterName="@BranchId", SqlDbType=SqlDbType.Int, Value=branchId }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetMenuTheme", spTheme);
                if (ds != null && ds.Tables.Count > 0)
                {
                    foreach (DataRow r in ds.Tables[0].Rows)
                    {
                        string nm = Convert.ToString(r["Name"]).Trim();
                        if (string.IsNullOrEmpty(nm) || vals.ContainsKey(nm)) continue;
                        vals[nm] = Convert.ToString(r["Color"]).Trim();
                    }
                }
                // Theme version (css cache-buster) = the Color of the row Name='Version' (bumped +1 on save).
                try
                {
                    DataSet dvr = DB.ExecuteStoredProcDataSet("sp_GetMenuThemeVersion");
                    if (dvr != null && dvr.Tables.Count > 0 && dvr.Tables[0].Rows.Count > 0)
                        ViewBag.CssVersion = Convert.ToString(dvr.Tables[0].Rows[0]["Color"]).Trim();
                }
                catch (Exception exv) { DB.AuditTrail(exv, "ItemsViewNewController", "LoadMenuColors-Version", null); }
                if (vals.Count > 0)
                {
                    // The DB row Name IS the CSS custom-property name for almost every field
                    // (identity). Only these few use dashes in the css, so remap them. Every other
                    // row is injected as --<Name> as-is, so NEW rows added to tblMenuTheme (e.g. the
                    // Design_4_* fields) are picked up automatically — no code change needed.
                    Dictionary<string, string> dashRemap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                    {
                        { "fixd_item_list_title_background_color", "fixd_item-list-title_background_color" },
                        { "fixd_item_list_title_text_color", "fixd_item-list-title_text_color" },
                        { "Item_details_price_background_color", "item-details-price-background-color" },
                        { "item_details_price_text", "item-details-price-text" },
                        { "item_details_price_total_price_background_color", "item-details-price-total-price-background-color" },
                        { "item_details_price_total_price_text", "item-details-price-total-price-text" },
                        { "item_details_extra_price_text_color", "item-details-extra-price-text-color" }
                    };

                    System.Text.StringBuilder sb = new System.Text.StringBuilder();
                    sb.Append(":root{");
                    foreach (KeyValuePair<string, string> kv in vals)
                    {
                        string name = (kv.Key ?? "").Trim();
                        if (name.Length == 0) continue;
                        if (name.Equals("Version", StringComparison.OrdinalIgnoreCase)) continue; // counter row, not a colour
                        // CSS custom properties are case-SENSITIVE while SQL Server is not,
                        // so a row stored as e.g. "design_1_selected_category_name_color"
                        // would be emitted as a variable no stylesheet references and the
                        // saved colour would silently never apply. Normalise to the casing
                        // the editor / views use.
                        name = MenuColorsFields.CanonicalFieldName(name);
                        string val = (kv.Value ?? "").Trim();
                        if (string.IsNullOrEmpty(val)) continue;
                        string cssVar;
                        if (!dashRemap.TryGetValue(name, out cssVar)) cssVar = name; // identity for all the rest
                        sb.Append("--").Append(cssVar).Append(":").Append(val).Append(";");
                    }
                    sb.Append("}");
                    ViewBag.MenuColorsCss = sb.ToString();
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "LoadMenuColors", null);
                ViewBag.MenuColorsCss = "";
            }
        }

        [HttpPost]
        public JsonResult GenerateCartCommentsObject(List<CartComments> cartdetails)
        {
            try
            {
                DataTable dt = DB.ToDataTable(cartdetails);
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@dttblCartComment",
                                       Value=dt
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GenerateCartCommentsObject", spa1);
                List<CartComments> objcmt = new List<CartComments>();
                if (ds != null && ds.Tables.Count > 0)
                {
                    DataTable dtItems = ds.Tables[0];
                    if (dtItems.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtItems.Rows)
                        {
                            objcmt.Add(new CartComments
                            {
                                II = Convert.ToInt32(dtRow["II"].ToString()),
                                CI = Convert.ToInt32(dtRow["CI"].ToString()),
                                comments_eng = dtRow["comments_eng"].ToString(),
                                comments_arb = dtRow["comments_arb"].ToString(),
                            });
                        }
                    }
                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);

                }

                return Json(new { Message = "Success", dtComments = objcmt }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "GenerateCartCommentsObject", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        //[HttpPost]
        //public JsonResult GenerateExtraItemsObject(List<CartExtraItems> cartdetails)
        //{
        //    try
        //    {
        //        DataTable dt = DB.ToDataTable(cartdetails);
        //        SqlParameter[] spa1 ={
        //                               new SqlParameter(){
        //                               ParameterName="@dttblCartExtraItems",
        //                               Value=dt
        //                            }
        //        };
        //        DataSet ds = DB.ExecuteStoredProcDataSet("sp_GenerateCartExtraItemsObject", spa1);
        //        List<CartExtraItems> objExtraitems = new List<CartExtraItems>();
        //        if (ds != null && ds.Tables.Count > 0)
        //        {
        //            DataTable dtItems = ds.Tables[0];
        //            if (dtItems.Rows.Count > 0)
        //            {
        //                foreach (DataRow dtRow in dtItems.Rows)
        //                {
        //                    objExtraitems.Add(new CartExtraItems
        //                    {
        //                        II = Convert.ToInt32(dtRow["II"].ToString()),
        //                        EI = Convert.ToInt32(dtRow["EI"].ToString()),
        //                        ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
        //                        ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
        //                        PRICE = Convert.ToDecimal(dtRow["PRICE"].ToString())
        //                    });
        //                }
        //            }
        //        }
        //        else
        //        {
        //            return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);

        //        }

        //        return Json(new { Message = "Success", dtExtraItems = objExtraitems }, JsonRequestBehavior.AllowGet);

        //    }
        //    catch (Exception ex)
        //    {
        //        DB.AuditTrail(ex, "ItemsViewNewController", "GenerateExtraItemsObject", null);
        //        return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
        //    }

        //}

        [HttpPost]
        public JsonResult GenerateExtraItemsAndChoicesObject(List<ExtraItemsobject> extras, List<choicesobject> choices)
        {
            try
            {
                DataTable dtextras = DB.ToDataTable(extras);
                DataTable dtchoices = DB.ToDataTable(choices);
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@dtextras",
                                       Value=dtextras
                                    },new SqlParameter(){
                                       ParameterName="@dtchoices",
                                       Value=dtchoices
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GenerateCartExtraAndChoicesObject", spa1);
                List<CartExtraItems> objExtraitems = new List<CartExtraItems>();
                if (ds != null && ds.Tables.Count > 0)
                {
                    DataTable dtExtItems = ds.Tables[0];
                    DataTable dtchoicesItems = ds.Tables[1];
                    //if (dtItems.Rows.Count > 0)
                    //{
                    //    foreach (DataRow dtRow in dtItems.Rows)
                    //    {
                    //        objExtraitems.Add(new CartExtraItems
                    //        {
                    //            II = Convert.ToInt32(dtRow["II"].ToString()),
                    //            EI = Convert.ToInt32(dtRow["EI"].ToString()),
                    //            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                    //            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                    //            PRICE = Convert.ToDecimal(dtRow["PRICE"].ToString())
                    //        });
                    //    }
                    //}
                    return Json(new
                    {
                        Message = "Success",
                        dtExtraItems = JsonConvert.SerializeObject(dtExtItems),
                        dtChoices = JsonConvert.SerializeObject(dtchoicesItems)
                    }, JsonRequestBehavior.AllowGet);

                }

                return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);


            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "GenerateExtraItemsObject", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }
        [HttpPost]
        public JsonResult BindTrackorderdataNew(string InoiceNumber)
        {
            try
            {
                string webServiceUrl = ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                if (!string.IsNullOrEmpty(webServiceUrl))
                {
                    var data = new
                    {
                        InvoiceNo = InoiceNumber
                    };
                    string inputJson = (new JavaScriptSerializer()).Serialize(data);
                    WebClient client = new WebClient();
                    client.Headers["Content-type"] = "application/json";
                    client.Encoding = System.Text.Encoding.UTF8;
                    var jsonresult = client.UploadString(webServiceUrl + "/DmToCallCenterServices/GetInvoiceDriverStatus", inputJson);
                    //InvoiceNo = (new JavaScriptSerializer()).Deserialize<List<CustomerModel>>(json);
                    //return jsonresult;
                    return Json(jsonresult);

                }
                return Json(new { Message = "Error,Contact Your Manager." }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "BindTrackorderdataNew", null);
                return Json(new { Message = "Error,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
            }

        }

        /// <summary>
        /// Saved addresses + pickup branches for the checkout Delivery/Pickup step.
        ///
        /// This used to POST to the Call Centre
        /// (/DmToCallCenterServices/GetDeliveryServiceData). Now that orders are
        /// written locally that service is not in the loop any more, and the call
        /// returned nothing - which is why the Pickup tab listed no branches at
        /// all. The list is not static markup anywhere; it is built entirely from
        /// this response.
        ///
        /// The response is a JSON *string* wrapped in Json(), because the caller
        /// does JSON.parse(result) on it. Changing that shape would mean touching
        /// every consumer, so the original contract is kept exactly.
        /// </summary>
        [HttpPost]
        public JsonResult GetDeliveryServiceData(string Mobile, string Email, int? BrandID = null)
        {
            try
            {
                SqlParameter[] spa =
                {
                    new SqlParameter("@Mobile",  SqlDbType.NVarChar,  50) { Value = (object)Mobile ?? DBNull.Value },
                    new SqlParameter("@Email",   SqlDbType.NVarChar, 100) { Value = (object)Email  ?? DBNull.Value },
                    new SqlParameter("@BrandID", SqlDbType.Int)
                        { Value = (BrandID.HasValue && BrandID.Value > 0) ? (object)BrandID.Value : DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetDeliveryServiceData", spa);

                string addresses = "";
                string branches = "[]";

                if (ds != null && ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0)
                    addresses = JsonConvert.SerializeObject(ds.Tables[0]);

                if (ds != null && ds.Tables.Count > 1)
                    branches = JsonConvert.SerializeObject(ds.Tables[1]);

                // dtAddressList is deliberately "" and not "[]" when there are no
                // saved addresses: BindDeliveryServiceData tests for the empty
                // string to decide whether to null out customerAddresses.
                string payload = JsonConvert.SerializeObject(new
                {
                    Message = "Success",
                    dtAddressList = addresses,
                    dtBranchList = branches
                });

                return Json(payload);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "GetDeliveryServiceData", null);

                // Detail is what turns "Service Not Connected, Please Contact Your
                // Manager." from a dead end into something diagnosable: the alert in
                // DeliveryService.js appends it when present. The Message value must
                // stay byte-identical - the JS branches on that exact string. Shown
                // only when custom errors are off, i.e. not to real customers.
                bool showDetail = HttpContext.RequestServices.GetRequiredService<IWebHostEnvironment>().IsDevelopment();
                return Json(new
                {
                    Message = "Error,Contact Your Manager.",
                    Detail  = showDetail ? ex.Message : null
                }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult GetTimeSlot(string reservationDate)
        {
            try
            {
                DateTime dtt = reservationDate == null ? DateTime.Now : Convert.ToDateTime(reservationDate);
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@reservationDate",
                                        SqlDbType=SqlDbType.DateTime,
                                        Value=dtt
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetTimeSlot", spa1);
                if (ds.Tables.Count > 0)
                {
                    if (ds.Tables[0].Rows.Count > 0)
                    {
                        DataTable dt = ds.Tables[0];
                        string jsonData = JsonConvert.SerializeObject(dt);
                        return Json(new { Message = "Success", dtresult = jsonData }, JsonRequestBehavior.AllowGet);
                    }
                }
                return Json(new { Message = "Success", dtLabels = "" }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "GetTimeSlot", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult SendMailtoExpiredBrands()
        {
            try
            {
                string retMessage = "";
                DataTable dtUpdateEmailSentCount = new DataTable();
                dtUpdateEmailSentCount.Clear();
                dtUpdateEmailSentCount.Columns.Add("BrandId");
                dtUpdateEmailSentCount.Columns.Add("BrandName");
                dtUpdateEmailSentCount.Columns.Add("ExpiryDate");
                dtUpdateEmailSentCount.Columns.Add("ContactDetails");

                //SqlParameter[] spa ={
                //    new SqlParameter(){
                //                           ParameterName="@BrandID",
                //                           SqlDbType=SqlDbType.Int,
                //                           Value=BrandID
                //                        },
                //                   };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetExpiredBrandList");
                if (ds != null)
                {
                    if (ds.Tables[0].Rows.Count > 0)
                    {
                        foreach (DataRow item in ds.Tables[0].Rows)
                        {
                            string status = SendMail(item["EmailReminderContent"].ToString(), item["Email"].ToString());
                            if (status == "Success")
                            {
                                DB.ExecuteNonQuery("update tblbrand set EmailReminderCount= isnull(EmailReminderCount,0)+1 where BrandID=" + item["BrandID"] + "");

                                DataRow _row = dtUpdateEmailSentCount.NewRow();
                                _row["BrandId"] = item["BrandID"];
                                _row["BrandName"] = item["BrandName"];
                                _row["ExpiryDate"] = item["ExpiryDate"];
                                _row["ContactDetails"] = item["ContactDetails"];
                                dtUpdateEmailSentCount.Rows.Add(_row);

                                retMessage += "[BrandId=" + item["BrandID"]
                                    + "," + "BrandName = " + item["BrandName"]
                                    + "," + "ExpiryDate = " + item["ExpiryDate"]
                                    + "," + "ContactDetails = " + item["ContactDetails"]
                                    + "]";
                            }
                        }

                        //if (dtUpdateEmailSentCount.Rows.Count > 0)
                        //{
                        //    SqlParameter[] spa1 ={
                        //                       new SqlParameter(){
                        //                       ParameterName="@dtextras",
                        //                       Value=dtUpdateEmailSentCount
                        //                        }
                        //                    };
                        //    DataSet UpdatedRecord = DB.ExecuteStoredProcDataSet("sp_UpdateEmailReminderCount", spa1);
                        //}
                    }
                }

                return Json(new
                {
                    Message = "Success",
                    dtExtraItems = JsonConvert.SerializeObject(dtUpdateEmailSentCount),
                }, JsonRequestBehavior.AllowGet);
                //return retMessage;
            }
            catch (Exception ex)
            {
                //return ex.ToString(); 
                DB.AuditTrail(ex, "ItemsViewNewController", "SendMailtoExpiredBrands", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public string SendMail(string MailText, string ToEmail)
        {
            string returnmsg = "";
            try
            {
                //string FilePath = Server.MapPath("~\\EmailTemplate\\ReservationConfirmMail.html");
                //StreamReader str = new StreamReader(FilePath);
                //string MailText = str.ReadToEnd();
                //MailText = MailText.Replace("[ConfirmationID]", dt.Rows[0]["confirmationId"].ToString().Trim());
                //MailText = MailText.Replace("[CustomerName]", dt.Rows[0]["customerName"].ToString().Trim());
                //MailText = MailText.Replace("[ReservationDate]", dt.Rows[0]["reservationDate"].ToString().Trim());
                //MailText = MailText.Replace("[SlotName]", dt.Rows[0]["slotName"].ToString().Trim());
                //MailText = MailText.Replace("[comments]", dt.Rows[0]["comments"].ToString().Trim());
                //str.Close();

                MailMessage mail = new MailMessage();
                mail.IsBodyHtml = true;
                mail.To.Add(ToEmail);
                string FromEmail = ConfigurationManager.AppSettings["FromEmail"].ToString();
                string Subject = ConfigurationManager.AppSettings["Subject"].ToString();
                string SMTPHost = ConfigurationManager.AppSettings["SMTPHost"].ToString();
                int SMTPPort = Convert.ToInt32(ConfigurationManager.AppSettings["SMTPPort"].ToString());
                bool IsSSL = Convert.ToBoolean(ConfigurationManager.AppSettings["IsSSL"].ToString());
                string SenderEmail = ConfigurationManager.AppSettings["FromEmail"].ToString();
                string SenderPassword = ConfigurationManager.AppSettings["SenderPassword"].ToString();

                mail.From = new MailAddress(FromEmail);
                mail.Sender = new MailAddress(SenderEmail);
                mail.Subject = Subject;
                //mail.Body = MailText;
                mail.Body = MailText;

                SmtpClient smtp = new SmtpClient();
                smtp.Host = SMTPHost;
                smtp.Timeout = int.MaxValue;
                //smtp.UseDefaultCredentials = true;
                //////smtp.DeliveryMethod = System.Net.Mail.SmtpDeliveryMethod.Network;

                smtp.Port = SMTPPort;
                smtp.EnableSsl = IsSSL;
                smtp.Credentials = new System.Net.NetworkCredential
                (SenderEmail, SenderPassword);// Enter seders User name and password	
                smtp.Send(mail);
                returnmsg = "Success";
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "BranchReservationController", "SendMail", null);
                returnmsg = "Fail";
            }
            return returnmsg;
        }

        [HttpPost]
        public JsonResult GetFeedbackFormQuestion(int BrandId)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@BrandId",
                                       Value=BrandId
                                    }};
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetFeedbackFormQuestion", spa1);

                if (ds != null && ds.Tables.Count > 0)
                {
                    DataTable dtQuestions = ds.Tables[0];
                    return Json(new
                    {
                        Message = "Success",
                        dtQuestions = JsonConvert.SerializeObject(dtQuestions),
                    }, JsonRequestBehavior.AllowGet);
                }

                return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "GetFeedbackFormQuestion", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        [HttpPost]
        public JsonResult PostFeedback(int BranchId, string customerEmail, string customerMobile, string customerName, string UDID, List<FeedBackResponse> questionList)
        {
            try
            {
                DataTable dt = DB.ToDataTable(questionList);
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@BranchId",
                                       Value=BranchId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@customerEmail",
                                       Value=customerEmail
                                    },
                                       new SqlParameter(){
                                       ParameterName="@customerMobile",
                                       Value=customerMobile
                                    },
                                       new SqlParameter(){
                                       ParameterName="@customerName",
                                       Value=customerName
                                    },
                                       new SqlParameter(){
                                       ParameterName="@UDID",
                                       Value=(object)UDID ?? DBNull.Value
                                    },
                                       new SqlParameter(){
                                       ParameterName="@dttblFeedBackData",
                                       Value=dt
                                    }

                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_PostFeedbackData", spa1);

                if (ds != null && ds.Tables.Count > 0)
                {
                    DataTable dtQuestions = ds.Tables[0];
                    if (dtQuestions.Rows.Count > 0)
                    {
                        if (dtQuestions.Rows[0]["result"].ToString() == "Success")
                        {
                            return Json(new
                            {
                                Message = "Success",
                                dtQuestions = JsonConvert.SerializeObject(dtQuestions),
                            }, JsonRequestBehavior.AllowGet);
                        }
                    }

                }
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "PostFeedback", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        /*  Web App manifest - lets the landing page be added to the Home Screen as
            an app (standalone, no browser bar) for Guided Access / kiosk tablets.

            Name and icons are the common TMM branding for EVERY brand (marketing).
            Only start_url / id change: ?start= is the page the app was installed
            from (path + query, e.g. "/BrandName" or "/?id=1,2"), so each
            restaurant's tablet opens straight into its own menu, and two brands
            installed on one device stay two separate apps.
            Icons: ~/assets/media/logos/app-icons/ (built from TMM_New_Logo22.png). */
        [HttpGet]
        [ResponseCache(Duration = 3600, Location = ResponseCacheLocation.Any, VaryByQueryKeys = new[] { "start" })]
        public ActionResult Manifest(string start)
        {
            string startUrl = Url.Content("~/");
            if (!string.IsNullOrWhiteSpace(start) && start.Length <= 400 &&
                start.StartsWith("/") && !start.StartsWith("//") && !start.StartsWith("/\\"))
            {
                startUrl = start;   // same-origin relative path only
            }

            Func<string, string> icon = file => Url.Content("~/assets/media/logos/app-icons/" + file);
            var manifest = new
            {
                id = startUrl,
                name = "TMM eMenu",
                short_name = "TMM",
                description = "Digital menu and online ordering - powered by TMM eMenu",
                start_url = startUrl,
                scope = Url.Content("~/"),
                display = "standalone",
                display_override = new[] { "fullscreen", "standalone" },
                orientation = "any",
                background_color = "#ffffff",
                theme_color = "#ffffff",
                icons = new object[]
                {
                    new { src = icon("icon-192.png"),          sizes = "192x192", type = "image/png", purpose = "any" },
                    new { src = icon("icon-512.png"),          sizes = "512x512", type = "image/png", purpose = "any" },
                    new { src = icon("icon-maskable-192.png"), sizes = "192x192", type = "image/png", purpose = "maskable" },
                    new { src = icon("icon-maskable-512.png"), sizes = "512x512", type = "image/png", purpose = "maskable" }
                }
            };
            return Content(JsonConvert.SerializeObject(manifest), "application/manifest+json", System.Text.Encoding.UTF8);
        }

        [HttpPost]
        public JsonResult GetItemImages(int ItemId)
        {
            try
            {
                SqlParameter[] spa = { new SqlParameter(){ ParameterName="@ItemID", SqlDbType=SqlDbType.Int, Value=ItemId } };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemImages", spa);
                if (ds != null && ds.Tables.Count > 0)
                {
                    return Json(new { Message = "Success", dtImages = JsonConvert.SerializeObject(ds.Tables[0]) }, JsonRequestBehavior.AllowGet);
                }
                return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "GetItemImages", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }
    }
    public class ExtraItemsobject
    {
        public int UID { get; set; }
        public int MI { get; set; }
        public int ExId { get; set; }
        public int GId { get; set; }
        public string ITEM_NAME { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public decimal PRICE { get; set; }
    }
    public class choicesobject
    {
        public int UID { get; set; }
        public int MI { get; set; }
        public int ChId { get; set; }
        public int GId { get; set; }
        public string ITEM_NAME { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public decimal PRICE { get; set; }
    }
    public class FeedBackResponse
    {
        public int QuestionId { get; set; }
        public int Response_Type { get; set; }
        public string Response { get; set; }
    }
}
