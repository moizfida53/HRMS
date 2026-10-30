using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using Jar.Helper;

namespace Jar.Controllers
{
    public class WaiterController : Controller
    {
        //
        // GET: /Waiter/

        //public ActionResult Index(string id)
        //{
        //    if (!string.IsNullOrEmpty(id))
        //    {
        //        List<int> TagIds = id.Split(',').Select(int.Parse).ToList();
        //        if (TagIds.Count() > 0)
        //        {
        //            ViewBag.BrandId = TagIds[0];
        //            if (TagIds.Count() > 1)
        //            {
        //                ViewBag.Branchid = TagIds[1];
        //            }
        //            else
        //            {
        //                ViewBag.Branchid = 0;
        //            }
        //        }
        //    }
        //    else
        //    {
        //        ViewBag.BrandId = 0;
        //        ViewBag.Branchid = 0;
        //    }
        //    ViewBag.IsCartVisible = Convert.ToBoolean(System.Configuration.ConfigurationManager.AppSettings["IsCartVisible"]);
        //    GetBrandHomePaggeImage(ViewBag.BrandId);
        //    ViewBag.LoginUser = "Waiter";
        //    return View();
        //}

        public ActionResult Index(string name)
        {
            ViewBag.BrandId = 0;
            ViewBag.Branchid = 0;
            string brandName = "";
            string branchName = "";

            if (!string.IsNullOrEmpty(name))
            {
                string[] values = name != null ? name.Split(',') : "".Split(',');
                
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
                                               Value=0
                                            }
                                        };
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetBrandBranchDetails", spa);
            if (ds != null && ds.Tables.Count > 0)
            {
                if (ds.Tables[0].Rows.Count > 0)
                {
                    //BrandId = Convert.ToInt32(ds.Tables[0].Rows[0]["Brandid"].ToString());
                    ViewBag.BrandId = ds.Tables[0].Rows[0]["Brandid"].ToString();
                    ViewBag.Branchid = ds.Tables[0].Rows[0]["BranchId"].ToString();
                    ViewBag.BannerImage = ds.Tables[0].Rows[0]["BannerImage"].ToString();
                    ViewBag.MobileImage = ds.Tables[0].Rows[0]["MobileImage"].ToString();
                    ViewBag.DesktopImage = ds.Tables[0].Rows[0]["DesktopImage"].ToString();
                    ViewBag.BrandCssFileName = ds.Tables[0].Rows[0]["Css"].ToString();

                }
            }
            ViewBag.IsCartVisible = Convert.ToBoolean(System.Configuration.ConfigurationManager.AppSettings["IsCartVisible"]);
            GetBrandHomePaggeImage(Convert.ToInt32(ViewBag.BrandId));
            ViewBag.LoginUser = "Waiter";
            return View();
        }
        public void GetBrandHomePaggeImage(int? BrandId)
        {
            try
            {
                string ImageName = "";
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
                    CurrencyENG = ds.Tables[0].Rows[0]["Currency"].ToString();
                    CurrencyArab = ds.Tables[0].Rows[0]["CurrencyArabic"].ToString();
                    IsCartVisible = Convert.ToInt32(ds.Tables[0].Rows[0]["IsCartVisible"]);
                }
                ViewBag.BrandHomePageImage = ImageName;
                ViewBag.CurrencyENG = CurrencyENG;
                ViewBag.CurrencyArab = CurrencyArab;
                ViewBag.IsCrtVisible = IsCartVisible;
            }
            catch (Exception ex)
            {
            }
        }
    }
}
