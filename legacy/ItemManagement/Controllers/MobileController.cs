using Jar.Models;
using Jar.Helper;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using static Jar.Models.mobileData;
using System.Data.SqlClient;
using Newtonsoft.Json;
using System.Net;
using System.Xml;
using System.IO;
using System.Configuration;

namespace Jar.Controllers
{
    public class MobileController : Controller
    {
        public JsonResult GetBrands(string Password)
        {
            SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@Password",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=Password
                                    },
                               };
            DataSet ds = DB.ExecuteStoredProcDataSet("[sp_GetBrandsMobile]", spa);
            List<brandData> brandData = new List<brandData>();
            List<themeData> themeData = new List<themeData>();

            try
            {
                DataTable brand = ds.Tables[0];

                if (brand.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in brand.Rows)
                    {
                        brandData.Add(new brandData
                        {
                            brandID = Convert.ToInt32(dtRow["BrandID"].ToString()),
                            themeID = Convert.ToInt32(dtRow["Theme"].ToString()),
                            brandLogo = dtRow["BrandImage"].ToString(),
                            brandName = dtRow["BrandName"].ToString(),
                            brandNameAr = dtRow["BrandNameAra"].ToString(),
                            brandSeq = Convert.ToInt32(dtRow["BrandSeq"].ToString()),
                            russian = Convert.ToInt32(dtRow["Russian"].ToString()),
                            mandarin = Convert.ToInt32(dtRow["Mandarin"].ToString()),
                            feedback = Convert.ToBoolean(dtRow["Feedback"].ToString()),
                            currency = dtRow["currency"].ToString(),
                            Telephone = dtRow["Telephone"].ToString(),
                            facebook = dtRow["Facebook"].ToString(),
                            instagram = dtRow["Instagram"].ToString(),
                            orderTaking = Convert.ToBoolean(dtRow["orderTaking"].ToString()),
                        });
                        themeData.Add(new themeData
                        {
                            themeID = Convert.ToInt32(dtRow["Theme"].ToString()),
                            themeName = dtRow["themeName"].ToString(),
                            categoryActive = dtRow["categoryActive"].ToString(),
                            categoryInActive = dtRow["categoryInActive"].ToString(),
                            setting = dtRow["setting"].ToString(),
                            englishButton = dtRow["englishButton"].ToString(),
                            arabicButton = dtRow["arabicButton"].ToString(),
                            mandarinButton = dtRow["mandarinButton"].ToString(),
                            russianButton = dtRow["russianButton"].ToString(),
                            closeButton = dtRow["closeButton"].ToString(),
                            homeScreen = dtRow["homeScreen"].ToString(),
                            popUpBackground = dtRow["popUpBackground"].ToString(),

                            separatorLine = dtRow["SeperatorLine"].ToString(),
                            leftArrow = dtRow["leftArrow"].ToString(),
                            leftBottom = dtRow["leftBottom"].ToString(),
                            leftTop = dtRow["leftTop"].ToString(),
                            rightArrow = dtRow["rightArrow"].ToString(),
                            rightBottom = dtRow["RightButton"].ToString(),
                            rightTop = dtRow["rightTop"].ToString(),


                            FontColor = dtRow["FontColor"].ToString(),
                            FontColorItemName = dtRow["FontColorItemName"].ToString(),
                            FontColorIngName = dtRow["FontColorIngName"].ToString(),
                            FontColorPrice = dtRow["FontColorPrice"].ToString(),
                            itemBackgroundColor = dtRow["itemBackgroundColor"].ToString(),
                        });
                    }
                }

