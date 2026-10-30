//==============================================================================
//  Areas/POS/Controllers/DashboardController.cs
//------------------------------------------------------------------------------
//  The reporting dashboard, and the POS landing page - the area route defaults
//  to this controller, so Index() is what a signed-in user sees first.
//
//  Ported from the Call Centre project. Four things changed and they are the
//  four that would otherwise fail at runtime rather than at build:
//
//    * namespace and auth      Jar.Areas.POS.Controllers, [POSAuthorize]
//    * error logging           DB.AuditTrail(...) instead of the sp_AuditTrail
//                              call with its own parameter list
//    * partial view paths      the originals said "ReportDashboard/..."; the
//                              views live in this Area now, so they are given
//                              as full ~/Areas/... paths. From inside an Area
//                              a bare name is resolved against the Area's own
//                              folders first, which is a good way to render
//                              the wrong file quietly.
//    * result set indexes      unchanged. sp_DashbordSalesData (POS_31) returns
//                              its tables in the order this code reads them,
//                              including the empty ones - see POS_31 for why.
//
//  @CountryId is still posted by the JS and still passed through. Every
//  procedure accepts and ignores it: there is one country here.
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Controllers\DashboardController.cs" />
//==============================================================================

using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Web.Mvc;

using Jar.Helper;
using Jar.Areas.POS.Models;
using Newtonsoft.Json;

namespace Jar.Areas.POS.Controllers
{
    [POSAuthorize]
    public class DashboardController : Controller
    {
        // Where the dashboard's own views live. Written once: a typo in one of
        // three copies is a tab that fails and two that do not.
        private const string ViewRoot = "~/Areas/POS/Views/Dashboard/";

        public ActionResult Index()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }

