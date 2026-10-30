//==============================================================================
//  Helper/PaymentLinkService.cs
//------------------------------------------------------------------------------
//  The single place a payment link is created.
//
//  Both entry points use it:
//      POS      Areas/POS/Controllers/PaymentController.CreateLink   (operator)
//      Checkout Controllers/ItemsViewController.StartOnlinePayment   (customer)
//
//  They deliberately share one implementation. Two copies of a money path drift
//  - one gets an idempotency guard or an amount check and the other does not -
//  and the difference only shows up as a double charge in production.
//
//  Add to the .csproj:
//      <Compile Include="Helper\PaymentLinkService.cs" />
//==============================================================================

using System;
using System.Data;
using System.Data.SqlClient;

namespace Jar.Helper
{
    public class PaymentLinkResult
    {
        public bool Success { get; set; }
        public string PaymentUrl { get; set; }
        public long LinkID { get; set; }
        public string Reference { get; set; }
        public decimal Amount { get; set; }
        public bool Reused { get; set; }
        public string Error { get; set; }
    }

    public static class PaymentLinkService
    {
        /// <summary>
        /// Creates (or reuses) a MyFatoorah payment page for an order.
        /// amount = null means "whatever is still owed".
        /// </summary>
        public static PaymentLinkResult Start(
            long invoiceNo,
            decimal? amount,
            string callBackUrl,
            string errorUrl,
            int? createdByUserId)
        {
            // Which gateway - if any - this order's payment method is paid
            // through. Read from tblInvoicePaymentType.Provider, so switching a
            // method on or off is a data change, not a redeploy.
            //
            // Before this, ANY method flagged IsOnline was handed to MyFatoorah.
            // That is how choosing cash ended at "MyFatoorah.ApiToken is not
            // set": one wrong flag on the cash row was enough. A method now
            // reaches a gateway only when it names one.
            string provider = GetProvider(invoiceNo);

            if (string.IsNullOrEmpty(provider))
                return new PaymentLinkResult
                {
                    Success = false,
                    Error = "This payment method is not linked to a payment gateway."
                };

            if (!provider.Equals("MyFatoorah", StringComparison.OrdinalIgnoreCase))
                return new PaymentLinkResult
                {
                    Success = false,
                    Error = "Payment gateway '" + provider + "' is not supported yet."
                };

            string why;
            if (!MyFatoorahService.IsConfigured(out why))
                return new PaymentLinkResult { Success = false, Error = why };

            // Header, for the balance due and the customer's details
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderDetails",
                new[] { new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = invoiceNo } });

            if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                return new PaymentLinkResult { Success = false, Error = "Order not found." };

            DataRow h = ds.Tables[0].Rows[0];
            decimal due = Dec(h, "NetPayable") - Dec(h, "AmountPaid");
            decimal amt = (amount.HasValue && amount.Value > 0) ? amount.Value : due;

            if (amt <= 0)
                return new PaymentLinkResult { Success = false, Error = "Nothing left to pay on this order." };

            // Unique per attempt. MyFatoorah echoes it back on the callback and
            // the webhook, so it must never be reused across attempts.
            string reference = "INV" + invoiceNo
                             + "-" + DateTime.UtcNow.ToString("yyMMddHHmmss")
                             + "-" + Guid.NewGuid().ToString("N").Substring(0, 6);

            SqlParameter[] cp =
            {
                new SqlParameter("@InvoiceNo",         SqlDbType.BigInt)      { Value = invoiceNo },
                new SqlParameter("@CustomerReference", SqlDbType.VarChar, 60) { Value = reference },
                new SqlParameter("@Amount",            SqlDbType.Decimal)     { Precision = 18, Scale = 3, Value = amt },
                new SqlParameter("@CurrencyIso",       SqlDbType.VarChar, 5)  { Value = MyFatoorahService.CurrencyIso },
                new SqlParameter("@Provider",          SqlDbType.VarChar, 30) { Value = "MyFatoorah" },
                new SqlParameter("@PaymentTypeID",     SqlDbType.Int)         { Value = DBNull.Value },
                new SqlParameter("@CreatedBy",         SqlDbType.Int)         { Value = createdByUserId.HasValue ? (object)createdByUserId.Value : DBNull.Value }
            };

            DataSet cds = DB.ExecuteStoredProcDataSet("sp_POS_PaymentLink_Create", cp);
            if (cds == null || cds.Tables.Count == 0 || cds.Tables[0].Rows.Count == 0)
                return new PaymentLinkResult { Success = false, Error = "Could not record the payment attempt." };

            DataRow cr = cds.Tables[0].Rows[0];
            string msg = Convert.ToString(cr["Message"]);

            if (msg == "Fail")
                return new PaymentLinkResult { Success = false, Error = Convert.ToString(cr["ErrorMessage"]) };

            long linkId = Convert.ToInt64(cr["LinkID"]);

