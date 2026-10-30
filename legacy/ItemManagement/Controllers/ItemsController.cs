using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using Jar.Models;
using System.Data;
using Jar.Helper;
using System.Data.SqlClient;
using System.Collections;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Configuration;
using static Jar.Models.mobileData;
using System.Web.Script.Serialization;
using System.Net;

namespace Jar.Controllers
{
    public class ItemsController : Controller
    {
        public static int RoleID;
        public static int FeedBack;
        
        public static Boolean isLogin;
        public static Boolean OtherLanguages;
        public static Boolean isSlideShow;
        public static Boolean isTheme;
        public static int WaiterID;
        public static string BrandID;
        public static int MultipleBranch;
        //public ActionResult Login()
        //{
        //    return View();
        //}
        [HttpPost]
        public JsonResult UserLogin(UserLogin value)
        {
            HttpCookie cookie = new HttpCookie("eCommerceCook");
            SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@Username",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Username
                                    }, new SqlParameter(){
                                       ParameterName="@Password",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Password
                                    }
                               };
            DataSet ds = DB.ExecuteStoredProcDataSet("mvc_sp_Login", spa);
            if (ds.Tables[0].Rows.Count > 0)
            {
                DataRow dtRow = ds.Tables[0].Rows[0];

                isLogin = true;
                //string Username = ds.Tables[0].Rows[0][1].ToString();
                //string Name = ds.Tables[0].Rows[0][2].ToString();
                //BrandID = ds.Tables[0].Rows[0][3].ToString();
                //RoleID = Convert.ToInt16(ds.Tables[0].Rows[0][4].ToString());
                //WaiterID = Convert.ToInt32(ds.Tables[0].Rows[0][0].ToString());
                string Username = dtRow["UserName"].ToString();
                string Name = dtRow["Name"].ToString();
                BrandID = dtRow["BrandID"].ToString();
                RoleID = Convert.ToInt32(dtRow["Role_ID"].ToString());
                WaiterID = Convert.ToInt32(dtRow["ID"].ToString());
                FeedBack = Convert.ToBoolean(dtRow["FeedBack"].ToString()) == true ? 1 : 0;
                MultipleBranch = Convert.ToBoolean(dtRow["MultipleBranch"].ToString()) == true ? 1 : 0;

                cookie["UserName"] = Username;
                cookie["Name"] = Name;
                cookie["BrandID"] = BrandID.ToString();
                cookie["RoleID"] = RoleID.ToString();
                cookie["WaiterID"] = WaiterID.ToString();
                cookie["FeedBack"] = FeedBack.ToString();
                cookie["MultipleBranch"] = MultipleBranch.ToString();
                Response.Cookies.Add(cookie);

                return Json(new { Message = "Success", RoleID = RoleID, OtherLanguages = false }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
        }

        [HttpPost]
        public JsonResult WaiterLogin(WaiterLogin value)
        {
            try
            {
                HttpCookie cookie = new HttpCookie("eCommerceCook");
                string webServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                if (!string.IsNullOrEmpty(webServiceUrl))
                {
                    var data = new
                    {
                        BranchId = value.BranchId,
                        Password = value.Password,
                    };
                    string inputJson = (new JavaScriptSerializer()).Serialize(data);
                    WebClient client = new WebClient();
                    client.Headers["Content-type"] = "application/json";
                    client.Encoding = System.Text.Encoding.UTF8;
                    var jsonresult = client.UploadString(webServiceUrl + "/DmToCallCenterServices/WaiterLoginverify", inputJson);
                    WaiterLoginData LoginData = (new JavaScriptSerializer()).Deserialize<WaiterLoginData>(jsonresult);
                    //return jsonresult;

                    if (LoginData != null)
                    {
                        if (LoginData.Message == "Success")
                        {
                            WaiterUser objWaiterUser = LoginData.dtLoginData[0];

                            isLogin = true;
                            //string Username = ds.Tables[0].Rows[0][1].ToString();
                            //string Name = ds.Tables[0].Rows[0][2].ToString();
                            //BrandID = ds.Tables[0].Rows[0][3].ToString();
                            //RoleID = Convert.ToInt16(ds.Tables[0].Rows[0][4].ToString());
                            //WaiterID = Convert.ToInt32(ds.Tables[0].Rows[0][0].ToString());
                            string Username = objWaiterUser.UserName;
                            string Name = objWaiterUser.Name;
                            string BrandID = objWaiterUser.BrandID.ToString();
                            string BrandName = objWaiterUser.BrandName.ToString();
                            string BranchName = objWaiterUser.BranchName.ToString();
                            RoleID = Convert.ToInt32(objWaiterUser.Role);
                            WaiterID = Convert.ToInt32(objWaiterUser.ID);
                            FeedBack = 0;
                            MultipleBranch = 0;
                            //FeedBack = Convert.ToBoolean(objWaiterUser.FeedBack) == true ? 1 : 0;
                            //MultipleBranch = Convert.ToBoolean(dtRow["MultipleBranch"].ToString()) == true ? 1 : 0;

                            cookie["UserName"] = Username;
                            cookie["Name"] = Name;
                            cookie["BrandID"] = BrandID.ToString();
                            cookie["RoleID"] = RoleID.ToString();
                            cookie["WaiterID"] = WaiterID.ToString();
                            cookie["FeedBack"] = FeedBack.ToString();
                            cookie["MultipleBranch"] = MultipleBranch.ToString();
                            cookie["IsWaiterLogin"] = "true";
                            Response.Cookies.Add(cookie);

                            string id = "";

                            if(objWaiterUser.BrandID > 0 && objWaiterUser.BranchID > 0)
                            {
                                id = objWaiterUser.BrandID.ToString() + "," + objWaiterUser.BranchID.ToString();
                                //name = BrandName + "," + BranchName;
                            }

                            return Json(new { Message = "Success", RoleID = RoleID, OtherLanguages = false, id = id }, JsonRequestBehavior.AllowGet);
                            //return Json(new { Message = "Success", RoleID = RoleID, OtherLanguages = false, name = name }, JsonRequestBehavior.AllowGet);

                        }
                        else
                        {
                            //Message = LoginData.Message
                            return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
                        }
                        
                    }

                    return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);

                    //return Json(jsonresult);

                }
                return Json(new { Message = "Error,Contact Your Manager." }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewNewController", "BindTrackorderdataNew", null);
                return Json(new { Message = "Error,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
            }

        }
        public ActionResult Logout(UserLogin value)
        {
            HttpCookie cookie = new HttpCookie("eCommerceCook");
            cookie.Expires = DateTime.Now.AddDays(-1);
            Response.Cookies.Add(cookie);

            return RedirectToAction("Index", "Login");
        }

        public ActionResult Index()
        {
            return View();
        }
        public ActionResult Items()
        {
            if (isLogin)
            {
                ViewData["RoleID"] = RoleID;
                ViewData["ThemeUser"] = isTheme;
                ViewData["OtherLanguages"] = OtherLanguages;
                ViewData["FeedBack"] = FeedBack;
                if (RoleID == 5)
                    return RedirectToAction("SlideShows", "SlideShow");
                else
                {
                    return View();
                }
            }
            else
            {
                return View("AccessDenied");
            }

        }
        public JsonResult Item(int CatNo)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=BrandID
                                    }, new SqlParameter(){
                                       ParameterName="@CatNo",
                                       SqlDbType=SqlDbType.Int,
                                       Value=CatNo
                                    },
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("mvc_sp_GetItems", spa);
                List<Items> Items = new List<Items>();
                DataTable dtItems = ds.Tables[1];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {


                        Items.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                            ItemNameMan = dtRow["ItemNameMan"].ToString(),
                            ItemNameRus = dtRow["ItemNameRus"].ToString(),
                            PRICE = dtRow["PRICE"].ToString(),
                            INGREDIENT = dtRow["INGREDIENT"].ToString(),
                            INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                            INGREDIENT_Man = dtRow["INGREDIENT_Man"].ToString(),
                            INGREDIENT_Rus = dtRow["INGREDIENT_Rus"].ToString(),
                            BrandName = dtRow["BrandName"].ToString(),
                            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                            ITEM_DESC_ENG = dtRow["ITEM_DESC_ENG"].ToString(),
                            Video = dtRow["Video"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                            BrandID = Convert.ToInt32(dtRow["BrandID"].ToString()),
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
                            IsExtraItems = Convert.ToBoolean(dtRow["isExtra"].ToString()),

                        });
                    }
                }

                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json("'Fail':'true'");
            }

        }

        public JsonResult AddItem(Items value)
        {
            try
            {
                var ImageName = value.IMAGENAME;
                string strpath = ".jpg";
                if (value.IMAGENAME != null)
                {
                    ImageName = RenameImanges(value.IMAGENAME);
                    strpath = Path.GetExtension(ImageName);

                }
                if (strpath != ".jpg" && strpath != ".jpeg" && strpath != ".gif" && strpath != ".png")
                {
                    return Json(new { Message = "Extension Not Supported" }, JsonRequestBehavior.AllowGet);
                }
                else
                {
                    SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.CAT_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@ITEM_NAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ITEM_NAME
                                    },  new SqlParameter(){
                                       ParameterName="@ITEM_NAME_ARABIC",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ITEM_NAME_ARABIC
                                    },  new SqlParameter(){
                                       ParameterName="@ItemNameMan",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ItemNameMan
                                    },  new SqlParameter(){
                                       ParameterName="@ItemNameRus",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ItemNameRus
                                    },  new SqlParameter(){
                                       ParameterName="@PRICE",
                                       SqlDbType=SqlDbType.Decimal,
                                       Value=value.PRICE
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT_ARABIC",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT_ARABIC
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT_Rus",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT_Rus
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT_Man",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT_Man
                                    },  new SqlParameter(){
                                       ParameterName="@IMAGENAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=ImageName
                                    },  new SqlParameter(){
                                       ParameterName="@ITEM_DESC_ENG",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ITEM_DESC_ENG
                                    },  new SqlParameter(){
                                       ParameterName="@Seq_Num",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Seq_Num
                                    },  new SqlParameter(){
                                       ParameterName="@ShowInTablet",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ShowInTablet
                                    },  new SqlParameter(){
                                       ParameterName="@Video",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Video
                                    },  new SqlParameter(){
                                       ParameterName="@isExtra",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.IsExtraItems
                                    }
                               };

                    //int ds = DB.ExecuteStoredProc("mvc_sp_AddItem", spa);
                    DataSet ds = DB.ExecuteStoredProcDataSet("mvc_sp_AddItem", spa);
                    int ItemId = Convert.ToInt32(ds.Tables[0].Rows[0][0].ToString());



                    if (!value.IsExtraItems)
                    {
                        //start assign Branches 
                        if (value.BranchData != null)
                        {
                            if (value.BranchData.Count > 0)
                            {
                                for (int i = 0; i < value.BranchData.Count; i++)
                                {
                                    SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@BranchId",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.BranchData[i].BranchId
                                        },new SqlParameter(){
                                           ParameterName="@BrandID",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.BrandID
                                        },  new SqlParameter(){
                                           ParameterName="@Itemid",
                                           SqlDbType=SqlDbType.Int,
                                           Value=ItemId
                                        }, new SqlParameter(){
                                           ParameterName="@Count",
                                           SqlDbType=SqlDbType.Int,
                                           Value=i
                                        }
                            };
                                    DB.ExecuteStoredProcDataSet("sp_AssignBrandItems", spa1);
                                }
                            }
                        }
                        //End assign Branches 

                        //start assign extra items 
                        if (value.ExtraItems != null)
                        {
                            if (value.ExtraItems.Count > 0)
                            {
                                for (int i = 0; i < value.ExtraItems.Count; i++)
                                {
                                    SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@ExtraItemId",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.ExtraItems[i].ID
                                        },new SqlParameter(){
                                           ParameterName="@Itemid",
                                           SqlDbType=SqlDbType.Int,
                                           Value=ItemId
                                        }, new SqlParameter(){
                                           ParameterName="@Count",
                                           SqlDbType=SqlDbType.Int,
                                           Value=i
                                        }
                            };

                                    DB.ExecuteStoredProcDataSet("sp_Assign_Item_Extras", spa1);

                                }
                            }
                        }
                        //End assign extra items 

                        //start assign Items Comments
                        if (value.Comments != null)
                        {
                            if (value.Comments.Count > 0)
                            {
                                for (int i = 0; i < value.Comments.Count; i++)
                                {
                                    SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@commentid",
                                           SqlDbType=SqlDbType.Int,
                                           Value =value.Comments[i].id
                                        },new SqlParameter(){
                                           ParameterName="@Itemid",
                                           SqlDbType=SqlDbType.Int,
                                           Value=ItemId
                                        }, new SqlParameter(){
                                           ParameterName="@Count",
                                           SqlDbType=SqlDbType.Int,
                                           Value=i
                                        }
                            };

                                    DB.ExecuteStoredProcDataSet("sp_Assign_Item_Comments", spa1);

                                }
                            }
                        }
                        //End assign Items Comments
                    }

                }

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UpdateItem(Items value)
        {
            try
            {
                var ImageName = value.IMAGENAME;
                string strpath = ".jpg";
                if (value.IMAGENAME != null)
                {
                    ImageName = RenameImanges(value.IMAGENAME);
                    strpath = Path.GetExtension(ImageName);
                }
                if (strpath != ".jpg" && strpath != ".jpeg" && strpath != ".gif" && strpath != ".png")
                {
                    return Json(new { Message = "Extension Not Supported" }, JsonRequestBehavior.AllowGet);
                }
                else
                {

                    SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ID
                                    }, new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.CAT_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@ITEM_NAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ITEM_NAME
                                    },  new SqlParameter(){
                                       ParameterName="@ITEM_NAME_ARABIC",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ITEM_NAME_ARABIC
                                    },  new SqlParameter(){
                                       ParameterName="@ItemNameMan",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ItemNameMan
                                    },  new SqlParameter(){
                                       ParameterName="@ItemNameRus",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ItemNameRus
                                    },  new SqlParameter(){
                                       ParameterName="@PRICE",
                                       SqlDbType=SqlDbType.Decimal,
                                       Value=value.PRICE
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT_ARABIC",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT_ARABIC
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT_Rus",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT_Rus
                                    },  new SqlParameter(){
                                       ParameterName="@INGREDIENT_Man",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.INGREDIENT_Man
                                    },  new SqlParameter(){
                                       ParameterName="@IMAGENAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=ImageName
                                    },  new SqlParameter(){
                                       ParameterName="@ITEM_DESC_ENG",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ITEM_DESC_ENG
                                    },  new SqlParameter(){
                                       ParameterName="@Seq_Num",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Seq_Num
                                    },  new SqlParameter(){
                                       ParameterName="@ShowInTablet",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ShowInTablet
                                    },  new SqlParameter(){
                                       ParameterName="@Video",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Video
                                    },  new SqlParameter(){
                                       ParameterName="@isExtra",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.IsExtraItems
                                    }
                               };

                    int ds = DB.ExecuteStoredProc("mvc_sp_UpdateItem", spa);

                    if (!value.IsExtraItems)
                    {
                        //start assign Branches
                        if (value.BranchData != null)
                        {
                            if (value.BranchData.Count > 0)
                            {
                                for (int i = 0; i < value.BranchData.Count; i++)
                                {
                                    SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@BranchId",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.BranchData[i].BranchId
                                        },new SqlParameter(){
                                           ParameterName="@BrandID",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.BrandID
                                        },   new SqlParameter(){
                                           ParameterName="@Itemid",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.ID
                                        }, new SqlParameter(){
                                           ParameterName="@Count",
                                           SqlDbType=SqlDbType.Int,
                                           Value=i
                                        }
                            };
                                    DB.ExecuteStoredProcDataSet("sp_AssignBrandItems", spa1);
                                }
                            }
                            else
                            {
                                DB.ExecuteNonQuery("delete from Assign_Item where itemid = " + value.ID + "");
                            }
                        }
                        else
                        {
                            DB.ExecuteNonQuery("delete from Assign_Item where itemid = " + value.ID + "");
                        }
                        //End assign Branches 

                        //start assign extra items 
                        if (value.ExtraItems != null)
                        {
                            if (value.ExtraItems.Count > 0)
                            {
                                for (int i = 0; i < value.ExtraItems.Count; i++)
                                {
                                    SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@ExtraItemId",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.ExtraItems[i].ID
                                        },new SqlParameter(){
                                           ParameterName="@Itemid",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.ID
                                        }, new SqlParameter(){
                                           ParameterName="@Count",
                                           SqlDbType=SqlDbType.Int,
                                           Value=i
                                        }
                            };

                                    DB.ExecuteStoredProcDataSet("sp_Assign_Item_Extras", spa1);

                                }
                            }
                            else
                            {
                                DB.ExecuteNonQuery("delete from tblItem_Extras where itemid = " + value.ID + "");
                            }
                        }
                        else
                        {
                            DB.ExecuteNonQuery("delete from tblItem_Extras where itemid = " + value.ID + "");
                        }
                        //End assign extra items 

                        //start assign Items Comments
                        if (value.Comments != null)
                        {
                            if (value.Comments.Count > 0)
                            {
                                for (int i = 0; i < value.Comments.Count; i++)
                                {
                                    SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@commentid",
                                           SqlDbType=SqlDbType.Int,
                                           Value =value.Comments[i].id
                                        },new SqlParameter(){
                                           ParameterName="@Itemid",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.ID
                                        }, new SqlParameter(){
                                           ParameterName="@Count",
                                           SqlDbType=SqlDbType.Int,
                                           Value=i
                                        }
                            };
                                    DB.ExecuteStoredProcDataSet("sp_Assign_Item_Comments", spa1);
                                }
                            }
                            else
                            {
                                DB.ExecuteNonQuery("delete from tblItemComments where itemid = " + value.ID + "");
                            }
                        }
                        else
                        {
                            DB.ExecuteNonQuery("delete from tblItemComments where itemid = " + value.ID + "");
                        }
                        //End assign Items Comments
                    }

                }
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }   
        public JsonResult DeleteItem(Items value)
        {
            var ID = value.ID;
            try
            {
                DB.ExecuteNonQuery("delete from tblitems where ID = " + ID + "");
                DB.ExecuteNonQuery("delete from Assign_Item where itemid = " + ID + "");
                DB.ExecuteNonQuery("delete from tblItem_Extras where itemid = " + ID + "");
                DB.ExecuteNonQuery("delete from tblItemComments where itemid = " + ID + "");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UpdateItemSequence(List<Items> value)
        {
            try
            {
                for (int i = 0; i < value.Count; i++)
                {
                    SqlParameter[] spa ={  new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].ID
                                    },  new SqlParameter(){
                                       ParameterName="@Seq_Num",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].Seq_Num
                                    }
                               };

                    DB.ExecuteStoredProc("Items_UpdateSequence", spa);

                }

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult GetBrands()
        {
            SqlParameter[] spa ={
                                     new SqlParameter(){
                                       ParameterName="@WaiterID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=WaiterID
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBrands", spa);
            List<Brand> Brand = new List<Brand>();
            DataTable dtgrdBrand = ds.Tables[0];
            try
            {

                if (dtgrdBrand.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdBrand.Rows)
                    {
                        Brand.Add(new Brand
                        {
                            BrandID = Convert.ToInt32(dtRow["BrandID"].ToString()),
                            ThemeID = Convert.ToInt32(dtRow["Theme"].ToString()),
                            ThemeName = dtRow["ThemeName"].ToString(),
                            BrandLogo = dtRow["BrandImage"].ToString(),
                            BrandName = dtRow["BrandName"].ToString(),
                            BrandNameAr = dtRow["BrandNameAra"].ToString(),
                            BrandSeq = Convert.ToInt32(dtRow["BrandSeq"].ToString()),
                            Russian = Convert.ToInt32(dtRow["Russian"].ToString()),
                            Mandarin = Convert.ToInt32(dtRow["Mandarin"].ToString()),
                            BrandUrl = dtRow["brandUrl"].ToString(),
                        });
                    }
                }

                return Json(new { dtgrdBrand = Brand }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetTheme()
        {

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetThemes");
            List<themeData> themeData = new List<themeData>();
            DataTable dtgrdBrand = ds.Tables[0];
            try
            {

                if (dtgrdBrand.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdBrand.Rows)
                    {
                        themeData.Add(new themeData
                        {
                            themeID = Convert.ToInt32(dtRow["ThemeID"].ToString()),
                            brandID = Convert.ToInt32(dtRow["brandID"].ToString()),
                            themeName = dtRow["themeName"].ToString(),
                            categoryActive = dtRow["categoryActive"].ToString(),
                            BrandName = dtRow["BrandName"].ToString(),
                            categoryInActive = dtRow["categoryInActive"].ToString(),
                            setting = dtRow["setting"].ToString(),
                            englishButton = dtRow["englishButton"].ToString(),
                            arabicButton = dtRow["arabicButton"].ToString(),
                            closeButton = dtRow["closeButton"].ToString(),
                            homeScreen = dtRow["homeScreen"].ToString(),
                            popUpBackground = dtRow["popUpBackground"].ToString(),
                            FontColor = dtRow["FontColor"].ToString(),
                            FontColorItemName = dtRow["FontColorItemName"].ToString(),
                            FontColorIngName = dtRow["FontColorIngName"].ToString(),
                            FontColorPrice = dtRow["FontColorPrice"].ToString(),
                            itemBackgroundColor = dtRow["itemBackgroundColor"].ToString(),
                        });
                    }
                }

                return Json(new { dtgrdBrand = themeData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult EditTheme(themeData value, string Command)
        {
            try
            {
                value.categoryActive = RenameImanges(value.categoryActive);
                value.categoryInActive = RenameImanges(value.categoryInActive);
                value.englishButton = RenameImanges(value.englishButton);
                value.arabicButton = RenameImanges(value.arabicButton);
                value.closeButton = RenameImanges(value.closeButton);
                value.homeScreen = RenameImanges(value.homeScreen);
                value.popUpBackground = RenameImanges(value.popUpBackground);
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@themeID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.themeID
                                    },  new SqlParameter(){
                                       ParameterName="@themeName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.themeName
                                    },  new SqlParameter(){
                                       ParameterName="@categoryActive",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.categoryActive
                                    },  new SqlParameter(){
                                       ParameterName="@categoryInActive",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.categoryInActive
                                    },  new SqlParameter(){
                                       ParameterName="@englishButton",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.englishButton
                                    },  new SqlParameter(){
                                       ParameterName="@arabicButton",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.arabicButton
                                    },  new SqlParameter(){
                                       ParameterName="@closeButton",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.closeButton
                                    },  new SqlParameter(){
                                       ParameterName="@homeScreen",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.homeScreen
                                    },  new SqlParameter(){
                                       ParameterName="@popUpBackground",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.popUpBackground
                                    },  new SqlParameter(){
                                       ParameterName="@FontColor",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColor
                                    },  new SqlParameter(){
                                       ParameterName="@FontColorItemName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColorItemName
                                    },  new SqlParameter(){
                                       ParameterName="@FontColorIngName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColorIngName
                                    },  new SqlParameter(){
                                       ParameterName="@FontColorPrice",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColorPrice
                                    },  new SqlParameter(){
                                       ParameterName="@Command",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=Command
                                    },  new SqlParameter(){
                                       ParameterName="@itemBackgroundColor",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.itemBackgroundColor
                                    },  new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.brandID
                                    }
                               };

                DB.ExecuteStoredProc("sp_editThemes", spa);


            }
            catch (Exception ex)
            {
                return Json(new { Message = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        public ActionResult FeedbackData()
        {
            return View();

        }


        public JsonResult AddBrand(Brand value)
        {
            try
            {
                SqlParameter[] spa ={    new SqlParameter(){
                                       ParameterName="@BrandName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandName
                                    }, new SqlParameter(){
                                       ParameterName="@BrandNameAr",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandNameAr
                                    }, new SqlParameter(){
                                       ParameterName="@BrandSeq",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandSeq
                                    }, new SqlParameter(){
                                       ParameterName="@Russian",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Russian
                                    }, new SqlParameter(){
                                       ParameterName="@Mandarin",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Mandarin
                                    }, new SqlParameter(){
                                       ParameterName="@ThemeID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ThemeID
                                    },new SqlParameter(){
                                       ParameterName="@BrandLogo",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandLogo
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@Brandurl",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandUrl
                                    }
                               };

                int ds = DB.ExecuteStoredProc("sp_AddBrand", spa);
            }

            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UpdateBrand(Brand value)
        {
            try
            {
                SqlParameter[] spa ={    new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },   new SqlParameter(){
                                       ParameterName="@BrandName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandName
                                    }, new SqlParameter(){
                                       ParameterName="@BrandNameAr",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandNameAr
                                    }, new SqlParameter(){
                                       ParameterName="@BrandSeq",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandSeq
                                    }, new SqlParameter(){
                                       ParameterName="@Russian",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Russian
                                    }, new SqlParameter(){
                                       ParameterName="@Mandarin",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Mandarin
                                    }, new SqlParameter(){
                                       ParameterName="@ThemeID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ThemeID
                                    } ,new SqlParameter(){
                                       ParameterName="@BrandLogo",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandLogo
                                    },new SqlParameter(){
                                       ParameterName="@Brandurl",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandUrl
                                    }
                               };

                int ds = DB.ExecuteStoredProc("sp_UpdateBrand", spa);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DeleteBrand(Brand value)
        {
            var ID = value.BrandID;

            try
            {
                DB.ExecuteNonQuery("delete from tblBrand where BrandID = '" + ID + "'");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult Category(Brand value)
        {

            SqlParameter[] spa ={
                                     new SqlParameter(){
                                       ParameterName="@WaiterID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=WaiterID
                                    },new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },
            };

            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategory", spa);
                List<Category2> Category = new List<Category2>();
                DataTable dtCategory = ds.Tables[0];
                if (dtCategory.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtCategory.Rows)
                    {
                        Category.Add(new Category2
                        {
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
                            CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                            CatNameMan = dtRow["CatNameMan"].ToString(),
                            CatNameRus = dtRow["CatNameRus"].ToString(),
                            SEQ_NUM = Convert.ToInt32(dtRow["SEQ_NUM"].ToString()),
                            BrandID = Convert.ToInt32(dtRow["BrandID"].ToString()),
                            BrandName = dtRow["BrandName"].ToString(),
                            MainCategory = Convert.ToInt32(dtRow["MainCategory"].ToString()),
                        });
                    }
                }

                return Json(new { dtCategory = Category }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json("'Fail':'true'");
            }

        }


        public JsonResult AddCategory(Category2 value)
        {
            try
            {
                SqlParameter[] spa ={
                                     new SqlParameter(){
                                       ParameterName="@CAT_NAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CAT_NAME
                                    },  new SqlParameter(){
                                       ParameterName="@CAT_NAME_ARABIC",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CAT_NAME_ARABIC
                                    },  new SqlParameter(){
                                       ParameterName="@CatNameMan",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CatNameMan
                                    },  new SqlParameter(){
                                       ParameterName="@CatNameRus",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CatNameRus
                                    },  new SqlParameter(){
                                       ParameterName="@SEQ_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.SEQ_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },  new SqlParameter(){
                                       ParameterName="@ShowInTablet",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ShowInTablet
                                    },  new SqlParameter(){
                                       ParameterName="@MainCategory",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.MainCategory
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("mvc_sp_AddCategory", spa);

                int CatNum = Convert.ToInt32(ds.Tables[0].Rows[0][0].ToString());

                UpdateCatAssign(value, CatNum);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        private static void UpdateCatAssign(Category2 value, int CatNum)
        {
            for (int i = 0; i < value.BranchData.Count; i++)
            {
                SqlParameter[] spa1 ={
                                     new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },new SqlParameter(){
                                       ParameterName="@BranchId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BranchData[i].BranchId
                                    },  new SqlParameter(){
                                       ParameterName="@Cat_Num",
                                       SqlDbType=SqlDbType.Int,
                                       Value=CatNum
                                    }, new SqlParameter(){
                                       ParameterName="@Count",
                                       SqlDbType=SqlDbType.Int,
                                       Value=i
                                    },
                    };

                DB.ExecuteStoredProcDataSet("sp_AssignBrand", spa1);

            }
        }

        public JsonResult UpdateCategory(Category2 value)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CAT_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@CAT_NAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CAT_NAME
                                    },  new SqlParameter(){
                                       ParameterName="@CAT_NAME_ARABIC",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CAT_NAME_ARABIC
                                    }, new SqlParameter(){
                                       ParameterName="@CatNameRus",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CatNameRus
                                    }, new SqlParameter(){
                                       ParameterName="@CatNameMan",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CatNameMan
                                    },  new SqlParameter(){
                                       ParameterName="@SEQ_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.SEQ_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },  new SqlParameter(){
                                       ParameterName="@ShowInTablet",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ShowInTablet
                                    },  new SqlParameter(){
                                       ParameterName="@MainCategory",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.MainCategory
                                    }
                               };

                int ds = DB.ExecuteStoredProc("mvc_sp_UpdateCategory", spa);

                UpdateCatAssign(value, value.CAT_NUM);
                //for (int i = 0; i < value.BranchData.Count; i++)
                //{
                //    SqlParameter[] spa1 ={
                //                    new SqlParameter(){
                //                       ParameterName="@BrandID",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=value.BrandID
                //                    },new SqlParameter(){
                //                       ParameterName="@BranchId",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=value.BranchData[i].BranchId
                //                    },  new SqlParameter(){
                //                       ParameterName="@Cat_Num",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=value.CAT_NUM
                //                    }, new SqlParameter(){
                //                       ParameterName="@Count",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=i
                //                    },
                // };

                //    DB.ExecuteStoredProcDataSet("sp_AssignBrand", spa1);

                //}

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult UpdateCategorySequence(List<Categories> value)
        {
            try
            {
                for (int i = 0; i < value.Count; i++)
                {
                    SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value[i].CAT_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@SEQ_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].SEQ_NUM
                                    }
                               };

                    DB.ExecuteStoredProc("Category_UpdateSequence", spa);

                }

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult GetWebImageSlideShow()
        {

            List<Items> Items = new List<Items>();
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("WebSlideshow_GetImages", spa);

                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {
                        Items.Add(new Items
                        {

                            IMAGENAME = dtRow["WebSlideImageName"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["WebImageSequence"].ToString()),
                            ID = Convert.ToInt32(dtRow["id"].ToString()),

                        });
                    }
                }

                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult updateWebSlideShowSequence(List<Categories> value)
        {
            try
            {
                for (int i = 0; i < value.Count; i++)
                {
                    SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@id",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].CAT_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@SEQ_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].SEQ_NUM
                                    }
                               };

                    DB.ExecuteStoredProc("[WebSlideShow_UpdateSequence]", spa);

                }

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult updateSlideShowSequence(List<Categories> value)
        {
            try
            {
                for (int i = 0; i < value.Count; i++)
                {
                    SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@id",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].CAT_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@SEQ_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].SEQ_NUM
                                    }
                               };

                    DB.ExecuteStoredProc("[SlideShow_UpdateSequence]", spa);

                }

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult updatePromotionSequence(List<Categories> value)
        {
            try
            {
                for (int i = 0; i < value.Count; i++)
                {
                    SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@id",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].CAT_NUM
                                    },  new SqlParameter(){
                                       ParameterName="@SEQ_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value[i].SEQ_NUM
                                    }
                               };

                    DB.ExecuteStoredProc("[Promotion_UpdateSequence]", spa);

                }

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult DelteSlideShow(Category value)
        {
            var CAT_NUM = value.CAT_NUM;

            try
            {
                DB.ExecuteNonQuery("delete from tblImageSlideShow where id = " + CAT_NUM + "");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DeltePromotion(Category value)
        {
            var CAT_NUM = value.CAT_NUM;

            try
            {
                DB.ExecuteNonQuery("delete from tblPromotion where id = " + CAT_NUM + "");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DelteWebSlideShow(Category value)
        {
            var CAT_NUM = value.CAT_NUM;

            try
            {
                DB.ExecuteNonQuery("delete from tblWebImageSlideShow where id = " + CAT_NUM + "");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DeleteCategory(Category value)
        {
            var CAT_NUM = value.CAT_NUM;

            try
            {
                DB.ExecuteNonQuery("delete from tblcategory where CAT_NUM = '" + CAT_NUM + "'");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        public string RenameImanges(string Filename)
        {
            Filename = Filename.ToLower();
            Filename = Filename.Replace(" ", "_");
            Filename = Filename.Trim();
            Filename = Filename.Replace("%", "_");
            Filename = Filename.Replace("&", "_");
            Filename = Filename.Replace("#", "_");
            Filename = Filename.Replace("-", "_");
            Filename = Filename.Replace("@", "_");
            Filename = Filename.Replace("(", "_");
            Filename = Filename.Replace(")", "_");
            Filename = Filename.Replace("[", "_");
            Filename = Filename.Replace("]", "_");
            Filename = Filename.Replace("-", "_");
            return Filename;
        }

        public void uploadGif(HttpPostedFileBase fileToUpload)
        {
            HttpPostedFileBase file = fileToUpload;
            string imageUrls = "";
            string _FileName = "";
            string _path = "";
            try
            {
                if (file.ContentLength > 0)
                {
                    var Filename = file.FileName;
                    Filename = RenameImanges(Filename);
                    _path = Path.Combine(Server.MapPath("~/images"), Filename);

                    fileToUpload.SaveAs(_path);
                }
                System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");


            }
            catch
            {
                ViewBag.Message = "File upload failed!!";
                System.Diagnostics.Debug.WriteLine("File upload failed!!");

            }

        }
        public JsonResult UploadFile(HttpPostedFileBase fileToUpload)
        {
            HttpPostedFileBase file = fileToUpload;
            string imageUrls = "";
            string _FileName = "";
            string _path = "";
            string _Thumbnailpath = "";
            try
            {
                if (file.ContentLength > 0)
                {
                    var Filename = file.FileName;
                    string strpath = Path.GetExtension(Filename);
                    Filename = RenameImanges(Filename);

                    if (strpath == ".gif")
                    {
                        uploadGif(fileToUpload);
                        return Json(Filename);
                    }
                    _path = Path.Combine(Server.MapPath("~/images"), Filename);
                    _Thumbnailpath = Path.Combine(Server.MapPath("~/ThumbnailImages"), Filename);
                    byte[] fileData = null;
                    using (var binaryReader = new BinaryReader(file.InputStream))
                    {
                        fileData = binaryReader.ReadBytes(file.ContentLength);
                    }

                    HandleImageUpload(fileData, _path);
                    HandleThumbnailImageUpload(fileData, _Thumbnailpath);

                    imageUrls = "/images/" + Filename;
                }
                System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");

                return Json(imageUrls);
            }
            catch
            {
                ViewBag.Message = "File upload failed!!";
                System.Diagnostics.Debug.WriteLine("File upload failed!!");
                return Json(ViewBag.Message);
            }
        }
        public void AddSlideShowImage(string ImageName, int brandID)
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ImageName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=ImageName
                                    },  new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    }
                               };

            DB.ExecuteStoredProc("SlideShows_Add", spa);

        }
        public void AddPromotionImage(string ImageName, int brandID)
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ImageName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=ImageName
                                    },  new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    }
                               };

            DB.ExecuteStoredProc("Promotion_Add", spa);

        }
        public void BrandPromotionShowChange(int brandID, Boolean IsSelected)
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    },  new SqlParameter(){
                                       ParameterName="@IsSelected",
                                       SqlDbType=SqlDbType.Bit,
                                       Value=IsSelected
                                    }
                               };

            DB.ExecuteStoredProc("BrandPromotion_ShowHide", spa);

        }
        public void AddWebSlideShowImage(string ImageName, int brandID)
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ImageName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=ImageName
                                    },  new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    }
                               };

            DB.ExecuteStoredProc("WebSlideShows_Add", spa);

        }

        public JsonResult UploadSlideShowImages(List<HttpPostedFileBase> fileToUpload, bool isMobile, int BrandID)
        {
            for (int i = 0; i < fileToUpload.Count; i++)
            {
                HttpPostedFileBase file = fileToUpload[i];
                string imageUrls = "";
                string _path = "";
                try
                {
                    if (file.ContentLength > 0)
                    {
                        var Filename = file.FileName;
                        string strpath = Path.GetExtension(Filename);
                        Filename = RenameImanges(Filename);
                        byte[] fileData = null;
                        using (var binaryReader = new BinaryReader(file.InputStream))
                        {
                            fileData = binaryReader.ReadBytes(file.ContentLength);
                        }
                        if (strpath == ".gif")
                        {
                            uploadGif(fileToUpload[i]);
                            return Json(Filename);
                        }
                        if (isMobile)
                        {
                            AddSlideShowImage(Filename, BrandID);
                            _path = Path.Combine(Server.MapPath("~/images"), Filename);
                            imageUrls = "/images/" + Filename;
                            HandleImageUpload(fileData, _path);
                        }
                        else
                        {
                            AddWebSlideShowImage(Filename, BrandID);
                            _path = Path.Combine(Server.MapPath("~/images/webSlide"), Filename);
                            imageUrls = "/images/webSlide/" + Filename;
                            HandleWebImageUpload(fileData, _path);
                        }
                    }
                    System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");
                    return Json(imageUrls);
                }
                catch
                {
                    ViewBag.Message = "File upload failed!!";
                    System.Diagnostics.Debug.WriteLine("File upload failed!!");
                }
            }
            return Json(ViewBag.Message);
        }
        public JsonResult UploadPromotionImages(List<HttpPostedFileBase> fileToUpload, bool isMobile, int BrandID)
        {
            for (int i = 0; i < fileToUpload.Count; i++)
            {
                HttpPostedFileBase file = fileToUpload[i];
                string imageUrls = "";
                string _path = "";
                try
                {
                    if (file.ContentLength > 0)
                    {
                        var Filename = file.FileName;
                        string strpath = Path.GetExtension(Filename);
                        Filename = RenameImanges(Filename);
                        byte[] fileData = null;
                        using (var binaryReader = new BinaryReader(file.InputStream))
                        {
                            fileData = binaryReader.ReadBytes(file.ContentLength);
                        }
                        if (strpath == ".gif")
                        {
                            uploadGif(fileToUpload[i]);
                            return Json(Filename);
                        }
                        if (isMobile)
                        {
                            AddPromotionImage(Filename, BrandID);
                            _path = Path.Combine(Server.MapPath("~/images"), Filename);
                            imageUrls = "/images/" + Filename;
                            HandleImageUpload(fileData, _path);
                        }
                        else
                        {
                            //AddWebPromotionImage(Filename, BrandID);
                            //_path = Path.Combine(Server.MapPath("~/images/webSlide"), Filename);
                            //imageUrls = "/images/webSlide/" + Filename;
                            //HandleWebImageUpload(fileData, _path);
                        }
                    }
                    System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");
                    return Json(imageUrls);
                }
                catch
                {
                    ViewBag.Message = "File upload failed!!";
                    System.Diagnostics.Debug.WriteLine("File upload failed!!");
                }
            }
            return Json(ViewBag.Message);
        }
        private void handleWebSlideshow(byte[] binaryImage, string path)
        {
            int MaxWidht = Convert.ToInt16(ConfigurationManager.AppSettings["webSlideShowWidth"].ToString());
            int Maxheight = Convert.ToInt16(ConfigurationManager.AppSettings["webSlideShowHeight"].ToString());
            Image img = RezizeImage(Image.FromStream(BytearrayToStream(binaryImage)), MaxWidht, Maxheight);
            img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
        }
        public ActionResult UploadVideo(HttpPostedFileBase fileToUpload)
        {
            HttpPostedFileBase file = fileToUpload;
            string imageUrls = "";
            string _FileName = "";
            string _path = "";
            try
            {
                if (file.ContentLength > 0)
                {
                    var Filename = file.FileName;
                    _path = Path.Combine(Server.MapPath("~/Video"), Filename);

                    fileToUpload.SaveAs(_path);
                }
                System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");

                return Json(imageUrls);
            }
            catch
            {
                ViewBag.Message = "File upload failed!!";
                System.Diagnostics.Debug.WriteLine("File upload failed!!");
                return Json(ViewBag.Message);
            }
        }
        public bool ThumbnailCallback()
        {
            return false;
        }
        private Image RezizeImage(Image img, int maxWidth, int maxHeight)
        {
            if (maxHeight == 150 && maxWidth == 300)
            {
                System.Drawing.Image thumbnailImage = img.GetThumbnailImage(64, 64, new System.Drawing.Image.GetThumbnailImageAbort(ThumbnailCallback), IntPtr.Zero);
                return thumbnailImage;
            }

            if (img.Height < maxHeight && img.Width < maxWidth) return img;
            using (img)
            {
                Double xRatio = (double)img.Width / maxWidth;
                Double yRatio = (double)img.Height / maxHeight;
                Double ratio = Math.Max(xRatio, yRatio);
                int nnx = (int)Math.Floor(img.Width / ratio);
                int nny = (int)Math.Floor(img.Height / ratio);
                Bitmap cpy = new Bitmap(nnx, nny, PixelFormat.Format32bppArgb);
                using (Graphics gr = Graphics.FromImage(cpy))
                {
                    gr.Clear(Color.Transparent);

                    // This is said to give best quality when resizing images
                    gr.InterpolationMode = InterpolationMode.HighQualityBicubic;

                    gr.DrawImage(img,
                        new Rectangle(0, 0, nnx, nny),
                        new Rectangle(0, 0, img.Width, img.Height),
                        GraphicsUnit.Pixel);
                }
                return cpy;
            }



        }
        private MemoryStream BytearrayToStream(byte[] arr)
        {
            return new MemoryStream(arr, 0, arr.Length);
        }
        public void HandleImageUpload(byte[] binaryImage, string path)
        {
            int MaxWidht = Convert.ToInt16(ConfigurationManager.AppSettings["Width"].ToString());
            int Maxheight = Convert.ToInt16(ConfigurationManager.AppSettings["Height"].ToString());
            Image img = RezizeImage(Image.FromStream(BytearrayToStream(binaryImage)), MaxWidht, Maxheight);
            img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
        }
        public void HandleThumbnailImageUpload(byte[] binaryImage, string path)
        {
            int MaxWidht = Convert.ToInt16(ConfigurationManager.AppSettings["ThumbnailWidth"].ToString());
            int Maxheight = Convert.ToInt16(ConfigurationManager.AppSettings["ThumbnailHeight"].ToString());
            //Image img = RezizeImage(Image.FromStream(BytearrayToStream(binaryImage)), MaxWidht, Maxheight);
            Size newSize = new Size();
            newSize.Width = MaxWidht;
            newSize.Height = Maxheight;
            Image img = ResizeThumbnailImage(Image.FromStream(BytearrayToStream(binaryImage)), newSize);
            img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
        }
        public static Image ResizeThumbnailImage(Image imgToResize, Size destinationSize)
        {
            var originalWidth = imgToResize.Width;
            var originalHeight = imgToResize.Height;

            //how many units are there to make the original length
            var hRatio = (float)originalHeight / destinationSize.Height;
            var wRatio = (float)originalWidth / destinationSize.Width;

            //get the shorter side
            var ratio = Math.Min(hRatio, wRatio);

            var hScale = Convert.ToInt32(destinationSize.Height * ratio);
            var wScale = Convert.ToInt32(destinationSize.Width * ratio);

            //start cropping from the center
            var startX = (originalWidth - wScale) / 2;
            var startY = (originalHeight - hScale) / 2;

            //crop the image from the specified location and size
            var sourceRectangle = new Rectangle(startX, startY, wScale, hScale);

            //the future size of the image
            var bitmap = new Bitmap(destinationSize.Width, destinationSize.Height);

            //fill-in the whole bitmap
            var destinationRectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);

            //generate the new image
            using (var g = Graphics.FromImage(bitmap))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(imgToResize, destinationRectangle, sourceRectangle, GraphicsUnit.Pixel);
            }

            return bitmap;

        }
        private void HandleWebImageUpload(byte[] binaryImage, string path)
        {
            int MaxWidht = Convert.ToInt16(ConfigurationManager.AppSettings["WebSlideShowImageWidth"].ToString());
            int Maxheight = Convert.ToInt16(ConfigurationManager.AppSettings["WebSlideShowImageHeight"].ToString());
            Image img = RezizeImage(Image.FromStream(BytearrayToStream(binaryImage)), MaxWidht, Maxheight);
            img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
        }

        public JsonResult GetWaiter()
        {
            try
            {

                DataSet ds = DB.ExecuteStoredProcDataSet("mvc_sp_GetWaiter");
                List<Waiter> Waiter = new List<Waiter>();
                DataTable dtWaiter = ds.Tables[0];
                if (dtWaiter.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtWaiter.Rows)
                    {
                        Waiter.Add(new Waiter
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            Role_ID = Convert.ToInt32(dtRow["Role_ID"].ToString()),
                            NAME = dtRow["NAME"].ToString(),
                            RoleName = dtRow["RoleName"].ToString(),
                            USERNAME = dtRow["USERNAME"].ToString(),
                            //BrandName = dtRow["BrandName"].ToString(),
                            BrandID = dtRow["BrandID"].ToString(),

                        });
                    }
                }


                return Json(new { dtWaiter = Waiter }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json("'Fail':'true'");
            }

        }
        public JsonResult GetRole()
        {
            try
            {

                DataSet ds = DB.ExecuteStoredProcDataSet("[mvc_sp_GetRole]");
                List<Waiter> Waiter = new List<Waiter>();
                DataTable dtWaiter = ds.Tables[0];
                if (dtWaiter.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtWaiter.Rows)
                    {
                        Waiter.Add(new Waiter
                        {

                            Role_ID = Convert.ToInt32(dtRow["Role_ID"].ToString()),
                            RoleName = dtRow["RoleName"].ToString(),

                        });
                    }
                }


                return Json(new { dtRole = Waiter }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json("'Fail':'true'");
            }

        }

        public JsonResult AddWaiter(Waiter value)
        {
            try
            {

                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@NAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.NAME
                                    }, new SqlParameter(){
                                       ParameterName="@USERNAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.USERNAME
                                    }, new SqlParameter(){
                                       ParameterName="@PASSWORD",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.PASSWORD
                                    }, new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandID
                                    }, new SqlParameter(){
                                       ParameterName="@Role_ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Role_ID
                                    },
                               };

                int ds = DB.ExecuteStoredProc("mvc_sp_AddWaiter", spa);
            }

            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UpdateWaiter(Waiter value)
        {
            try
            {
                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ID
                                    }, new SqlParameter(){
                                       ParameterName="@NAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.NAME
                                    }, new SqlParameter(){
                                       ParameterName="@USERNAME",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.USERNAME
                                    }, new SqlParameter(){
                                       ParameterName="@PASSWORD",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.PASSWORD
                                    }, new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BrandID
                                    }, new SqlParameter(){
                                       ParameterName="@Role_ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Role_ID
                                    },
                               };

                int ds = DB.ExecuteStoredProc("mvc_sp_UpdateWaiter", spa);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DeleteWaiter(Waiter value)
        {
            try
            {
                DB.ExecuteNonQuery("delete from tblUser where ID=" + value.ID + "");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult GetAssignedBrand(Category2 value)
        {
            try
            {
                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.CAT_NUM
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAssignBrand", spa);
                List<Brand> Waiter = new List<Brand>();
                DataTable dtWaiter = ds.Tables[0];
                if (dtWaiter.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtWaiter.Rows)
                    {
                        Waiter.Add(new Brand
                        {
                            BrandID = Convert.ToInt32(dtRow["BrandID"].ToString()),
                            BrandName = dtRow["BrandName"].ToString(),

                        });
                    }
                }
                return Json(new { dtBrand = Waiter }, JsonRequestBehavior.AllowGet);
            }

            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult GetAssignedBranch(Category2 value)
        {
            try
            {
                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.CAT_NUM
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAssignBranch", spa);
                List<Branch> Waiter = new List<Branch>();
                DataTable dtWaiter = ds.Tables[0];
                if (dtWaiter.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtWaiter.Rows)
                    {
                        Waiter.Add(new Branch
                        {
                            BranchId = Convert.ToInt32(dtRow["BranchId"].ToString()),
                            branchName = dtRow["branchName"].ToString(),

                        });
                    }
                }
                return Json(new { dtBrand = Waiter }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetAssignedBranchItemsAndComments(Items value)
        {
            try
            {
                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@ItemId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ID
                                    },new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAssignBranchItemsAndComments", spa);
                List<Branch> Waiter = new List<Branch>();
                List<ItemsComments> Extraitems = new List<ItemsComments>();
                List<ItemsComments> Comments = new List<ItemsComments>();
                DataTable dtWaiter = ds.Tables[0];
                if (dtWaiter.Rows.Count > 0)
                {
                    //set Selected Branchs
                    foreach (DataRow dtRow in dtWaiter.Rows)
                    {
                        Waiter.Add(new Branch
                        {
                            BranchId = Convert.ToInt32(dtRow["BranchId"].ToString()),
                            branchName = dtRow["branchName"].ToString(),

                        });
                    }

                    if (ds.Tables.Count > 0)
                    {
                        DataTable dtExtraItems = ds.Tables[1];
                        //set Selected Extra Items
                        foreach (DataRow dtRow in dtExtraItems.Rows)
                        {
                            Extraitems.Add(new ItemsComments
                            {
                                id = Convert.ToInt32(dtRow["ExtraItemId"].ToString())

                            });
                        }
                    }

                    if (ds.Tables.Count > 1)
                    {
                        DataTable dtComments = ds.Tables[2];
                        //set selected Comments
                        foreach (DataRow dtRow in dtComments.Rows)
                        {
                            Comments.Add(new ItemsComments
                            {
                                id = Convert.ToInt32(dtRow["commentid"].ToString())
                            });
                        }

                    }
                }
                return Json(new { Message = "Success", dtBranch = Waiter, dtExtraitems = Extraitems, dtComments = Comments }, JsonRequestBehavior.AllowGet);
            }

            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult FeedBackLayout(FeedBackLayout value)
        {


            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetFeedBackLayout");
                List<FeedBackLayout> FeedBackLayout = new List<FeedBackLayout>();
                List<FeedBackLayout> FeedBackType = new List<FeedBackLayout>();
                DataTable dtFeedBackLayout = ds.Tables[0];
                DataTable dtFeedBackType = ds.Tables[1];
                if (dtFeedBackLayout.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtFeedBackLayout.Rows)
                    {
                        FeedBackLayout.Add(new FeedBackLayout
                        {
                            id = Convert.ToInt32(dtRow["id"].ToString()),
                            BrandID = Convert.ToInt32(dtRow["BrandID"].ToString()),
                            Question = dtRow["Questions"].ToString(),
                            Type = dtRow["Type"].ToString(),
                            Sequence = Convert.ToInt32(dtRow["Sequence"].ToString()),
                            TypeId = Convert.ToInt32(dtRow["TypeId"].ToString()),
                        });
                    }
                }
                if (dtFeedBackType.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtFeedBackType.Rows)
                    {
                        FeedBackType.Add(new FeedBackLayout
                        {
                            Type = dtRow["Type"].ToString(),
                            TypeId = Convert.ToInt32(dtRow["id"].ToString()),
                        });
                    }
                }

                return Json(new { dtFeedBackLayout = FeedBackLayout, dtFeedBackType = FeedBackType }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json("'Fail':'true'");
            }

        }

        public JsonResult AddFeedBackLayout(FeedBackLayout value)
        {
            try
            {
                SqlParameter[] spa ={
                                     new SqlParameter(){
                                       ParameterName="@Question",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Question
                                    },  new SqlParameter(){
                                       ParameterName="@TypeId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.TypeId
                                    }, new SqlParameter(){
                                       ParameterName="@Sequence",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Sequence
                                    }, new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("AddFeedBackLayout", spa);

            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UpdateFeedBackLayout(FeedBackLayout value)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@Question",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.Question
                                    },   new SqlParameter(){
                                       ParameterName="@Sequence",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Sequence
                                    },  new SqlParameter(){
                                       ParameterName="@TypeId",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.TypeId
                                    }, new SqlParameter(){
                                       ParameterName="@id",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.id
                                    },new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },
                               };

                int ds = DB.ExecuteStoredProc("UpdateFeedBackLayout", spa);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DeleteFeedBackLayout(FeedBackLayout value)
        {
            var CAT_NUM = value.id;

            try
            {
                DB.ExecuteNonQuery("delete from feedback_Layout where id = " + CAT_NUM + "");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult GetFeedbackReport()
        {


            try
            {
                //SqlParameter[] spa ={
                //                     new SqlParameter(){
                //                       ParameterName="@StartDate",
                //                       SqlDbType=SqlDbType.DateTime,
                //                       Value=StartDate
                //                    },  new SqlParameter(){
                //                       ParameterName="@EndDate",
                //                       SqlDbType=SqlDbType.DateTime,
                //                       Value=EndDate
                //                    }
                //               };
                DataSet ds = DB.ExecuteStoredProcDataSet("Feedback_GetReport");
                List<FeedBackDataNew> lstFeedbackData = new List<FeedBackDataNew>();

                DataTable dt = ds.Tables[0];
                List<DataRow> list = dt.AsEnumerable().ToList();
                if (dt.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dt.Rows)
                    {
                        lstFeedbackData.Add(new FeedBackDataNew
                        {
                            CustomerName = dtRow["Customer_name"].ToString(),
                            Email = dtRow["Customer_email"].ToString(),
                            ContactNo = dtRow["Customer_mobile"].ToString(),
                            Question = dtRow["Question"].ToString(),
                            //Response = dtRow["Response"].ToString(),
                            ResponseType = dtRow["ResponseType"].ToString(),
                            DateTime = dtRow["Datetime"].ToString(),
                            BranchName = dtRow["Branch_Name"].ToString(),
                            IMEI = dtRow["UDID"].ToString(),
                            Response = dtRow["Response"].ToString(),
                        });
                    }
                }

                return Json(new { dtPivot = lstFeedbackData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json("'Fail':'true'");
            }

        }


        #region Branchs
        public JsonResult GetBranchsBrandWise(int brandid)
        {
            SqlParameter[] spa ={
                                    // new SqlParameter(){
                                    //   ParameterName="@WaiterID",
                                    //   SqlDbType=SqlDbType.Int,
                                    //   Value=WaiterID
                                    //},
                                    new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandid
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBranchsBrandWise", spa);
            List<Branch> objBranch = new List<Branch>();
            DataTable dtgrdBranch = ds.Tables[0];
            try
            {

                if (dtgrdBranch.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdBranch.Rows)
                    {
                        objBranch.Add(new Branch
                        {
                            BranchId = Convert.ToInt32(dtRow["BranchId"].ToString()),
                            branchName = dtRow["branchName"].ToString(),
                            BranchNameAra = dtRow["BranchNameAra"].ToString(),


                        });
                    }
                }

                return Json(new { dtgrdBranch = objBranch }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetBranchsList()
        {
            //SqlParameter[] spa ={
            //                        // new SqlParameter(){
            //                        //   ParameterName="@WaiterID",
            //                        //   SqlDbType=SqlDbType.Int,
            //                        //   Value=WaiterID
            //                        //},
            //                        new SqlParameter(){
            //                           ParameterName="@BrandId",
            //                           SqlDbType=SqlDbType.Int,
            //                           Value=brandid
            //                        },
            //};
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBranchs");
            List<Branch> objBranch = new List<Branch>();
            DataTable dtgrdBranch = ds.Tables[0];
            try
            {

                if (dtgrdBranch.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdBranch.Rows)
                    {
                        objBranch.Add(new Branch
                        {
                            BranchId = Convert.ToInt32(dtRow["BranchId"].ToString()),
                            branchName = dtRow["branchName"].ToString(),
                            BranchNameAra = dtRow["BranchNameAra"].ToString(),

                            BrandID = Convert.ToInt32(dtRow["BrandID"].ToString()),
                            BrandName = dtRow["BrandName"].ToString(),
                            BrandNameAra = dtRow["BrandNameAra"].ToString(),
                        });
                    }
                }

                return Json(new { dtgrdBranch = objBranch }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult AddBranch(Branch value)
        {
            try
            {
                SqlParameter[] spa ={  new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value =value.BrandID
                                    },new SqlParameter(){
                                       ParameterName="@branchName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.branchName
                                    }, new SqlParameter(){
                                       ParameterName="@BrandNameAr",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BranchNameAra
                                    },new SqlParameter(){
                                       ParameterName="@CopyBranchID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.CopyBranchID
                                    }

                               };

                int ds = DB.ExecuteStoredProc("sp_AddBranch", spa);
            }

            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UpdateBranch(Branch value)
        {
            try
            {
                SqlParameter[] spa ={    new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BrandID
                                    },new SqlParameter(){
                                       ParameterName="@BranchId",
                                       SqlDbType=SqlDbType.Int,
                                       Value =value.BranchId
                                    },new SqlParameter(){
                                       ParameterName="@branchName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.branchName
                                    }, new SqlParameter(){
                                       ParameterName="@branchNameAra",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BranchNameAra
                                    }
                               };

                int ds = DB.ExecuteStoredProc("sp_UpdateBranch", spa);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DeleteBranch(Branch value)
        {
            var ID = value.BranchId;

            try
            {
                DB.ExecuteNonQuery("delete from tblbranch where id = '" + ID + "'");
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        #endregion Branchs


        public JsonResult GetExtraItems(int Cat_Num)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@Cat_Num",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Cat_Num
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetExtraItems", spa);
            List<Items> objItems = new List<Items>();
            DataTable dtgrdItems = ds.Tables[0];
            try
            {

                if (dtgrdItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdItems.Rows)
                    {
                        objItems.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                        });
                    }
                }

                return Json(new { dtgrdItems = objItems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetExtraComments()
        {
            //SqlParameter[] spa ={
            //                        new SqlParameter(){
            //                           ParameterName="@BrandId",
            //                           SqlDbType=SqlDbType.Int,
            //                           Value=brandid
            //                        },
            //};
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetExtraComments");
            List<Comments> objComments = new List<Comments>();
            DataTable dtgrdComments = ds.Tables[0];
            try
            {

                if (dtgrdComments.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdComments.Rows)
                    {
                        objComments.Add(new Comments
                        {
                            ID = Convert.ToInt32(dtRow["id"].ToString()),
                            comments_eng = dtRow["comments_eng"].ToString(),
                            comments_arb = dtRow["comments_arb"].ToString(),
                        });
                    }
                }

                return Json(new { dtgrdComments = objComments }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
    }

    public class Comments
    {
        public int ID { get; set; }
        public string comments_eng { get; set; }
        public string comments_arb { get; set; }
    }
    public class ModifierGroups
    {
        public int ID { get; set; }
        public string GroupNameEng { get; set; }
        public string GroupNameArb { get; set; }
        public int? TypeID { get; set; }
        public string TypeName { get; set; }
        public int? MinSelect { get; set; }
        public int? MaxSelect { get; set; }
        public int? Seq_Num { get; set; }
    }
    
    public class CartComments
    {
        public int II { get; set; }
        public int CI { get; set; }
        public string comments_eng { get; set; }
        public string comments_arb { get; set; }
    }
    public class CartExtraItems
    {
        public int II { get; set; }
        public int EI { get; set; }
        public string ITEM_NAME { get; set; }
        public string ITEM_NAME_ARABIC { get; set; }
        public decimal PRICE { get; set; }
    }

    public class Allergens
    {
        public int id { get; set; }
        public string name { get; set; }
        public string Name_arabic { get; set; }
        public string image { get; set; }
    }
}
