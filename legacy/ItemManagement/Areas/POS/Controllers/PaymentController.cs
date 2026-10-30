//==============================================================================
//  Areas/POS/Controllers/PaymentController.cs
//------------------------------------------------------------------------------
//  MyFatoorah payment flow.
//
//      POST CreateLink   create a hosted payment page for an order
//      GET  Callback     customer returns after paying   -> VERIFY, then book
//      GET  Failed       customer returns after failing
//      POST Webhook      MyFatoorah server-to-server     -> VERIFY, then book
//      POST Refresh      operator re-checks a stuck attempt
//
//  A redirect is never treated as proof of payment. Callback, Webhook and
//  Refresh all funnel into Settle(), which calls GetPaymentStatus
//  server-to-server first. Anyone can open the callback URL in a browser; only
//  MyFatoorah can answer the status API.
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Controllers\PaymentController.cs" />
//==============================================================================

using System;
using System.Data;
using System.Data.SqlClient;
using System.Web.Mvc;
using Jar.Helper;

namespace Jar.Areas.POS.Controllers
{
    public class PaymentController : Controller
    {
        // ---------------------------------------------------------------------
        // 1. Create the payment page
        // ---------------------------------------------------------------------
        [HttpPost]
        [POSAuthorize(POSPermission.TakePayment)]
        public JsonResult CreateLink(long invoiceNo, decimal? amount)
        {
            try
            {
                string root = Request.Url.GetLeftPart(UriPartial.Authority);
                string cb   = root + Url.Action("Callback", "Payment", new { area = "POS" });
                string er   = root + Url.Action("Failed",   "Payment", new { area = "POS" });

                var u = POSUser.Current;
                PaymentLinkResult r = PaymentLinkService.Start(
                    invoiceNo, amount, cb, er, u != null ? (int?)u.UserID : null);

                if (!r.Success)
                    return Json(new { Message = "Fail", Detail = r.Error });

                return Json(new
                {
                    Message    = "Success",
                    PaymentUrl = r.PaymentUrl,
                    LinkID     = r.LinkID,
                    Reference  = r.Reference,
                    Amount     = r.Amount,
                    Reused     = r.Reused
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PaymentController", "CreateLink", null);
                return Json(new { Message = "Fail", Detail = "Could not start the payment." });
            }
        }

        // ---------------------------------------------------------------------
        // 2. Customer returns from the payment page
        //
        // No [POSAuthorize]: the person landing here is the CUSTOMER, on their
        // own phone, not a signed-in operator.
        // ---------------------------------------------------------------------
        [HttpGet]
        [AllowAnonymous]
        public ActionResult Callback(string paymentId, string Id)
        {
            string key = !string.IsNullOrWhiteSpace(paymentId) ? paymentId : Id;
            string outcome = Settle(key, "PaymentId");

            ViewBag.Outcome = outcome;
            return View("Result");
        }

        [HttpGet]
        [AllowAnonymous]
        public ActionResult Failed(string paymentId, string Id)
        {
            string key = !string.IsNullOrWhiteSpace(paymentId) ? paymentId : Id;

            // Still verified rather than assumed: a customer can reach the error
            // URL after a payment that actually succeeded, e.g. by going back.
            string outcome = Settle(key, "PaymentId");

            ViewBag.Outcome = outcome == "Paid" ? "Paid" : "Failed";
            return View("Result");
        }

        // ---------------------------------------------------------------------
        // 3. Webhook. The reliable channel - it arrives even if the customer
        //    closes the browser on the payment page.
        // ---------------------------------------------------------------------
        [HttpPost]
        [AllowAnonymous]
        [ValidateInput(false)]
        public ActionResult Webhook()
        {
            try
            {
                string body;
                Request.InputStream.Position = 0;
                using (var rd = new System.IO.StreamReader(Request.InputStream)) body = rd.ReadToEnd();

                // The payload is only a hint about WHICH payment to look at. The
                // authority is GetPaymentStatus, so no signature check is relied
                // upon to decide whether money moved.
                string key = null, keyType = "PaymentId";
                try
                {
                    var o = Newtonsoft.Json.Linq.JObject.Parse(body);
                    var d = o["Data"] ?? o;
                    if (d["PaymentId"] != null)              { key = d["PaymentId"].ToString();         keyType = "PaymentId"; }
                    else if (d["InvoiceId"] != null)         { key = d["InvoiceId"].ToString();         keyType = "InvoiceId"; }
                    else if (d["CustomerReference"] != null) { key = d["CustomerReference"].ToString(); keyType = "CustomerReference"; }
                }
                catch { }

                if (string.IsNullOrWhiteSpace(key))
                    return new HttpStatusCodeResult(400, "No payment identifier in payload.");

                Settle(key, keyType);

                // 200 regardless of our own outcome: a non-2xx makes MyFatoorah
                // retry, and a duplicate delivery is not an error here.
                return new HttpStatusCodeResult(200, "OK");
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PaymentController", "Webhook", null);
                return new HttpStatusCodeResult(200, "OK");
            }
        }

        // ---------------------------------------------------------------------
        // 4. Operator re-checks an attempt that never came back
        // ---------------------------------------------------------------------
        [HttpPost]
        [POSAuthorize(POSPermission.TakePayment)]
        public JsonResult Refresh(string reference)
        {
            if (string.IsNullOrWhiteSpace(reference))
                return Json(new { Message = "Fail", Detail = "No reference." });

            string outcome = Settle(reference, "CustomerReference");
            return Json(new { Message = "Success", Outcome = outcome });
        }

        // =====================================================================
        //  The single place a payment can be booked.
        // =====================================================================
        private string Settle(string key, string keyType)
        {
            try
            {
                MFStatus st = MyFatoorahService.VerifyAsPaid(key, keyType);

                if (!st.Success)
                {
                    DB.AuditTrail(new Exception("MyFatoorah verify failed: " + st.Error),
                                  "POS.PaymentController", "Settle", null);
                    return "Unknown";
                }

                string reference = !string.IsNullOrWhiteSpace(st.CustomerReference)
                                 ? st.CustomerReference
                                 : (keyType == "CustomerReference" ? key : null);

                if (string.IsNullOrWhiteSpace(reference))
                    return "Unknown";       // nothing to match the attempt on

                SqlParameter[] spa =
                {
                    new SqlParameter("@CustomerReference", SqlDbType.VarChar, 60)  { Value = reference },
                    new SqlParameter("@Success",           SqlDbType.Bit)          { Value = st.IsPaid },
                    new SqlParameter("@ProviderPaymentId", SqlDbType.VarChar, 60)  { Value = (object)st.PaymentId ?? DBNull.Value },
                    new SqlParameter("@PaidAmount",        SqlDbType.Decimal)      { Precision = 18, Scale = 3, Value = st.PaidAmount > 0 ? (object)st.PaidAmount : DBNull.Value },
                    new SqlParameter("@FailureReason",     SqlDbType.NVarChar,500) { Value = st.IsPaid ? (object)DBNull.Value : (object)("Status: " + st.InvoiceStatus) },
                    new SqlParameter("@RawResponse",       SqlDbType.NVarChar)     { Value = (object)st.Raw ?? DBNull.Value }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_PaymentLink_Complete", spa);
                string msg = (ds != null && ds.Tables.Count > 0 && ds.Tables[0].Rows.Count > 0)
                           ? Convert.ToString(ds.Tables[0].Rows[0]["Message"]) : "Unknown";

                // Success and Duplicate both mean the money is booked; only the
                // first caller actually wrote it.
                if (msg == "Success" || msg == "Duplicate") return "Paid";
                if (msg == "Failed") return "Failed";
                return "Unknown";
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PaymentController", "Settle", null);
                return "Unknown";
            }
        }

        private static decimal Dec(DataRow r, string c)
        {
            return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? Convert.ToDecimal(r[c]) : 0m;
        }
    }
}
