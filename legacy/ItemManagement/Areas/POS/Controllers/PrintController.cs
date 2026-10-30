//==============================================================================
//  Areas/POS/Controllers/PrintController.cs
//------------------------------------------------------------------------------
//  Printer Settings (admin) and the print jobs the browser sends to LAN printers.
//
//  WHY THE BROWSER SENDS THE JOB
//  The application is hosted on a VPS; the printers sit on each restaurant's own
//  LAN, which the server cannot reach. So this controller only says WHAT to print
//  and WHERE (printer, IP, port, ticket data). The browser draws the ticket and
//  hands it to the small Print Agent running on a PC in the restaurant, which
//  opens the TCP connection to the printer (see PrintAgent/README.md and
//  Scripts/pos.print.js).
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Controllers\PrintController.cs" />
//==============================================================================

using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Web.Mvc;
using Jar.Helper;

namespace Jar.Areas.POS.Controllers
{
    [POSAuthorize]
    public class PrintController : Controller
    {
        // ======================================================================
        //  Printer Settings page (admin)
        // ======================================================================
        [POSAuthorize(POSPermission.ManageMasters)]
        public ActionResult Index()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }

        [HttpGet, POSAuthorize(POSPermission.ManageMasters)]
        public JsonResult Settings(int? branchId)
        {
            try
            {
                var u = POSUser.Current;
                DataSet lk = DB.ExecuteStoredProcDataSet("sp_POS_GetLookups",
                    new[] { new SqlParameter("@BrandID", SqlDbType.Int) { Value = u.BrandID > 0 ? (object)u.BrandID : DBNull.Value } });
                var branches = lk != null && lk.Tables.Count > 0 ? Rows(lk.Tables[0]) : new List<Dictionary<string, object>>();

                // the page is gated on ManageMasters, which sees every branch
                int? branch = branchId.HasValue && branches.Any(b => Convert.ToInt32(b["BranchID"]) == branchId.Value)
                    ? branchId
                    : (branches.Count > 0 ? Convert.ToInt32(branches[0]["BranchID"]) : (int?)null);
                if (!branch.HasValue) return JsonGet(new { Message = "Fail", ErrorMessage = "No branch is assigned to your user." });

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_Printer_List", new[] {
                    new SqlParameter("@BranchID", SqlDbType.Int) { Value = branch.Value },
                    new SqlParameter("@BrandID",  SqlDbType.Int) { Value = u.BrandID > 0 ? (object)u.BrandID : DBNull.Value } });

                return JsonGet(new
                {
                    Message    = "Success",
                    BranchID   = branch.Value,
                    Branches   = branches,
                    Printers   = Rows(ds.Tables[0]),
                    PrinterCats = Rows(ds.Tables[1]),
                    Categories = Rows(ds.Tables[2])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PrintController", "Settings", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "Printer settings could not be loaded. Has POS_40_Printers.sql been run?" });
            }
        }

