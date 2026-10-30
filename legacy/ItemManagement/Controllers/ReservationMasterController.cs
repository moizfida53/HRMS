using Jar.Helper;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace Jar.Controllers
{
    public class ReservationMasterController : Controller
    {
        //
        // GET: /ReservationMaster/

        public ActionResult Index()
        {
            return View();
        }

        [HttpPost]
        public JsonResult GetDataList()
        {
            try
            {

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetReservationMasterData");
                DataTable dt = new DataTable();
                DataTable dt1 = new DataTable();
                if (ds.Tables.Count > 0)
                {
                    dt = ds.Tables[0];
                }

                if (ds.Tables.Count > 1)
                {
                    dt1 = ds.Tables[1];
                }
                string TablejsonData = JsonConvert.SerializeObject(dt);
                string TimeSlotjsonData = JsonConvert.SerializeObject(dt1);
                return Json(new { Message = "Success", dtTableresult = TablejsonData, dtTimeSlotresult = TimeSlotjsonData }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json("'Fail':'true'");
            }
        }
        public JsonResult ArrangeTable(Arrange value)
        {
            try
            {
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@TableStructureID",
                                        SqlDbType=SqlDbType.Int,
                                        Value=value.TableID
                                        },
                                        new SqlParameter(){
                                        ParameterName="@Xaxis",
                                        SqlDbType=SqlDbType.Decimal,
                                        Value=value.X
                                        },
                                        new SqlParameter(){
                                        ParameterName="@Yaxis",
                                        SqlDbType=SqlDbType.Decimal,
                                        Value=value.Y
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_ArrangeTable", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult AddEditTable(TableReservationData value)
        {
            try
            {
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@TableStructureID",
                                        SqlDbType=SqlDbType.Int,
                                        Value=value.id
                                        },
                                        new SqlParameter(){
                                        ParameterName="@TableName",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=value.TableName
                                        },
                                        new SqlParameter(){
                                        ParameterName="@DiningArea",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=value.DiningArea
                                        },
                                        new SqlParameter(){
                                        ParameterName="@Seating",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=value.Seating
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AddEditReservationTableStructure", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Fail", alert=ex.Message }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult DeleteTable(TableReservationData value)
        {
            try
            {
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@TableStructureID",
                                        SqlDbType=SqlDbType.Int,
                                        Value=value.id
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_DeleteReservationTableStructure", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Fail", alert = ex.Message }, JsonRequestBehavior.AllowGet);
            }

        }

        public JsonResult AddEditTimeSlot(ReservationSlot value)
        {
            try
            {
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@id",
                                        SqlDbType=SqlDbType.Int,
                                        Value=value.id
                                        },
                                        new SqlParameter(){
                                        ParameterName="@slotName",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=value.slotName
                                        },
                                        new SqlParameter(){
                                        ParameterName="@slotNameArabic",
                                        SqlDbType=SqlDbType.NVarChar,
                                        Value=value.slotNameArabic
                                        },
                                        new SqlParameter(){
                                        ParameterName="@fromTime",
                                        SqlDbType=SqlDbType.Time,
                                        Value=value.fromTime
                                        },
                                        new SqlParameter(){
                                        ParameterName="@toTime",
                                        SqlDbType=SqlDbType.Time,
                                        Value=value.toTime
                                        }
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_AddEditReservationSlot", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Fail", alert = ex.Message }, JsonRequestBehavior.AllowGet);
            }

        }
        public JsonResult DeleteTimeSlot(ReservationSlot value)
        {
            try
            {
                SqlParameter[] spa1 ={
                                        new SqlParameter(){
                                        ParameterName="@id",
                                        SqlDbType=SqlDbType.Int,
                                        Value=value.id
                                        },
                                    };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_DeleteReservationSlot", spa1);
                return Json(new { Message = "Success" }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                return Json(new { Message = "Fail", alert = ex.Message }, JsonRequestBehavior.AllowGet);
            }

        }
    }
    public class TableReservationData
    {
        public int id { get; set; }
        public string TableName { get; set; }
        public string DiningArea { get; set; }
        public int Seating { get; set; }
        public decimal Xaxis { get; set; }
        public decimal Yaxis { get; set; }
    }
    public class Arrange
    {
        public int TableID { get; set; }
        public decimal X { get; set; }
        public decimal Y { get; set; }
    }

    public class ReservationSlot
    {
        public int id { get; set; }
        public string slotName { get; set; }
        public string slotNameArabic { get; set; }
        public TimeSpan fromTime { get; set; }
        public TimeSpan toTime { get; set; }
    }
}
