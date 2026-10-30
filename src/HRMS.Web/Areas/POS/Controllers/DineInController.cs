#nullable disable
//==============================================================================
//  Areas/POS/Controllers/DineInController.cs
//------------------------------------------------------------------------------
//  Dine-In floor plan and everything done from it.
//
//  No second order store: a Dine-In bill is a normal tblInvoice / tblOrder row
//  created by sp_POS_ProcessOrder (OrderType 3, InvoiceType "Dine In"), then
//  linked to the table by sp_POS_DineIn_AttachInvoice. Delete line, cancel and
//  payment call the SAME procedures the Order List uses, so the rules
//  (manager password, waste/reuse, overpayment) are identical everywhere.
//
//  Every action that changes a table tells every open screen through
//  DineInHub, so a tablet and a cashier never take an order on the same table.
//
//  Procedures: DBScripts/POS_35_DineIn.sql, POS_37_DineIn_TakeAway.sql, POS_38_DineIn_SplitFlag.sql
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Controllers\DineInController.cs" />
//==============================================================================

using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Linq;
using System.Runtime.Caching;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.POS.Hubs;
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
using Newtonsoft.Json;

namespace HRMS.Web.Areas.POS.Controllers
{
    [POSAuthorize]
    public class DineInController : PosController
    {
        // ---------------------------------------------------------------------
        // Page
        // ---------------------------------------------------------------------
        public ActionResult Index()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }

        // ---------------------------------------------------------------------
        // Reads
        // ---------------------------------------------------------------------
        [HttpGet]
        public JsonResult Floor()
        {
            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_DineIn_GetFloor", null);
                if (ds == null || ds.Tables.Count < 2)
                    return Fail("The floor plan could not be loaded.");

                return JsonGet(new
                {
                    Message = "Success",
                    Areas   = Rows(ds.Tables[0]),
                    Tables  = Rows(ds.Tables[1])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Floor", null);
                return Fail("The floor plan could not be loaded." + Detail(ex));
            }
        }

        /// <summary>
        /// The Take Away tab: today's Take Away bills plus any older one still
        /// unpaid, with their lines. Newest first.
        /// </summary>
        [HttpGet]
        public JsonResult TakeAway(int? branchId)
        {
            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_DineIn_TakeAwayList",
                    new[] { new SqlParameter("@BranchID", SqlDbType.Int) { Value = (object)ResolveBranch(branchId) ?? DBNull.Value } });

                if (ds == null || ds.Tables.Count < 2)
                    return Fail("The Take Away orders could not be loaded.");

                return JsonGet(new
                {
                    Message = "Success",
                    Bills   = Rows(ds.Tables[0]),
                    Lines   = Rows(ds.Tables[1])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "TakeAway", null);
                return Fail("The Take Away orders could not be loaded." + Detail(ex));
            }
        }

        [HttpGet]
        public JsonResult Table(int id)
        {
            try
            {
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_DineIn_GetTable",
                    new[] { new SqlParameter("@TableID", SqlDbType.Int) { Value = id } });

                if (ds == null || ds.Tables.Count < 3 || ds.Tables[0].Rows.Count == 0)
                    return Fail("Table not found.");

                return JsonGet(new
                {
                    Message = "Success",
                    Table   = Rows(ds.Tables[0]).FirstOrDefault(),
                    Bills   = Rows(ds.Tables[1]),
                    Lines   = Rows(ds.Tables[2])
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Table", null);
                return Fail("The table could not be loaded." + Detail(ex));
            }
        }

        /// <summary>
        /// Categories and items for the order popup. Cached for two minutes per
        /// brand: every tablet opens this popup many times an hour, and the menu
        /// changes a few times a week.
        /// </summary>
        [HttpGet]
        public JsonResult Menu()
        {
            try
            {
                var u = POSUser.Current;
                string key = "POS_DineIn_Menu_" + u.BrandID;
                var cached = MemoryCache.Default.Get(key);
                if (cached != null) return JsonGet(cached);

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_DineIn_GetMenu",
                    new[] { new SqlParameter("@BrandID", SqlDbType.Int) { Value = u.BrandID > 0 ? (object)u.BrandID : DBNull.Value } });

                if (ds == null || ds.Tables.Count < 2)
                    return Fail("The menu could not be loaded.");

                var result = new
                {
                    Message    = "Success",
                    Categories = Rows(ds.Tables[0]),
                    Items      = Rows(ds.Tables[1])
                };
                MemoryCache.Default.Set(key, result, DateTimeOffset.Now.AddMinutes(2));
                return JsonGet(result);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Menu", null);
                return Fail("The menu could not be loaded." + Detail(ex));
            }
        }

