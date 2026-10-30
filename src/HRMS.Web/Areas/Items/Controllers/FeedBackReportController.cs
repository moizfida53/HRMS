#nullable disable
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Linq;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
namespace HRMS.Web.Areas.Items.Controllers
{
    public class FeedBackReportController : LegacyController
    {
        //
        // GET: /Home/

        public ActionResult Index()
        {
            return View();
        }
        public JsonResult GetDashboardData(DateTime FromDate, DateTime ToDate)
        {
            try
            {
                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@FromDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=FromDate
                                    }, new SqlParameter(){
                                       ParameterName="@ToDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=ToDate
                                    }
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetDashboardData", spa);

                //string ActualSales = ds.Tables[0].Rows[0][0].ToString();
                //string TotalDiscount = ds.Tables[1].Rows[0][0].ToString();
                //string TotalWaste = ds.Tables[2].Rows[0][0].ToString();
                //string TotalCancellation = ds.Tables[3].Rows[0][0].ToString();

                DataTable FirstChart = ds.Tables[0];
                DataTable SecondChart = ds.Tables[1];
                DataTable ThirdChart = ds.Tables[2];
                DataTable FourthDataGrid = ds.Tables[3];
                string JSONString = JsonConvert.SerializeObject(FirstChart);
                string JSONString1 = JsonConvert.SerializeObject(SecondChart);
                string JSONString2 = JsonConvert.SerializeObject(ThirdChart);
                string JSONString3 = JsonConvert.SerializeObject(FourthDataGrid);

                return Json(new
                {
                    Message = "Success",
                    FirstChart = JSONString,
                    SecondChart = JSONString1,
                    ThirdChart = JSONString2,
                    FourthDataGrid = JSONString3,
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
                DB.AuditTrail(ex, "FeedBackReportController", "GetDashboardData", null);
                return Json("'Fail':'true'");
            }
            
        }
       
        public JsonResult GetFeedbackDetailsData(DateTime FromDate, DateTime ToDate,string QuestionId, string Response)
        {
            try
            {
                SqlParameter[] spa ={
                                       new SqlParameter(){
                                       ParameterName="@FromDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=FromDate
                                    }, new SqlParameter(){
                                       ParameterName="@ToDate",
                                       SqlDbType=SqlDbType.Date,
                                       Value=ToDate
                                    }
                                    , new SqlParameter(){
                                       ParameterName="@QuestionId",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=QuestionId
                                    }
                                    , new SqlParameter(){
                                       ParameterName="@Response",
                                       SqlDbType=SqlDbType.NVarChar,
                                       Value=Response
                                    }
                               };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetFeedbackDetailsData", spa);

                //string ActualSales = ds.Tables[0].Rows[0][0].ToString();
                //string TotalDiscount = ds.Tables[1].Rows[0][0].ToString();
                //string TotalWaste = ds.Tables[2].Rows[0][0].ToString();
                //string TotalCancellation = ds.Tables[3].Rows[0][0].ToString();

                DataTable dt = ds.Tables[0];
                string JSONString = JsonConvert.SerializeObject(dt);
                return Json(new
                {
                    Message = "Success",
                    GridData = JSONString,
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
                DB.AuditTrail(ex, "FeedBackReportController", "GetFeedbackDetailsData", null);

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

    }
}
