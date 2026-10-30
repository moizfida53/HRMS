using Jar.Helper;
using Jar.Models;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Dynamic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using static Jar.Models.mobileData;

namespace Jar.Controllers
{
    public class imageController : Controller
    {
        

        //
        // GET: /image/

        public ActionResult mainpage()
        {

            return View();
        }
        public ActionResult themepage()
        {

            return View();
        }


        //  -------------------------partial view-------------------------------------
        public ActionResult homepageview()
        {


            return PartialView("homepage");

        }


        public ActionResult categoryview()
        {
            //dynamic mymodel = new ExpandoObject();
          
            //List<image> Workflows = getcatimage();
          
            //mymodel.WorfklowInfo = Workflows;


            return View("catlist");

        }


        public ActionResult itemview()
        {
     

            return PartialView("itemlist");

        }

        public ActionResult itemdetail()
        {


            return PartialView("itemdetailpage");

        }


        public ActionResult Themechangepage()
        {


            return PartialView("themedemo");

        }




        //  -------------------------partial view-------------------------------------



        public JsonResult getitem(int CID)
        {
           
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=CID
                                    },
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("Getitem", spa);
                List<Items> Items1 = new List<Items>();
                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {


                        Items1.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                            PRICE = dtRow["PRICE"].ToString(),
                            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),

                        });
                    }
                }

                return Json(new { dtItems = Items1 }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "imageController", "getitem", null);
                return Json("'Fail':'true'");
            }

        }



        public JsonResult getitemwithselectedimage(int CID,int ItemID)
        {

            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=CID
                                    },new SqlParameter(){
                                       ParameterName="@itemid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=ItemID
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("Getitemselect", spa);
                List<Items> Items1 = new List<Items>();
                DataTable dtItems = ds.Tables[0];
                if (dtItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtItems.Rows)
                    {


                        Items1.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                            PRICE = dtRow["PRICE"].ToString(),
                            INGREDIENT = dtRow["INGREDIENT"].ToString(),
                            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),

                        });
                    }
                }

                return Json(new { dtItems = Items1 }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "imageController", "getitemwithselectedimage", null);
                return Json("'Fail':'true'");
            }

        }

        public JsonResult EditTheme(themeData value)
        {
            try
            {

                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@leftArrow",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.leftArrow
                                    },
                                    new SqlParameter(){
                                       ParameterName="@leftBottom",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.leftBottom
                                    },
                                    new SqlParameter(){
                                       ParameterName="@englishButton",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.englishButton
                                    },
                                    new SqlParameter(){
                                       ParameterName="@popUpBackground",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.popUpBackground
                                    },
                                    new SqlParameter(){
                                       ParameterName="@homeScreen",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.homeScreen
                                    },
                                    new SqlParameter(){
                                       ParameterName="@themeID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.themeID
                                    },
                                     new SqlParameter(){
                                       ParameterName="@FontColor",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColor
                                    },
                                      new SqlParameter(){
                                       ParameterName="@FontColorItemName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColorItemName
                                    },
                                       new SqlParameter(){
                                       ParameterName="@itemBackgroundColor",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.itemBackgroundColor
                                    },
                                        new SqlParameter(){
                                       ParameterName="@FontColorPrice",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColorPrice
                                    },
                                         new SqlParameter(){
                                       ParameterName="@FontColorIngName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.FontColorIngName
                                    },
                               };

                DB.ExecuteStoredProc("sp_updatethemes", spa);


            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "imageController", "EditTheme", null);

                return Json(new { Message = ex.ToString() }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Added Sucessfully changed" }, JsonRequestBehavior.AllowGet);

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
                            leftArrow = dtRow["leftArrow"].ToString(),
                            leftBottom = dtRow["leftBottom"].ToString(),

                        });
                    }
                }

                return Json(new { dtgrdBrand = themeData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "imageController", "GetTheme", null);

                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }


        public JsonResult getcategorylist()
        {

            DataSet ds = DB.ExecuteStoredProcDataSet("geticatdetails");
            List<image> categorylist = new List<image>();
            DataTable categorydata = ds.Tables[0];
            try
            {

                if (categorydata.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in categorydata.Rows)
                    {
                        categorylist.Add(new image
                        {
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
                            CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                            Imagename = dtRow["Imagename"].ToString(),


                        });
                    }
                }

                return Json(new { categorydata = categorylist }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "imageController", "getcategorylist", null);

                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }



        //public List<image> getcatimage()
        //{
        //    List<image> lstWorkflow = new List<image>();
        //    try
        //    {


        //        DataSet ds = DB.ExecuteStoredProcDataSet("geticatdetails");
        //        DataTable dtWorfklow = ds.Tables[0];

        //        if (dtWorfklow.Rows.Count > 0)
        //        {
        //            foreach (DataRow dtRow in dtWorfklow.Rows)
        //            {
        //                lstWorkflow.Add(new image
        //                {
        //                    CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
        //                    CAT_NAME = dtRow["CAT_NAME"].ToString(),
        //                    Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
        //                    ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
        //                    CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
        //                    Imagename = dtRow["Imagename"].ToString(),


        //                });
        //            }
        //        }

        //        Session["dataTable"] = dtWorfklow;
        //        return lstWorkflow;
        //    }
        //    catch (Exception ex)
        //    {
        //        return lstWorkflow;
        //    }
        //}





    }
}
