#nullable disable
//==============================================================================
//  Areas/POS/Controllers/OrdersController.cs   (v2)
//------------------------------------------------------------------------------
//  Order List: grid, facet counts, delta poll, details.
//==============================================================================

using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Linq;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
using Newtonsoft.Json;

namespace HRMS.Web.Areas.POS.Controllers
{
    [POSAuthorize]
    public class OrdersController : PosController
    {
        public ActionResult Index()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }

        /// <summary>Counter order entry. Placeholder screen for now.</summary>
        public ActionResult Place()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }

        /// <summary>
        /// Printable document for one order.
        ///
        /// Rendered server-side and told to print itself on load, so the
        /// operator gets the browser's printer chooser (or their default
        /// printer with one Enter). Nothing is fetched by AJAX here: a print
        /// window that has to wait for a round trip can fire window.print()
        /// against a half-built page.
        ///
        /// doc  = Thermal | A4 | Kitchen
        /// lang = en | ar   (ar switches the whole document to RTL)
        /// </summary>
        [HttpGet]
        public ActionResult Print(long id, string doc = "Thermal", string lang = "en")
        {
            try
            {
                SqlParameter[] spa = { new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = id } };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderDetails", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return NotFound("Order not found.");

                // Count the print BEFORE rendering, so the REPRINT stamp on the
                // paper reflects the copy actually coming out of the printer.
                // A kitchen ticket that can be reprinted silently is a standard
                // route to duplicate-order fraud.
                int printCount = MarkPrinted(id, doc);

                ViewBag.Doc        = doc;
                ViewBag.Lang       = (lang ?? "en").ToLowerInvariant() == "ar" ? "ar" : "en";
                ViewBag.PrintCount = printCount;
                // Printed By line on the receipt: who pressed the button.
                ViewBag.PrintedBy  = POSUser.Current != null ? POSUser.Current.UserName : "";
                ViewBag.Header     = ds.Tables[0].Rows[0];
                ViewBag.Lines      = ds.Tables.Count > 1 ? ds.Tables[1] : null;
                ViewBag.Payments   = ds.Tables.Count > 3 ? ds.Tables[3] : null;

                return View("Print");
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "Print", null);
                return StatusCode(500, "Could not build the document.");
            }
        }

        /// <summary>
        /// Increments PrintCount / LastPrintedOn via sp_POS_MarkPrinted and
        /// returns the new count. A failure here must not stop the operator
        /// printing, so it is logged and swallowed.
        /// </summary>
        private int MarkPrinted(long invoiceNo, string doc)
        {
            try
            {
                var dt = new DataTable();
                dt.Columns.Add("Value", typeof(long));
                dt.Rows.Add(invoiceNo);

                var u = POSUser.Current;
                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNos", SqlDbType.Structured)
                        { TypeName = "dbo.TVP_POS_BigIntList", Value = dt },
                    new SqlParameter("@DocType",  SqlDbType.VarChar, 20)  { Value = doc ?? "Invoice" },
                    new SqlParameter("@UserID",   SqlDbType.Int)          { Value = u != null ? (object)u.UserID : DBNull.Value },
                    new SqlParameter("@UserName", SqlDbType.NVarChar, 100){ Value = u != null ? (object)u.UserName : DBNull.Value }
                };

                DataSet r = DB.ExecuteStoredProcDataSet("sp_POS_MarkPrinted", spa);
                if (r != null && r.Tables.Count > 0 && r.Tables[0].Rows.Count > 0)
                    return Convert.ToInt32(r.Tables[0].Rows[0]["PrintCount"]);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "MarkPrinted", null);
            }
            return 1;
        }

        /// <summary>
        /// Moves an order to another branch. Wraps sp_POS_TransferOrder, which
        /// also moves the line rows - every branch-level item report reads
        /// BranchID from tblOrder, not from the header.
        /// </summary>
        [HttpPost]
        public JsonResult ChangeBranch(long invoiceNo, int branchId, string reason)
        {
            try
            {
                var u = POSUser.Current;
                if (u == null)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Your session has expired. Sign in again." });

                if (branchId <= 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Select a branch." });

                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNo",  SqlDbType.BigInt)        { Value = invoiceNo },
                    new SqlParameter("@ToBranchID", SqlDbType.Int)           { Value = branchId },
                    new SqlParameter("@Reason",     SqlDbType.NVarChar, 500) { Value = string.IsNullOrWhiteSpace(reason) ? (object)DBNull.Value : reason.Trim() },
                    new SqlParameter("@UserID",     SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",   SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_TransferOrder", spa);
                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The branch could not be changed." });

                DataRow r = ds.Tables[0].Rows[0];
                if (Convert.ToString(r["Message"]) != "Success")
                    return JsonGet(new { Message = "Fail", ErrorMessage = Convert.ToString(r["ErrorMessage"]) });

                return JsonGet(new
                {
                    Message = "Success",
                    Warning = r["Warning"] == DBNull.Value ? null : Convert.ToString(r["Warning"])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "ChangeBranch", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The branch could not be changed." });
            }
        }

        /// <summary>
        /// Moves one order to another status.
        ///
        /// sp_POS_ChangeStatus is bulk and returns the orders it REFUSED in a
        /// second result set with a reason each. With one order that reason is
        /// the whole answer, so it is lifted out and returned as the error
        /// rather than reporting a bare "0 updated".
        /// </summary>
        [HttpPost]
        public JsonResult ChangeStatus(long invoiceNo, int statusId, int? driverId, string comment)
        {
            try
            {
                var u = POSUser.Current;
                if (u == null)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Your session has expired. Sign in again." });

                if (!u.CanChangeStatus)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "You do not have permission to change the status." });

                var dt = new DataTable();
                dt.Columns.Add("Value", typeof(long));
                dt.Rows.Add(invoiceNo);

                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNos", SqlDbType.Structured)     { TypeName = "dbo.TVP_POS_BigIntList", Value = dt },
                    new SqlParameter("@ToStatusID", SqlDbType.Int)            { Value = statusId },
                    new SqlParameter("@UserID",     SqlDbType.Int)            { Value = u.UserID },
                    new SqlParameter("@UserName",   SqlDbType.NVarChar, 100)  { Value = (object)u.UserName ?? DBNull.Value },
                    new SqlParameter("@RoleID",     SqlDbType.Int)            { Value = u.RoleID },
                    new SqlParameter("@Comments",   SqlDbType.NVarChar, 1000) { Value = string.IsNullOrWhiteSpace(comment) ? (object)DBNull.Value : comment.Trim() },
                    new SqlParameter("@DriverID",   SqlDbType.Int)            { Value = driverId.HasValue ? (object)driverId.Value : DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_ChangeStatus", spa);
                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The status could not be changed." });

                DataRow r = ds.Tables[0].Rows[0];
                if (Convert.ToString(r["Message"]) == "Success")
                    return JsonGet(new { Message = "Success", OrderStatusID = statusId });

                string why = Convert.ToString(r["ErrorMessage"]);
                if (string.IsNullOrEmpty(why) && ds.Tables.Count > 1 && ds.Tables[1].Rows.Count > 0)
                    why = Convert.ToString(ds.Tables[1].Rows[0]["Reason"]);

                return JsonGet(new { Message = "Fail", ErrorMessage = string.IsNullOrEmpty(why) ? "That status change is not allowed." : why });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "ChangeStatus", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The status could not be changed." });
            }
        }

        /// <summary>
        /// Converts a delivery into a collection: invoice type 3, order type
        /// Pickup, the collecting branch, and no delivery charge. See
        /// POS_30_ChangeToPickup.sql for why those four move together.
        /// </summary>
        [HttpPost]
        public JsonResult ChangeToPickup(long invoiceNo, int branchId, int invoiceType = 3)
        {
            try
            {
                var u = POSUser.Current;
                if (u == null)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Your session has expired. Sign in again." });

                if (branchId <= 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Select the branch the customer is collecting from." });

                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNo",   SqlDbType.BigInt)       { Value = invoiceNo },
                    new SqlParameter("@BranchID",    SqlDbType.Int)          { Value = branchId },
                    new SqlParameter("@InvoiceType", SqlDbType.Int)          { Value = invoiceType },
                    new SqlParameter("@UserID",      SqlDbType.Int)          { Value = u.UserID },
                    new SqlParameter("@UserName",    SqlDbType.NVarChar,100) { Value = (object)u.UserName ?? DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_ChangeToPickup", spa);
                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The order could not be changed to pickup." });

                DataRow r = ds.Tables[0].Rows[0];
                if (Convert.ToString(r["Message"]) != "Success")
                    return JsonGet(new { Message = "Fail", ErrorMessage = Convert.ToString(r["ErrorMessage"]) });

                return JsonGet(new
                {
                    Message    = "Success",
                    NetPayable = r["NetPayable"] == DBNull.Value ? 0m : Convert.ToDecimal(r["NetPayable"]),
                    Warning    = r["Warning"] == DBNull.Value ? null : Convert.ToString(r["Warning"])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "ChangeToPickup", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The order could not be changed to pickup." });
            }
        }

        /// <summary>
        /// Voids one line off an order and re-totals the invoice.
        ///
        /// Authorised the same way as a cancellation: waste or reuse, a
        /// comment, and a RoleID = 1 user's delete password. The password is
        /// what authorises it, so this is gated on being signed in rather than
        /// on the cashier's own permissions.
        ///
        /// disposition: 1 = Waste, 2 = Reuse.
        /// </summary>
        [HttpPost]
        public JsonResult DeleteLine(long invoiceNo, long orderId, int disposition,
                                     string comment, string password)
        {
            try
            {
                var u = POSUser.Current;
                if (u == null)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Your session has expired. Sign in again." });

                if (disposition != 1 && disposition != 2)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Select Waste or Reuse." });

                if (string.IsNullOrWhiteSpace(comment))
                    return JsonGet(new { Message = "Fail", ErrorMessage = "A delete comment is required." });

                if (string.IsNullOrWhiteSpace(password))
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The manager password is required." });

                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNo",   SqlDbType.BigInt)        { Value = invoiceNo },
                    new SqlParameter("@OrderID",     SqlDbType.BigInt)        { Value = orderId },
                    new SqlParameter("@Disposition", SqlDbType.TinyInt)       { Value = disposition },
                    new SqlParameter("@Comments",    SqlDbType.NVarChar, 500) { Value = comment.Trim() },
                    new SqlParameter("@Password",    SqlDbType.NVarChar, 100) { Value = password },
                    new SqlParameter("@UserID",      SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",    SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_DeleteOrderLine", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The item could not be deleted." });

                DataRow r = ds.Tables[0].Rows[0];
                if (Convert.ToString(r["Message"]) != "Success")
                    return JsonGet(new { Message = "Fail", ErrorMessage = Convert.ToString(r["ErrorMessage"]) });

                return JsonGet(new
                {
                    Message      = "Success",
                    InvoiceNo    = invoiceNo,
                    OrderID      = orderId,
                    LinesDeleted = r["LinesDeleted"] == DBNull.Value ? 0  : Convert.ToInt32(r["LinesDeleted"]),
                    NetPayable   = r["NetPayable"]   == DBNull.Value ? 0m : Convert.ToDecimal(r["NetPayable"]),
                    // Not an error - the void succeeded - but the operator has
                    // something to do about it, so it is carried back rather
                    // than left in the audit log.
                    Warning      = r.Table.Columns.Contains("Warning") && r["Warning"] != DBNull.Value
                                   ? Convert.ToString(r["Warning"]) : null
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "DeleteLine", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The item could not be deleted." });
            }
        }

        /// <summary>
        /// Settles an order across one or more payment types.
        ///
        /// The amounts posted are what was TENDERED. Working out how much of
        /// that is payment and how much is change is the procedure's job, not
        /// the browser's - the figure on screen is a courtesy, and a tab that
        /// has been open since before a part-payment would compute it against a
        /// stale balance.
        ///
        /// lines is JSON: [{"TypeID":1,"Amount":10.5},{"TypeID":2,"Amount":5}]
        /// </summary>
        [HttpPost]
        public JsonResult TakePayment(long invoiceNo, string lines, string reference)
        {
            try
            {
                var u = POSUser.Current;
                if (u == null)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Your session has expired. Sign in again." });

                if (!u.CanTakePayment)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "You do not have permission to take payment." });

                List<PaymentLineInput> parsed;
                try
                {
                    parsed = JsonConvert.DeserializeObject<List<PaymentLineInput>>(lines ?? "[]");
                }
                catch
                {
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The payment lines could not be read." });
                }

                var dt = new DataTable();
                dt.Columns.Add("PaymentTypeID", typeof(int));
                dt.Columns.Add("Amount", typeof(decimal));

                if (parsed != null)
                {
                    // Zero and blank boxes are dropped here rather than sent as
                    // rows: the TVP is keyed on PaymentTypeID, so a duplicate
                    // or an empty line would be a primary key violation rather
                    // than a message the operator can act on.
                    foreach (var l in parsed)
                    {
                        if (l == null || l.Amount <= 0) continue;
                        if (dt.Select("PaymentTypeID = " + l.TypeID).Length > 0) continue;
                        dt.Rows.Add(l.TypeID, decimal.Round(l.Amount, 3));
                    }
                }

                if (dt.Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Enter an amount against at least one payment type." });

                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNo",   SqlDbType.BigInt)       { Value = invoiceNo },
                    new SqlParameter("@Lines",       SqlDbType.Structured)   { TypeName = "dbo.TVP_POS_PaymentLine", Value = dt },
                    new SqlParameter("@ReferenceNo", SqlDbType.NVarChar,100) { Value = string.IsNullOrWhiteSpace(reference) ? (object)DBNull.Value : reference.Trim() },
                    new SqlParameter("@UserID",      SqlDbType.Int)          { Value = u.UserID },
                    new SqlParameter("@UserName",    SqlDbType.NVarChar,100) { Value = (object)u.UserName ?? DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_TakePaymentSplit", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The payment could not be recorded." });

                DataRow r = ds.Tables[0].Rows[0];
                if (Convert.ToString(r["Message"]) != "Success")
                    return JsonGet(new { Message = "Fail", ErrorMessage = Convert.ToString(r["ErrorMessage"]) });

                return JsonGet(new
                {
                    Message       = "Success",
                    InvoiceNo     = invoiceNo,
                    AmountPaid    = r["AmountPaid"]    == DBNull.Value ? 0m : Convert.ToDecimal(r["AmountPaid"]),
                    AmountDue     = r["AmountDue"]     == DBNull.Value ? 0m : Convert.ToDecimal(r["AmountDue"]),
                    ChangeGiven   = r["ChangeGiven"]   == DBNull.Value ? 0m : Convert.ToDecimal(r["ChangeGiven"]),
                    PaymentStatus = Convert.ToString(r["PaymentStatus"])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "TakePayment", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The payment could not be recorded." });
            }
        }

        /// <summary>
        /// Cancels an order from the Order List.
        ///
        /// Two things are required and both are checked in SQL: a reason, and
        /// the delete password of a RoleID = 1 user. The password is the
        /// authorisation - a cashier without the cancel permission can still
        /// run this when a manager types their password - so this is NOT gated
        /// on POSUser.CanCancel. It IS gated on being logged in at all.
        ///
        /// The password is never logged, echoed back, or put in the audit
        /// detail; only the ID of the user it matched is recorded.
        /// </summary>
        [HttpPost]
        public JsonResult Cancel(long invoiceNo, string comment, string password)
        {
            try
            {
                var u = POSUser.Current;
                if (u == null)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "Your session has expired. Sign in again." });

                if (string.IsNullOrWhiteSpace(comment))
                    return JsonGet(new { Message = "Fail", ErrorMessage = "A reason is required." });

                if (string.IsNullOrWhiteSpace(password))
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The manager password is required." });

                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNo", SqlDbType.BigInt)        { Value = invoiceNo },
                    new SqlParameter("@Comments",  SqlDbType.NVarChar, 500) { Value = comment.Trim() },
                    new SqlParameter("@Password",  SqlDbType.NVarChar, 100) { Value = password },
                    new SqlParameter("@UserID",    SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",  SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_CancelOrderReject", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", ErrorMessage = "The cancellation could not be recorded." });

                DataRow r = ds.Tables[0].Rows[0];
                string msg = Convert.ToString(r["Message"]);

                if (msg != "Success")
                    return JsonGet(new { Message = "Fail", ErrorMessage = Convert.ToString(r["ErrorMessage"]) });

                return JsonGet(new
                {
                    Message       = "Success",
                    InvoiceNo     = invoiceNo,
                    OrderStatusID = 6,
                    ApprovedBy    = r.Table.Columns.Contains("ApprovedBy") ? Convert.ToString(r["ApprovedBy"]) : null
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "Cancel", null);
                return JsonGet(new { Message = "Fail", ErrorMessage = "The cancellation could not be recorded." });
            }
        }

        // ---------------------------------------------------------------------
        // Lookups - one call on page load
        // ---------------------------------------------------------------------
        [HttpGet]
        public JsonResult Lookups()
        {
            try
            {
                var u = POSUser.Current;
                SqlParameter[] spa =
                {
                    new SqlParameter("@BrandID", SqlDbType.Int)
                        { Value = u.BrandID > 0 ? (object)u.BrandID : DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetLookups", spa);
                if (ds == null || ds.Tables.Count < 6)
                    return JsonGet(new { Message = "Fail" });

                // Presentation only - Facets/List/Changes above are what
                // actually enforce this. Trimming the dropdown too just
                // keeps a restricted user from seeing branch NAMES they
                // cannot pull any data for.
                var branchRows = Rows(ds.Tables[0]);
                if (u != null && !u.CanManageMasters)
                {
                    var allowed = u.BranchIDs ?? new List<int>();
                    branchRows = branchRows.Where(row =>
                        row.ContainsKey("BranchID") && row["BranchID"] != null &&
                        allowed.Contains(Convert.ToInt32(row["BranchID"]))).ToList();
                }

                return JsonGet(new
                {
                    Message       = "Success",
                    Branches      = branchRows,
                    Statuses      = Rows(ds.Tables[1]),
                    PaymentTypes  = Rows(ds.Tables[2]),
                    CancelReasons = Rows(ds.Tables[3]),
                    Channels      = Rows(ds.Tables[4]),
                    Denominations = Rows(ds.Tables[5]),
                    Permissions   = new
                    {
                        u.CanChangeStatus, u.CanCancel, u.CanRefund, u.CanTransfer,
                        u.CanTakePayment, u.CanViewReports, u.CanEndDay, u.CanManageMasters
                    },
                    User = new { u.UserID, u.UserName, u.RoleName, u.BrandID }
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "Lookups", null);
                return JsonGet(new { Message = "Fail" });
            }
        }

        // ---------------------------------------------------------------------
        // Facet counts for the left filter panel
        // ---------------------------------------------------------------------
        [HttpPost]
        public JsonResult Facets(OrderListRequest req)
        {
            try
            {
                if (req == null) req = new OrderListRequest();

                SqlParameter[] spa =
                {
                    P("@BrandIDs",       SqlDbType.VarChar,  200, req.BrandIDs),
                    // Confined to this user's assigned branches, unless they
                    // have CanManageMasters - see POSBranchScope.
                    P("@BranchIDs",      SqlDbType.VarChar,  200, POSBranchScope.ResolveCsv(POSUser.Current, req.BranchIDs)),
                    P("@InvoiceTypeIDs", SqlDbType.VarChar,  200, req.InvoiceTypeIDs),
                    P("@StatusIDs",      SqlDbType.VarChar,  200, req.StatusIDs),
                    P("@DateMode",       SqlDbType.VarChar,   10, string.IsNullOrEmpty(req.DateMode) ? "Today" : req.DateMode),
                    P("@FromDate",       SqlDbType.Date,       0, req.FromDate),
                    P("@ToDate",         SqlDbType.Date,       0, req.ToDate),
                    P("@Search",         SqlDbType.NVarChar,  100, req.Search),
                    P("@PaymentStatus",  SqlDbType.VarChar,   10, req.PaymentStatus),
                    P("@ScheduledOnly",  SqlDbType.Bit,        0, req.ScheduledOnly)
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderFacets", spa);
                if (ds == null || ds.Tables.Count < 3)
                    return JsonGet(new { Message = "Fail" });

                return JsonGet(new
                {
                    Message      = "Success",
                    Brands       = Rows(ds.Tables[0]),
                    Branches     = Rows(ds.Tables[1]),
                    InvoiceTypes = Rows(ds.Tables[2]),

                    // Result set 3 is the per-status count, added by POS_23. It
                    // is null on a database where that script has not run yet,
                    // and the panel then draws the statuses without counts
                    // rather than showing a column of zeros.
                    Statuses     = ds.Tables.Count > 3 ? Rows(ds.Tables[3]) : null
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "Facets", null);
                return JsonGet(new { Message = "Fail" });
            }
        }

        // ---------------------------------------------------------------------
        // Grid - DataTables server-side
        // ---------------------------------------------------------------------
        [HttpPost]
        public JsonResult List(OrderListRequest req)
        {
            try
            {
                if (req == null) req = new OrderListRequest();

                SqlParameter[] spa =
                {
                    P("@BrandIDs",       SqlDbType.VarChar,  200, req.BrandIDs),
                    // Confined to this user's assigned branches, unless they
                    // have CanManageMasters - see POSBranchScope.
                    P("@BranchIDs",      SqlDbType.VarChar,  200, POSBranchScope.ResolveCsv(POSUser.Current, req.BranchIDs)),
                    P("@InvoiceTypeIDs", SqlDbType.VarChar,  200, req.InvoiceTypeIDs),
                    P("@StatusIDs",      SqlDbType.VarChar,  200, req.StatusIDs),
                    P("@DateMode",       SqlDbType.VarChar,   10, string.IsNullOrEmpty(req.DateMode) ? "Today" : req.DateMode),
                    P("@FromDate",       SqlDbType.Date,       0, req.FromDate),
                    P("@ToDate",         SqlDbType.Date,       0, req.ToDate),
                    P("@Search",         SqlDbType.NVarChar,  100, req.Search),
                    P("@OrderType",      SqlDbType.Int,        0, req.OrderType),
                    P("@PaymentTypeID",  SqlDbType.Int,        0, req.PaymentTypeID),
                    P("@PaymentStatus",  SqlDbType.VarChar,   10, req.PaymentStatus),
                    P("@SourceID",       SqlDbType.Int,        0, req.SourceID),
                    P("@DriverID",       SqlDbType.Int,        0, req.DriverID),
                    P("@MinAmount",      SqlDbType.Decimal,    0, req.MinAmount),
                    P("@MaxAmount",      SqlDbType.Decimal,    0, req.MaxAmount),
                    P("@IncludeDeleted", SqlDbType.Bit,        0, req.IncludeDeleted),
                    P("@ScheduledOnly",  SqlDbType.Bit,        0, req.ScheduledOnly),
                    P("@Skip",           SqlDbType.Int,        0, req.Start),
                    P("@Take",           SqlDbType.Int,        0, req.Length <= 0 ? 50 : req.Length),
                    P("@SortCol",        SqlDbType.VarChar,   30, req.SortCol),
                    P("@SortDir",        SqlDbType.VarChar,    4, req.SortDir)
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrders", spa);
                DataTable dt = (ds != null && ds.Tables.Count > 0) ? ds.Tables[0] : null;

                // TotalRows is a window function on the same pass, so it only
                // exists when at least one row came back.
                int total = (dt != null && dt.Rows.Count > 0) ? Convert.ToInt32(dt.Rows[0]["TotalRows"]) : 0;

                return JsonGet(new
                {
                    draw            = req.Draw,
                    recordsTotal    = total,
                    recordsFiltered = total,
                    data            = dt != null ? Rows(dt) : new List<Dictionary<string, object>>()
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "List", null);

                // "Query failed." on its own is a dead end: DataTables shows it
                // for every possible cause - a bad sort column, a missing proc,
                // a login failure - and the only way to tell them apart was to
                // attach a debugger. The SQL message is appended, along with the
                // sort that produced it, whenever custom errors are off. Real
                // users on a live server still see just the sentence.
                string detail = "";
                if (IsDevelopment)
                {
                    detail = " [" + (req != null ? (req.SortCol ?? "(no sort col)") + " "
                                                 + (req.SortDir ?? "") + " - " : "")
                           + ex.Message
                           + (ex.InnerException != null ? " | " + ex.InnerException.Message : "")
                           + "]";
                }

                return JsonGet(new
                {
                    draw            = req == null ? 0 : req.Draw,
                    recordsTotal    = 0,
                    recordsFiltered = 0,
                    data            = new object[0],
                    error           = "Query failed." + detail
                });
            }
        }

        // ---------------------------------------------------------------------
        // Delta poll.
        //
        // rowversion travels as a hex string: a JS number cannot hold 64 bits
        // without losing precision, which would silently skip orders.
        // ---------------------------------------------------------------------
        [HttpPost]
        public JsonResult Changes(string sinceRowVer, string branchIDs)
        {
            try
            {
                SqlParameter[] spa =
                {
                    new SqlParameter("@SinceRowVer", SqlDbType.Binary, 8)
                        { Value = HexToBytes(sinceRowVer) ?? (object)DBNull.Value },
                    // Confined to this user's assigned branches, unless they
                    // have CanManageMasters - see POSBranchScope.
                    P("@BranchIDs", SqlDbType.VarChar, 200, POSBranchScope.ResolveCsv(POSUser.Current, branchIDs)),
                    new SqlParameter("@MaxRows", SqlDbType.Int) { Value = 200 }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderChanges", spa);
                if (ds == null || ds.Tables.Count == 0)
                    return JsonGet(new { Message = "Fail" });

                string watermark = null;
                if (ds.Tables[0].Rows.Count > 0 && ds.Tables[0].Rows[0]["CurrentRowVer"] != DBNull.Value)
                    watermark = BytesToHex((byte[])ds.Tables[0].Rows[0]["CurrentRowVer"]);

                var changed = ds.Tables.Count > 1 ? Rows(ds.Tables[1]) : new List<Dictionary<string, object>>();
                return JsonGet(new { Message = "Success", RowVer = watermark, Changed = changed });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "Changes", null);
                return JsonGet(new { Message = "Fail" });
            }
        }

        // ---------------------------------------------------------------------
        // Details panel
        // ---------------------------------------------------------------------
        [HttpGet]
        public JsonResult Details(long id)
        {
            try
            {
                SqlParameter[] spa = { new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = id } };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderDetails", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "NotFound" });

                return JsonGet(new
                {
                    Message      = "Success",
                    Header       = Rows(ds.Tables[0]).FirstOrDefault(),
                    Lines        = ds.Tables.Count > 1 ? Rows(ds.Tables[1]) : null,
                    Timeline     = ds.Tables.Count > 2 ? Rows(ds.Tables[2]) : null,
                    Payments     = ds.Tables.Count > 3 ? Rows(ds.Tables[3]) : null,
                    Transfers    = ds.Tables.Count > 4 ? Rows(ds.Tables[4]) : null,
                    NextStatuses = ds.Tables.Count > 5 ? Rows(ds.Tables[5]) : null
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "Details", null);
                return JsonGet(new { Message = "Fail" });
            }
        }

        // ---------------------------------------------------------------------
        // helpers
        // ---------------------------------------------------------------------

        /// <summary>
        /// MaxJsonLength is raised because the 4 MB default is reached by a
        /// large page with Arabic names, and it fails with an opaque error.
        /// </summary>
        private JsonResult JsonGet(object data)
        {
            return new LegacyJsonResult(data);
        }

        private static SqlParameter P(string name, SqlDbType type, int size, object value)
        {
            var p = size > 0 ? new SqlParameter(name, type, size) : new SqlParameter(name, type);
            if (value == null) { p.Value = DBNull.Value; return p; }
            var s = value as string;
            p.Value = (s != null && s.Length == 0) ? DBNull.Value : value;
            return p;
        }

        private static List<Dictionary<string, object>> Rows(DataTable dt)
        {
            var list = new List<Dictionary<string, object>>(dt.Rows.Count);
            foreach (DataRow r in dt.Rows)
            {
                var d = new Dictionary<string, object>(dt.Columns.Count);
                foreach (DataColumn c in dt.Columns)
                {
                    object v = r[c];
                    if (v == DBNull.Value) { d[c.ColumnName] = null; continue; }
                    d[c.ColumnName] = c.DataType == typeof(byte[]) ? BytesToHex((byte[])v) : v;
                }
                list.Add(d);
            }
            return list;
        }

        private static string BytesToHex(byte[] b)
        {
            return b == null ? null : "0x" + BitConverter.ToString(b).Replace("-", "");
        }

        private static byte[] HexToBytes(string hex)
        {
            if (string.IsNullOrWhiteSpace(hex)) return null;
            hex = hex.Trim();
            if (hex.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) hex = hex.Substring(2);
            if (hex.Length != 16) return null;                 // rowversion is 8 bytes
            var b = new byte[8];
            for (int i = 0; i < 8; i++)
            {
                if (!byte.TryParse(hex.Substring(i * 2, 2), System.Globalization.NumberStyles.HexNumber,
                                   System.Globalization.CultureInfo.InvariantCulture, out b[i]))
                    return null;
            }
            return b;
        }
    }

    /// <summary>Filter payload posted by the grid and the facet panel.</summary>
    /// <summary>One amount box from the Take Payment dialog.</summary>
    public class PaymentLineInput
    {
        public int TypeID { get; set; }
        public decimal Amount { get; set; }
    }

    public class OrderListRequest
    {
        public int Draw { get; set; }
        public int Start { get; set; }
        public int Length { get; set; }

        public string BrandIDs { get; set; }
        public string BranchIDs { get; set; }
        public string InvoiceTypeIDs { get; set; }
        public string StatusIDs { get; set; }
        public string DateMode { get; set; }        // Today | Future | Past | Range | All
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public string Search { get; set; }
        public int? OrderType { get; set; }
        public int? PaymentTypeID { get; set; }
        public string PaymentStatus { get; set; }   // Paid | Unpaid | Partial
        public int? SourceID { get; set; }
        public int? DriverID { get; set; }
        public decimal? MinAmount { get; set; }
        public decimal? MaxAmount { get; set; }
        public bool IncludeDeleted { get; set; }
        public bool ScheduledOnly { get; set; }     // only orders whose DeliveryDate is a later calendar day than InvoiceDate
        public string SortCol { get; set; }
        public string SortDir { get; set; }
    }
}