            // An unfinished attempt for the same amount is reused rather than
            // stacked: two live payment links for one order is how an order
            // ends up paid twice.
            if (msg == "Reused")
            {
                DataSet ex = DB.ExecuteStoredProcDataSet("sp_POS_PaymentLink_Get",
                    new[] { new SqlParameter("@LinkID", SqlDbType.BigInt) { Value = linkId } });

                if (ex != null && ex.Tables.Count > 0 && ex.Tables[0].Rows.Count > 0)
                {
                    string existing = Convert.ToString(ex.Tables[0].Rows[0]["PaymentUrl"]);
                    string existingRef = Convert.ToString(ex.Tables[0].Rows[0]["CustomerReference"]);
                    if (!string.IsNullOrEmpty(existing))
                        return new PaymentLinkResult
                        {
                            Success = true, PaymentUrl = existing, LinkID = linkId,
                            Reference = existingRef, Amount = amt, Reused = true
                        };
                }
            }

            MFPaymentLink link = MyFatoorahService.CreatePaymentLink(
                amt, reference,
                Convert.ToString(h["CustomerName"]),
                h.Table.Columns.Contains("Mobile") ? Convert.ToString(h["Mobile"]) : null,
                null, callBackUrl, errorUrl, null);

            if (!link.Success)
            {
                // Close the attempt off, so a failed gateway call does not leave
                // a Pending row that blocks the next try for 30 minutes.
                DB.ExecuteStoredProc("sp_POS_PaymentLink_Complete", new[]
                {
                    new SqlParameter("@CustomerReference", SqlDbType.VarChar, 60)  { Value = reference },
                    new SqlParameter("@Success",           SqlDbType.Bit)          { Value = false },
                    new SqlParameter("@FailureReason",     SqlDbType.NVarChar,500) { Value = (object)link.Error ?? DBNull.Value },
                    new SqlParameter("@RawResponse",       SqlDbType.NVarChar)     { Value = (object)link.Raw ?? DBNull.Value }
                });
                return new PaymentLinkResult { Success = false, Error = link.Error };
            }

            DB.ExecuteStoredProc("sp_POS_PaymentLink_SetProvider", new[]
            {
                new SqlParameter("@LinkID",            SqlDbType.BigInt)         { Value = linkId },
                new SqlParameter("@ProviderInvoiceId", SqlDbType.VarChar, 60)    { Value = (object)link.InvoiceId ?? DBNull.Value },
                new SqlParameter("@PaymentUrl",        SqlDbType.NVarChar, 1000) { Value = (object)link.PaymentUrl ?? DBNull.Value },
                new SqlParameter("@RawResponse",       SqlDbType.NVarChar)       { Value = (object)link.Raw ?? DBNull.Value }
            });

            return new PaymentLinkResult
            {
                Success = true, PaymentUrl = link.PaymentUrl, LinkID = linkId,
                Reference = reference, Amount = amt
            };
        }

        /// <summary>Is this order's chosen payment method an online one?</summary>
        public static bool IsOnlineOrder(long invoiceNo)
        {
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderDetails",
                new[] { new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = invoiceNo } });

            if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0) return false;

            // Read the method off the ORDER, not off anything the browser sent:
            // the invoice is the record of what was chosen.
            DataRow h = ds.Tables[0].Rows[0];
            int typeId = h["PaymentType"] != DBNull.Value ? Convert.ToInt32(h["PaymentType"]) : 0;

            object v = DB.ExecuteStoredProcScaler("sp_POS_IsOnlinePaymentType",
                new[] { new SqlParameter("@PaymentTypeID", SqlDbType.Int) { Value = typeId } });

            return v != null && v != DBNull.Value && Convert.ToInt32(v) == 1;
        }

        /// <summary>
        /// The gateway name for the method recorded on the invoice, or null when
        /// the method is cash, inactive, or has no gateway configured.
        ///
        /// Falls back to MyFatoorah only when the Provider column does not exist
        /// yet (POS_22 not run), so an existing install keeps working until the
        /// script is applied.
        /// </summary>
        private static string GetProvider(long invoiceNo)
        {
            DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderDetails",
                new[] { new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = invoiceNo } });

            if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0) return null;

            DataRow h = ds.Tables[0].Rows[0];
            int typeId = h["PaymentType"] != DBNull.Value ? Convert.ToInt32(h["PaymentType"]) : 0;

            DataSet pds;
            try
            {
                pds = DB.ExecuteStoredProcDataSet("sp_POS_GetPaymentProvider",
                    new[] { new SqlParameter("@PaymentTypeID", SqlDbType.Int) { Value = typeId } });
            }
            catch
            {
                // POS_22 has not been run. Keep the old behaviour rather than
                // breaking payments that work today.
                return IsOnlineOrder(invoiceNo) ? "MyFatoorah" : null;
            }

            if (pds == null || pds.Tables.Count == 0 || pds.Tables[0].Rows.Count == 0) return null;

            DataRow pr = pds.Tables[0].Rows[0];
            if (!pr.Table.Columns.Contains("Provider") || pr["Provider"] == DBNull.Value) return null;

            string provider = Convert.ToString(pr["Provider"]);
            return string.IsNullOrWhiteSpace(provider) ? null : provider.Trim();
        }

        private static decimal Dec(DataRow r, string c)
        {
            return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? Convert.ToDecimal(r[c]) : 0m;
        }
    }
}