        // ---------------------------------------------------------------------
        // Table state
        // ---------------------------------------------------------------------

        /// <summary>
        /// Vacant -> occupied, the moment the table is tapped. The unique index
        /// on tblPOS_TableSession decides a race; the loser gets Code=Occupied.
        /// </summary>
        [HttpPost]
        public JsonResult Lock(int tableId, int? branchId)
        {
            try
            {
                var u = POSUser.Current;
                DataRow r = One("sp_POS_DineIn_LockTable",
                    new SqlParameter("@TableID",  SqlDbType.Int)           { Value = tableId },
                    new SqlParameter("@BranchID", SqlDbType.Int)           { Value = (object)ResolveBranch(branchId) ?? DBNull.Value },
                    new SqlParameter("@UserID",   SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName", SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });

                if (r == null || Str(r, "Message") != "Success")
                {
                    DineInHub.TableChanged(tableId, "refresh", null);   // the loser's screen is stale
                    return JsonGet(new { Message = "Fail", Code = r != null ? Str(r, "Code") : "Error",
                                         ErrorMessage = r != null ? Str(r, "ErrorMessage") : "The table could not be opened." });
                }

                DineInHub.TableChanged(tableId, "occupied", u.UserName);
                return JsonGet(new { Message = "Success", SessionID = r["SessionID"] });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Lock", null);
                return Fail("The table could not be opened." + Detail(ex));
            }
        }

        [HttpPost]
        public JsonResult SetGuest(int tableId, string name, string mobile, int persons)
        {
            try
            {
                DataRow r = One("sp_POS_DineIn_SetGuest",
                    new SqlParameter("@TableID",      SqlDbType.Int)           { Value = tableId },
                    new SqlParameter("@CustomerName", SqlDbType.NVarChar, 200) { Value = Db(name) },
                    new SqlParameter("@Mobile",       SqlDbType.NVarChar, 30)  { Value = Db(CleanMobile(mobile)) },
                    new SqlParameter("@Persons",      SqlDbType.Int)           { Value = persons });

                if (r == null || Str(r, "Message") != "Success")
                    return Fail(r != null ? Str(r, "ErrorMessage") : "The guest details could not be saved.");

                DineInHub.TableChanged(tableId, "guest", POSUser.Current.UserName);
                return JsonGet(new { Message = "Success" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "SetGuest", null);
                return Fail("The guest details could not be saved." + Detail(ex));
            }
        }

        /// <summary>
        /// Occupied -> vacant. Refused while a bill is unpaid. force = clear a
        /// stuck table regardless; Settings permission only.
        /// </summary>
        [HttpPost]
        public JsonResult Release(int tableId, string reason, bool force = false)
        {
            try
            {
                var u = POSUser.Current;
                if (force && !u.CanManageMasters)
                    return Fail("Only an administrator can force a table free.");

                DataRow r = One("sp_POS_DineIn_ReleaseTable",
                    new SqlParameter("@TableID",  SqlDbType.Int)           { Value = tableId },
                    new SqlParameter("@Reason",   SqlDbType.NVarChar, 50)  { Value = string.IsNullOrWhiteSpace(reason) ? "Released" : reason.Trim() },
                    new SqlParameter("@UserID",   SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName", SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value },
                    new SqlParameter("@Force",    SqlDbType.Bit)           { Value = force });

                if (r == null || Str(r, "Message") != "Success")
                    return Fail(r != null ? Str(r, "ErrorMessage") : "The table could not be freed.");

                DineInHub.TableChanged(tableId, "vacant", u.UserName);
                return JsonGet(new { Message = "Success" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Release", null);
                return Fail("The table could not be freed." + Detail(ex));
            }
        }

        // ---------------------------------------------------------------------
        // Ordering
        // ---------------------------------------------------------------------

        /// <summary>
        /// A NEW bill. tableId = Dine-In against that table; no tableId = Take
        /// Away. items is JSON: [{"ItemID":12,"Quantity":2,"Comments":null}]
        /// clientGuid makes a double-tap on Process Order return the first bill
        /// instead of creating a second (sp_POS_ProcessOrder idempotency).
        /// </summary>
        [HttpPost]
        public JsonResult PlaceOrder(int? tableId, int? branchId, string items, Guid clientGuid,
                                     string name, string mobile)
        {
            try
            {
                var u = POSUser.Current;
                int? branch = ResolveBranch(branchId);
                if (branch == null)
                    return Fail("No branch is assigned to your user. Ask an administrator.");

                bool dineIn = tableId.HasValue && tableId.Value > 0;

                // Take Away bills are Take Away as a whole; the per-item mark is for Dine-In only.
                List<POSOrderItem> lines = ParseItems(items, dineIn);
                if (lines.Count == 0)
                    return Fail("Add at least one item.");

                DataRow ctx = Context(branch.Value);

                int? invoiceType = IntOrNull(ctx, dineIn ? "DineInTypeID" : "TakeAwayTypeID");
                if (invoiceType == null)
                    return Fail("tblInvoiceType_Master has no '" + (dineIn ? "Dine In" : "Take Away") + "' row.");

                // Dine-In takes the guest from the seating, not from the browser.
                if (dineIn)
                {
                    DataSet t = DB.ExecuteStoredProcDataSet("sp_POS_DineIn_GetTable",
                        new[] { new SqlParameter("@TableID", SqlDbType.Int) { Value = tableId.Value } });
                    if (t == null || t.Tables.Count == 0 || t.Tables[0].Rows.Count == 0 || t.Tables[0].Rows[0]["SessionID"] == DBNull.Value)
                        return Fail("This table is not open any more. Tap it again to seat guests.");
                    name   = Str(t.Tables[0].Rows[0], "CustomerName");
                    mobile = Str(t.Tables[0].Rows[0], "Mobile");
                }

                mobile = CleanMobile(mobile);
                bool anonymous = string.IsNullOrWhiteSpace(name) && string.IsNullOrWhiteSpace(mobile);

                var spa = new List<SqlParameter>
                {
                    new SqlParameter("@BranchID",        SqlDbType.Int)              { Value = branch.Value },
                    new SqlParameter("@BrandID",         SqlDbType.Int)              { Value = u.BrandID > 0 ? u.BrandID : Convert.ToInt32(ctx["BrandID"]) },
                    new SqlParameter("@InvoiceTypeID",   SqlDbType.Int)              { Value = invoiceType.Value },
                    new SqlParameter("@OrderType",       SqlDbType.Int)              { Value = dineIn ? 3 : 1 },
                    new SqlParameter("@CustomerId",      SqlDbType.Int)              { Value = anonymous ? ctx["WalkInCustomerID"] : DBNull.Value },
                    new SqlParameter("@CustomerName",    SqlDbType.NVarChar, 200)    { Value = anonymous ? (object)"Walk-in Customer" : Db(name) },
                    new SqlParameter("@Mobile",          SqlDbType.NVarChar, 30)     { Value = Db(mobile) },
                    new SqlParameter("@WaiterID",        SqlDbType.Int)              { Value = u.UserID },
                    new SqlParameter("@ClientOrderGuid", SqlDbType.UniqueIdentifier) { Value = clientGuid },
                    new SqlParameter("@dtOrderItems",    SqlDbType.Structured)       { TypeName = "dbo.TVP_POS_OrderItem", Value = DB.ToDataTable(lines) }
                };
                if (ctx["CashPaymentTypeID"] != DBNull.Value)
                    spa.Add(new SqlParameter("@PaymentTypeID", SqlDbType.Int) { Value = ctx["CashPaymentTypeID"] });

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_ProcessOrder", spa.ToArray());
                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return Fail("No response while saving the order.");

                DataRow r = ds.Tables[0].Rows[0];
                string msg = Str(r, "Message");
                if (msg != "Success" && msg != "Duplicate")
                    return Fail(Str(r, "ErrorMessage") ?? "The order could not be saved.");

                long invoiceNo = Convert.ToInt64(r["InvoiceNo"]);

                if (dineIn && msg == "Success")
                {
                    DataRow a = One("sp_POS_DineIn_AttachInvoice",
                        new SqlParameter("@InvoiceNo",         SqlDbType.BigInt)        { Value = invoiceNo },
                        new SqlParameter("@TableID",           SqlDbType.Int)           { Value = tableId.Value },
                        new SqlParameter("@DineInTableTypeID", SqlDbType.Int)           { Value = ctx["DineInTableTypeID"] },
                        new SqlParameter("@UserID",            SqlDbType.Int)           { Value = u.UserID },
                        new SqlParameter("@UserName",          SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });

                    if (a == null || Str(a, "Message") != "Success")
                        return JsonGet(new
                        {
                            Message = "Fail",
                            ErrorMessage = "Bill " + invoiceNo + " was saved but could not be linked to the table: "
                                         + (a != null ? Str(a, "ErrorMessage") : "no response") + " Find it in the Order List."
                        });
                }

                if (dineIn) DineInHub.TableChanged(tableId.Value, "order", u.UserName);
                else        DineInHub.TakeAwayChanged(u.UserName);

                return JsonGet(new
                {
                    Message      = "Success",
                    InvoiceNo    = invoiceNo,
                    RunningOrder = r["RunningOrder"],
                    NetPayable   = r["NetPayable"],
                    Warning      = Str(r, "Warning")
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "PlaceOrder", null);
                return Fail("The order could not be saved." + Detail(ex));
            }
        }

        /// <summary>Append items to a bill that is already on the table.</summary>
        [HttpPost]
        public JsonResult AddItems(long invoiceNo, string items, int tableId = 0)
        {
            try
            {
                var u = POSUser.Current;
                bool onTable = tableId > 0;
                List<POSOrderItem> lines = ParseItems(items, onTable);
                if (lines.Count == 0)
                    return Fail("Add at least one item.");

                DataRow ctx = Context(null);

                DataRow r = One("sp_POS_DineIn_AddItems",
                    new SqlParameter("@InvoiceNo",         SqlDbType.BigInt)        { Value = invoiceNo },
                    new SqlParameter("@DineInTableTypeID", SqlDbType.Int)           { Value = onTable ? ctx["DineInTableTypeID"] : -1 },
                    new SqlParameter("@UserID",            SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",          SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value },
                    new SqlParameter("@dtOrderItems",      SqlDbType.Structured)    { TypeName = "dbo.TVP_POS_OrderItem", Value = DB.ToDataTable(lines) });

                if (r == null || Str(r, "Message") != "Success")
                    return Fail(r != null ? Str(r, "ErrorMessage") : "The items could not be added.");

                Notify(tableId, "order", u.UserName);
                return JsonGet(new { Message = "Success", InvoiceNo = invoiceNo, NetPayable = r["NetPayable"] });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "AddItems", null);
                return Fail("The items could not be added." + Detail(ex));
            }
        }

        // ---------------------------------------------------------------------
        // Bill actions - same procedures as the Order List
        // ---------------------------------------------------------------------

        /// <summary>Voids one line. disposition: 1 Waste, 2 Reuse.</summary>
        [HttpPost]
        public JsonResult DeleteLine(long invoiceNo, long orderId, int disposition,
                                     string comment, string password, int tableId = 0)
        {
            try
            {
                var u = POSUser.Current;
                if (disposition != 1 && disposition != 2) return Fail("Select Waste or Reuse.");
                if (string.IsNullOrWhiteSpace(comment))    return Fail("A delete comment is required.");
                if (string.IsNullOrWhiteSpace(password))   return Fail("The manager password is required.");

                DataRow r = One("sp_POS_DeleteOrderLine",
                    new SqlParameter("@InvoiceNo",   SqlDbType.BigInt)        { Value = invoiceNo },
                    new SqlParameter("@OrderID",     SqlDbType.BigInt)        { Value = orderId },
                    new SqlParameter("@Disposition", SqlDbType.TinyInt)       { Value = disposition },
                    new SqlParameter("@Comments",    SqlDbType.NVarChar, 500) { Value = comment.Trim() },
                    new SqlParameter("@Password",    SqlDbType.NVarChar, 100) { Value = password },
                    new SqlParameter("@UserID",      SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",    SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });

                if (r == null || Str(r, "Message") != "Success")
                    return Fail(r != null ? Str(r, "ErrorMessage") : "The item could not be deleted.");

                Notify(tableId, "order", u.UserName);
                return JsonGet(new { Message = "Success", Warning = Str(r, "Warning") });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "DeleteLine", null);
                return Fail("The item could not be deleted." + Detail(ex));
            }
        }

        /// <summary>
        /// Deletes (cancels) a whole bill - reason + manager password, exactly
        /// like Cancel on the Order List. Frees the table when nothing else on
        /// it is owed.
        /// </summary>
        [HttpPost]
        public JsonResult DeleteInvoice(long invoiceNo, string comment, string password, int tableId = 0)
        {
            try
            {
                var u = POSUser.Current;
                if (string.IsNullOrWhiteSpace(comment))  return Fail("A reason is required.");
                if (string.IsNullOrWhiteSpace(password)) return Fail("The manager password is required.");

                DataRow r = One("sp_POS_CancelOrderReject",
                    new SqlParameter("@InvoiceNo", SqlDbType.BigInt)        { Value = invoiceNo },
                    new SqlParameter("@Comments",  SqlDbType.NVarChar, 500) { Value = comment.Trim() },
                    new SqlParameter("@Password",  SqlDbType.NVarChar, 100) { Value = password },
                    new SqlParameter("@UserID",    SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",  SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });

                if (r == null || Str(r, "Message") != "Success")
                    return Fail(r != null ? Str(r, "ErrorMessage") : "The bill could not be deleted.");

                bool freed = tableId > 0 && CloseIfSettled(tableId, "BillDeleted");
                Notify(tableId, freed ? "vacant" : "order", u.UserName);
                return JsonGet(new { Message = "Success", Freed = freed });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "DeleteInvoice", null);
                return Fail("The bill could not be deleted." + Detail(ex));
            }
        }

        /// <summary>
        /// Takes payment on one bill. lines is JSON [{"TypeID":1,"Amount":10.5}],
        /// the amounts TENDERED - change is worked out by the procedure. The
        /// table turns green once every bill on it is settled.
        /// </summary>
        [HttpPost]
        public JsonResult Pay(long invoiceNo, string lines, string reference, int tableId = 0)
        {
            try
            {
                var u = POSUser.Current;
                DataRow r; string err;
                if (!TryPay(invoiceNo, lines, reference, out r, out err))
                    return Fail(err);

                bool freed = tableId > 0 && CloseIfSettled(tableId, "Paid");
                Notify(tableId, freed ? "vacant" : "order", u.UserName);

                return JsonGet(PayResult(r, freed));
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Pay", null);
                return Fail("The payment could not be recorded." + Detail(ex));
            }
        }

        /// <summary>
        /// Marks (or unmarks) one item on a Dine-In bill as Take Away, so the
        /// kitchen packs it. The mark is the text TAKE AWAY at the start of the
        /// item's comment, which the kitchen ticket prints under the item.
        /// </summary>
        [HttpPost]
        public JsonResult SetLineTakeAway(long invoiceNo, long orderId, bool on, int tableId = 0)
        {
            try
            {
                var u = POSUser.Current;
                DataRow r = One("sp_POS_DineIn_SetLineTakeAway",
                    new SqlParameter("@InvoiceNo", SqlDbType.BigInt)        { Value = invoiceNo },
                    new SqlParameter("@OrderID",   SqlDbType.BigInt)        { Value = orderId },
                    new SqlParameter("@On",        SqlDbType.Bit)           { Value = on },
                    new SqlParameter("@UserID",    SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",  SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });

                if (r == null || Str(r, "Message") != "Success")
                    return Fail(r != null ? Str(r, "ErrorMessage") : "The item could not be updated.");

                Notify(tableId, "order", u.UserName);
                return JsonGet(new { Message = "Success" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "SetLineTakeAway", null);
                return Fail("The item could not be updated." + Detail(ex));
            }
        }

        [HttpPost]
        public JsonResult Transfer(int fromTableId, int toTableId)
        {
            try
            {
                var u = POSUser.Current;
                DataRow r = One("sp_POS_DineIn_TransferTable",
                    new SqlParameter("@FromTableID", SqlDbType.Int)           { Value = fromTableId },
                    new SqlParameter("@ToTableID",   SqlDbType.Int)           { Value = toTableId },
                    new SqlParameter("@UserID",      SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",    SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });

                if (r == null || Str(r, "Message") != "Success")
                    return Fail(r != null ? Str(r, "ErrorMessage") : "The table could not be transferred.");

                DineInHub.TableChanged(fromTableId, "vacant", u.UserName);
                DineInHub.TableChanged(toTableId, "occupied", u.UserName);
                return JsonGet(new { Message = "Success" });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Transfer", null);
                return Fail("The table could not be transferred." + Detail(ex));
            }
        }

        /// <summary>
        /// Split only: the chosen item rows go on a new bill that stays unpaid.
        /// lines is JSON [{"OrderID":55,"Quantity":1}] (a row always moves whole).
        /// </summary>
        [HttpPost]
        public JsonResult Split(int tableId, long invoiceNo, string lines)
        {
            try
            {
                long newNo; string err;
                if (!TrySplit(invoiceNo, lines, out newNo, out err))
                    return Fail(err);

                Notify(tableId, "order", POSUser.Current.UserName);
                return JsonGet(new { Message = "Success", NewInvoiceNo = newNo });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "Split", null);
                return Fail("The bill could not be split." + Detail(ex));
            }
        }

        /// <summary>
        /// Split and pay in one step: the chosen rows go on a NEW bill and the
        /// payment is taken on that new bill. Nothing is split if the payment
        /// could not even be read or the user may not take payment. If the split
        /// worked but the payment was refused, the reply says so and carries
        /// NewInvoiceNo so the screen can show the new (unpaid) bill.
        /// </summary>
        [HttpPost]
        public JsonResult SplitPay(int tableId, long invoiceNo, string lines, string payLines, string reference)
        {
            try
            {
                var u = POSUser.Current;
                DataTable pay; string err;
                if (!ParsePayment(payLines, out pay, out err))
                    return Fail(err);

                long newNo;
                if (!TrySplit(invoiceNo, lines, out newNo, out err))
                    return Fail(err);

                DataRow r;
                if (!TryPay(newNo, payLines, reference, out r, out err))
                {
                    Notify(tableId, "order", u.UserName);
                    return JsonGet(new
                    {
                        Message      = "Fail",
                        Split        = true,
                        NewInvoiceNo = newNo,
                        ErrorMessage = "The bill was split into a new bill, but the payment was not recorded: " + err
                                     + " Take payment from the table."
                    });
                }

                bool freed = tableId > 0 && CloseIfSettled(tableId, "Paid");
                Notify(tableId, freed ? "vacant" : "order", u.UserName);

                var res = PayResult(r, freed);
                return JsonGet(new
                {
                    Message       = "Success",
                    NewInvoiceNo  = newNo,
                    AmountPaid    = res.AmountPaid,
                    AmountDue     = res.AmountDue,
                    ChangeGiven   = res.ChangeGiven,
                    PaymentStatus = res.PaymentStatus,
                    Freed         = freed
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "SplitPay", null);
                return Fail("The bill could not be split." + Detail(ex));
            }
        }

        // ---------------------------------------------------------------------
        // Admin: drag-and-drop layout
        // ---------------------------------------------------------------------
        /// <summary>positions is JSON [{"TableID":3,"X":120,"Y":40}]</summary>
        [HttpPost]
        public JsonResult SaveLayout(string positions)
        {
            try
            {
                var u = POSUser.Current;
                if (!u.CanManageMasters)
                    return Fail("Only an administrator can arrange tables.");

                List<PositionInput> parsed;
                try { parsed = JsonConvert.DeserializeObject<List<PositionInput>>(positions ?? "[]"); }
                catch { return Fail("The layout could not be read."); }

                var dt = new DataTable();
                dt.Columns.Add("TableID", typeof(int));
                dt.Columns.Add("Xaxis", typeof(decimal));
                dt.Columns.Add("Yaxis", typeof(decimal));
                foreach (var p in parsed ?? new List<PositionInput>())
                {
                    if (p == null || dt.Select("TableID = " + p.TableID).Length > 0) continue;
                    dt.Rows.Add(p.TableID, Math.Max(0m, decimal.Round(p.X, 2)), Math.Max(0m, decimal.Round(p.Y, 2)));
                }
                if (dt.Rows.Count == 0)
                    return JsonGet(new { Message = "Success", Updated = 0 });

                DataRow r = One("sp_POS_DineIn_SaveLayout",
                    new SqlParameter("@UserID",    SqlDbType.Int)           { Value = u.UserID },
                    new SqlParameter("@UserName",  SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value },
                    new SqlParameter("@Positions", SqlDbType.Structured)    { TypeName = "dbo.TVP_POS_TablePosition", Value = dt });

                DineInHub.LayoutChanged(u.UserName);
                return JsonGet(new { Message = "Success", Updated = r != null ? r["Updated"] : 0 });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInController", "SaveLayout", null);
                return Fail("The layout could not be saved." + Detail(ex));
            }
        }

        // ---------------------------------------------------------------------
        // helpers
        // ---------------------------------------------------------------------

        /// <summary>
        /// The branch the order is booked against. A user restricted to some
        /// branches can only use one of those; an administrator any.
        /// </summary>
        private static int? ResolveBranch(int? requested)
        {
            var u = POSUser.Current;
            var allowed = u.BranchIDs ?? new List<int>();
            if (requested.HasValue && requested.Value > 0 && (u.CanManageMasters || allowed.Contains(requested.Value)))
                return requested.Value;
            return allowed.Count > 0 ? allowed[0] : (int?)null;
        }

        private static DataRow Context(int? branchId)
        {
            var u = POSUser.Current;
            DataRow r = One("sp_POS_DineIn_Context",
                new SqlParameter("@BrandID",  SqlDbType.Int) { Value = u.BrandID > 0 ? (object)u.BrandID : DBNull.Value },
                new SqlParameter("@BranchID", SqlDbType.Int) { Value = branchId.HasValue ? (object)branchId.Value : DBNull.Value });
            if (r == null) throw new InvalidOperationException("sp_POS_DineIn_Context returned nothing. Has POS_35_DineIn.sql been run?");
            return r;
        }

        /// <summary>The payment lines, read and checked. False + error when unusable.</summary>
        private static bool ParsePayment(string lines, out DataTable dt, out string error)
        {
            dt = null; error = null;
            if (!POSUser.Current.CanTakePayment) { error = "You do not have permission to take payment."; return false; }

            List<PaymentLineInput> parsed;
            try { parsed = JsonConvert.DeserializeObject<List<PaymentLineInput>>(lines ?? "[]"); }
            catch { error = "The payment lines could not be read."; return false; }

            dt = new DataTable();
            dt.Columns.Add("PaymentTypeID", typeof(int));
            dt.Columns.Add("Amount", typeof(decimal));
            foreach (var l in parsed ?? new List<PaymentLineInput>())
            {
                if (l == null || l.Amount <= 0) continue;
                if (dt.Select("PaymentTypeID = " + l.TypeID).Length > 0) continue;
                dt.Rows.Add(l.TypeID, decimal.Round(l.Amount, 3));
            }
            if (dt.Rows.Count == 0) { error = "Enter an amount against at least one payment type."; return false; }
            return true;
        }

        private static bool TryPay(long invoiceNo, string lines, string reference, out DataRow result, out string error)
        {
            result = null;
            DataTable dt;
            if (!ParsePayment(lines, out dt, out error)) return false;

            var u = POSUser.Current;
            DataRow r = One("sp_POS_TakePaymentSplit",
                new SqlParameter("@InvoiceNo",   SqlDbType.BigInt)        { Value = invoiceNo },
                new SqlParameter("@Lines",       SqlDbType.Structured)    { TypeName = "dbo.TVP_POS_PaymentLine", Value = dt },
                new SqlParameter("@ReferenceNo", SqlDbType.NVarChar, 100) { Value = Db(reference) },
                new SqlParameter("@UserID",      SqlDbType.Int)           { Value = u.UserID },
                new SqlParameter("@UserName",    SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });

            if (r == null || Str(r, "Message") != "Success")
            {
                error = r != null ? Str(r, "ErrorMessage") : "The payment could not be recorded.";
                return false;
            }
            result = r;
            return true;
        }

        private static PayOutcome PayResult(DataRow r, bool freed)
        {
            return new PayOutcome
            {
                Message       = "Success",
                AmountPaid    = r["AmountPaid"],
                AmountDue     = r["AmountDue"],
                ChangeGiven   = r["ChangeGiven"],
                PaymentStatus = Str(r, "PaymentStatus"),
                Freed         = freed
            };
        }

        /// <summary>Runs sp_POS_DineIn_SplitInvoice for the chosen rows (OrderID; a row moves whole).</summary>
        private static bool TrySplit(long invoiceNo, string lines, out long newInvoiceNo, out string error)
        {
            newInvoiceNo = 0; error = null;

            List<SplitLineInput> parsed;
            try { parsed = JsonConvert.DeserializeObject<List<SplitLineInput>>(lines ?? "[]"); }
            catch { error = "The split could not be read."; return false; }

            var dt = new DataTable();
            dt.Columns.Add("OrderID", typeof(long));
            dt.Columns.Add("Quantity", typeof(int));
            foreach (var l in parsed ?? new List<SplitLineInput>())
            {
                if (l == null || l.OrderID <= 0) continue;
                if (dt.Select("OrderID = " + l.OrderID).Length > 0) continue;
                dt.Rows.Add(l.OrderID, Math.Max(1, l.Quantity));
            }
            if (dt.Rows.Count == 0) { error = "Select at least one item to split."; return false; }

            var u = POSUser.Current;
            DataRow r = One("sp_POS_DineIn_SplitInvoice",
                new SqlParameter("@InvoiceNo", SqlDbType.BigInt)        { Value = invoiceNo },
                new SqlParameter("@UserID",    SqlDbType.Int)           { Value = u.UserID },
                new SqlParameter("@UserName",  SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value },
                new SqlParameter("@Lines",     SqlDbType.Structured)    { TypeName = "dbo.TVP_POS_DineInSplitLine", Value = dt });

            if (r == null || Str(r, "Message") != "Success")
            {
                error = r != null ? Str(r, "ErrorMessage") : "The bill could not be split.";
                return false;
            }
            newInvoiceNo = Convert.ToInt64(r["NewInvoiceNo"]);
            return true;
        }

        /// <summary>Tell every screen: the table (Dine-In) or the Take Away list (no table).</summary>
        private static void Notify(int tableId, string reason, string by)
        {
            if (tableId > 0) DineInHub.TableChanged(tableId, reason, by);
            else             DineInHub.TakeAwayChanged(by);
        }

        private static bool CloseIfSettled(int tableId, string reason)
        {
            var u = POSUser.Current;
            DataRow r = One("sp_POS_DineIn_CloseIfSettled",
                new SqlParameter("@TableID",  SqlDbType.Int)           { Value = tableId },
                new SqlParameter("@Reason",   SqlDbType.NVarChar, 50)  { Value = reason },
                new SqlParameter("@UserID",   SqlDbType.Int)           { Value = u.UserID },
                new SqlParameter("@UserName", SqlDbType.NVarChar, 100) { Value = (object)u.UserName ?? DBNull.Value });
            return r != null && r["Freed"] != DBNull.Value && Convert.ToBoolean(r["Freed"]);
        }

        /// <summary>First words of an item's comment when it is packed to take away.</summary>
        private const string TakeAwayTag = "TAKE AWAY";

        /// <param name="allowTakeAwayMark">Dine-In bills only: an item flagged TakeAway
        /// gets the TAKE AWAY tag in front of its comment, which the kitchen ticket prints.</param>
        private static List<POSOrderItem> ParseItems(string json, bool allowTakeAwayMark)
        {
            List<OrderLineInput> parsed;
            try { parsed = JsonConvert.DeserializeObject<List<OrderLineInput>>(json ?? "[]"); }
            catch { return new List<POSOrderItem>(); }

            return (parsed ?? new List<OrderLineInput>())
                .Where(l => l != null && l.ItemID > 0 && l.Quantity > 0)
                .Select((l, i) => new POSOrderItem
                {
                    ItemID         = l.ItemID,
                    CartItemUniqID = i + 1,
                    LineType       = 1,
                    Quantity       = Math.Min(l.Quantity, 999),
                    Price          = null,          // priced from tblItems by the procedure
                    Comments       = TagComment(l.Comments, allowTakeAwayMark && l.TakeAway)
                })
                .ToList();
        }

        private static string TagComment(string comment, bool takeAway)
        {
            string c = string.IsNullOrWhiteSpace(comment) ? null : comment.Trim();
            if (!takeAway) return c;
            return c == null ? TakeAwayTag : TakeAwayTag + " - " + c;
        }

        private static DataRow One(string proc, params SqlParameter[] spa)
        {
            DataSet ds = DB.ExecuteStoredProcDataSet(proc, spa);
            return ds != null && ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0 ? ds.Tables[0].Rows[0] : null;
        }

        private static string CleanMobile(string m)
        {
            if (string.IsNullOrWhiteSpace(m)) return null;
            var digits = new string(m.Where(char.IsDigit).ToArray());
            return digits.Length == 0 ? null : digits;
        }

        private static object Db(string s)
        {
            return string.IsNullOrWhiteSpace(s) ? (object)DBNull.Value : s.Trim();
        }

        private static string Str(DataRow r, string c)
        {
            return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? Convert.ToString(r[c]) : null;
        }

        private static int? IntOrNull(DataRow r, string c)
        {
            return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? (int?)Convert.ToInt32(r[c]) : null;
        }

        /// <summary>SQL detail is only shown while custom errors are off (development).</summary>
        private string Detail(Exception ex)
        {
            return HttpContext != null && IsDevelopment ? " [" + ex.Message + "]" : "";
        }

        private JsonResult Fail(string message)
        {
            return JsonGet(new { Message = "Fail", ErrorMessage = message });
        }

        private JsonResult JsonGet(object data)
        {
            return new LegacyJsonResult(data);
        }

        private static List<Dictionary<string, object>> Rows(DataTable dt)
        {
            var list = new List<Dictionary<string, object>>(dt.Rows.Count);
            foreach (DataRow r in dt.Rows)
            {
                var d = new Dictionary<string, object>(dt.Columns.Count);
                foreach (DataColumn c in dt.Columns)
                    d[c.ColumnName] = r[c] == DBNull.Value ? null
                                    : r[c] is DateTime ? ((DateTime)r[c]).ToString("yyyy-MM-ddTHH:mm:ss")
                                    : r[c];
                list.Add(d);
            }
            return list;
        }
    }

    public class OrderLineInput
    {
        public int ItemID { get; set; }
        public int Quantity { get; set; }
        public string Comments { get; set; }
        public bool TakeAway { get; set; }
    }

    public class PayOutcome
    {
        public string Message { get; set; }
        public object AmountPaid { get; set; }
        public object AmountDue { get; set; }
        public object ChangeGiven { get; set; }
        public string PaymentStatus { get; set; }
        public bool Freed { get; set; }
    }

    public class SplitLineInput
    {
        public long OrderID { get; set; }
        public int Quantity { get; set; }
    }

    public class PositionInput
    {
        public int TableID { get; set; }
        public decimal X { get; set; }
        public decimal Y { get; set; }
    }
}