        [HttpPost, POSAuthorize(POSPermission.ManageMasters)]
        public JsonResult Save(int? printerId, int branchId, string name, string ip, int? port, int? paperWidth,
                               bool printInvoice, bool printOrder, bool allCategories, string categoryIds, bool? active)
        {
            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_Printer_Save", new[]
                {
                    new SqlParameter("@PrinterID",     SqlDbType.Int)         { Value = printerId ?? 0 },
                    new SqlParameter("@BranchID",      SqlDbType.Int)         { Value = branchId },
                    new SqlParameter("@PrinterName",   SqlDbType.NVarChar, 100) { Value = (object)name ?? DBNull.Value },
                    new SqlParameter("@IPAddress",     SqlDbType.VarChar, 45)   { Value = (object)ip ?? DBNull.Value },
                    new SqlParameter("@Port",          SqlDbType.Int)         { Value = port ?? 9100 },
                    new SqlParameter("@PaperWidthMM",  SqlDbType.Int)         { Value = paperWidth == 58 ? 58 : 80 },
                    new SqlParameter("@PrintInvoice",  SqlDbType.Bit)         { Value = printInvoice },
                    new SqlParameter("@PrintOrder",    SqlDbType.Bit)         { Value = printOrder },
                    new SqlParameter("@AllCategories", SqlDbType.Bit)         { Value = allCategories },
                    new SqlParameter("@CategoryIDs",   SqlDbType.VarChar, -1)   { Value = (object)categoryIds ?? DBNull.Value },
                    new SqlParameter("@IsActive",      SqlDbType.Bit)         { Value = active ?? true },
                    new SqlParameter("@UserID",        SqlDbType.Int)         { Value = POSUser.Current.UserID }
                });
                DataRow r = ds.Tables[0].Rows[0];
                return JsonGet(new { Message = Convert.ToString(r["Message"]),
                                     ErrorMessage = ds.Tables[0].Columns.Contains("ErrorMessage") ? r["ErrorMessage"] as string : null });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PrintController", "Save", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The printer could not be saved." });
            }
        }

        [HttpPost, POSAuthorize(POSPermission.ManageMasters)]
        public JsonResult Delete(int printerId, int branchId)
        {
            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_Printer_Delete", new[]
                {
                    new SqlParameter("@PrinterID", SqlDbType.Int) { Value = printerId },
                    new SqlParameter("@BranchID",  SqlDbType.Int) { Value = branchId },
                    new SqlParameter("@UserID",    SqlDbType.Int) { Value = POSUser.Current.UserID }
                });
                return JsonGet(new { Message = Convert.ToString(ds.Tables[0].Rows[0]["Message"]) });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PrintController", "Delete", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The printer could not be removed." });
            }
        }

        // ======================================================================
        //  Print jobs
        // ======================================================================

        /// <summary>
        /// What to print for one invoice. kind = order (kitchen tickets, new items
        /// only unless reprint) or invoice (the bill). One job per matching printer.
        /// </summary>
        [HttpGet]
        public JsonResult Jobs(long invoiceNo, string kind, bool? reprint, string orderIds)
        {
            try
            {
                bool order = string.Equals(kind, "order", StringComparison.OrdinalIgnoreCase);
                bool re    = reprint == true;

                DataSet t = DB.ExecuteStoredProcDataSet("sp_POS_Print_Ticket", new[]
                {
                    new SqlParameter("@InvoiceNo",  SqlDbType.BigInt) { Value = invoiceNo },
                    new SqlParameter("@OnlyUnsent", SqlDbType.Bit)    { Value = order && !re },
                    new SqlParameter("@OrderIDs",   SqlDbType.VarChar, -1) { Value = string.IsNullOrWhiteSpace(orderIds) ? (object)DBNull.Value : orderIds }
                });
                if (t == null || t.Tables.Count < 3 || t.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "That order was not found." });

                DataRow h = t.Tables[0].Rows[0];
                int branch = Convert.ToInt32(h["BranchID"]);
                if (!BranchAllowed(branch))
                    return JsonGet(new { Message = "Fail", ErrorMessage = "You do not have access to that branch." });

                DataSet p = DB.ExecuteStoredProcDataSet("sp_POS_Printer_List", new[] {
                    new SqlParameter("@BranchID", SqlDbType.Int) { Value = branch },
                    new SqlParameter("@BrandID",  SqlDbType.Int) { Value = DBNull.Value } });
                var cats = new Dictionary<int, HashSet<int>>();
                foreach (DataRow r in p.Tables[1].Rows)
                {
                    int pid = Convert.ToInt32(r["PrinterID"]);
                    if (!cats.ContainsKey(pid)) cats[pid] = new HashSet<int>();
                    cats[pid].Add(Convert.ToInt32(r["CAT_NUM"]));
                }

                var lines = t.Tables[1].Rows.Cast<DataRow>().ToList();
                var printers = p.Tables[0].Rows.Cast<DataRow>()
                    .Where(r => Convert.ToBoolean(r["IsActive"]) && Convert.ToBoolean(order ? r["PrintOrder"] : r["PrintInvoice"]))
                    .ToList();

                var jobs = new List<object>();
                foreach (DataRow pr in printers)
                {
                    int pid = Convert.ToInt32(pr["PrinterID"]);
                    var mine = lines;

                    if (order && !Convert.ToBoolean(pr["AllCategories"]))
                    {
                        HashSet<int> set; cats.TryGetValue(pid, out set);
                        // an extra follows its item, so the item's category decides for both
                        var keepParents = new HashSet<long>(lines
                            .Where(l => l["ParentOrderID"] == DBNull.Value && l["CAT_NUM"] != DBNull.Value
                                        && set != null && set.Contains(Convert.ToInt32(l["CAT_NUM"])))
                            .Select(l => Convert.ToInt64(l["OrderID"])));
                        mine = lines.Where(l => l["ParentOrderID"] == DBNull.Value
                                                ? keepParents.Contains(Convert.ToInt64(l["OrderID"]))
                                                : keepParents.Contains(Convert.ToInt64(l["ParentOrderID"]))).ToList();
                    }
                    if (order && mine.Count == 0) continue;                // nothing for this printer

                    jobs.Add(new
                    {
                        PrinterID = pid,
                        Name  = Convert.ToString(pr["PrinterName"]),
                        Host  = Convert.ToString(pr["IPAddress"]),
                        Port  = Convert.ToInt32(pr["Port"]),
                        Width = Convert.ToInt32(pr["PaperWidthMM"]),
                        Kind  = order ? "order" : "invoice",
                        Ticket = new
                        {
                            Header   = Row(h),
                            Lines    = mine.Select(l => Row(l)).ToList(),
                            Payments = order ? new List<Dictionary<string, object>>() : Rows(t.Tables[2]),
                            Reprint  = re,
                            PrintedBy = POSUser.Current.UserName
                        }
                    });
                }

                // every order line that went to at least one printer
                var sent = new HashSet<long>();
                if (order)
                    foreach (var l in lines) sent.Add(Convert.ToInt64(l["OrderID"]));

                return JsonGet(new
                {
                    Message    = "Success",
                    InvoiceNo  = invoiceNo,
                    NoPrinters = printers.Count == 0,
                    Jobs       = jobs,
                    OrderIDs   = order && jobs.Count > 0 ? sent.ToList() : new List<long>()
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PrintController", "Jobs", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The print job could not be prepared. Has POS_40_Printers.sql been run?" });
            }
        }

        /// <summary>The kitchen tickets were printed: those lines are not printed again as "new".</summary>
        [HttpPost]
        public JsonResult MarkSent(long invoiceNo, string orderIds)
        {
            try
            {
                DB.ExecuteStoredProcDataSet("sp_POS_Print_MarkSent", new[]
                {
                    new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = invoiceNo },
                    new SqlParameter("@OrderIDs",  SqlDbType.VarChar, -1) { Value = (object)orderIds ?? DBNull.Value }
                });
                return JsonGet(new { Message = "Success" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PrintController", "MarkSent", null);
                return JsonGet(new { Message = "Fail" });
            }
        }

        // ======================================================================
        private static bool BranchAllowed(int branch)
        {
            var u = POSUser.Current;
            var allowed = u.BranchIDs ?? new List<int>();
            return branch <= 0 || u.CanManageMasters || allowed.Contains(branch);
        }

        private JsonResult JsonGet(object data)
        {
            return new JsonResult { Data = data, JsonRequestBehavior = JsonRequestBehavior.AllowGet, MaxJsonLength = int.MaxValue };
        }

        private static Dictionary<string, object> Row(DataRow r)
        {
            var d = new Dictionary<string, object>(r.Table.Columns.Count);
            foreach (DataColumn c in r.Table.Columns) { object v = r[c]; d[c.ColumnName] = v == DBNull.Value ? null : v; }
            return d;
        }

        private static List<Dictionary<string, object>> Rows(DataTable dt)
        {
            return dt.Rows.Cast<DataRow>().Select(Row).ToList();
        }
    }
}