        [HttpPost]
        public JsonResult GetReportDashboardData(int CountryId, DateTime FromDate, DateTime ToDate,
                                                 string[] locationIDs, string[] BrandIDs, string[] orderTypeIDs,
                                                 string[] paymentTypeIDs, string[] endDates, string LateMinDuration,
                                                 string SelectedTab, int? GroupByFlag, int? ShowDefaultValueFlag,
                                                 bool IsDefaultLoad)
        {
            try
            {
                locationIDs = locationIDs != null ? locationIDs.Where(x => x != "0").ToArray() : null;
                BrandIDs    = BrandIDs    != null ? BrandIDs.Where(x => x != "0").ToArray()    : null;

                // 0 is NOT stripped from payment types: it means cash.
                endDates = endDates != null ? endDates.Where(x => x != "0").ToArray() : null;

                // A date with no time means "the whole of that day", not
                // midnight - otherwise today's orders are all after the range.
                if (ToDate.Hour == 0 && ToDate.Minute == 0 && ToDate.Second == 0)
                    ToDate = ToDate.Date + new TimeSpan(23, 59, 59);

                // Confined to this user's assigned branches, unless they have
                // CanManageMasters - see POSBranchScope. BrandIDs (a chain-
                // level concept, unrelated to branch access) is untouched.
                string requestedBranchCsv = locationIDs != null && locationIDs.Length > 0 ? string.Join(",", locationIDs) : null;
                string effectiveBranchCsv = POSBranchScope.ResolveCsv(POSUser.Current, requestedBranchCsv);

                SqlParameter[] spa =
                {
                    new SqlParameter("@CountryId",       SqlDbType.Int)             { Value = CountryId },
                    new SqlParameter("@FromDate",        SqlDbType.DateTime)        { Value = FromDate },
                    new SqlParameter("@ToDate",          SqlDbType.DateTime)        { Value = ToDate },
                    new SqlParameter("@BranchIds",       SqlDbType.NVarChar, 1000)  { Value = (object)effectiveBranchCsv ?? DBNull.Value },
                    new SqlParameter("@BrandIds",        SqlDbType.NVarChar, 1000)  { Value = Csv(BrandIDs) },
                    new SqlParameter("@InvoiceTypeIds",  SqlDbType.NVarChar, 1000)  { Value = Csv(orderTypeIDs) },
                    new SqlParameter("@PaymentTypeIds",  SqlDbType.NVarChar, 1000)  { Value = Csv(paymentTypeIDs) },
                    new SqlParameter("@GroupByFlag",     SqlDbType.Int)             { Value = GroupByFlag ?? 1 },
                    new SqlParameter("@EndDates",        SqlDbType.NVarChar, 4000)  { Value = Csv(endDates) },
                    new SqlParameter("@LateMinDuration", SqlDbType.Int)
                        { Value = string.IsNullOrEmpty(LateMinDuration) ? 70 : Convert.ToInt32(LateMinDuration) },
                    new SqlParameter("@IsDefaultLoad",   SqlDbType.Bit)             { Value = IsDefaultLoad }
                };

                switch (SelectedTab)
                {
                    case "sales-tab-md":            return SalesTab(spa, GroupByFlag, ShowDefaultValueFlag);
                    case "SalesDetailsView":        return SalesDetails(spa, ShowDefaultValueFlag);
                    case "HoursWiseSalesDataView":  return HoursWise(spa, GroupByFlag);
                    case "PaymentTypeDetails":      return OneGrid("sp_DashbordPaymentTypesData", spa);
                    case "LateOrderDetails":        return OneGrid("sp_GetDashboardLateOrdersData", spa, "dtLateOrdersSummaryData");
                    case "TopItemsDetails":         return OneGrid("sp_GetDashboardTopItemsSummaryData", spa, "dtTopItemsSummaryData");
                    case "DiscountWiseItems":       return OneGrid("sp_DashbordDiscountWiseItemsData", spa);
                    case "DeletedReUseWiseItems":   return OneGrid("sp_DashbordDeletedReUseWiseItemsData", spa);
                    case "DeletedWasteWiseItems":   return OneGrid("sp_DashbordDeletedWasteWiseItemsData", spa);
                }

                return JsonBig(new { Message = "NoData" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DashboardController", "GetReportDashboardData", null);
                return JsonBig(new { Message = "Fail" });
            }
        }

        // ---------------------------------------------------------------- tabs

        /// <summary>
        /// The landing tab. Reads sp_DashbordSalesData BY INDEX - the procedure
        /// returns empty tables at 8, 11 and 13 for exactly this reason.
        /// </summary>
        private JsonResult SalesTab(SqlParameter[] spa, int? groupBy, int? showDefault)
        {
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_DashbordSalesData", spa);
            if (ds == null || ds.Tables.Count < 16) return JsonBig(new { Message = "NoData" });

            var hourly = ds.Tables[9].AsEnumerable()
                .GroupBy(r => r.Field<string>("Name"))
                .Select(t => new
                {
                    name = t.Key,
                    data = t.ToList().ToDictionary(
                        x => x.Field<string>("HoursBreak"),
                        x => showDefault == 2 ? (decimal)x.Field<int>("TotalCount")
                                              : x.Field<decimal>("TotalSales"))
                })
                .OrderBy(c => c.name)
                .ToList();

            return JsonBig(new
            {
                Message             = "Success",
                dtTotalSales        = JsonConvert.SerializeObject(ds.Tables[0]),
                dtTotalDiscount     = JsonConvert.SerializeObject(ds.Tables[1]),
                dtPaymentTypes      = JsonConvert.SerializeObject(ds.Tables[2]),
                dtOrderTypes        = JsonConvert.SerializeObject(ds.Tables[5]),
                dtCancellationReUse = JsonConvert.SerializeObject(ds.Tables[6]),
                dtCancellationWaste = JsonConvert.SerializeObject(ds.Tables[7]),
                dtTopItems          = JsonConvert.SerializeObject(ds.Tables[10]),
                dtBranchSales       = JsonConvert.SerializeObject(ds.Tables[12]),
                dtLateOrders        = JsonConvert.SerializeObject(ds.Tables[14]),
                dtCountryData       = JsonConvert.SerializeObject(ds.Tables[15]),
                hourlyWiseSalesData = hourly,
                GroupByFlag         = groupBy ?? 1
            });
        }

        private JsonResult SalesDetails(SqlParameter[] spa, int? showDefault)
        {
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_DashbordSalesData", spa);
            if (ds == null || ds.Tables.Count < 5) return JsonBig(new { Message = "NoData" });

            var line = ds.Tables[3].AsEnumerable()
                .GroupBy(r => r.Field<string>("BranchName"))
                .Select(t => new
                {
                    name = t.Key,
                    data = t.ToList().ToDictionary(
                        x => x.Field<DateTime>("InvoiceDate").ToString("MM-dd-yyyy HH:mm:ss:F"),
                        x => showDefault == 2 ? (decimal)x.Field<int>("TotalCount")
                                              : x.Field<decimal>("NetTotal"))
                })
                .ToList();

            var pivot = ds.Tables[4].AsEnumerable().Select(r => new PivotTotalSalesData
            {
                BranchName       = Convert.ToString(r["BranchName"]),
                OrderSales       = Convert.ToString(r["keyName"]),
                OrderSalesValues = r["KeyValue"] == DBNull.Value ? 0m : Convert.ToDecimal(r["KeyValue"]),
                InvoiceDate      = Convert.ToString(r["InvoiceDate"])
            }).ToList();

            return JsonBig(new
            {
                Message = "Success",
                totalSalesLineChartData = line,
                view = RenderHelper.PartialView(this, ViewRoot + "SalesReportDetailsView.cshtml", pivot)
            });
        }

        private JsonResult HoursWise(SqlParameter[] spa, int? groupBy)
        {
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_DashbordSalesData", spa);
            if (ds == null || ds.Tables.Count < 10) return JsonBig(new { Message = "NoData" });

            var hourly = ds.Tables[9].AsEnumerable()
                .GroupBy(r => r.Field<string>("Name"))
                .Select(t => new
                {
                    name = t.Key,
                    data = t.ToList().ToDictionary(x => x.Field<string>("HoursBreak"),
                                                   x => x.Field<decimal>("TotalSales"))
                })
                .ToList();

            return JsonBig(new
            {
                Message = "Success",
                hourlyWiseSalesData = hourly,
                GroupByFlag = groupBy ?? 1,
                view = RenderHelper.PartialView(this, ViewRoot + "HoursWiseSalesDataView.cshtml", null)
            });
        }

        /// <summary>
        /// The drill-down tabs are all the same shape: one procedure, one
        /// table, rendered into a DataTable by whatever columns come back. The
        /// JS reads two different property names depending on the tab, so the
        /// caller says which one it wants.
        /// </summary>
        private JsonResult OneGrid(string proc, SqlParameter[] spa, string property = "dtPaymentTypesSummaryData")
        {
            DataSet ds = DB.ExecuteStoredProcDataSet(proc, spa);
            if (ds == null || ds.Tables.Count == 0) return JsonBig(new { Message = "NoData" });

            string json = JsonConvert.SerializeObject(ds.Tables[0]);
            var payload = new Dictionary<string, object>
            {
                { "Message", "Success" },
                { property, json }
            };

            return JsonBig(payload);
        }

        // ------------------------------------------------------------- filters

        public JsonResult GetFilter(int CountryId)
        {
            try
            {
                SqlParameter[] spa = { new SqlParameter("@CountryId", SqlDbType.Int) { Value = CountryId } };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_DashboardFilter", spa);

                if (ds == null || ds.Tables.Count < 4)
                    return JsonBig(new { Message = "NoData" });

                // Presentation only - GetReportDashboardData above is what
                // actually enforces this. Trimming the dropdown too just
                // keeps a restricted user from seeing branch NAMES they
                // cannot pull any report data for. sp_DashboardFilter's
                // branch result set uses generic val/txt columns (val = the
                // branch id).
                DataTable dtBranch = ds.Tables[0];
                var du = POSUser.Current;
                if (du != null && !du.CanManageMasters)
                {
                    var allowed = du.BranchIDs ?? new List<int>();
                    var filteredRows = dtBranch.AsEnumerable()
                        .Where(row => row["val"] != DBNull.Value && allowed.Contains(Convert.ToInt32(row["val"])));
                    dtBranch = filteredRows.Any() ? filteredRows.CopyToDataTable() : dtBranch.Clone();
                }

                return JsonBig(new
                {
                    Message       = "Success",
                    dtBranch      = JsonConvert.SerializeObject(dtBranch),
                    dtInvoiceType = JsonConvert.SerializeObject(ds.Tables[1]),
                    dtPaymentType = JsonConvert.SerializeObject(ds.Tables[2]),
                    dtBrand       = JsonConvert.SerializeObject(ds.Tables[3])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DashboardController", "GetFilter", null);
                return JsonBig(new { Message = "Fail" });
            }
        }

        public JsonResult GetEndDates(int CountryId, DateTime FromDate, DateTime ToDate)
        {
            try
            {
                if (ToDate.Hour == 0 && ToDate.Minute == 0 && ToDate.Second == 0)
                    ToDate = ToDate.Date + new TimeSpan(23, 59, 59);

                SqlParameter[] spa =
                {
                    new SqlParameter("@CountryId", SqlDbType.Int)      { Value = CountryId },
                    new SqlParameter("@FromDate",  SqlDbType.DateTime) { Value = FromDate },
                    new SqlParameter("@ToDate",    SqlDbType.DateTime) { Value = ToDate }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetEndDatesForRptDashboard", spa);
                var list = new List<tmpclsEndDate>();

                if (ds != null && ds.Tables.Count > 0)
                {
                    foreach (DataRow r in ds.Tables[0].Rows)
                    {
                        list.Add(new tmpclsEndDate
                        {
                            StartDateName         = Convert.ToString(r["StartDateName"]),
                            // Formatted here, and invariant: this string is
                            // handed straight back to SQL as a date.
                            EndDateForValProperty = Convert.ToDateTime(r["StartDate"])
                                                    .ToString("yyyy-MM-dd",
                                                        System.Globalization.CultureInfo.InvariantCulture)
                        });
                    }
                }

                return JsonBig(new { dtEndDate = list });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DashboardController", "GetEndDates", null);
                return JsonBig(new { Message = "Error,Contact Your Manager" });
            }
        }

        // ------------------------------------------------------------- helpers

        private static object Csv(string[] values)
        {
            return (values == null || values.Length == 0)
                 ? (object)DBNull.Value
                 : string.Join(",", values);
        }

        /// <summary>
        /// A day of orders across every branch comfortably exceeds the default
        /// 4 MB JSON ceiling, and the failure is an exception on the way out
        /// rather than a truncated response, so every action returns this.
        /// </summary>
        private JsonResult JsonBig(object data)
        {
            var r = Json(data, JsonRequestBehavior.AllowGet);
            r.MaxJsonLength = int.MaxValue;
            return r;
        }
    }
}
