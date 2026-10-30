#nullable disable
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
using HRMS.Web.Areas.Items.Models;
using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Net;
using HRMS.Web.Areas.Items.Legacy;
using HRMS.Web.Areas.Items.Models;
using Newtonsoft.Json;

namespace HRMS.Web.Areas.Items.Controllers
{
    using Items = HRMS.Web.Areas.Items.Models.Items;
    using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;

    public class CategoryController : LegacyController
    {
        //
        // GET: /Category/

        public static int WaiterID = 1;

        public ActionResult Index()
        {
            //var WaiterID = 0;
            //var BrandID = 0;
            //var RoleID = 0;
            var cookie = QrCookie;
            if (cookie != null)
            {
                if (!string.IsNullOrEmpty(cookie["WaiterID"]))
                {
                    //WaiterID = Convert.ToInt32(cookie["WaiterID"]);
                    //BrandID = Convert.ToInt32(cookie["BrandID"]);
                    //RoleID = Convert.ToInt32(cookie["RoleID"]);

                    //ViewBag.WaiterID = WaiterID;
                    //ViewBag.BrandID = BrandID;
                    //ViewBag.RoleID = RoleID;
                    return View();
                }
            }
            return Redirect("/account/login");
        }
        public JsonResult GetBrands()
        {
            try
            {
                List<Brand> Brands = new List<Brand>();

                // WaiterID normally comes from the admin panel's eCommerceCook.
                // The POS panel's Item Management page (/POS/Menu) renders this
                // same view for an operator who signed in at /POS/Auth/Login and
                // therefore has no such cookie, so fall back to the POS session.
                // Its UserID is the very same tblUser.ID the cookie's WaiterID
                // holds - see ItemsController.UserLogin, which writes it.
                int WaiterID = 0;
                var cookie = QrCookie;
                if (cookie != null && !string.IsNullOrEmpty(cookie["WaiterID"]))
                {
                    WaiterID = Convert.ToInt32(cookie["WaiterID"].ToString());
                }

                if (WaiterID > 0)
                {
                    SqlParameter[] spa ={
                                 new SqlParameter(){
                                   ParameterName="@WaiterID",
                                   SqlDbType=SqlDbType.Int,
                                   Value=WaiterID
                                    },
                                };
                    DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBrands", spa);

                    DataTable dtgrdBrand = ds.Tables[0];
                    if (dtgrdBrand.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtgrdBrand.Rows)
                        {
                            Brands.Add(new Brand
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
                }
                return Json(new { dtgrdBrand = Brands }, JsonRequestBehavior.AllowGet);

                //return Redirect("/account/login");
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetBrands", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
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
                            IsActive = Convert.ToBoolean(dtRow["IsActive"].ToString()),
                            //SEQ_NUM = Convert.ToInt32(dtRow["SEQ_NUM"].ToString()),
                        });
                    }
                }

                return Json(new { dtgrdBranch = objBranch }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetBranchsBrandWise", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult GetCategoryList(int? BrandId, int? Branchid, int? MainCategoryId)
        {
            try
            {
                int isSubcategoryProject = 0;
                if (Convert.ToBoolean(ConfigurationManager.AppSettings["IsSubCategory"]) == true)
                {
                    isSubcategoryProject = 1;
                }
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    },new SqlParameter(){
                                       ParameterName="@Branchid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Branchid
                                    },new SqlParameter(){
                                       ParameterName="@MainCategoryId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=MainCategoryId
                                    },new SqlParameter(){
                                       ParameterName="@isSubcategoryProject",
                                       SqlDbType=SqlDbType.Int,
                                       Value=isSubcategoryProject
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryDragDrop", spa);
                List<CategoriesManage> Category = new List<CategoriesManage>();
                //List<ItemsList> Items = new List<ItemsList>();
                //if (ds != null && ds.Tables.Count > 1)
                //{
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
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
                            MainCategory = Convert.ToInt32(dtRow["MainCategory"].ToString()),
                            IsHaveSubCategory = Convert.ToInt32(dtRow["IsHaveSubCategory"].ToString()),
                        });
                    }
                }

                //DataTable dtItems = ds.Tables[1];
                //if (dtItems.Rows.Count > 0)
                //{
                //    foreach (DataRow dtRow in dtItems.Rows)
                //    {
                //        Items.Add(new ItemsList
                //        {
                //            id = Convert.ToInt32(dtRow["id"].ToString()),
                //            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                //            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                //            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                //            CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                //            PRICE = dtRow["PRICE"].ToString(),
                //            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                //            INGREDIENT = dtRow["INGREDIENT"].ToString(),
                //            INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                //            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                //            Currency = dtRow["Currency"].ToString(),
                //            HID = Convert.ToInt32(dtRow["HID"].ToString()),
                //        });
                //    }
                //}
                //}
                //else
                //{
                //    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);

                //}

                return Json(new { Message = "Success", dtCategory = Category }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetCategoryList", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult GetCategoryDetails(int? CAT_NUM)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=CAT_NUM,
                                    }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryDetails", spa);
                List<Category2> Category = new List<Category2>();
                List<int> objSelectedBranch = new List<int>();
                DataTable dtCategoryDet = ds.Tables[0];
                if (ds != null)
                {
                    foreach (DataRow dtRow in dtCategoryDet.Rows)
                    {
                        Category.Add(new Category2
                        {
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                            SEQ_NUM = Convert.ToInt32(dtRow["SEQ_NUM"].ToString()),
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
                            MainCategory = Convert.ToInt32(dtRow["MainCategory"].ToString()),
                            //BranchData = new List<Branch>()
                            //{
                            //    new Branch() { BranchId = Convert.ToInt32(dtRow["BranchId"].ToString()) },
                            //},
                        });
                    }

                    if (ds.Tables.Count > 1)
                    {
                        foreach (DataRow dtRow in ds.Tables[1].Rows)
                        {
                            objSelectedBranch.Add(Convert.ToInt32(dtRow["BranchId"]));
                        }
                    }
                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
                }

