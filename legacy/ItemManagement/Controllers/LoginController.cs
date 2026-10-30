using Jar.Helper;
using Jar.Models;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Net;
using System.Web;
using System.Web.Mvc;

namespace Jar.Controllers
{
    public class LoginController : Controller
    {
        //
        // GET: /Login/

        public ActionResult Index()
        {
            ViewBag.BrandCssFileName = "root.css";
            //if (!string.IsNullOrEmpty(name))
            //{
            try
            {
                //string[] values = name != null ? name.Split(',') : "".Split(',');
                string brandName = "";
                string branchName = "";
                //if (!string.IsNullOrEmpty(values[0]))
                //{
                //    brandName = values[0];
                //}
                //if (values.Count() > 1)
                //{
                //    if (!string.IsNullOrEmpty(values[1]))
                //    {
                //        branchName = values[1];
                //    }
                //}

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
                        //ViewBag.BrandId = ds.Tables[0].Rows[0]["Brandid"].ToString();
                        //ViewBag.Branchid = ds.Tables[0].Rows[0]["BranchId"].ToString();
                        //ViewBag.BannerImage = ds.Tables[0].Rows[0]["BannerImage"].ToString();
                        //ViewBag.MobileImage = ds.Tables[0].Rows[0]["MobileImage"].ToString();
                        //ViewBag.DesktopImage = ds.Tables[0].Rows[0]["DesktopImage"].ToString();
                        ViewBag.BrandCssFileName = ds.Tables[0].Rows[0]["Css"].ToString();

                    }
                }
            }
            catch
            {
            }
            return View();
        }

        public ActionResult LoginWaiter()
        {
            ViewBag.BrandCssFileName = "root.css";
            //if (!string.IsNullOrEmpty(name))
            //{
            try
            {
                string brandName = "";
                string branchName = "";

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
                        //ViewBag.BrandId = ds.Tables[0].Rows[0]["Brandid"].ToString();
                        //ViewBag.Branchid = ds.Tables[0].Rows[0]["BranchId"].ToString();
                        //ViewBag.BannerImage = ds.Tables[0].Rows[0]["BannerImage"].ToString();
                        //ViewBag.MobileImage = ds.Tables[0].Rows[0]["MobileImage"].ToString();
                        //ViewBag.DesktopImage = ds.Tables[0].Rows[0]["DesktopImage"].ToString();
                        ViewBag.BrandCssFileName = ds.Tables[0].Rows[0]["Css"].ToString();

                    }
                }
            }
            catch
            {
            }
            return View();
        }


        [HttpPost]
        public JsonResult GetBranchList()
        {
            try
            {
                string webServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"].ToString();
                if (!string.IsNullOrEmpty(webServiceUrl))
                {
                    //var data = new
                    //{
                    //    InvoiceNo = InoiceNumber
                    //};
                    //string inputJson = (new JavaScriptSerializer()).Serialize(data);
                    WebClient client = new WebClient();
                    client.Headers["Content-type"] = "application/json";
                    client.Encoding = System.Text.Encoding.UTF8;
                    //var jsonresult = client.UploadString(webServiceUrl + "/DmToCallCenterServices/GetInvoiceDriverStatus", inputJson);
                    var jsonresult = client.UploadString(webServiceUrl + "/DmToCallCenterServices/GetBranchList", "");

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
    }
}
