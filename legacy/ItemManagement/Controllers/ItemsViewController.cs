using AttributeRouting.Web.Mvc;
using Jar.Helper;
using Jar.Models;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Net;
using System.Web;
using System.Web.Mvc;
using System.Web.Script.Serialization;

namespace Jar.Controllers
{
    public class ItemsViewController : Controller
    {
        public static string PublicIP = "";
        public static string BrowserName = "";
        //Mobile Manufacturer
        public static string MobileDeviceManu = "";
        //Mobile Manufacturer
        public static string MobileDeviceModal = "";

        //
        // GET: /ItemsView/
        public ActionResult Index(string id)
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
            ViewBag.IsCartVisible = Convert.ToBoolean(System.Configuration.ConfigurationManager.AppSettings["IsCartVisible"]);
            GetBrandHomePaggeImage(ViewBag.BrandId);
            return View();
        }

        public ActionResult IndexOld(string id)
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
            ViewBag.IsCartVisible = Convert.ToBoolean(System.Configuration.ConfigurationManager.AppSettings["IsCartVisible"]);
            GetBrandHomePaggeImage(ViewBag.BrandId);
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
                int IsCartVisible = 0;
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBrandHomePageImage", spa);
                if (ds != null && ds.Tables.Count > 0)
                {
                    ImageName = ds.Tables[0].Rows[0]["BrandHomePageImage"].ToString();
                    facebookUrl = ds.Tables[0].Rows[0]["Facebook"].ToString();
                    instagramUrl = ds.Tables[0].Rows[0]["Instagram"].ToString();
                    whatsAppUrl = ds.Tables[0].Rows[0]["WhatsAppURL"].ToString();
                    CurrencyENG = ds.Tables[0].Rows[0]["Currency"].ToString();
                    CurrencyArab = ds.Tables[0].Rows[0]["CurrencyArabic"].ToString();
                    IsCartVisible = Convert.ToInt32(ds.Tables[0].Rows[0]["IsCartVisible"]);
                }
                ViewBag.BrandHomePageImage = ImageName;
                ViewBag.facebookUrl = facebookUrl;
                ViewBag.instagramUrl = instagramUrl;
                ViewBag.whatsAppUrl = whatsAppUrl;
                ViewBag.CurrencyENG = CurrencyENG;
                ViewBag.CurrencyArab = CurrencyArab;
                ViewBag.IsCrtVisible = IsCartVisible;
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetBrandHomePaggeImage", null);
            }
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
                DB.AuditTrail(ex, "ItemsViewController", "setViewBagFromSettings", null);
                ViewBag.isReservation = false;
            }

        }
        public JsonResult GetBranchAndSectionList(int? BrandId)
        {
            try
            {
                GetAuditDetails();
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBranchAndSectionList", spa);
                List<Sections> Sections = new List<Sections>();
                List<SectionBranch> Branch = new List<SectionBranch>();
                if (ds != null && ds.Tables.Count > 1)
                {
                    DataTable dtSections = ds.Tables[0];
                    if (dtSections.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtSections.Rows)
                        {
                            Sections.Add(new Sections
                            {
                                id = Convert.ToInt32(dtRow["id"].ToString()),
                                sectionName = dtRow["sectionName"].ToString(),
                                SectionNameArabic = dtRow["SectionNameArabic"].ToString(),
                            });
                        }
                    }

                    DataTable dtBranch = ds.Tables[1];
                    if (dtBranch.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtBranch.Rows)
                        {
                            Branch.Add(new SectionBranch
                            {
                                id = Convert.ToInt32(dtRow["id"].ToString()),
                                branchName = dtRow["branchName"].ToString(),
                                branchNameAra = dtRow["branchNameAra"].ToString(),
                                brandId = Convert.ToInt32(dtRow["brandId"].ToString()),
                                sectionId = Convert.ToInt32(dtRow["sectionId"].ToString()),
                                branchImg = dtRow["branchImg"].ToString(),
                            });
                        }
                    }
                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);

                }

                return Json(new { Message = "Success", dtSections = Sections, dtBranch = Branch }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetBranchAndSectionList", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult GetCategoryList(int? BrandId, int? Branchid, int? CategoryId)
        {
            try
            {
                // The CUSTOMER menu is always sub-category-aware. Whether a category
                // actually nests is decided per-category (IsHaveSubCategory from the DB),
                // and how it renders is design-driven (only Design4 shows the accordion).
                // The "IsSubCategory" AppSetting must NOT affect the customer menu — it only
                // governs the admin Add/Edit-Category "Is Sub Category" option. Forcing this
                // to 1 keeps Design1/2/3 rendering correctly regardless of that admin setting.
                // (Previously this read AppSettings["IsSubCategory"]; setting it false made
                //  sp_GetCategoryList return all categories for a selected category, which
                //  made Design1 render the sub-category accordion instead of item cards.)
                int isSubcategoryProject = 1;

                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    },new SqlParameter(){
                                       ParameterName="@Branchid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Branchid
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@IPAddress",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=PublicIP
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@BrowserName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=BrowserName
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@DeviceModal",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=MobileDeviceModal
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@DeviceManufacturer",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=MobileDeviceManu
                                    }

                                    ,new SqlParameter(){
                                       ParameterName="@MainCategoryId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=CategoryId
                                    }

                                    ,new SqlParameter(){
                                       ParameterName="@isSubcategoryProject",
                                       SqlDbType=SqlDbType.Int,
                                       Value=isSubcategoryProject
                                    }

                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryList", spa);
                List<CategoriesManage> Category = new List<CategoriesManage>();
                List<CategoriesManage> subCategory = new List<CategoriesManage>();
                List<ItemsList> Items = new List<ItemsList>();
                if (ds != null && ds.Tables.Count > 1)
                {
                    DataTable dtCategory = ds.Tables[0];
                    if (dtCategory.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtCategory.Rows)
                        {
                            Category.Add(new CategoriesManage
                            {
                                CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                                CAT_NAME = dtRow["CAT_NAME"].ToString(),
                                CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                                ImageName = dtRow["ImageName"].ToString(),
                                MainCategory = Convert.ToInt32(dtRow["MainCategory"].ToString()),
                                IsHaveSubCategory = Convert.ToInt32(dtRow["IsHaveSubCategory"].ToString()),
                            });
                        }
                    }

                    DataTable dtItems = ds.Tables[1];
                    if (dtItems.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtItems.Rows)
                        {
                            Items.Add(new ItemsList
                            {
                                id = Convert.ToInt32(dtRow["id"].ToString()),
                                CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                                ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                                CAT_NAME = dtRow["CAT_NAME"].ToString(),
                                CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                                PRICE = dtRow["PRICE"].ToString(),
                                ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                                INGREDIENT = dtRow["INGREDIENT"].ToString(),
                                INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                                IMAGENAME = dtRow["IMAGENAME"].ToString(),
                                Video = dtRow["Video"].ToString(),
                                Currency = dtRow["Currency"].ToString(),
                                HID = Convert.ToInt32(dtRow["HID"].ToString()),
                                MinGroupModifierSelection = Convert.ToInt32(dtRow["MinGroupModifierSelection"].ToString()),
                            });
                        }
                    }

                    DataTable dtSubCategories = ds.Tables[2];
                    if (dtSubCategories.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtSubCategories.Rows)
                        {
                            subCategory.Add(new CategoriesManage
                            {
                                CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                                CAT_NAME = dtRow["CAT_NAME"].ToString(),
                                CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                                ImageName = dtRow["ImageName"].ToString(),
                                MainCategory = Convert.ToInt32(dtRow["MainCategory"].ToString()),
                                IsHaveSubCategory = Convert.ToInt32(dtRow["IsHaveSubCategory"].ToString()),
                            });
                        }
                    }
                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);

                }

                return Json(new { Message = "Success", dtCategory = Category, dtItems = Items, dtSubCategory= subCategory }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetCategoryList", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult GetItemList(int Cat_Num, int? BrandId, int? Branchid)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Cat_Num
                                    },new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    },new SqlParameter(){
                                       ParameterName="@Branchid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Branchid
                                    }

                                    ,new SqlParameter(){
                                       ParameterName="@IPAddress",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=PublicIP
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@BrowserName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=BrowserName
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@DeviceModal",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=MobileDeviceModal
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@DeviceManufacturer",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=MobileDeviceManu
                                    }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryWiseItemList", spa);
                List<ItemsList> Items = new List<ItemsList>();
                List<ItemsAllergenList> itemsAllergenList = new List<ItemsAllergenList>();
                
                if (ds != null && ds.Tables.Count > 0)
                {
                    DataTable dtItems = ds.Tables[0];
                    if (dtItems.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtItems.Rows)
                        {
                            Items.Add(new ItemsList
                            {
                                id = Convert.ToInt32(dtRow["id"].ToString()),
                                CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                                ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                                CAT_NAME = dtRow["CAT_NAME"].ToString(),
                                CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                                PRICE = dtRow["PRICE"].ToString(),
                                ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                                INGREDIENT = dtRow["INGREDIENT"].ToString(),
                                INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                                IMAGENAME = dtRow["IMAGENAME"].ToString(),
                                Video = dtRow["Video"].ToString(),
                                Currency = dtRow["Currency"].ToString(),
                                HID = Convert.ToInt32(dtRow["HID"].ToString()),
                                MinGroupModifierSelection = Convert.ToInt32(dtRow["MinGroupModifierSelection"].ToString()),
                            });
                        }
                    }

                    DataTable dtAllergenList = ds.Tables[1];
                    if (dtAllergenList.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtAllergenList.Rows)
                        {
                            itemsAllergenList.Add(new ItemsAllergenList
                            {
                                itemId = Convert.ToInt32(dtRow["itemId"].ToString()),
                                allergenId = Convert.ToInt32(dtRow["allergenId"].ToString()),
                                allergenName = dtRow["allergenName"].ToString(),
                                allergenNameArabic = dtRow["allergenNameArabic"].ToString(),
                                image = dtRow["image"].ToString(),
                            });
                        }
                    }
                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);

                }

                return Json(new { Message = "Success", dtItems = Items, dtItemsAllergenList= itemsAllergenList }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetItemList", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult GetCartViewItems(List<CartDetails> cartdetails,
            List<BindCartChoices> cartChoices, List<BindCartExtraItems> cartExtraItems,
             List<BindCartComments> cartComments)
        {
            try
            {
                List<ItemsListWithUID> Items = new List<ItemsListWithUID>();
                if (cartdetails != null)
                {
                    DataTable dtMainItems = cartdetails != null ? DB.ToDataTable(cartdetails) : null;
                    DataTable dtcartChoices = cartChoices != null ? DB.ToDataTable(cartChoices) : null;
                    DataTable dtcartExtraItems = cartExtraItems != null ? DB.ToDataTable(cartExtraItems) : null;
                    DataTable dtcartComments = cartComments != null ? DB.ToDataTable(cartComments) : null;
                    SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@dttblCartItems",
                                       Value=dtMainItems
                                    },
                                       new SqlParameter(){
                                       ParameterName="@dttblCartChoices",
                                       Value=dtcartChoices
                                    },new SqlParameter(){
                                       ParameterName="@dttblCartExtraItems",
                                       Value=dtcartExtraItems
                                    },new SqlParameter(){
                                       ParameterName="@dttblCartComments",
                                       Value=dtcartComments
                                    }
                                    };
                    DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCartItemChoicesExtraCommentList", spa1);

                    if (ds != null && ds.Tables.Count > 0)
                    {
                        DataTable dtItems = ds.Tables[0];
                        DataTable dtChoices = ds.Tables[1];
                        DataTable dtExtraItems = ds.Tables[2];
                        DataTable dtComments = ds.Tables[3];
                        if (dtItems.Rows.Count > 0)
                        {
                            foreach (DataRow dtRow in dtItems.Rows)
                            {
                                Items.Add(new ItemsListWithUID
                                {
                                    UID = Convert.ToInt32(dtRow["UID"].ToString()),
                                    id = Convert.ToInt32(dtRow["id"].ToString()),
                                    CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                                    ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                                    CAT_NAME = dtRow["CAT_NAME"].ToString(),
                                    CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                                    PRICE = dtRow["PRICE"].ToString(),
                                    ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                                    INGREDIENT = dtRow["INGREDIENT"].ToString(),
                                    INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                                    IMAGENAME = dtRow["IMAGENAME"].ToString(),
                                    Video = dtRow["Video"].ToString(),
                                    TotalPrice = dtRow["TotalPrice"].ToString(),
                                    qty = Convert.ToInt32(dtRow["Qty"].ToString()),
                                    Currency = dtRow["Currency"].ToString(),
                                    Comments = dtRow["Comments"].ToString(),
                                    HID = Convert.ToInt32(dtRow["HID"].ToString()),
                                    ChoiceName = dtRow["ChoiceName"].ToString(),
                                    ChoiceName_ARABIC = dtRow["ChoiceName_ARABIC"].ToString(),
                                    //Comments= cartdetails.Where(x=>x.ItemId == Convert.ToInt32(dtRow["id"].ToString())).Select(x=>x.Comments).FirstOrDefault()
                                });
                            }
                        }
                        return Json(new
                        {
                            Message = "Success",
                            dtItems = Items,
                            dtChoicesItems = JsonConvert.SerializeObject(dtChoices),
                            dtExtraItems = JsonConvert.SerializeObject(dtExtraItems),
                            dtComments = JsonConvert.SerializeObject(dtComments)
                        }, JsonRequestBehavior.AllowGet);
                    }
                }
                return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetCartViewItems", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        [HttpPost]
        public JsonResult SubmitOrder(List<CartDetails> orderDetails, CustomerNew customerInfo, Address addressInfo,
            int branchid, DateTime? DeliveryDate, int selectedPayementType, int DiscountTypeID, decimal InvoiceDiscount,
            string DiscountCode, Guid? clientOrderGuid = null)
        {
            try
            {
                // ----------------------------------------------------------
                // 1. Expand the cart (unchanged - resolves choices and extras)
                // ----------------------------------------------------------
                DataTable dt = DB.ToDataTable(orderDetails);
                SqlParameter[] spa1 = {
                    new SqlParameter { ParameterName = "@dttblCartItems", Value = dt }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCartItemList", spa1);
                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return Json(new { Message = "Fail", dtresult = "", InvoiceNo = (long?)null }, JsonRequestBehavior.AllowGet);

                int brandid = 0;
                if (ds.Tables.Count == 2 && ds.Tables[1].Rows.Count > 0)
                    brandid = Convert.ToInt32(ds.Tables[1].Rows[0]["BrandID"]);

                // ----------------------------------------------------------
                // 2. Waiter (unchanged)
                // ----------------------------------------------------------
                int WaiterID = 0;
                HttpCookie cookie = Request.Cookies["eCommerceCook"];
                if (cookie != null && !string.IsNullOrEmpty(cookie["IsWaiterLogin"]))
                    WaiterID = Convert.ToInt32(cookie["WaiterID"]);

                // ----------------------------------------------------------
                // 3. Legacy path, behind a switch. Flip OrderMode back to
                //    CallCenter to revert without a redeploy.
                // ----------------------------------------------------------
                string orderMode = System.Configuration.ConfigurationManager.AppSettings["OrderMode"] ?? "LocalDB";
                if (orderMode.Equals("CallCenter", StringComparison.OrdinalIgnoreCase))
                    return SubmitOrderViaCallCenter(ds.Tables[0], customerInfo, addressInfo, branchid, brandid,
                                                    DeliveryDate, selectedPayementType, DiscountTypeID,
                                                    InvoiceDiscount, DiscountCode, WaiterID);

                // ----------------------------------------------------------
                // 4. Build the TVP rows
                // ----------------------------------------------------------
                var items = new List<POSOrderItem>();
                foreach (DataRow row in ds.Tables[0].Rows)
                {
                    int? parentId = ToNullableInt(row["ParentItemID"]);
                    items.Add(new POSOrderItem
                    {
                        // The cart identifies items by HID; the proc resolves
                        // either HID or tblItems.ID, so both are sent.
                        ItemID         = ToNullableInt(row["HID"]),
                        HID            = ToNullableInt(row["HID"]),
                        ParentItemID   = parentId,
                        CartItemUniqID = ToNullableInt(row["CartItemUniqID"]),
                        LineType       = (parentId ?? 0) > 0 ? (byte)2 : (byte)1,
                        Quantity       = Convert.ToInt32(row["Qty"]),
                        Price          = row["PRICE"] != DBNull.Value ? Convert.ToDecimal(row["PRICE"]) : (decimal?)null,
                        Comments       = row.Table.Columns.Contains("Comments")   ? Convert.ToString(row["Comments"])   : null,
                        Extra          = row.Table.Columns.Contains("ChoiceName") ? Convert.ToString(row["ChoiceName"]) : null
                    });
                }

                // ----------------------------------------------------------
                // 5. Order type + payment type
                // ----------------------------------------------------------
                bool isTakeAway = customerInfo != null && customerInfo.TakeAway == true;
                int orderType   = isTakeAway ? 1 : 2;                 // 1 Pickup, 2 Delivery

                bool isPrepaid;
                int paymentType = POSOrderService.MapPaymentType(selectedPayementType, !isTakeAway, out isPrepaid);

                // Idempotency key: a retry or a double-tap must return the
                // original invoice rather than creating a second one.
                Guid guid = clientOrderGuid ?? BuildFallbackGuid(customerInfo, branchid, items);

                // ----------------------------------------------------------
                // 6. Insert
                // ----------------------------------------------------------
                POSOrderResult res = POSOrderService.ProcessOrder(
                    items, customerInfo, addressInfo,
                    branchid, brandid, orderType, paymentType, isPrepaid, null,
                    DeliveryDate, DiscountTypeID, InvoiceDiscount, DiscountCode,
                    WaiterID, guid);

                if (res.Message != "Success" && res.Message != "Duplicate")
                {
                    DB.AuditTrail(new Exception(res.ErrorMessage ?? "sp_POS_ProcessOrder returned no invoice"),
                                  "ItemsViewController", "SubmitOrder", null);
                    return Json(new { Message = "Fail", dtresult = "", InvoiceNo = (long?)null }, JsonRequestBehavior.AllowGet);
                }

                // ----------------------------------------------------------
                // 7. Response shaped exactly like the call-centre one.
                //    An array, because Payment.cshtml does JSON.parse(...)[0].
                //    FinalAmount carries NetPayable: the DB column of that name
                //    excludes DeliveryCharges, but the customer pays it.
                // ----------------------------------------------------------
                // The number the customer is shown, read from the row rather
                // than rebuilt here. Keeping the formula in one place - the
                // computed column - is the point of POS_32: a second copy in C#
                // is a second thing to keep in step, and the copy that gets
                // forgotten is the one printed on the customer's receipt.
                string invoiceNumShow = null;
                if (res.InvoiceNo.HasValue)
                {
                    try
                    {
                        DataSet dsShow = DB.ExecuteStoredProcDataSet("sp_POS_GetInvoiceNumShow",
                            new[] { new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = res.InvoiceNo.Value } });

                        if (dsShow != null && dsShow.Tables.Count > 0 && dsShow.Tables[0].Rows.Count > 0
                            && dsShow.Tables[0].Rows[0]["InvoiceNumShow"] != DBNull.Value)
                            invoiceNumShow = Convert.ToString(dsShow.Tables[0].Rows[0]["InvoiceNumShow"]);
                    }
                    catch
                    {
                        // POS_32 not run yet. The confirmation falls back to the
                        // invoice number, which is what it showed before.
                    }
                }

                var payload = new[]
                {
                    new
                    {
                        InvoiceNo       = res.InvoiceNo,
                        InvoiceNumShow  = invoiceNumShow,
                        TrackingCode    = res.TrackingCode,
                        RunningOrder    = res.RunningOrder,
                        DeliveryDate    = DeliveryDate,
                        BillAmount      = res.BillAmount,
                        Discount        = res.Discount,
                        DeliveryCharges = res.DeliveryCharges,
                        FinalAmount     = res.NetPayable,
                        InvoiceTotal    = res.FinalAmount,
                        PaymentType     = paymentType,
                        CustomerId      = res.CustomerId,
                        AddressID       = res.AddressID,
                        Warning         = res.Warning
                    }
                };

                // ----------------------------------------------------------
                // 8. WhatsApp the customer.
                //
                //    Only on "Success". res.Message can also be "Duplicate",
                //    which is the idempotency key doing its job on a retry or a
                //    double-tap - the order already existed and was already
                //    confirmed, so sending again would mean two messages for
                //    one order.
                //
                //    Queued rather than called inline. The customer is waiting
                //    on this response, and a provider that is slow to answer
                //    would hold up a confirmation for an order that is already
                //    safely committed. QueueBackgroundWorkItem hands the work to
                //    the ASP.NET runtime, which keeps the app pool alive until
                //    it finishes instead of tearing the thread down mid-request
                //    the way a raw ThreadPool item can be.
                //
                //    Nothing here can fail the order: SendOrderConfirmation
                //    returns its errors rather than throwing, and the whole
                //    block is wrapped anyway.
                // ----------------------------------------------------------
                if (res.Message == "Success" && Jar.Helper.WhatsAppService.Enabled)
                {
                    string waMobile   = customerInfo != null ? customerInfo.Mobile : null;
                    string waName     = customerInfo != null ? customerInfo.CustomerName : null;
                    string waOrderNo  = invoiceNumShow ?? (res.InvoiceNo.HasValue
                                                            ? res.InvoiceNo.Value.ToString()
                                                            : "");
                    decimal waTotal   = res.NetPayable;      // what the customer actually pays
                    string waTracking = res.TrackingCode;

                    System.Web.Hosting.HostingEnvironment.QueueBackgroundWorkItem(_ =>
                    {
                        try
                        {
                            var wa = Jar.Helper.WhatsAppService.SendOrderConfirmation(
                                waMobile, waName, waOrderNo, waTotal, waTracking);

                            // Anything that is not a successful send is logged,
                            // skips included. This block only runs when the
                            // feature is switched ON, and once it is on,
                            // "skipped because the token is blank" is exactly
                            // what someone wondering why no message arrived
                            // needs to see. A silent skip there is
                            // indistinguishable from the feature not running.
                            if (!wa.Sent)
                            {
                                DB.AuditTrail(
                                    Loggable((wa.Skipped ? "WhatsApp SKIPPED" : "WhatsApp FAILED")
                                             + " for order " + waOrderNo
                                             + " to " + (wa.To ?? waMobile ?? "(no number)")
                                             + ": " + wa.Reason
                                             + (string.IsNullOrEmpty(wa.Raw) ? "" : " | " + wa.Raw)),
                                    "ItemsViewController", "SubmitOrder.WhatsApp", null);
                            }
                        }
                        catch (Exception waEx)
                        {
                            // This runs after the response has gone; an escape
                            // here would be an unhandled exception on a
                            // background thread, which recycles the app pool.
                            try { DB.AuditTrail(waEx, "ItemsViewController", "SubmitOrder.WhatsApp", null); }
                            catch { }
                        }
                    });
                }

                // One-shot token for StartOnlinePayment. Held in session so the
                // customer's own browser can start a payment for THIS order
                // without a login, and nobody else can.
                string payToken = Guid.NewGuid().ToString("N");
                if (res.InvoiceNo.HasValue)
                    Session["POSPayToken_" + res.InvoiceNo.Value] = payToken;

                return Json(new
                {
                    Message      = "Success",
                    dtresult     = JsonConvert.SerializeObject(payload),
                    InvoiceNo    = res.InvoiceNo,
                    TrackingCode = res.TrackingCode,
                    Warning      = res.Warning,
                    PayToken     = payToken,
                    IsOnlinePayment = isPrepaid
                }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "SubmitOrder", null);
                return Json(new { Message = "Fail", dtresult = "", InvoiceNo = (long?)null }, JsonRequestBehavior.AllowGet);
            }
        }

        /// <summary>
        /// Wraps a message in an exception that is safe to hand to DB.AuditTrail.
        ///
        /// AuditTrail reads ex.StackTrace.ToString(), and StackTrace is NULL on
        /// an exception that was constructed but never thrown - so logging a
        /// plain "new Exception(msg)" throws a NullReferenceException INSIDE the
        /// logger and the message is lost. Throwing and immediately catching it
        /// here is what gives it a stack trace.
        ///
        /// Worth knowing: the "new Exception(...)" call in the failure branch of
        /// SubmitOrder above has this same fault and has therefore never
        /// recorded a failed order. Left alone here to keep this change to the
        /// WhatsApp work, but it wants the same treatment.
        /// </summary>
        private static Exception Loggable(string message)
        {
            try { throw new InvalidOperationException(message); }
            catch (Exception ex) { return ex; }
        }

        private static int? ToNullableInt(object v)
        {
            if (v == null || v == DBNull.Value) return null;
            int i;
            return int.TryParse(v.ToString(), out i) ? i : (int?)null;
        }

        /// <summary>
        /// Deterministic idempotency key for clients that do not send one:
        /// same customer + branch + cart within the same minute yields the same
        /// GUID, so a double-tap returns the original invoice.
        /// </summary>
        private static Guid BuildFallbackGuid(CustomerNew c, int branchId, List<POSOrderItem> items)
        {
            string basis = string.Concat(
                c != null ? c.Mobile : "", "|", branchId, "|",
                DateTime.Now.ToString("yyyyMMddHHmm"), "|",
                string.Join(",", items.Select(x => x.ItemID + "x" + x.Quantity)));

            using (var md5 = System.Security.Cryptography.MD5.Create())
                return new Guid(md5.ComputeHash(System.Text.Encoding.UTF8.GetBytes(basis)));
        }

        /// <summary>
        /// The original call-centre path, unchanged. Reachable via
        /// OrderMode=CallCenter. Delete once the local path is proven.
        /// </summary>
        private JsonResult SubmitOrderViaCallCenter(DataTable dtItems, CustomerNew customerInfo, Address addressInfo,
            int branchid, int brandid, DateTime? DeliveryDate, int selectedPayementType, int DiscountTypeID,
            decimal InvoiceDiscount, string DiscountCode, int WaiterID)
        {
            var value = new List<ItemViewOrder>();
            foreach (DataRow dtRow in dtItems.Rows)
            {
                value.Add(new ItemViewOrder
                {
                    WaiterID       = WaiterID,
                    ItemID         = dtRow["HID"].ToString(),
                    Quantity       = Convert.ToInt32(dtRow["Qty"].ToString()),
                    Comments       = dtRow["Comments"].ToString(),
                    Price          = Convert.ToDecimal(dtRow["PRICE"].ToString()),
                    HID            = 0,
                    BID            = 0,
                    CartItemUniqID = Convert.ToInt32(dtRow["CartItemUniqID"].ToString()),
                    ParentItemID   = Convert.ToInt32(dtRow["ParentItemID"].ToString())
                });
            }

            string webServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"];
            if (string.IsNullOrEmpty(webServiceUrl))
                return Json(new { Message = "Fail", dtresult = "" }, JsonRequestBehavior.AllowGet);

            var data = new
            {
                OrderDetails    = value,
                CustomerInfo    = customerInfo,
                addressInfo     = addressInfo,
                DeliveryDate    = DeliveryDate,
                DiscountTypeID  = DiscountTypeID,
                InvoiceDiscount = InvoiceDiscount,
                selectedPayementType = selectedPayementType,
                BranchID        = branchid,
                HID             = 0,
                BID             = 0,
                WaiterID        = WaiterID,
                BrandId         = brandid,
                InvoiceTypeID   = System.Configuration.ConfigurationManager.AppSettings["InvoiceTypeID"],
                DeliveryCharges = 0,
                DiscountCode    = DiscountCode,
                IsOnlineOrder   = true
            };

            string inputJson = (new JavaScriptSerializer()).Serialize(data);
            using (var client = new WebClient())
            {
                client.Headers["Content-type"] = "application/json";
                client.Encoding = System.Text.Encoding.UTF8;
                string jsonstr = client.UploadString(webServiceUrl + "/DmToCallCenterServices/ProcessOrderHD", inputJson);
                result str = JsonConvert.DeserializeObject<result>(jsonstr);
                return Json(str, JsonRequestBehavior.AllowGet);
            }
        }


        [HttpPost]
        public JsonResult GetLangLabels(string selectedLang)
        {
            try
            {
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@selectedLang",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=selectedLang
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetLangLabels", spa1);
                if (ds.Tables.Count > 0)
                {
                    if (ds.Tables[0].Rows.Count > 0)
                    {
                        DataTable dt = ds.Tables[0];
                        string jsonData = JsonConvert.SerializeObject(dt);
                        return Json(new { Message = "Success", dtLabels = jsonData }, JsonRequestBehavior.AllowGet);
                    }
                }
                return Json(new { Message = "Success", dtLabels = "" }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetLangLabels", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

        }

        //[HttpPost]
        //public JsonResult TrackOrder(string InoiceNumber)
        //{
        //    try
        //    {
        //        SqlParameter[] spa1 ={
        //                                new SqlParameter(){
        //                                ParameterName="@InvoiceNo",
        //                                SqlDbType=SqlDbType.NVarChar,
        //                                Value=InoiceNumber
        //                                }
        //                            };
        //        DataSet ds = DB2.ExecuteStoredProcDataSet("sp_GetInvoiceTrackOrder", spa1);
        //        if (ds.Tables.Count > 0)
        //        {
        //            if (ds.Tables[0].Rows.Count > 0)
        //            {
        //                List<DriverTrackingData> objdata = new List<DriverTrackingData>();

        //                string InvoiceStatus = ds.Tables[0].Rows[0][0].ToString();

        //                if (ds.Tables.Count > 1)
        //                {
        //                    DataTable dtMapdata = ds.Tables[1];
        //                    if (dtMapdata.Rows.Count > 0)
        //                    {
        //                        foreach (DataRow dtRow in dtMapdata.Rows)
        //                        {
        //                            objdata.Add(new DriverTrackingData
        //                            {
        //                                InvoiceNo = dtRow["InvoiceNo"].ToString(),
        //                                DriverId = Convert.ToInt32(dtRow["DriverId"].ToString()),
        //                                DriverName = dtRow["DriverName"].ToString(),
        //                                DriverColor = dtRow["DriverColor"].ToString(),
        //                                DriverImage = dtRow["DriverImage"].ToString(),
        //                                FromLat = dtRow["FromLat"].ToString(),
        //                                FromLong = dtRow["FromLong"].ToString(),
        //                                FromDateTime = dtRow["FromDateTime"].ToString(),
        //                                ToLat = dtRow["ToLat"].ToString(),
        //                                ToLong = dtRow["ToLong"].ToString(),

        //                                CurrentLat = dtRow["CurrentLat"].ToString(),
        //                                CurrentLong = dtRow["CurrentLong"].ToString(),
        //                                CustomerName = dtRow["CustomerName"].ToString(),
        //                                CustomerAddress = dtRow["CustomerAddress"].ToString(),
        //                            });
        //                        }
        //                    }
        //                }
        //                return Json(new { Message = "Success", InvoiceStatus = InvoiceStatus, dtMapData = objdata }, JsonRequestBehavior.AllowGet);
        //            }
        //            return Json(new { Message = "Invalid Invoice Number.", InvoiceStatus = "" }, JsonRequestBehavior.AllowGet);

        //        }
        //        return Json(new { Message = "Invalid Invoice Number.", InvoiceStatus = "" }, JsonRequestBehavior.AllowGet);
        //    }
        //    catch (Exception ex)
        //    {
        //        return Json(new { Message = "Error,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
        //    }

        //}

        /// <summary>
        /// Starts an online payment for an order the customer has just placed,
        /// and returns the gateway URL for the browser to go to.
        ///
        /// This is reachable WITHOUT a POS login, because the caller is the
        /// customer. It is guarded by a one-shot token that SubmitOrder put in
        /// their session: without it, anyone could POST an invoice number and
        /// have us send that customer's name to the gateway, or mint payment
        /// links for orders that are not theirs.
        ///
        /// Whether the order is an online one is read from the INVOICE, never
        /// from the request - the browser does not get to decide that a
        /// cash-on-delivery order should skip payment.
        /// </summary>
        [HttpPost]
        public JsonResult StartOnlinePayment(long invoiceNo, string payToken)
        {
            try
            {
                string expected = Session["POSPayToken_" + invoiceNo] as string;

                if (string.IsNullOrEmpty(expected) ||
                    !string.Equals(expected, payToken, StringComparison.Ordinal))
                {
                    DB.AuditTrail(new Exception("StartOnlinePayment token mismatch for invoice " + invoiceNo),
                                  "ItemsViewController", "StartOnlinePayment", null);
                    return Json(new { Message = "Fail", Detail = "This payment session is no longer valid." },
                                JsonRequestBehavior.AllowGet);
                }

                if (!PaymentLinkService.IsOnlineOrder(invoiceNo))
                    return Json(new { Message = "NotOnline" }, JsonRequestBehavior.AllowGet);

                string root = Request.Url.GetLeftPart(UriPartial.Authority);
                string cb   = root + Url.Action("Callback", "Payment", new { area = "POS" });
                string er   = root + Url.Action("Failed",   "Payment", new { area = "POS" });

                PaymentLinkResult r = PaymentLinkService.Start(invoiceNo, null, cb, er, null);

                if (!r.Success)
                    return Json(new { Message = "Fail", Detail = r.Error }, JsonRequestBehavior.AllowGet);

                // One shot. The token is spent whether or not the customer
                // completes the payment, so a stale confirmation page cannot be
                // replayed to mint more links.
                Session.Remove("POSPayToken_" + invoiceNo);

                return Json(new
                {
                    Message    = "Success",
                    PaymentUrl = r.PaymentUrl,
                    Reference  = r.Reference,
                    Amount     = r.Amount
                }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "StartOnlinePayment", null);
                return Json(new { Message = "Fail", Detail = "Could not start the payment." },
                            JsonRequestBehavior.AllowGet);
            }
        }

        /// <summary>
        /// Payment methods for the customer checkout.
        ///
        /// Returns only tblInvoicePaymentType rows with IsOnline = 1, so the
        /// list is controlled from the database rather than from markup and an
        /// appSetting. Image holds a file name resolved against /images.
        ///
        /// Pass includeCOD=1 to also show cash on delivery.
        /// </summary>
        [HttpPost]
        public JsonResult GetPaymentTypes(bool includeCOD = false)
        {
            try
            {
                SqlParameter[] spa =
                {
                    new SqlParameter("@IncludeCOD", SqlDbType.Bit) { Value = includeCOD }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetOnlinePaymentTypes", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return Json(new { Message = "Success", dtresult = "[]" }, JsonRequestBehavior.AllowGet);

                // Resolve the image to a usable URL here rather than in the
                // browser: the site can run under a virtual directory, where a
                // hard-coded "../../images/x.png" breaks depending on the
                // current route depth.
                string baseUrl = Url.Content("~/images/");
                DataTable dt = ds.Tables[0];

                if (!dt.Columns.Contains("ImageUrl")) dt.Columns.Add("ImageUrl", typeof(string));

                foreach (DataRow r in dt.Rows)
                {
                    string img = r["Image"] != DBNull.Value ? Convert.ToString(r["Image"]).Trim() : "";
                    if (img.Length == 0)
                    {
                        r["ImageUrl"] = "";                       // the view falls back to a label
                    }
                    else if (img.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                          || img.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                          || img.StartsWith("/"))
                    {
                        r["ImageUrl"] = img;                      // already a full path or CDN url
                    }
                    else
                    {
                        r["ImageUrl"] = baseUrl + img;
                    }
                }

                return Json(new
                {
                    Message  = "Success",
                    dtresult = JsonConvert.SerializeObject(dt)
                }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetPaymentTypes", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        /// <summary>
        /// Area list for the delivery-address screen.
        ///
        /// Now served from the LOCAL tblArea. It previously called the call
        /// centre, which meant the dropdown carried the call centre's AreaIDs
        /// while orders inserted into the local database -- so every
        /// tblCustomerAddress.AreaID, every delivery charge lookup and every
        /// branch-serves-area check was reading a foreign ID.
        ///
        /// Response shape is unchanged ({ Message, dtresult }) so the existing
        /// JS keeps working.
        /// </summary>
        [HttpPost]
        public JsonResult GetAreaList(int? branchId = null)
        {
            try
            {
                SqlParameter[] spa =
                {
                    new SqlParameter("@BranchID", SqlDbType.Int)
                        { Value = (branchId.HasValue && branchId.Value > 0) ? (object)branchId.Value : DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAreaListForDeliveryAddress", spa);

                if (ds != null && ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0)
                    return Json(new
                    {
                        Message  = "Success",
                        dtresult = JsonConvert.SerializeObject(ds.Tables[0])
                    }, JsonRequestBehavior.AllowGet);

                return Json(new { Message = "Success", dtresult = "[]" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetAreaList", null);
                return Json(new { Message = "Error,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
            }
        }

        /// <summary>
        /// Resolves a delivery area from map coordinates plus whatever name
        /// hints the reverse geocoder produced.
        ///
        /// Matching is done in SQL rather than by comparing dropdown text in
        /// the browser: ESRI returns 'Al Salmiyah' where tblArea holds
        /// 'Salmiya', so exact text equality -- which is what the page did --
        /// essentially never matched.
        ///
        /// MatchType tells the caller how far to trust the answer:
        ///   Polygon / Name -> safe to select automatically
        ///   Nearest        -> suggest only; never silently commit a guess
        /// </summary>
        [HttpPost]
        public JsonResult ResolveArea(decimal? lat, decimal? lng, string areaHint, string areaHint2, int? branchId)
        {
            try
            {
                SqlParameter[] spa =
                {
                    new SqlParameter("@Lat",       SqlDbType.Decimal)      { Precision = 10, Scale = 7, Value = (object)lat ?? DBNull.Value },
                    new SqlParameter("@Lng",       SqlDbType.Decimal)      { Precision = 10, Scale = 7, Value = (object)lng ?? DBNull.Value },
                    new SqlParameter("@AreaHint",  SqlDbType.NVarChar, 200){ Value = string.IsNullOrWhiteSpace(areaHint)  ? (object)DBNull.Value : areaHint },
                    new SqlParameter("@AreaHint2", SqlDbType.NVarChar, 200){ Value = string.IsNullOrWhiteSpace(areaHint2) ? (object)DBNull.Value : areaHint2 },
                    new SqlParameter("@BranchID",  SqlDbType.Int)          { Value = (branchId.HasValue && branchId.Value > 0) ? (object)branchId.Value : DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_ResolveArea", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return Json(new { Message = "NotFound" }, JsonRequestBehavior.AllowGet);

                DataRow r = ds.Tables[0].Rows[0];
                return Json(new
                {
                    Message         = "Success",
                    AreaID          = Convert.ToInt32(r["AreaID"]),
                    AreaName        = Convert.ToString(r["AreaName"]),
                    AreaNameAra     = Convert.ToString(r["AreaNameAra"]),
                    DeliveryCharges = Convert.ToDecimal(r["DeliveryCharges"]),
                    MatchType       = Convert.ToString(r["MatchType"]),
                    DistanceKm      = r["DistanceKm"]     == DBNull.Value ? (decimal?)null : Convert.ToDecimal(r["DistanceKm"]),
                    ServedByBranch  = r["ServedByBranch"] != DBNull.Value && Convert.ToBoolean(r["ServedByBranch"])
                }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "ResolveArea", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        /// <summary>
        /// Block lookup for the delivery-address map, from OpenStreetMap's
        /// geocoder (Nominatim), cached in tblPOS_GeoCache.
        ///
        /// TLS NOTE - this is the most likely reason the previous version
        /// returned nothing. .NET Framework 4.8 honours whatever
        /// ServicePointManager.SecurityProtocol was left at, and on many
        /// existing app pools that still means SSL3/TLS1.0. Nominatim is
        /// HTTPS-only and TLS 1.2+, so WebClient throws
        /// "The request was aborted: Could not create SSL/TLS secure channel"
        /// -- which the catch block swallowed into a generic Fail. The
        /// protocol is now forced explicitly.
        ///
        /// Pass debug=1 to get the raw response and the real exception back,
        /// instead of having failures disappear into the audit log.
        /// </summary>
        [HttpPost]
        public JsonResult ReverseGeocodeBlock(decimal? lat, decimal? lng, int debug = 0)
        {
            if (!lat.HasValue || !lng.HasValue)
                return Json(new { Message = "Fail", Detail = "lat/lng missing" }, JsonRequestBehavior.AllowGet);

            // ~11 metres. Rounding is what makes the cache hit at all, rather
            // than storing a row per pixel of the map.
            decimal rlat = Math.Round(lat.Value, 4);
            decimal rlng = Math.Round(lng.Value, 4);

            string rawJson = null;
            string errDetail = null;

            try
            {
                // ---- cache ----
                SqlParameter[] cget =
                {
                    new SqlParameter("@Lat", SqlDbType.Decimal) { Precision = 10, Scale = 4, Value = rlat },
                    new SqlParameter("@Lng", SqlDbType.Decimal) { Precision = 10, Scale = 4, Value = rlng }
                };
                DataSet cds = DB.ExecuteStoredProcDataSet("sp_POS_GeoCacheGet", cget);
                if (cds != null && cds.Tables.Count > 0 && cds.Tables[0].Rows.Count > 0)
                {
                    DataRow c = cds.Tables[0].Rows[0];
                    string cb = Convert.ToString(c["Block"]);
                    return Json(new
                    {
                        Message = string.IsNullOrEmpty(cb) ? "NotFound" : "Success",
                        Block = cb,
                        Neighbourhood = Convert.ToString(c["Neighbourhood"]),
                        Cached = true,
                        Detail = "from cache"
                    }, JsonRequestBehavior.AllowGet);
                }

                // ---- Nominatim ----
                // Force a modern protocol. Without this the call fails on any
                // app pool whose default is still TLS 1.0.
                System.Net.ServicePointManager.SecurityProtocol =
                    (System.Net.SecurityProtocolType)3072 |            // Tls12
                    (System.Net.SecurityProtocolType)12288;            // Tls13 where available

                string url = string.Format(
                    System.Globalization.CultureInfo.InvariantCulture,
                    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat={0}&lon={1}&zoom=18&addressdetails=1&accept-language=en",
                    rlat, rlng);

                using (var client = new WebClient())
                {
                    // Nominatim rejects anonymous agents outright.
                    // >>> put a real contact address here <<<
                    client.Headers["User-Agent"] = "QRMenuPOS/1.0 (+admin@tmm-menu.com)";
                    client.Headers["Accept"] = "application/json";
                    client.Encoding = System.Text.Encoding.UTF8;
                    rawJson = client.DownloadString(url);
                }

                var root = JsonConvert.DeserializeObject<Newtonsoft.Json.Linq.JObject>(rawJson);
                var addr = root != null ? root["address"] as Newtonsoft.Json.Linq.JObject : null;

                string block = null, hood = null;
                if (addr != null)
                {
                    // OSM in Kuwait carries the block in one of these, usually
                    // as literal text ("Block 4") or the bare number.
                    block = FirstBlockLike(addr, "neighbourhood", "quarter", "city_block",
                                                 "suburb", "city_district", "residential", "hamlet");
                    hood = Str(addr, "suburb") ?? Str(addr, "neighbourhood") ?? Str(addr, "city_district");
                }

                // Cache the miss too: asking Nominatim the same unanswerable
                // question forever is exactly what its rate limits punish.
                SqlParameter[] cset =
                {
                    new SqlParameter("@Lat",           SqlDbType.Decimal)      { Precision = 10, Scale = 4, Value = rlat },
                    new SqlParameter("@Lng",           SqlDbType.Decimal)      { Precision = 10, Scale = 4, Value = rlng },
                    new SqlParameter("@Block",         SqlDbType.NVarChar, 50) { Value = (object)block ?? DBNull.Value },
                    new SqlParameter("@Neighbourhood", SqlDbType.NVarChar,200) { Value = (object)hood  ?? DBNull.Value },
                    new SqlParameter("@RawJson",       SqlDbType.NVarChar)     { Value = (object)rawJson ?? DBNull.Value }
                };
                DB.ExecuteStoredProc("sp_POS_GeoCacheSet", cset);

                return Json(new
                {
                    Message = string.IsNullOrEmpty(block) ? "NotFound" : "Success",
                    Block = block,
                    Neighbourhood = hood,
                    Cached = false,
                    Detail = string.IsNullOrEmpty(block) ? "OSM returned no block field" : null,
                    Raw = debug == 1 ? rawJson : null
                }, JsonRequestBehavior.AllowGet);
            }
            catch (WebException wex)
            {
                // Surface the real cause. A silent Fail here is what made the
                // last two rounds of this guesswork.
                errDetail = wex.Status + ": " + wex.Message;
                var resp = wex.Response as HttpWebResponse;
                if (resp != null) errDetail += " (HTTP " + (int)resp.StatusCode + ")";

                DB.AuditTrail(wex, "ItemsViewController", "ReverseGeocodeBlock", null);
                return Json(new { Message = "Fail", Detail = errDetail, Raw = debug == 1 ? rawJson : null },
                            JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                errDetail = ex.GetType().Name + ": " + ex.Message;
                if (ex.InnerException != null) errDetail += " | inner: " + ex.InnerException.Message;

                DB.AuditTrail(ex, "ItemsViewController", "ReverseGeocodeBlock", null);
                return Json(new { Message = "Fail", Detail = errDetail, Raw = debug == 1 ? rawJson : null },
                            JsonRequestBehavior.AllowGet);
            }
        }

        private static string Str(Newtonsoft.Json.Linq.JObject o, string key)
        {
            var t = o[key];
            if (t == null) return null;
            string s = t.ToString().Trim();
            return s.Length == 0 ? null : s;
        }

        /// <summary>
        /// Pulls a block number out of the first OSM field that looks like one.
        /// Accepts "Block 4", "Blk 4", "قطعة 4" or a bare number, and nothing
        /// else: a wrong block on a delivery is worse than a blank box the
        /// customer fills in themselves.
        /// </summary>
        private static string FirstBlockLike(Newtonsoft.Json.Linq.JObject addr, params string[] keys)
        {
            var re = new System.Text.RegularExpressions.Regex(
                @"(?:block|blk|qitaa|قطعة|قطعه|القطعة)\s*[:\-]?\s*(\d{1,3}[A-Za-z]?)",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);

            foreach (string k in keys)
            {
                string v = Str(addr, k);
                if (v == null) continue;

                var m = re.Match(v);
                if (m.Success) return m.Groups[1].Value;

                if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^\d{1,3}[A-Za-z]?$"))
                    return v;
            }
            return null;
        }

        [HttpPost]
        public JsonResult BindItemExtraItemsAndComments(int itemid, int Branchid)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@itemid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=itemid
                                    },new SqlParameter(){
                                       ParameterName="@Branchid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Branchid
                                    }

                                    ,new SqlParameter(){
                                       ParameterName="@IPAddress",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=PublicIP
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@BrowserName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=BrowserName
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@DeviceModal",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=MobileDeviceModal
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@DeviceManufacturer",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=MobileDeviceManu
                                    }

                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemExtraItemsAndComments", spa);
                //List<ExtraItemsList> Items = new List<ExtraItemsList>();
                //List<ItemExtraComments> ExtraComments = new List<ItemExtraComments>();
                //List<ExtraItemsList> Choices = new List<ExtraItemsList>();
                if (ds != null && ds.Tables.Count > 0)
                {
                    //DataTable dtItems = ds.Tables[0];
                    //if (dtItems.Rows.Count > 0)
                    //{
                    //    foreach (DataRow dtRow in dtItems.Rows)
                    //    {
                    //        Items.Add(new ExtraItemsList
                    //        {
                    //            id = Convert.ToInt32(dtRow["id"].ToString()),
                    //            //CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                    //            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                    //            //CAT_NAME = dtRow["CAT_NAME"].ToString(),
                    //            //CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                    //            PRICE = dtRow["PRICE"].ToString(),
                    //            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                    //            //INGREDIENT = dtRow["INGREDIENT"].ToString(),
                    //            //INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                    //            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                    //            //Currency = dtRow["Currency"].ToString(),
                    //            HID = Convert.ToInt32(dtRow["HID"].ToString()),
                    //        });
                    //    }
                    //}



                    //if (ds.Tables.Count > 1)
                    //{
                    //    DataTable dtComments = ds.Tables[1];
                    //    if (dtComments.Rows.Count > 0)
                    //    {
                    //        foreach (DataRow dtRow in dtComments.Rows)
                    //        {
                    //            ExtraComments.Add(new ItemExtraComments
                    //            {
                    //                id = Convert.ToInt32(dtRow["id"].ToString()),
                    //                comments_arb = dtRow["comments_arb"].ToString(),
                    //                comments_eng = dtRow["comments_eng"].ToString(),
                    //            });
                    //        }
                    //    }
                    //}


                    //if (ds.Tables.Count > 2)
                    //{
                    //    DataTable dtChoices = ds.Tables[2];
                    //    if (dtChoices.Rows.Count > 0)
                    //    {
                    //        foreach (DataRow dtRow in dtChoices.Rows)
                    //        {
                    //            Choices.Add(new ExtraItemsList
                    //            {
                    //                id = Convert.ToInt32(dtRow["id"].ToString()),
                    //                //CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                    //                ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                    //                //CAT_NAME = dtRow["CAT_NAME"].ToString(),
                    //                //CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                    //                PRICE = dtRow["PRICE"].ToString(),
                    //                ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                    //                //INGREDIENT = dtRow["INGREDIENT"].ToString(),
                    //                //INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                    //                IMAGENAME = dtRow["IMAGENAME"].ToString(),
                    //                //Currency = dtRow["Currency"].ToString(),
                    //                HID = Convert.ToInt32(dtRow["HID"].ToString()),
                    //            });
                    //        }
                    //    }
                    //}

                    return Json(new
                    {
                        Message = "Success",
                        //dtItems = JsonConvert.SerializeObject(ds.Tables[0]),
                        dtchoicesAndExtraItems = JsonConvert.SerializeObject(ds.Tables[0]),
                        dtExtraComments = JsonConvert.SerializeObject(ds.Tables[1]),
                        //dtChoices = JsonConvert.SerializeObject(ds.Tables[2]) 
                    }, JsonRequestBehavior.AllowGet);

                }
                else
                {
                    return Json(new
                    {
                        Message = "NoData",
                        dtItems = "",
                        dtExtraComments = "",
                        dtChoices = ""
                    }, JsonRequestBehavior.AllowGet);

                }

                //return Json(new
                //{
                //    Message = "Success",
                //    dtItems = Items,
                //    dtExtraComments = ExtraComments,
                //    dtChoices = Choices
                //}, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "BindItemExtraItemsAndComments", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        public void GetAuditDetails()
        {
            HttpBrowserCapabilitiesBase browser = Request.Browser;

            //PublicIP = GetPublicIPAddress();
            MobileDeviceManu = browser.MobileDeviceManufacturer;
            MobileDeviceModal = browser.MobileDeviceModel;
            BrowserName = browser.Browser;
        }

        static string GetPublicIPAddress()
        {
            try
            {
                String address = "";
                WebRequest request = WebRequest.Create("http://checkip.dyndns.org/");
                using (WebResponse response = request.GetResponse())
                using (StreamReader stream = new StreamReader(response.GetResponseStream()))
                {
                    address = stream.ReadToEnd();
                }

                int first = address.IndexOf("Address: ") + 9;
                int last = address.LastIndexOf("</body>");
                address = address.Substring(first, last - first);

                return address;
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetPublicIPAddress", null);
                return "";
            }
        }

        [HttpPost]
        public JsonResult SetIpAddress(string IpAddress)
        {
            try
            {
                PublicIP = IpAddress;
                //SqlParameter[] spa1 ={
                //                        new SqlParameter(){
                //                        ParameterName="@selectedLang",
                //                        SqlDbType=SqlDbType.NVarChar,
                //                        Value=selectedLang
                //                        }
                //                    };
                //DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetLangLabels", spa1);
                //if (ds.Tables.Count > 0)
                //{
                //    if (ds.Tables[0].Rows.Count > 0)
                //    {
                //        DataTable dt = ds.Tables[0];
                //        string jsonData = JsonConvert.SerializeObject(dt);
                //        return Json(new { Message = "Success", dtLabels = jsonData }, JsonRequestBehavior.AllowGet);
                //    }
                //}
                return Json(new { Message = "Success", dtLabels = "" }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "SetIpAddress", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult CheckDiscountCouponCode(string DiscountCode)
        {
            try
            {
                if (!string.IsNullOrEmpty(DiscountCode))
                {
                    string webServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                    if (!string.IsNullOrEmpty(webServiceUrl))
                    {
                        var data = new
                        {
                            DiscountCode = DiscountCode
                        };

                        string inputJson = (new JavaScriptSerializer()).Serialize(data);
                        WebClient client = new WebClient();
                        client.Headers["Content-type"] = "application/json";
                        client.Encoding = System.Text.Encoding.UTF8;
                        string jsonstr = client.UploadString(webServiceUrl + "/DmToCallCenterServices/CheckDiscountCouponCode", inputJson);
                        result str = JsonConvert.DeserializeObject<result>(jsonstr);
                        return Json(str, JsonRequestBehavior.AllowGet);
                    }

                    //SqlParameter[] spa1 ={
                    //                   new SqlParameter(){
                    //                   ParameterName="@DiscountCode",
                    //                   SqlDbType=SqlDbType.NVarChar,
                    //                   Value=DiscountCode
                    //                }
                    //                };
                    //DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCartItemList", spa1);
                    //if (ds != null && ds.Tables.Count > 0)
                    //{
                    //    if (ds.Tables[0].Rows.Count > 0)
                    //    {
                    //        return Json(new { Message = "Success", CouponCodeId = ds.Tables[0].Rows[0]["CouponCodeId"] }, JsonRequestBehavior.AllowGet);
                    //    }
                    //}
                }
                else
                {
                    return Json(new { Message = "InValid" }, JsonRequestBehavior.AllowGet);
                }
                return Json(new { Message = "InValid" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "CheckDiscountCouponCode", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }
    }

    public class result
    {
        public string Message { get; set; }
        public string dtresult { get; set; }
    }
}