                return Json(new { brand = brandData, theme = themeData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetBrands", null);
                return Json(new { brand = 0, theme = 0 }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult Item(int brandID)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=brandID
                                    },
                };
                //DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemMobile", spa);
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemMobileIPad", spa);
                List<Items> Items = new List<Items>();
                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {


                        Items.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            HID = Convert.ToInt32(dtRow["HID"].ToString()),
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            catNameArabic = dtRow["CAT_NAME_ARABIC"].ToString(),
                            catNameMan = dtRow["CatNameMan"].ToString(),
                            catNameRus = dtRow["CatNameRus"].ToString(),
                            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                            ItemNameMan = dtRow["ItemNameMan"].ToString(),
                            PRICE = dtRow["PRICE"].ToString(),
                            INGREDIENT = dtRow["INGREDIENT"].ToString(),
                            INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                            INGREDIENT_Man = dtRow["INGREDIENT_Man"].ToString(),
                            INGREDIENT_Rus = dtRow["INGREDIENT_Rus"].ToString(),
                            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                            ITEM_DESC_ENG = dtRow["ITEM_DESC_ENG"].ToString(),
                            Video = dtRow["Video"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                            BrandID = brandID,
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),

                        });
                    }
                }

                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "Item", null);
                return Json("'Fail':'true'");
            }

        }
        public JsonResult GetExtra(int brandID)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=brandID
                                    },
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetExtra", spa);
                List<Extra> Items = new List<Extra>();
                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {


                        Items.Add(new Extra
                        {
                            ExtraID = Convert.ToInt32(dtRow["id"].ToString()),
                            BrandID = brandID,
                            ItemID = Convert.ToInt32(dtRow["ItemID"].ToString()),
                            ExtraName = dtRow["ExtraName"].ToString(),
                            ExtraNameArabic = dtRow["ExtraNameAra"].ToString(),
                            Price = dtRow["Price"].ToString(),
                            ImageName = dtRow["ImageName"].ToString(),

                        });
                    }
                }

                return Json(new { dtExtras = Items }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetExtra", null);
                return Json(new { dtItems = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult GetImageSlideShow(int brandID)
        {
            List<Items> Items = new List<Items>();
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    },
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("Image_Slideshow", spa);

                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {


                        Items.Add(new Items
                        {

                            IMAGENAME = dtRow["SlideImageName"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["ImageSequence"].ToString()),
                            ID = Convert.ToInt32(dtRow["id"].ToString()),
                            BrandID = brandID,

                        });
                    }
                }

                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetImageSlideShow", null);
                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult GetImagePromotion(int brandID)
        {
            List<Items> Items = new List<Items>();
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    },
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("Image_Promotion", spa);

                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {


                        Items.Add(new Items
                        {

                            IMAGENAME = dtRow["ImageName"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["ImageSequence"].ToString()),
                            ID = Convert.ToInt32(dtRow["id"].ToString()),
                            BrandID = brandID,

                        });
                    }
                }
                int ShowPromotion = 0;
                if (ds.Tables.Count > 1)
                {
                    DataTable dtItems1 = ds.Tables[1];
                    if (dtItems1.Rows.Count > 0)
                    {
                        ShowPromotion = Convert.ToInt32(dtItems1.Rows[0][0]);
                    }
                }

                return Json(new { dtItems = Items, IsShowPromotion = ShowPromotion }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetImagePromotion", null);
                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult GetWebImageSlideShow(int brandID)
        {

            List<Items> Items = new List<Items>();
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@brandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
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
                            BrandID = brandID,
                        });
                    }
                }

                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetWebImageSlideShow", null);
                return Json(new { dtItems = Items }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult Category(int brandID)
        {

            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=brandID
                                    },
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryMobile", spa);

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
                            MainCategory = Convert.ToInt32(dtRow["MainCategory"].ToString()),
                            BrandID = brandID
                        });
                    }
                }

                return Json(new { dtCategory = Category }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "Category", null);
                return Json("'Fail':'true'");
            }

        }
        public JsonResult GetFeedBack(int BrandID)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("Mobile_GetFeedBackLayout", spa);
                List<FeedBackLayout> FeedBackLayout = new List<FeedBackLayout>();
                DataTable dtFeedBackLayout = ds.Tables[0];
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
                return Json(new { Message = "Success", dtFeedBackLayout = FeedBackLayout }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetFeedBack", null);
                return Json(new { Message = "Failure", dtFeedBackLayout = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult getOutofStock(int BrandID)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetIoutofStock", spa);
                List<FeedBackLayout> FeedBackLayout = new List<FeedBackLayout>();
                DataTable dtFeedBackLayout = ds.Tables[0];
                if (dtFeedBackLayout.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtFeedBackLayout.Rows)
                    {
                        FeedBackLayout.Add(new FeedBackLayout
                        {
                            id = Convert.ToInt32(dtRow["id"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtItems = FeedBackLayout }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "getOutofStock", null);
                return Json(new { Message = "Failure", dtFeedBackLayout = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
        }
        public bool OutofStock(string Json)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ItemID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=Json
                                    },
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_UpdateOutOfStock", spa);
                return true;
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "OutofStock", null);
                return false;
            }

        }
        public JsonResult DigitalMenuLogin(string Password)
        {
            SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@Password",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=Password
                                    }
                               };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_Authentication", spa);
            List<UserLogin> Users = new List<UserLogin>();
            DataTable dtDineIn = ds.Tables[0];
            if (dtDineIn.Rows.Count > 0)
            {
                foreach (DataRow dtRow in dtDineIn.Rows)
                {
                    Users.Add(new UserLogin
                    {
                        WaiterID = 1,
                        RoleID = 1,
                        Authentication = true,
                    });
                }
            }
            else
            {
                Users.Add(new UserLogin
                {
                    WaiterID = 0,
                    RoleID = 0,
                    Authentication = false,
                });
            }
            return Json(new { dtUsers = Users }, JsonRequestBehavior.AllowGet);

        }


        public JsonResult UserLogin(string password)
        {
            UserLogin user = new UserLogin();
            try
            {
                IDataReader reader = null;
                string connection = System.Configuration.ConfigurationManager.ConnectionStrings["POSConnection"].ConnectionString;
                SqlConnection con = new SqlConnection(connection);

                using (SqlCommand cmd = new SqlCommand("mvc_sp_Login", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;

                    cmd.Parameters.Add("@Username", SqlDbType.VarChar).Value = password;
                    cmd.Parameters.Add("@Password", SqlDbType.VarChar).Value = password;

                    con.Open();
                    reader = cmd.ExecuteReader();
                }

                while (reader.Read())
                {

                    user.WaiterID = (int)reader["ID"];
                    user.PORT = ConfigurationManager.AppSettings["POSPORT"].ToString();

                }
                return Json(new { dtUsers = user }, JsonRequestBehavior.AllowGet);
            }
            catch (SqlException ex)
            {
                user.WaiterID = 0;
                user.PORT = "0";
                DB.AuditTrail(ex, "MobileController", "UserLogin", null);
                return Json(new { dtUsers = user, error = ex.ToString() }, JsonRequestBehavior.AllowGet);

            }
        }

        public bool AddFeedBack(string UDID, int responseType, string custMobile, string custName, string custEmail, string question, string response, string branchName, string date)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@UDID",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=UDID
                                    },  new SqlParameter(){
                                       ParameterName="@CustomerMobile",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=custMobile
                                    },  new SqlParameter(){
                                       ParameterName="@CustomerName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=custName
                                    },  new SqlParameter(){
                                       ParameterName="@CustomerEmail",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=custEmail
                                    },  new SqlParameter(){
                                       ParameterName="@Question",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=question
                                    },  new SqlParameter(){
                                       ParameterName="@ResponseType",
                                       SqlDbType=SqlDbType.Int,
                                       Value=responseType
                                    },  new SqlParameter(){
                                       ParameterName="@Response",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=response
                                    }, new SqlParameter(){
                                       ParameterName="@branchName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=branchName
                                    }, new SqlParameter(){
                                       ParameterName="@Date",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=date
                                    },
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("FeedbackData_Add", spa);
                return true;
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "AddFeedBack", null);
                return false;
            }
        }

        public JsonResult GetGroupModifierMaster()
        {
            try
            {
                //SqlParameter[] spa ={
                //                        new SqlParameter(){
                //                       ParameterName="@BrandID",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=BrandID
                //                    },
                //               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_MobileGetGroupModifier");
                List<GroupModifierMaster> objGroupModifierMaster = new List<GroupModifierMaster>();
                DataTable dtGroupModifierMaster = ds.Tables[0];
                if (dtGroupModifierMaster.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtGroupModifierMaster.Rows)
                    {
                        objGroupModifierMaster.Add(new GroupModifierMaster
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            GroupNameEng = dtRow["GroupNameEng"].ToString(),
                            GroupNameArb = dtRow["GroupNameArb"].ToString(),
                            Type = Convert.ToInt32(dtRow["Type"].ToString()),
                            MinSelect = Convert.ToInt32(dtRow["MinSelect"].ToString()),
                            MaxSelect = Convert.ToInt32(dtRow["MaxSelect"].ToString()),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                            BrandId = Convert.ToInt32(dtRow["BrandId"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtGroupModifierMaster = objGroupModifierMaster }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetGroupModifierMaster", null);
                return Json(new { Message = "Failure", dtGroupModifierMaster = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetGroupModifierType()
        {
            try
            {
                //SqlParameter[] spa ={
                //                        new SqlParameter(){
                //                       ParameterName="@BrandID",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=BrandID
                //                    },
                //               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_MobileGroupModifierType");
                List<GroupModifierType> objGroupModifierType = new List<GroupModifierType>();
                DataTable dtGroupModifierType = ds.Tables[0];
                if (dtGroupModifierType.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtGroupModifierType.Rows)
                    {
                        objGroupModifierType.Add(new GroupModifierType
                        {

                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            TypeName_Deliverect = dtRow["TypeName_Deliverect"].ToString(),
                            TypeName_TMM = dtRow["TypeName_TMM"].ToString(),
                        });
                    }
                }
                return Json(new { Message = "Success", dtGroupModifierType = objGroupModifierType }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetGroupModifierType", null);
                return Json(new { Message = "Failure", dtGroupModifierMaster = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetGroupModifierSubDetails()
        {
            try
            {
                //SqlParameter[] spa ={
                //                        new SqlParameter(){
                //                       ParameterName="@BrandID",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=BrandID
                //                    },
                //               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_MobileGroupModifierSubDetails");
                List<GroupModifierSubDetails> objGroupModifierSubDetails = new List<GroupModifierSubDetails>();
                DataTable dtGroupModifierSubDetails = ds.Tables[0];
                if (dtGroupModifierSubDetails.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtGroupModifierSubDetails.Rows)
                    {
                        objGroupModifierSubDetails.Add(new GroupModifierSubDetails
                        {

                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            GroupID = Convert.ToInt32(dtRow["GroupID"].ToString()),
                            ItemID = Convert.ToInt32(dtRow["ItemID"].ToString()),
                            ExtraID = Convert.ToInt32(dtRow["ExtraID"].ToString()),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtGroupModifierType = objGroupModifierSubDetails }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetGroupModifierSubDetails", null);
                return Json(new { Message = "Failure", dtGroupModifierMaster = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetGroupModifierDetails()
        {
            try
            {
                //SqlParameter[] spa ={
                //                        new SqlParameter(){
                //                       ParameterName="@BrandID",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=BrandID
                //                    },
                //};

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_MobileGetGroupModifierDetails");
                List<GroupModifierDetails> objGroupModifierDetails = new List<GroupModifierDetails>();
                DataTable dtGroupModifierDetails = ds.Tables[0];
                if (dtGroupModifierDetails.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtGroupModifierDetails.Rows)
                    {
                        objGroupModifierDetails.Add(new GroupModifierDetails
                        {
                            ID = Convert.ToInt32(dtRow["id"].ToString()),
                            MainItemId = Convert.ToInt32(dtRow["MainItemId"].ToString()),
                            GroupId = Convert.ToInt32(dtRow["GroupId"].ToString()),
                            Deleted = Convert.ToBoolean(dtRow["Deleted"].ToString()),
                            ItemID = Convert.ToInt32(dtRow["ItemID"].ToString()),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtGroupModifierDetails = objGroupModifierDetails }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetGroupModifierDetails", null);
                return Json(new { Message = "Failure", dtGroupModifierDetails = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetGroupModifierAllergenMasterData()
        {
            try
            {
                APIMasterData objAPIMasterData = new APIMasterData();
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_MobileGetGroupModifierAllergenMasterData");
                
                if(ds!=null)
                {
                    if(ds.Tables.Count > 0)
                    {
                        List<GroupModifierMaster> objGroupModifierMaster = new List<GroupModifierMaster>();
                        DataTable dtGroupModifierMaster = ds.Tables[0];
                        if (dtGroupModifierMaster.Rows.Count > 0)
                        {
                            foreach (DataRow dtRow in dtGroupModifierMaster.Rows)
                            {
                                objGroupModifierMaster.Add(new GroupModifierMaster
                                {
                                    ID = Convert.ToInt32(dtRow["ID"].ToString()),
                                    GroupNameEng = dtRow["GroupNameEng"].ToString(),
                                    GroupNameArb = dtRow["GroupNameArb"].ToString(),
                                    Type = Convert.ToInt32(dtRow["Type"].ToString()),
                                    MinSelect = Convert.ToInt32(dtRow["MinSelect"].ToString()),
                                    MaxSelect = Convert.ToInt32(dtRow["MaxSelect"].ToString()),
                                    Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                                    BrandId = Convert.ToInt32(dtRow["BrandId"].ToString()),
                                });
                            }
                        }
                        objAPIMasterData.GroupModifierMaster = objGroupModifierMaster;

                        List<GroupModifierType> objGroupModifierType = new List<GroupModifierType>();
                        DataTable dtGroupModifierType = ds.Tables[1];
                        if (dtGroupModifierType.Rows.Count > 0)
                        {
                            foreach (DataRow dtRow in dtGroupModifierType.Rows)
                            {
                                objGroupModifierType.Add(new GroupModifierType
                                {

                                    ID = Convert.ToInt32(dtRow["ID"].ToString()),
                                    TypeName_Deliverect = dtRow["TypeName_Deliverect"].ToString(),
                                    TypeName_TMM = dtRow["TypeName_TMM"].ToString(),
                                });
                            }
                        }
                        objAPIMasterData.GroupModifierType = objGroupModifierType;

                        List<GroupModifierSubDetails> objGroupModifierSubDetails = new List<GroupModifierSubDetails>();
                        DataTable dtGroupModifierSubDetails = ds.Tables[2];
                        if (dtGroupModifierSubDetails.Rows.Count > 0)
                        {
                            foreach (DataRow dtRow in dtGroupModifierSubDetails.Rows)
                            {
                                objGroupModifierSubDetails.Add(new GroupModifierSubDetails
                                {

                                    ID = Convert.ToInt32(dtRow["ID"].ToString()),
                                    GroupID = Convert.ToInt32(dtRow["GroupID"].ToString()),
                                    ItemID = Convert.ToInt32(dtRow["ItemID"].ToString()),
                                    ExtraID = Convert.ToInt32(dtRow["ExtraID"].ToString()),
                                    Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                                });
                            }
                        }
                        objAPIMasterData.GroupModifierSubDetails = objGroupModifierSubDetails;

                        List<GroupModifierDetails> objGroupModifierDetails = new List<GroupModifierDetails>();
                        DataTable dtGroupModifierDetails = ds.Tables[3];
                        if (dtGroupModifierDetails.Rows.Count > 0)
                        {
                            foreach (DataRow dtRow in dtGroupModifierDetails.Rows)
                            {
                                objGroupModifierDetails.Add(new GroupModifierDetails
                                {
                                    ID = Convert.ToInt32(dtRow["id"].ToString()),
                                    MainItemId = Convert.ToInt32(dtRow["MainItemId"].ToString()),
                                    GroupId = Convert.ToInt32(dtRow["GroupId"].ToString()),
                                    Deleted = Convert.ToBoolean(dtRow["Deleted"].ToString()),
                                    ItemID = Convert.ToInt32(dtRow["ItemID"].ToString()),
                                    Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                                    PRICE = Convert.ToDecimal(dtRow["PRICE"].ToString()),
                                });
                            }
                        }
                        objAPIMasterData.GroupModifierDetails = objGroupModifierDetails;

                        List<AllergenMasterData> objAllergenMasterData = new List<AllergenMasterData>();
                        DataTable dtAllergenMasterData = ds.Tables[4];
                        if (dtAllergenMasterData.Rows.Count > 0)
                        {
                            foreach (DataRow dtRow in dtAllergenMasterData.Rows)
                            {
                                objAllergenMasterData.Add(new AllergenMasterData
                                {
                                    allergenid = Convert.ToInt32(dtRow["allergenid"].ToString()),
                                    name = dtRow["name"].ToString(),
                                    image = dtRow["image"].ToString(),
                                    itemid = Convert.ToInt32(dtRow["itemid"].ToString()),
                                    Allergen_AssignID = Convert.ToInt32(dtRow["Allergen_AssignID"].ToString()),
                                    arabicname = dtRow["arabicname"].ToString(),
                                });
                            }
                        }
                        objAPIMasterData.AllergenMasterData = objAllergenMasterData;

                    }
                }


                return Json(new { Message = "Success", dtAPIMasterData = objAPIMasterData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "MobileController", "GetGroupModifierAllergenMasterData", null);
                return Json(new { Message = "Failure", dtGroupModifierMaster = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
        }

    }

    public class APIMasterData
    {
        public List<GroupModifierMaster> GroupModifierMaster { get; set; }
        public List<GroupModifierType> GroupModifierType { get; set; }
        public List<GroupModifierSubDetails> GroupModifierSubDetails { get; set; }
        public List<GroupModifierDetails> GroupModifierDetails { get; set; }
        public List<AllergenMasterData> AllergenMasterData { get; set; }
    }


}