                return Json(new { Message = "Success", dtCategoryDetails = Category, dtselectedBranch = objSelectedBranch }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetCategoryDetails", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult GetMainCategoryList(int Brandid)
        {
            try
            {
                SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    },
            };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetMainCategoryList", spa);
                List<Category2> MainCategory = new List<Category2>();
                DataTable dtCategoryDet = ds.Tables[0];
                if (ds != null)
                {
                    foreach (DataRow dtRow in ds.Tables[0].Rows)
                    {
                        MainCategory.Add(new Category2
                        {
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            CAT_NAME_ARABIC = dtRow["CAT_NAME_ARABIC"].ToString(),
                        });
                    }
                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
                }

                return Json(new { Message = "Success", dtMainCategory = MainCategory }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetMainCategoryList", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }
        /// <summary>
        /// Add Category
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        /// 

        public JsonResult AddCategory(Category2 value)
        {
            try
            {
                SqlParameter[] spa ={
                                     new SqlParameter(){
                                       ParameterName ="@CAT_NAME",
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
                                    //,  new SqlParameter(){
                                    //   ParameterName="@HID",
                                    //   SqlDbType=SqlDbType.Int,
                                    //   Value=0
                                    //}
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("mvc_sp_AddCategory", spa);

                int CatNum = Convert.ToInt32(ds.Tables[0].Rows[0][0].ToString());

                UpdateCatAssign(value, CatNum);


                //string webServiceUrl = ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                //if (!string.IsNullOrEmpty(webServiceUrl))
                //{
                //    try
                //    {
                //        Category2 objCat = new Category2();
                //        objCat.CAT_NAME = value.CAT_NAME;
                //        objCat.CAT_NAME_ARABIC = value.CAT_NAME_ARABIC;
                //        objCat.CatNameMan = value.CatNameMan;
                //        objCat.CatNameRus = value.CatNameRus;
                //        objCat.SEQ_NUM = value.SEQ_NUM;
                //        objCat.BrandID = value.BrandID;
                //        objCat.ShowInTablet = value.ShowInTablet;
                //        objCat.MainCategory = value.MainCategory;

                //        if (objCat.MainCategory > 0)
                //        {
                //            SqlParameter[] spa ={
                //                     new SqlParameter(){
                //                       ParameterName ="@CAT_NUM",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=objCat.MainCategory
                //                    }
                //               };

                //            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetHIDasMainCategory", spa);
                //            objCat.MainCategory = Convert.ToInt32(ds.Tables[0].Rows[0]["HID"].ToString());
                //        }


                //        var data = new
                //        {
                //            CategoryData = objCat
                //        };
                //        string inputJson = (new JavaScriptSerializer()).Serialize(data);
                //        WebClient client = new WebClient();
                //        client.Headers["Content-type"] = "application/json";
                //        client.Encoding = System.Text.Encoding.UTF8;
                //        var jsonresult = client.UploadString(webServiceUrl + "/DmToCallCenterServices/AddUpdateCategoryFromDM", inputJson);
                //        FromCallCresultCategoryAdd objretData = (new JavaScriptSerializer()).Deserialize<FromCallCresultCategoryAdd>(jsonresult);
                //        //return jsonresult;
                //        if (objretData.HID > 0)
                //        {
                //            addcategorynew(value, objretData.HID);
                //        }

                //    }
                //    catch (Exception ex)
                //    {
                //        return Json(new { Message = "Error Connecting Head offce url,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
                //    }
                //    //return Json(jsonresult);

                //}
                //else
                //{
                //    addcategorynew(value, 0);
                //}
                //return Json(new { Message = "Error Connecting Head offce url,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AddCategory", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        //private static void addcategorynew(Category2 value, int HID)
        //{
        //    SqlParameter[] spa ={
        //                             new SqlParameter(){
        //                               ParameterName ="@CAT_NAME",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CAT_NAME
        //                            },  new SqlParameter(){
        //                               ParameterName="@CAT_NAME_ARABIC",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CAT_NAME_ARABIC
        //                            },  new SqlParameter(){
        //                               ParameterName="@CatNameMan",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CatNameMan
        //                            },  new SqlParameter(){
        //                               ParameterName="@CatNameRus",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CatNameRus
        //                            },  new SqlParameter(){
        //                               ParameterName="@SEQ_NUM",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.SEQ_NUM
        //                            },  new SqlParameter(){
        //                               ParameterName="@BrandID",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.BrandID
        //                            },  new SqlParameter(){
        //                               ParameterName="@ShowInTablet",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.ShowInTablet
        //                            },  new SqlParameter(){
        //                               ParameterName="@MainCategory",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.MainCategory
        //                            },  new SqlParameter(){
        //                               ParameterName="@HID",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=HID
        //                            }
        //                       };

        //    DataSet ds = DB.ExecuteStoredProcDataSet("mvc_sp_AddCategory", spa);

        //    int CatNum = Convert.ToInt32(ds.Tables[0].Rows[0][0].ToString());

        //    UpdateCatAssign(value, CatNum);
        //}


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


                //string webServiceUrl = ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                //if (!string.IsNullOrEmpty(webServiceUrl))
                //{
                //    try
                //    {
                //        Category2 objCat = new Category2();
                //        objCat.CAT_NUM = value.CAT_NUM;
                //        objCat.CAT_NAME = value.CAT_NAME;
                //        objCat.CAT_NAME_ARABIC = value.CAT_NAME_ARABIC;
                //        objCat.CatNameMan = value.CatNameMan;
                //        objCat.CatNameRus = value.CatNameRus;
                //        objCat.SEQ_NUM = value.SEQ_NUM;
                //        objCat.BrandID = value.BrandID;
                //        objCat.ShowInTablet = value.ShowInTablet;
                //        objCat.MainCategory = value.MainCategory;

                //        if (objCat.CAT_NUM > 0)
                //        {
                //            SqlParameter[] spa ={
                //                     new SqlParameter(){
                //                       ParameterName ="@CAT_NUM",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=objCat.CAT_NUM
                //                    }
                //               };

                //            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetHIDasMainCategory", spa);
                //            objCat.CAT_NUM = Convert.ToInt32(ds.Tables[0].Rows[0]["HID"].ToString());
                //        }


                //        var data = new
                //        {
                //            CategoryData = objCat
                //        };
                //        string inputJson = (new JavaScriptSerializer()).Serialize(data);
                //        WebClient client = new WebClient();
                //        client.Headers["Content-type"] = "application/json";
                //        client.Encoding = System.Text.Encoding.UTF8;
                //        var jsonresult = client.UploadString(webServiceUrl + "/DmToCallCenterServices/AddUpdateCategoryFromDM", inputJson);
                //        FromCallCresultCategoryAdd objretData = (new JavaScriptSerializer()).Deserialize<FromCallCresultCategoryAdd>(jsonresult);
                //        //return jsonresult;
                //        if (objretData.HID > 0)
                //        {
                //            updatecategorynew(value, objretData.HID);
                //        }

                //    }
                //    catch (Exception ex)
                //    {
                //        return Json(new { Message = "Error Connecting Head offce url,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
                //    }
                //    //return Json(jsonresult);
                //}
                //else
                //{
                //    updatecategorynew(value, 0);
                //}
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "UpdateCategory", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        //private static void updatecategorynew(Category2 value, int HID)
        //{
        //    SqlParameter[] spa ={
        //                               new SqlParameter(){
        //                               ParameterName="@CAT_NUM",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CAT_NUM
        //                            },  new SqlParameter(){
        //                               ParameterName="@CAT_NAME",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CAT_NAME
        //                            },  new SqlParameter(){
        //                               ParameterName="@CAT_NAME_ARABIC",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CAT_NAME_ARABIC
        //                            }, new SqlParameter(){
        //                               ParameterName="@CatNameRus",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CatNameRus
        //                            }, new SqlParameter(){
        //                               ParameterName="@CatNameMan",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CatNameMan
        //                            },  new SqlParameter(){
        //                               ParameterName="@SEQ_NUM",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.SEQ_NUM
        //                            },  new SqlParameter(){
        //                               ParameterName="@BrandID",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.BrandID
        //                            },  new SqlParameter(){
        //                               ParameterName="@ShowInTablet",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.ShowInTablet
        //                            },  new SqlParameter(){
        //                               ParameterName="@MainCategory",
        //                               SqlDbType=SqlDbType.Int,
        //                               Value=value.MainCategory
        //                            }
        //                       };

        //    int ds = DB.ExecuteStoredProc("mvc_sp_UpdateCategory", spa);

        //    UpdateCatAssign(value, value.CAT_NUM);
        //}
        public JsonResult DeleteCategory(Category2 value)
        {
            try
            {
                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.CAT_NUM
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_DeleteCategory", spa);
                DataTable dtCategory = ds.Tables[0];
                if (dtCategory.Rows.Count > 0)
                {
                    string msg = dtCategory.Rows[0]["msg"].ToString();
                    if (msg != "success")
                    {
                        return Json(new { Message = msg }, JsonRequestBehavior.AllowGet);
                    }
                }
                return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);



                //string webServiceUrl = ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                //if (!string.IsNullOrEmpty(webServiceUrl))
                //{
                //    try
                //    {
                //        Category2 objCat = new Category2();
                //        objCat.CAT_NUM = value.CAT_NUM;
                //        objCat.Deleted = true;
                //        if (objCat.CAT_NUM > 0)
                //        {
                //            SqlParameter[] spa ={
                //                     new SqlParameter(){
                //                       ParameterName ="@CAT_NUM",
                //                       SqlDbType=SqlDbType.Int,
                //                       Value=objCat.CAT_NUM
                //                    }
                //               };

                //            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetHIDasMainCategory", spa);
                //            objCat.CAT_NUM = Convert.ToInt32(ds.Tables[0].Rows[0]["HID"].ToString());
                //        }


                //        var data = new
                //        {
                //            CategoryData = objCat
                //        };
                //        string inputJson = (new JavaScriptSerializer()).Serialize(data);
                //        WebClient client = new WebClient();
                //        client.Headers["Content-type"] = "application/json";
                //        client.Encoding = System.Text.Encoding.UTF8;
                //        var jsonresult = client.UploadString(webServiceUrl + "/DmToCallCenterServices/AddUpdateCategoryFromDM", inputJson);
                //        FromCallCresultCategoryAdd objretData = (new JavaScriptSerializer()).Deserialize<FromCallCresultCategoryAdd>(jsonresult);
                //        //return jsonresult;
                //        if (objretData.HID > 0)
                //        {
                //            deletecate(value);
                //        }

                //    }
                //    catch (Exception ex)
                //    {
                //        return Json(new { Message = "Error Connecting Head offce url,Contact Your Manager." }, JsonRequestBehavior.AllowGet);
                //    }
                //    //return Json(jsonresult);
                //    return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
                //}
                //else
                //{
                //    return deletecate(value);
                //}
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "DeleteCategory", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        //private JsonResult deletecate(Category2 value)
        //{
        //    SqlParameter[] spa ={
        //                               new SqlParameter(){
        //                               ParameterName="@CAT_NUM",
        //                               SqlDbType=SqlDbType.NVarChar,
        //                               Value=value.CAT_NUM
        //                            }
        //                       };

        //    DataSet ds = DB.ExecuteStoredProcDataSet("sp_DeleteCategory", spa);
        //    DataTable dtCategory = ds.Tables[0];
        //    if (dtCategory.Rows.Count > 0)
        //    {
        //        string msg = dtCategory.Rows[0]["msg"].ToString();
        //        if (msg != "success")
        //        {
        //            return Json(new { Message = msg }, JsonRequestBehavior.AllowGet);
        //        }
        //    }
        //    return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        //}

        /// <summary>
        /// Update category sequence number.
        /// </summary>
        /// <param name="value"></param>
        /// <param name="CatNum"></param>
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

        public JsonResult GetItemList(int Cat_Num, int? BrandId, int? Branchid)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@CAT_NUM",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Cat_Num
                                    }
                                    ,new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    },new SqlParameter(){
                                       ParameterName="@Branchid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Branchid
                                    }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryWiseItemListDragDrop", spa);
                List<ItemsList> Items = new List<ItemsList>();
                int isShowAllergen = 0;
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
                                Currency = dtRow["Currency"].ToString(),
                                HID = Convert.ToInt32(dtRow["HID"].ToString()),
                                ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
                                //IsExtraItem = Convert.ToBoolean(dtRow["isExtra"].ToString())
                            });
                        }
                    }

                    
                    DataTable dtShowAllergen = ds.Tables[1];
                    if (dtShowAllergen.Rows.Count > 0)
                    {
                        foreach (DataRow dtRow in dtShowAllergen.Rows)
                        {
                            isShowAllergen = Convert.ToBoolean(dtRow["ShowAllergen"].ToString()) == true ? 1 : 0;
                        }
                    }
                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
                }

