using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using Jar.Helper;
using Newtonsoft.Json;

namespace Jar.Controllers
{
    public class ItemViewDashboardController : Controller
    {
        //
        // GET: /ItemViewDashboard/

        public ActionResult Index()
        {
            return View();
        }

        public JsonResult GetAuditReportsData(int BrandId, string FromDate, string ToDate)
        {
            DateTime FromDateDt = Convert.ToDateTime(FromDate);
            DateTime ToDateDt = Convert.ToDateTime(ToDate);
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@FromDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=FromDateDt
                                    }, new SqlParameter(){
                                       ParameterName="@ToDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=ToDateDt
                                    }
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetAuditReportsData", spa);

                DataTable TopCardsDetails = ds.Tables[0];

                DataTable FirstChart = ds.Tables[1];
                DataTable SecondChart = ds.Tables[2];
                DataTable ThirdChart = ds.Tables[3];
                DataTable FourthChart = ds.Tables[4];

                string JSONString = JsonConvert.SerializeObject(TopCardsDetails);

                string JSONString1 = JsonConvert.SerializeObject(FirstChart);
                string JSONString2 = JsonConvert.SerializeObject(SecondChart);
                string JSONString3 = JsonConvert.SerializeObject(ThirdChart);
                string JSONString4 = JsonConvert.SerializeObject(FourthChart);

                return Json(new
                {
                    Message = "Success",
                    TopCardsDetails = JSONString,
                    FirstChart = JSONString1,
                    SecondChart = JSONString2,
                    ThirdChart = JSONString3,
                    FourthChart = JSONString4,
                }, JsonRequestBehavior.AllowGet);
                //return Json(new
                //{
                //    Message = "Success",
                //    ActualSales = ActualSales,
                //    TotalDiscount = TotalDiscount,
                //    TotalWaste = TotalWaste,
                //    TotalCancellation = TotalCancellation,
                //    TopBranchSales = JSONString,
                //    LastBranchSales = JSONString1,
                //    FranchiseSales = JSONString2,
                //    DiscountTypeWiseSales = JSONString3,
                //}, JsonRequestBehavior.AllowGet);

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemViewDashboardController", "GetAuditReportsData", null);

                //var Message = ex.ToString();
                //var Function = "Home/GetDashboardData";

                //SqlParameter[] spa ={
                //                       new SqlParameter(){
                //                       ParameterName="@Message",
                //                       SqlDbType=SqlDbType.NVarChar,
                //                       Value=Message
                //                    }, new SqlParameter(){
                //                       ParameterName="@Function",
                //                       SqlDbType=SqlDbType.NVarChar,
                //                       Value=Function
                //                    }
                //               };

                //var Exc = DB.ExecuteStoredProc("sp_AuditTrail", spa);
                return Json("'Fail':'true'");
            }

        }

        public JsonResult GetCategoryVisits(int BrandId, string FromDate, string ToDate)
        {
            DateTime FromDateDt = Convert.ToDateTime(FromDate);
            DateTime ToDateDt = Convert.ToDateTime(ToDate);
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@FromDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=FromDateDt
                                    }, new SqlParameter(){
                                       ParameterName="@ToDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=ToDateDt
                                    }
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCategoryVisits", spa);

                List<DashboardCategoryData> catVisits = new List<DashboardCategoryData>();
                DataTable dtDineIn = ds.Tables[0];
                if (dtDineIn.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtDineIn.Rows)
                    {
                        catVisits.Add(new DashboardCategoryData
                        {
                            CategoryName = dtRow["CAT_NAME"].ToString(),
                            Visits = Convert.ToInt32(dtRow["VisitorsCount"].ToString()),
                        });
                    }
                }
                var pagedata = new
                {
                    page = 1,
                    pages = 1,
                    perpage = -1,
                    total = catVisits.Count(),
                    sort = "desc",
                    field = "CategoryName"
                };


                //string JSONString1 = JsonConvert.SerializeObject(pagedata);
                //string JSONString2 = JsonConvert.SerializeObject(DineIn);
                var temp = Json(new
                {
                    meta = pagedata,
                    data = catVisits,
                }, JsonRequestBehavior.AllowGet);
                return temp;

                //return Json(new { data = DineIn }, JsonRequestBehavior.AllowGet);

                //var result = new { meta = pagedata, data = DineIn };
                //var str= Json(result, JsonRequestBehavior.AllowGet);
                //return str;

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemViewDashboardController", "GetCategoryVisits", null);

                return Json("'Fail':'true'");
            }
        }
        public JsonResult GetItemsVisits(int BrandId, string FromDate, string ToDate)
        {
            DateTime FromDateDt = Convert.ToDateTime(FromDate);
            DateTime ToDateDt = Convert.ToDateTime(ToDate);
            try
            {
                SqlParameter[] spa ={
                                        new SqlParameter(){
                                       ParameterName="@BrandId",
                                       SqlDbType=SqlDbType.Int,
                                       Value=BrandId
                                    },
                                       new SqlParameter(){
                                       ParameterName="@FromDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=FromDateDt
                                    }, new SqlParameter(){
                                       ParameterName="@ToDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=ToDateDt
                                    }
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetItemsVisits", spa);
                List<DashboardItemsData> ItemsVisits = new List<DashboardItemsData>();
                DataTable dtDineIn = ds.Tables[0];
                if (dtDineIn.Rows.Count > 0)
                {
                    foreach (DataRow dtRow in dtDineIn.Rows)
                    {
                        ItemsVisits.Add(new DashboardItemsData
                        {
                            ItemName = dtRow["ITEM_NAME"].ToString(),
                            CategoryName = dtRow["CAT_NAME"].ToString(),
                            Visits = Convert.ToInt32(dtRow["VisitorsCount"].ToString()),
                        });
                    }
                }
                var pagedata = new
                {
                    page = 1,
                    pages = 1,
                    perpage = -1,
                    total = ItemsVisits.Count(),
                    sort = "desc",
                    field = "InvoiceNo"
                };


                //string JSONString1 = JsonConvert.SerializeObject(pagedata);
                //string JSONString2 = JsonConvert.SerializeObject(DineIn);
                var temp = Json(new
                {
                    meta = pagedata,
                    data = ItemsVisits,
                }, JsonRequestBehavior.AllowGet);
                return temp;

                //return Json(new { data = DineIn }, JsonRequestBehavior.AllowGet);

                //var result = new { meta = pagedata, data = DineIn };
                //var str= Json(result, JsonRequestBehavior.AllowGet);
                //return str;

            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemViewDashboardController", "GetItemsVisits", null);
                return Json("'Fail':'true'");
            }
        }
    }
}