                return Json(new { Message = "Success", dtItems = Items, IsShowAllergen = isShowAllergen }, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemList", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult GetExtraComments(int Brandid)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetExtraComments", spa);
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
                DB.AuditTrail(ex, "CategoryController", "GetExtraComments", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult GetGroupModifier(int Brandid)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetGroupModifier", spa);
            List<ModifierGroups> objModifierGroups = new List<ModifierGroups>();
            DataTable dtGetModifierGroups = ds.Tables[0];
            try
            {
                if (dtGetModifierGroups.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtGetModifierGroups.Rows)
                    {
                        objModifierGroups.Add(new ModifierGroups
                        {
                            ID = Convert.ToInt32(dtRow["id"].ToString()),
                            GroupNameEng = dtRow["GroupNameEng"].ToString(),
                            GroupNameArb = dtRow["GroupNameArb"].ToString(),
                            TypeID = Convert.ToInt32(dtRow["TypeID"].ToString()),
                            TypeName = dtRow["TypeName"].ToString(),
                            MinSelect = Convert.ToInt32(dtRow["MinSelect"].ToString()),
                            MaxSelect = Convert.ToInt32(dtRow["MaxSelect"].ToString()),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                        });
                    }
                }

                return Json(new { dtGroupModifier = objModifierGroups }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetGroupModifier", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        // Extracted from the original GetAllergens body so AddItem/UpdateItem's
        // allergen-sync (see SyncItemAllergens below) and GetItemAllergens can reuse
        // the exact same master-list fetch instead of duplicating it.
        private List<Allergens> GetAllergensList(int Brandid)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAllergens", spa);
            List<Allergens> objAllergens = new List<Allergens>();
            DataTable dtAllergens = ds.Tables[0];
            if (dtAllergens.Rows.Count > 0)
            {
                foreach (DataRow dtRow in dtAllergens.Rows)
                {
                    objAllergens.Add(new Allergens
                    {
                        id = Convert.ToInt32(dtRow["id"].ToString()),
                        name = dtRow["name"].ToString(),
                        Name_arabic = dtRow["Name_arabic"].ToString(),
                        image = dtRow["image"].ToString(),
                    });
                }
            }
            return objAllergens;
        }

        public JsonResult GetAllergens(int Brandid)
        {
            try
            {
                List<Allergens> objAllergens = GetAllergensList(Brandid);
                return Json(new { dtAllergens = objAllergens }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetAllergens", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        // Edit Item modal: which of the brand's allergens are currently assigned to
        // this item, so the "Select Allergen" multi-select can pre-select them. There
        // is no dedicated "allergens for one item" proc yet, so this composes from the
        // two allergen procs that already exist and are already proven to work (the
        // master list, and sp_GetItemsAllergenWise - the same allergen -> assigned-items
        // reverse lookup the Allergens sidebar panel already uses): for each master
        // allergen, check whether this item is in its assigned-items list. The master
        // allergen list is small (a per-brand handful of records), so this is cheap -
        // and, importantly, needs no new stored procedure or schema assumptions.
        public JsonResult GetItemAllergens(int ItemId, int BrandId)
        {
            try
            {
                List<Allergens> allAllergens = GetAllergensList(BrandId);
                List<int> selectedIds = new List<int>();
                foreach (var allergen in allAllergens)
                {
                    SqlParameter[] spa = {
                        new SqlParameter(){
                           ParameterName="@AllergenId",
                           SqlDbType=SqlDbType.Int,
                           Value=allergen.id
                        },
                    };
                    DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemsAllergenWise", spa);
                    if (ds != null && ds.Tables.Count > 0)
                    {
                        foreach (DataRow dtRow in ds.Tables[0].Rows)
                        {
                            if (Convert.ToInt32(dtRow["ItemId"].ToString()) == ItemId)
                            {
                                selectedIds.Add(allergen.id);
                                break;
                            }
                        }
                    }
                }
                return Json(new { Message = "Success", dtselectedAllergens = selectedIds }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemAllergens", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        // Called from AddItem/UpdateItem right after the item itself is saved (same
        // spot Branches/Extras/Choices/Comments are synced). Reuses the EXISTING
        // sp_AssignAllergenToItem toggle proc (already live - it backs the Allergens
        // sidebar's per-item checkbox) instead of a new bulk-assign proc.
        //
        // Per explicit request: unassign every allergen for this item first, then
        // reassign exactly the ones currently checked - a full replace on every save,
        // rather than diffing against a previously-read "current" state. This is
        // simpler and more robust than a diff (nothing depends on correctly reading
        // prior state first), and it also sidesteps sp_AssignAllergenToItem's
        // Isselected=1 branch having no "if not exists" guard on its INSERT (see the
        // proc source) - since every allergen is unassigned immediately before being
        // possibly reassigned, the insert can never collide with an existing row.
        private void SyncItemAllergens(int itemId, List<Allergens> selectedAllergens, int brandId)
        {
            HashSet<int> selectedIds = new HashSet<int>();
            if (selectedAllergens != null)
            {
                foreach (var a in selectedAllergens) selectedIds.Add(a.id);
            }

            List<Allergens> allAllergens = GetAllergensList(brandId);

            // Step 1: unassign every allergen for this item. sp_AssignAllergenToItem's
            // Isselected=0 branch is a plain DELETE ... WHERE, safe to call even when
            // no such row exists (affects 0 rows, no error).
            foreach (var allergen in allAllergens)
            {
                SqlParameter[] spaClear = {
                    new SqlParameter(){
                       ParameterName="@AllergenId",
                       SqlDbType=SqlDbType.Int,
                       Value=allergen.id
                    },
                    new SqlParameter(){
                       ParameterName="@ItemId",
                       SqlDbType=SqlDbType.Int,
                       Value=itemId
                    },
                    new SqlParameter(){
                       ParameterName="@Isselected",
                       Value=false
                    }
                };
                DB.ExecuteStoredProcDataSet("sp_AssignAllergenToItem", spaClear);
            }

            // Step 2: reassign exactly the ones currently checked.
            foreach (var allergen in allAllergens)
            {
                if (!selectedIds.Contains(allergen.id))
                {
                    continue;
                }

                SqlParameter[] spaSet = {
                    new SqlParameter(){
                       ParameterName="@AllergenId",
                       SqlDbType=SqlDbType.Int,
                       Value=allergen.id
                    },
                    new SqlParameter(){
                       ParameterName="@ItemId",
                       SqlDbType=SqlDbType.Int,
                       Value=itemId
                    },
                    new SqlParameter(){
                       ParameterName="@Isselected",
                       Value=true
                    }
                };
                DB.ExecuteStoredProcDataSet("sp_AssignAllergenToItem", spaSet);
            }
        }

        public JsonResult GetItemDetails(int ID)
        {
            try
            {
                SqlParameter[] spa ={ new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=ID,
                                    }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemDetails", spa);
                List<Items> Item = new List<Items>();

                List<int> objSelectedBranch = new List<int>();
                List<int> objSelectedExtraItems = new List<int>();
                List<int> objSelectedComments = new List<int>();
                List<int> objSelectedChoices = new List<int>();

                DataTable dtItemDet = ds.Tables[0];
                if (ds != null)
                {
                    foreach (DataRow dtRow in dtItemDet.Rows)
                    {
                        Item.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            OrderID = "",
                            catNameArabic = dtRow["CAT_NAME_ARABIC"].ToString(),
                            catNameRus = "",
                            catNameMan = "",
                            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                            ITEM_NAME_ARABIC = dtRow["ITEM_NAME_ARABIC"].ToString(),
                            ITEM_DESC_ENG = "",
                            IMAGENAME = dtRow["ImageName"].ToString(),
                            INGREDIENT_ARABIC = dtRow["INGREDIENT_ARABIC"].ToString(),
                            INGREDIENT = dtRow["INGREDIENT"].ToString(),
                            Seq_Num = Convert.ToInt32(dtRow["Seq_Num"].ToString()),
                            ShowInTablet = Convert.ToBoolean(dtRow["ShowInTablet"].ToString()),
                            PRICE = dtRow["PRICE"].ToString(),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            TotalPrice = "",
                            BrandID = 0,
                            ItemNameMan = "",
                            ItemNameRus = "",
                            INGREDIENT_Man = "",
                            INGREDIENT_Rus = "",
                            Video = dtRow["Video"].ToString(),
                            BrandName = "",
                            HID = 0,
                            IsActive = Convert.ToBoolean(dtRow["IsActive"].ToString()),
                            IsExtraItems = Convert.ToBoolean(dtRow["isExtra"].ToString()),

                            //ExtraItems = new List<Items>()
                            //{
                            //    new Items() { ID = Convert.ToInt32(dtRow["ID"].ToString()) },
                            //},
                            //Comments = new List<ItemsComments>()
                            //{
                            //    new ItemsComments() { ItemID = dtRow["ItemID"].ToString() },
                            //},
                            //BranchData = new List<Branch>()
                            //{
                            //    new Branch() { BranchId = Convert.ToInt32(dtRow["BranchId"].ToString()) },
                            //},
                        });
                    }

                    if (ds.Tables[1] != null)
                    {
                        foreach (DataRow dtRow in ds.Tables[1].Rows)
                        {
                            objSelectedBranch.Add(Convert.ToInt32(dtRow["BranchId"]));
                        }
                    }
                    if (ds.Tables[2] != null)
                    {
                        foreach (DataRow dtRow in ds.Tables[2].Rows)
                        {
                            objSelectedExtraItems.Add(Convert.ToInt32(dtRow["ExtraItemId"]));
                        }
                    }
                    if (ds.Tables[3] != null)
                    {
                        foreach (DataRow dtRow in ds.Tables[3].Rows)
                        {
                            objSelectedComments.Add(Convert.ToInt32(dtRow["commentid"]));
                        }
                    }
                    if (ds.Tables[4] != null)
                    {
                        foreach (DataRow dtRow in ds.Tables[4].Rows)
                        {
                            objSelectedChoices.Add(Convert.ToInt32(dtRow["ChoiceId"]));
                        }
                    }

                }
                else
                {
                    return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
                }

                return Json(new
                {
                    Message = "Success",
                    dtItemDetails = Item,
                    dtselectedBranch = objSelectedBranch,
                    dtselectedExtraItems = objSelectedExtraItems,
                    dtselectedComments = objSelectedComments,
                    dtselectedChoices = objSelectedChoices
                },
                                JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemDetails", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult AddItem(Items value)
        {
            int ItemId = 0;
            try
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
                                       Value=value.IMAGENAME
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
                                    ,  new SqlParameter(){
                                       ParameterName="@ischoice",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Ischoice
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AddItem", spa);
                ItemId = Convert.ToInt32(ds.Tables[0].Rows[0][0].ToString());

                if (!value.IsExtraItems && !value.Ischoice)
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

                    //start assign items Choices 
                    if (value.Choices != null)
                    {
                        if (value.Choices.Count > 0)
                        {
                            for (int i = 0; i < value.Choices.Count; i++)
                            {
                                SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@ChoiceId",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.Choices[i].ID
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

                                DB.ExecuteStoredProcDataSet("sp_Assign_Item_Choices", spa1);

                            }
                        }
                    }
                    //End assign items Choices

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

                    //start assign Allergens (Edit Item modal's "Select Allergen" control).
                    // Gated on the explicit IsAllergenSectionVisible flag, NOT on
                    // "Allergens != null" - an empty selection can legitimately bind as
                    // null (ASP.NET MVC JSON-binding quirk for empty arrays), which would
                    // be indistinguishable from "section hidden, ShowAllergen=0" if we
                    // checked Allergens alone. IsAllergenSectionVisible removes that
                    // ambiguity: false means leave existing assignments untouched, true
                    // means sync (SyncItemAllergens treats a null Allergens the same as
                    // an empty one - "nothing selected").
                    if (value.IsAllergenSectionVisible)
                    {
                        SyncItemAllergens(ItemId, value.Allergens, value.BrandID);
                    }
                    //End assign Allergens
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AddItem", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Added Sucessfully", ID = ItemId }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UploadFile(IFormFile fileToUpload)
        {
            string imageUrls = "";
            string _path = "";
            string _Thumbnailpath = "";

            IFormFileCollection files = Request.Form.Files;
            if (files.Count > 0)
            {
                for (int i = 0; i < files.Count; i++)
                {
                    IFormFile file = files[i];
                    try
                    {
                        if (file.Length > 0)
                        {
                            var Filename = Path.GetFileName(file.FileName);
                            //string strpath = Path.GetExtension(Filename);
                            //Filename = RenameImanges(Filename);

                            string strpath = Path.GetExtension(Filename);
                            Filename = RenameImanges(Filename) + strpath;

                            var objitemcont = new LegacyImageUpload(Server);

                            if (strpath == ".gif")
                            {
                                objitemcont.uploadGif(fileToUpload);
                                return Json(Filename);
                            }
                            _path = Path.Combine(Server.MapPath("~/images"), Filename);
                            _Thumbnailpath = Path.Combine(Server.MapPath("~/ThumbnailImages"), Filename);
                            byte[] fileData = null;
                            using (var binaryReader = new BinaryReader(file.OpenReadStream()))
                            {
                                fileData = binaryReader.ReadBytes((int)file.Length);
                            }

                            objitemcont.HandleImageUpload(fileData, _path);
                            objitemcont.HandleThumbnailImageUpload(fileData, _Thumbnailpath);

                            //imageUrls = "/images/" + Filename;
                            imageUrls = Filename;
                        }
                        //System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");
                    }
                    catch (Exception ex)
                    {
                        //return Json(ViewBag.Message);
                        return Json(new { Message = "Fail," + ex.Message + "" }, JsonRequestBehavior.AllowGet);
                    }
                }
            }
            else
            {
                return Json(new { Message = "Fail, Please Select file." }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Success", FileName = imageUrls }, JsonRequestBehavior.AllowGet);

        }

        [HttpPost]
        public JsonResult VideoUploadFile(IFormFile fileToUpload)
        {
            string imageUrls = "";
            string _path = "";

            IFormFileCollection files = Request.Form.Files;
            if (files.Count > 0)
            {
                for (int i = 0; i < files.Count; i++)
                {
                    IFormFile file = files[i];
                    try
                    {
                        if (file.Length > 0)
                        {
                            var Filename = Path.GetFileName(file.FileName);
                            //string strpath = Path.GetExtension(Filename);
                            //Filename = RenameImanges(Filename);

                            string strpath = Path.GetExtension(Filename);
                            Filename = RenameImanges(Filename) + strpath;


                            //var Filename = Path.GetFileName(file.FileName);
                            _path = Path.Combine(Server.MapPath("~/Video"), Filename);
                            file.SaveAs(_path);

                            //_path = Path.Combine(Server.MapPath("~/Video"), Filename);
                            //byte[] fileData = null;
                            //file.SaveAs(_path);


                            //img.Save(path, System.Drawing.Imaging.ImageFormat.Jpeg);
                            //objitemcont.HandleImageUpload(fileData, _path);
                            //objitemcont.HandleThumbnailImageUpload(fileData, _Thumbnailpath);

                            //imageUrls = "/images/" + Filename;
                            imageUrls = Filename;
                        }
                        //System.Diagnostics.Debug.WriteLine("File Uploaded Successfully!!");
                    }
                    catch (Exception ex)
                    {
                        //return Json(ViewBag.Message);
                        return Json(new { Message = "Fail," + ex.Message + "" }, JsonRequestBehavior.AllowGet);
                    }
                }
            }
            else
            {
                return Json(new { Message = "Fail, Please Select file." }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Success", FileName = imageUrls }, JsonRequestBehavior.AllowGet);

        }
        public JsonResult UpdateItem(Items value)
        {
            try
            {
                var ImageName = value.IMAGENAME;
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
                                    },  new SqlParameter(){
                                       ParameterName="@ischoice",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Ischoice
                                    }
                               };

                int ds = DB.ExecuteStoredProc("sp_UpdateItem", spa);

                if (!value.IsExtraItems && !value.Ischoice)
                {
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

                    //start assign items Choices 
                    if (value.Choices != null)
                    {
                        if (value.Choices.Count > 0)
                        {
                            for (int i = 0; i < value.Choices.Count; i++)
                            {
                                SqlParameter[] spa1 ={
                                         new SqlParameter(){
                                           ParameterName="@ChoiceId",
                                           SqlDbType=SqlDbType.Int,
                                           Value=value.Choices[i].ID
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

                                DB.ExecuteStoredProcDataSet("sp_Assign_Item_Choices", spa1);

                            }
                        }
                    }
                    else
                    {
                        DB.ExecuteNonQuery("delete from tblItem_Choices where itemid = " + value.ID + "");
                    }
                    //End assign items Choices

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
                    }
                    //End assign Items Comments

                    //start assign Allergens (Edit Item modal's "Select Allergen" control).
                    // Gated on the explicit IsAllergenSectionVisible flag, NOT on
                    // "Allergens != null" - an empty selection can legitimately bind as
                    // null (ASP.NET MVC JSON-binding quirk for empty arrays), which would
                    // be indistinguishable from "section hidden, ShowAllergen=0" if we
                    // checked Allergens alone. IsAllergenSectionVisible removes that
                    // ambiguity: false means leave existing assignments untouched, true
                    // means sync (SyncItemAllergens treats a null Allergens the same as
                    // an empty one - "nothing selected").
                    if (value.IsAllergenSectionVisible)
                    {
                        SyncItemAllergens(value.ID, value.Allergens, value.BrandID);
                    }
                    //End assign Allergens
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "UpdateItem", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Updated Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult DeleteItem(Items value)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ID
                                    }
                               };

                int ds = DB.ExecuteStoredProc("sp_DeleteItem", spa);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "DeleteItem", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public string RenameImanges(string Filename)
        {
            //Filename = Filename.ToLower();
            //Filename = Filename.Replace(" ", "_");
            //Filename = Filename.Trim();
            //Filename = Filename.Replace("%", "_");
            //Filename = Filename.Replace("&", "_");
            //Filename = Filename.Replace("#", "_");
            //Filename = Filename.Replace("-", "_");
            //Filename = Filename.Replace("@", "_");
            //Filename = Filename.Replace("(", "_");
            //Filename = Filename.Replace(")", "_");
            //Filename = Filename.Replace("[", "_");
            //Filename = Filename.Replace("]", "_");
            //Filename = Filename.Replace("-", "_");

            Filename = "";
            //System.DateTime moment = new System.DateTime();
            var moment = DateTime.Now;
            Filename = Filename + moment.Year.ToString();
            Filename = Filename + moment.Month.ToString();
            Filename = Filename + moment.Day.ToString();
            Filename = Filename + moment.Hour.ToString();
            Filename = Filename + moment.Minute.ToString();
            Filename = Filename + moment.Second.ToString();
            return Filename;
        }


        [HttpPost]
        public JsonResult updateCategorySequance(List<CatSequance> CatSequanceList)
        {
            try
            {
                DataTable dt = DB.ToDataTable(CatSequanceList);
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@dttblCatSeq",
                                       Value=dt
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_updateCategorySequance", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "updateCategorySequance", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }


        [HttpPost]
        public JsonResult updateItemsSequance(List<ItemSequance> ItemsSequanceList)
        {
            try
            {
                DataTable dt = DB.ToDataTable(ItemsSequanceList);
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@dttblItemsSeq",
                                       Value=dt
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_updateItemsSequance", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "updateItemsSequance", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult GetCategoryBranchwise(int BrandID, int BranchId)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@branchid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BranchId
                                    },
                                    new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryBranchwise", spa);
            List<Category> objcate = new List<Category>();
            DataTable dtgrdBranch = ds.Tables[0];
            try
            {

                if (dtgrdBranch.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdBranch.Rows)
                    {
                        objcate.Add(new Category
                        {
                            CAT_NUM = Convert.ToInt32(dtRow["CAT_NUM"].ToString()),
                            CAT_NAME = dtRow["CAT_NAME"].ToString(),
                        });
                    }
                }

                return Json(new { Message = "Success", dtcate = objcate }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetCategoryBranchwise", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetItemsBranchwise(int BrandID, int BranchId)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@branchid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BranchId
                                    },
                                    new SqlParameter(){
                                       ParameterName="@BrandID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandID
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemsBranchwise", spa);
            List<Items> objitems = new List<Items>();
            DataTable dtgrdBranch = ds.Tables[0];
            try
            {
                if (dtgrdBranch.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdBranch.Rows)
                    {
                        objitems.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ItemId"].ToString()),
                            ITEM_NAME = dtRow["ITEM_NAME"].ToString(),
                        });
                    }
                }
                return Json(new { Message = "Success", dtItems = objitems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemsBranchwise", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult GetItemsExtraItemsWise(int ExtraItemId)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@ExtraItemId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=ExtraItemId
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemsExtraItemsWise", spa);
            List<Items> objitems = new List<Items>();
            DataTable dtitemsId = ds.Tables[0];
            try
            {
                if (dtitemsId.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtitemsId.Rows)
                    {
                        objitems.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ItemId"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtItemIds = objitems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemsExtraItemsWise", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetChoicesItemsWise(int choiceId)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@choiceId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=choiceId
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetChoicesItemsWise", spa);
            List<Items> objitems = new List<Items>();
            DataTable dtitemsId = ds.Tables[0];
            try
            {
                if (dtitemsId.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtitemsId.Rows)
                    {
                        objitems.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ItemId"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtItemIds = objitems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetChoicesItemsWise", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult GetItemsCommentWise(int CommentId)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@CommentId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=CommentId
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemsCommentWise", spa);
            List<Items> objitems = new List<Items>();
            DataTable dtitemsId = ds.Tables[0];
            try
            {
                if (dtitemsId.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtitemsId.Rows)
                    {
                        objitems.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ItemId"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtItemIds = objitems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemsCommentWise", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }
        public JsonResult GetItemsAllergenWise(int AllergenId)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@AllergenId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=AllergenId
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemsAllergenWise", spa);
            List<Items> objitems = new List<Items>();
            DataTable dtitemsId = ds.Tables[0];
            try
            {
                if (dtitemsId.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtitemsId.Rows)
                    {
                        objitems.Add(new Items
                        {
                            ID = Convert.ToInt32(dtRow["ItemId"].ToString()),
                        });
                    }
                }
                return Json(new { Message = "Success", dtItemIds = objitems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemsAllergenWise", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        [HttpPost]
        public JsonResult UpdateCategoryBranchAssign(int brandId, int branchId, int cat_num, bool Isselected)
        {
            try
            {

                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@brandId",
                                       Value=brandId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@branchId",
                                       Value=branchId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@cat_num",
                                       Value=cat_num
                                    },
                                       new SqlParameter(){
                                       ParameterName="@Isselected",
                                       Value=Isselected
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_UpdateCategoryBranchAssign", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "UpdateCategoryBranchAssign", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult AssignItemToBranch(int brandId, int branchId, int ItemId, bool Isselected)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@brandId",
                                       Value=brandId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@branchId",
                                       Value=branchId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@ItemId",
                                       Value=ItemId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@Isselected",
                                       Value=Isselected
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AssignItemToBranch", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AssignItemToBranch", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult AssignChoiceToItem(int ChoiceId, int ItemId, bool Isselected)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@ChoiceId",
                                       Value=ChoiceId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@ItemId",
                                       Value=ItemId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@Isselected",
                                       Value=Isselected
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AssignChoiceToItem", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AssignChoiceToItem", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult AssignExtraItemToItem(int ExtraItemId, int ItemId, bool Isselected)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@ExtraItemId",
                                       Value=ExtraItemId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@ItemId",
                                       Value=ItemId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@Isselected",
                                       Value=Isselected
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AssignExtraItemToItem", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AssignExtraItemToItem", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult AssignCommentToItem(int Commentid, int ItemId, bool Isselected)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@Commentid",
                                       Value=Commentid
                                    },
                                       new SqlParameter(){
                                       ParameterName="@ItemId",
                                       Value=ItemId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@Isselected",
                                       Value=Isselected
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AssignCommentToItem", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AssignCommentToItem", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        [HttpPost]
        public JsonResult AssignAllergen(int AllergenId, int ItemId, bool Isselected)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@AllergenId",
                                       Value=AllergenId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@ItemId",
                                       Value=ItemId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@Isselected",
                                       Value=Isselected
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AssignAllergenToItem", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AssignAllergen", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        /// <summary>
        /// Add and Edit Comments
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public JsonResult SaveComment(Comments value,int? Brandid)
        {
            try
            {
                SqlParameter[] spa ={
                                     new SqlParameter(){
                                       ParameterName ="@id",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.ID
                                    },  new SqlParameter(){
                                       ParameterName="@comments_eng",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.comments_eng
                                    },  new SqlParameter(){
                                       ParameterName="@comments_arb",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.comments_arb
                                    }
                                    ,  new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AddUpdateComments", spa);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "SaveComment", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult GetExtraItems(int Brandid)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAllExtraItems", spa);
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
                            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                            PRICE = dtRow["PRICE"].ToString(),
                            Currency = dtRow["Currency"].ToString(),
                        });
                    }
                }

                return Json(new { dtgrdItems = objItems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetExtraItems", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult GetChoices(int Brandid)
        {
            SqlParameter[] spa ={
                                    new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    },
            };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAllChoices", spa);
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
                            IMAGENAME = dtRow["IMAGENAME"].ToString(),
                            PRICE = dtRow["PRICE"].ToString(),
                            Currency = dtRow["Currency"].ToString(),
                        });
                    }
                }

                return Json(new { dtgrdItems = objItems }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetChoices", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult ChangePassword(int? UserId, string OldPassword, string NewPassword)
        {
            // Only ever the signed-in user's own password (the old page sent any UserId).
            UserId = int.TryParse(QrCookie?["WaiterID"], out var signedInUserId) ? signedInUserId : 0;
            try
            {
                SqlParameter[] spa ={  new SqlParameter(){
                                       ParameterName="@UserId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=UserId
                                    },  new SqlParameter(){
                                       ParameterName="@OldPassword",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=OldPassword
                                    }, new SqlParameter()
                                    {
                                        ParameterName = "@NewPassword",
                                        SqlDbType = SqlDbType.NVarChar,
                                        Value = NewPassword
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_changePassword", spa);
                if (ds.Tables.Count > 0)
                {
                    DataTable dtUsers = ds.Tables[0];
                    if (dtUsers.Rows[0]["Msg"].ToString() == "Wrong Password")
                    {
                        return Json(new { message = "fail", alert = "Wrong Password" }, JsonRequestBehavior.AllowGet);
                    }
                    else
                    {
                        return Json(new { message = "Success" }, JsonRequestBehavior.AllowGet);
                    }
                }
                else
                {
                    return Json(new { message = "Success" }, JsonRequestBehavior.AllowGet);
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "ChangePassword", null);
                return Json(new { message = "fail", alert = ex.Message }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult SaveBranch(Branch value)
        {
            try
            {
                SqlParameter[] spa ={
                                     new SqlParameter(){
                                       ParameterName ="@BranchId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.BranchId
                                    },  new SqlParameter(){
                                       ParameterName="@branchName",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.branchName
                                    },  new SqlParameter(){
                                       ParameterName="@BranchNameAra",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.BranchNameAra
                                    }
                                    ,  new SqlParameter(){
                                       ParameterName="@IsActive",
                                       SqlDbType=SqlDbType.Bit,
                                       Value=value.IsActive
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AddUpdateBranch", spa);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "SaveBranch", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }

            return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult GetGroupModifierTypes()
        {
            //SqlParameter[] spa ={
            //                        new SqlParameter(){
            //                           ParameterName="@Brandid",
            //                           SqlDbType=SqlDbType.Int,
            //                           Value=Brandid
            //                        },
            //};
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetGroupModifierTypes");
            List<GroupModifierTypes> objtypes = new List<GroupModifierTypes>();
            DataTable dtgrdItems = ds.Tables[0];
            try
            {

                if (dtgrdItems.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtgrdItems.Rows)
                    {
                        objtypes.Add(new GroupModifierTypes
                        {
                            ID = Convert.ToInt32(dtRow["ID"].ToString()),
                            TypeName_TMM = dtRow["TypeName_TMM"].ToString(),
                        });
                    }
                }

                return Json(new { dtGroupModifierTypes = objtypes }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetChoices", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult AddGroupModifier(Group_Modifier_Master value, int? Brandid)
        {
            try
            {
                SqlParameter[] spa ={ 
                                    //    new SqlParameter(){
                                    //   ParameterName="@ID",
                                    //   SqlDbType=SqlDbType.Int,
                                    //   Value=value.CAT_NUM
                                    //},  
                                        new SqlParameter(){
                                       ParameterName="@GroupNameEng",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.GroupNameEng
                                    },  new SqlParameter(){
                                       ParameterName="@GroupNameArb",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.GroupNameArb
                                    },  new SqlParameter(){
                                       ParameterName="@Type",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Type
                                    },  new SqlParameter(){
                                       ParameterName="@MinSelect",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.MinSelect
                                    },  new SqlParameter(){
                                       ParameterName="@MaxSelect",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.MaxSelect
                                    },  new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AddGroupModifier", spa);
                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            if (ds.Tables[0].Rows[0]["Status"].ToString() == "Already Exists")
                            {
                                return Json(new { Message = "Group Modifier Name already Exists." }, JsonRequestBehavior.AllowGet);
                            }
                            else if (ds.Tables[0].Rows[0]["Status"].ToString() == "Success")
                            {
                                return Json(new { Message = "Added Sucessfully" }, JsonRequestBehavior.AllowGet);
                            }
                        }
                    }

                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AddGroupModifier", null);
                //return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult UpdateGroupModifier(Group_Modifier_Master value, int? Brandid)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ID
                                    },
                                        new SqlParameter(){
                                       ParameterName="@GroupNameEng",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.GroupNameEng
                                    },  new SqlParameter(){
                                       ParameterName="@GroupNameArb",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=value.GroupNameArb
                                    },  new SqlParameter(){
                                       ParameterName="@Type",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.Type
                                    },  new SqlParameter(){
                                       ParameterName="@MinSelect",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.MinSelect
                                    },  new SqlParameter(){
                                       ParameterName="@MaxSelect",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.MaxSelect
                                    },  new SqlParameter(){
                                       ParameterName="@Brandid",
                                       SqlDbType=SqlDbType.Int,
                                       Value=Brandid
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_UpdateGroupModifier", spa);
                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            if (ds.Tables[0].Rows[0]["Status"].ToString() == "Already Exists")
                            {
                                return Json(new { Message = "Group Modifier Name already Exists." }, JsonRequestBehavior.AllowGet);
                            }
                            else if (ds.Tables[0].Rows[0]["Status"].ToString() == "Success")
                            {
                                return Json(new { Message = "Update Sucessfully" }, JsonRequestBehavior.AllowGet);
                            }
                        }
                    }

                }

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "sp_UpdateGroupModifier", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult DeleteGroupModifier(Group_Modifier_Master value)
        {
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ID
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_DeleteGroupModifier", spa);
                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            if (ds.Tables[0].Rows[0]["Status"].ToString() == "Success")
                            {
                                return Json(new { Message = "Deleted Sucessfully" }, JsonRequestBehavior.AllowGet);
                            }
                        }
                    }

                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "DeleteGroupModifier", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
        }
        public JsonResult UpdateGroupModifierSequence(Group_Modifier_Master value)
        {
            try
            {
                SqlParameter[] spa =
                                    //{
                                    //   new SqlParameter(){
                                    //   ParameterName="@ID",
                                    //   SqlDbType=SqlDbType.Int,
                                    //   Value=value.ID
                                    //},
                                    //   new SqlParameter(){
                                    //   ParameterName="@Seq_Num",
                                    //   SqlDbType=SqlDbType.Int,
                                    //   Value=value.Seq_Num
                                    //}
                                    {
                                       new SqlParameter(){
                                       ParameterName="@ID",
                                       SqlDbType=SqlDbType.Int,
                                       Value=value.ID
                                    },
                                       new SqlParameter(){
                                       ParameterName="@SortingType",
                                       SqlDbType=SqlDbType.VarChar,
                                       Value=value.SortingType
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_UpdateGroupModifierSequence", spa);
                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            if (ds.Tables[0].Rows[0]["Status"].ToString() == "Success")
                            {
                                return Json(new { Message = "Update Sucessfully" }, JsonRequestBehavior.AllowGet);
                            }
                        }
                    }

                }

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "sp_UpdateGroupModifier", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult AssignGroupModifier(List<AssignGroupModifier> value, int? MainItemId)
        {
            try
            {
                DataSet ds = null;
                if (value != null)
                {
                    DataTable dt = DB.ToDataTable(value);
                    SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@dttblGroup_Modifier_Details",
                                       Value=dt
                                    },
                                       new SqlParameter(){
                                       ParameterName="@MainItemId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=MainItemId
                                    }
                    };
                    ds = DB.ExecuteStoredProcDataSet("sp_AssignGroupModifier", spa1);
                }
                else
                {
                    SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@dttblGroup_Modifier_Details",
                                       Value=null
                                    },
                                       new SqlParameter(){
                                       ParameterName="@MainItemId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=MainItemId
                                    }
                    };
                    ds = DB.ExecuteStoredProcDataSet("sp_AssignGroupModifier", spa1);
                }

                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            if (ds.Tables[0].Rows[0]["Status"].ToString() == "Success")
                            {
                                return Json(new { Message = "Assign Sucessfully" }, JsonRequestBehavior.AllowGet);
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "AssignGroupModifier", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult BindAssignGroupModifier(int MainItemId)
        {
            try
            {
                SqlParameter[] spa1 ={
                                       new SqlParameter(){
                                       ParameterName="@MainItemId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=MainItemId
                                    }
                };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBindAssignGroupModifier", spa1);
                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            return Json(new { Message = "Success", Groupsdata = JsonConvert.SerializeObject(ds.Tables[0]), GroupWiseItemsdata = JsonConvert.SerializeObject(ds.Tables[1]) }, JsonRequestBehavior.AllowGet);
                        }
                    }
                }
                return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "BindAssignGroupModifier", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
        }

        public JsonResult UpdateBranchSequence(int BranchId,string SortingType)
        {
            try
            {
                SqlParameter[] spa =
                                    {
                                       new SqlParameter(){
                                       ParameterName="@BranchId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BranchId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@SortingType",
                                       SqlDbType=SqlDbType.VarChar,
                                       Value=SortingType
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_UpdateBranchSequence", spa);
                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            if (ds.Tables[0].Rows[0]["Status"].ToString() == "Success")
                            {
                                return Json(new { Message = "Update Sucessfully" }, JsonRequestBehavior.AllowGet);
                            }
                        }
                    }

                }

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "UpdateBranchSequence", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
        }

        public JsonResult UpdateBranchStatus(int BranchId, int IsActive)
        {
            try
            {
                SqlParameter[] spa =
                                    {
                                       new SqlParameter(){
                                       ParameterName="@BranchId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BranchId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@IsActive",
                                       SqlDbType=SqlDbType.Int,
                                       Value=IsActive
                                    }
                               };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_UpdateBranchStatus", spa);
                if (ds != null)
                {
                    if (ds.Tables.Count > 0)
                    {
                        if (ds.Tables[0].Rows.Count > 0)
                        {
                            if (ds.Tables[0].Rows[0]["Status"].ToString() == "Success")
                            {
                                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
                            }
                        }
                    }

                }

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "UpdateBranchStatus", null);
                return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
            }
            return Json(new { Message = "Error,Contact Your Manager" }, JsonRequestBehavior.AllowGet);
        }

        [HttpPost]
        public JsonResult GetItemImages(int ItemID)
        {
            try
            {
                SqlParameter[] spa = { new SqlParameter(){ ParameterName="@ItemID", SqlDbType=SqlDbType.Int, Value=ItemID } };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemImages", spa);
                if (ds != null && ds.Tables.Count > 0)
                {
                    return Json(new { Message = "Success", dtImages = JsonConvert.SerializeObject(ds.Tables[0]) }, JsonRequestBehavior.AllowGet);
                }
                return Json(new { Message = "NoData" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "GetItemImages", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }

        [HttpPost]
        public JsonResult SaveItemImages(int ItemID, List<ItemImageDto> images)
        {
            try
            {
                if (ItemID <= 0)
                    return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);

                // Replace approach: soft-delete the item's existing images, then insert the current set.
                SqlParameter[] spaDel = { new SqlParameter(){ ParameterName="@ItemID", SqlDbType=SqlDbType.Int, Value=ItemID } };
                DB.ExecuteStoredProcDataSet("sp_DeleteItemImages", spaDel);

                if (images != null)
                {
                    int seq = 1;
                    foreach (var img in images)
                    {
                        if (img == null || string.IsNullOrEmpty(img.ImageName)) continue;
                        SqlParameter[] spa = {
                            new SqlParameter(){ ParameterName="@ItemID", SqlDbType=SqlDbType.Int, Value=ItemID },
                            new SqlParameter(){ ParameterName="@ImageName", SqlDbType=SqlDbType.NVarChar, Value=img.ImageName },
                            new SqlParameter(){ ParameterName="@Seq_No", SqlDbType=SqlDbType.Int, Value=(img.Seq_No > 0 ? img.Seq_No : seq) }
                        };
                        DB.ExecuteStoredProcDataSet("sp_AddItemImage", spa);
                        seq++;
                    }
                }
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "CategoryController", "SaveItemImages", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }
    }
    public class FromCallCresultCategoryAdd
    {
        public string Message { get; set; }
        public int HID { get; set; }
    }
}


