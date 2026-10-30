#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
//==============================================================================
//  Helper/MyFatoorahService.cs
//------------------------------------------------------------------------------
//  MyFatoorah v2 client. Two calls are used:
//
//      POST {BaseUrl}/v2/SendPayment       create a hosted payment page
//      POST {BaseUrl}/v2/GetPaymentStatus  verify what actually happened
//
//  Every setting comes from Web.config appSettings, so nothing here needs a
//  rebuild to move between the test and live gateways.
//
//  THE RULE THIS FILE EXISTS TO ENFORCE
//  ------------------------------------
//  A redirect back to CallBackUrl is NOT proof of payment. The customer's
//  browser can be sent to that URL by anyone, including by typing it. Payment
//  is only ever booked after GetPaymentStatus is called server-to-server and
//  MyFatoorah itself reports the invoice as Paid. VerifyAsPaid below is the
//  only path that returns a payable result.
//
//  Add to the .csproj:
//      <Compile Include="Helper\MyFatoorahService.cs" />
//==============================================================================

using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace HRMS.Web.Areas.Items.Legacy
{
    public class MFPaymentLink
    {
        public bool Success { get; set; }
        public string InvoiceId { get; set; }      // MyFatoorah's invoice id
        public string PaymentUrl { get; set; }
        public string Error { get; set; }
        public string Raw { get; set; }
    }

    public class MFStatus
    {
        public bool Success { get; set; }          // the API call worked
        public bool IsPaid { get; set; }           // MyFatoorah says Paid
        public string InvoiceStatus { get; set; }  // Paid | Pending | Failed | Expired
        public string InvoiceId { get; set; }
        public string PaymentId { get; set; }      // transaction reference
        public string CustomerReference { get; set; }
        public decimal PaidAmount { get; set; }
        public string Currency { get; set; }
        public string Error { get; set; }
        public string Raw { get; set; }
    }

    public static class MyFatoorahService
    {
        // ---------------------------------------------------------------- config

        private static string Cfg(string key, string fallback = null)
        {
            string v = ConfigurationManager.AppSettings["MyFatoorah." + key];
            return string.IsNullOrWhiteSpace(v) ? fallback : v.Trim();
        }

        public static bool Enabled
        {
            get
            {
                bool b;
                return bool.TryParse(Cfg("Enabled", "false"), out b) && b;
            }
        }

        public static string BaseUrl      { get { return (Cfg("BaseUrl", "https://apitest.myfatoorah.com")).TrimEnd('/'); } }
        public static string ApiToken     { get { return Cfg("ApiToken", ""); } }
        public static string CurrencyIso  { get { return Cfg("CurrencyIso", "KWD"); } }
        public static string Language     { get { return Cfg("Language", "EN"); } }
        public static string NotifyOption { get { return Cfg("NotificationOption", "LNK"); } }
        public static string CallBackUrl  { get { return Cfg("CallBackUrl", ""); } }
        public static string ErrorUrl     { get { return Cfg("ErrorUrl", ""); } }
        public static string WebhookSecret{ get { return Cfg("WebhookSecret", ""); } }

        public static int TimeoutMs
        {
            get { int n; return int.TryParse(Cfg("TimeoutMs", "20000"), out n) ? n : 20000; }
        }

        /// <summary>True when the integration is switched on and usable.</summary>
        public static bool IsConfigured(out string why)
        {
            if (!Enabled)                            { why = "MyFatoorah is disabled (MyFatoorah.Enabled)."; return false; }
            if (string.IsNullOrWhiteSpace(ApiToken)) { why = "MyFatoorah.ApiToken is not set.";              return false; }
            if (string.IsNullOrWhiteSpace(BaseUrl))  { why = "MyFatoorah.BaseUrl is not set.";               return false; }
            why = null;
            return true;
        }

        // ------------------------------------------------------------- SendPayment

        /// <summary>
        /// Creates a hosted payment page and returns its URL.
        /// customerReference is echoed back by MyFatoorah on the callback and
        /// the webhook; it is how a result is matched to our attempt row.
        /// </summary>
        public static MFPaymentLink CreatePaymentLink(
            decimal amount,
            string customerReference,
            string customerName,
            string customerMobile,
            string customerEmail,
            string callBackUrl,
            string errorUrl,
            List<KeyValuePair<string, decimal>> items = null)
        {
            string why;
            if (!IsConfigured(out why)) return new MFPaymentLink { Success = false, Error = why };

            var body = new Dictionary<string, object>
            {
                { "InvoiceValue",       amount },
                { "CustomerName",       Trunc(customerName, 100) },
                { "NotificationOption", NotifyOption },      // LNK = return a link, do not send SMS/email
                { "Language",           Language },
                { "DisplayCurrencyIso", CurrencyIso },
                { "CustomerReference",  customerReference },
                { "CallBackUrl",        string.IsNullOrWhiteSpace(callBackUrl) ? CallBackUrl : callBackUrl },
                { "ErrorUrl",           string.IsNullOrWhiteSpace(errorUrl)    ? ErrorUrl    : errorUrl }
            };

            // Mobile must be split from its country code, and MyFatoorah rejects
            // a mobile that carries '+' or dashes.
            if (!string.IsNullOrWhiteSpace(customerMobile))
            {
                string digits = System.Text.RegularExpressions.Regex.Replace(customerMobile, @"[^0-9]", "");
                string cc = Cfg("MobileCountryCode", "965");
                if (digits.StartsWith(cc) && digits.Length > cc.Length) digits = digits.Substring(cc.Length);
                if (digits.Length >= 6)
                {
                    body["MobileCountryCode"] = cc;
                    body["CustomerMobile"]    = digits;
                }
            }

            if (!string.IsNullOrWhiteSpace(customerEmail))
                body["CustomerEmail"] = customerEmail;

            if (items != null && items.Count > 0)
            {
                var arr = new List<object>();
                foreach (var it in items)
                    arr.Add(new { ItemName = Trunc(it.Key, 100), Quantity = 1, UnitPrice = it.Value });
                body["InvoiceItems"] = arr;
            }

            string raw;
            string err = Post("/v2/SendPayment", body, out raw);
            if (err != null) return new MFPaymentLink { Success = false, Error = err, Raw = raw };

            try
            {
                var o = JObject.Parse(raw);
                if (o["IsSuccess"] == null || !(bool)o["IsSuccess"])
                    return new MFPaymentLink { Success = false, Error = ReadError(o), Raw = raw };

                var d = o["Data"];
                return new MFPaymentLink
                {
                    Success    = true,
                    InvoiceId  = d["InvoiceId"] != null ? d["InvoiceId"].ToString() : null,
                    PaymentUrl = d["InvoiceURL"] != null ? d["InvoiceURL"].ToString() : null,
                    Raw        = raw
                };
            }
            catch (Exception ex)
            {
                return new MFPaymentLink { Success = false, Error = "Unreadable response: " + ex.Message, Raw = raw };
            }
        }

        // --------------------------------------------------------- GetPaymentStatus

        /// <summary>
        /// Asks MyFatoorah what actually happened. keyType is
        /// "InvoiceId", "PaymentId" or "CustomerReference".
        ///
        /// This is the ONLY thing that may be treated as proof of payment.
        /// </summary>
        public static MFStatus VerifyAsPaid(string key, string keyType)
        {
            string why;
            if (!IsConfigured(out why)) return new MFStatus { Success = false, Error = why };
            if (string.IsNullOrWhiteSpace(key)) return new MFStatus { Success = false, Error = "No key supplied." };

            var body = new Dictionary<string, object> { { "Key", key }, { "KeyType", keyType } };

            string raw;
            string err = Post("/v2/GetPaymentStatus", body, out raw);
            if (err != null) return new MFStatus { Success = false, Error = err, Raw = raw };

            try
            {
                var o = JObject.Parse(raw);
                if (o["IsSuccess"] == null || !(bool)o["IsSuccess"])
                    return new MFStatus { Success = false, Error = ReadError(o), Raw = raw };

                var d = o["Data"];
                string status = d["InvoiceStatus"] != null ? d["InvoiceStatus"].ToString() : "";

                var res = new MFStatus
                {
                    Success           = true,
                    InvoiceStatus     = status,
                    IsPaid            = string.Equals(status, "Paid", StringComparison.OrdinalIgnoreCase),
                    InvoiceId         = d["InvoiceId"] != null ? d["InvoiceId"].ToString() : null,
                    CustomerReference = d["CustomerReference"] != null ? d["CustomerReference"].ToString() : null,
                    Raw               = raw
                };

                // Take the amount and reference from the SUCCEEDED transaction.
                // An invoice can carry several attempts, and the failed ones
                // also have amounts - reading the first would credit a figure
                // from a transaction that never completed.
                var txns = d["InvoiceTransactions"] as JArray;
                if (txns != null)
                {
                    foreach (var t in txns)
                    {
                        string ts = t["TransactionStatus"] != null ? t["TransactionStatus"].ToString() : "";
                        if (!string.Equals(ts, "Succss", StringComparison.OrdinalIgnoreCase) &&   // MyFatoorah's own spelling
                            !string.Equals(ts, "Success", StringComparison.OrdinalIgnoreCase))
                            continue;

                        res.PaymentId = t["PaymentId"] != null ? t["PaymentId"].ToString() : null;
                        res.Currency  = t["Currency"]  != null ? t["Currency"].ToString()  : null;

                        decimal amt;
                        if (t["TransactionValue"] != null &&
                            decimal.TryParse(t["TransactionValue"].ToString(),
                                             System.Globalization.NumberStyles.Any,
                                             System.Globalization.CultureInfo.InvariantCulture, out amt))
                            res.PaidAmount = amt;

                        break;
                    }
                }
                return res;
            }
            catch (Exception ex)
            {
                return new MFStatus { Success = false, Error = "Unreadable response: " + ex.Message, Raw = raw };
            }
        }

        // ------------------------------------------------------------------ plumbing

        /// <summary>Returns null on success, or an error string. raw always gets the body.</summary>
        private static string Post(string path, object body, out string raw)
        {
            raw = null;
            try
            {
                // Same trap as the OSM lookup: .NET Framework honours whatever
                // SecurityProtocol was left at, and many app pools still default
                // to TLS 1.0. MyFatoorah is TLS 1.2+, so without this the call
                // dies with "Could not create SSL/TLS secure channel".
                ServicePointManager.SecurityProtocol =
                    (SecurityProtocolType)3072 | (SecurityProtocolType)12288;

                var req = (HttpWebRequest)WebRequest.Create(BaseUrl + path);
                req.Method      = "POST";
                req.ContentType = "application/json";
                req.Accept      = "application/json";
                req.Timeout     = TimeoutMs;
                req.ReadWriteTimeout = TimeoutMs;
                req.Headers["Authorization"] = "Bearer " + ApiToken;

                byte[] payload = Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(body));
                req.ContentLength = payload.Length;
                using (var s = req.GetRequestStream()) s.Write(payload, 0, payload.Length);

                using (var resp = (HttpWebResponse)req.GetResponse())
                using (var rd = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                    raw = rd.ReadToEnd();

                return null;
            }
            catch (WebException wex)
            {
                // MyFatoorah returns its validation errors in the body of a 4xx,
                // so the body is worth more than the status line.
                var r = wex.Response as HttpWebResponse;
                if (r != null)
                {
                    try
                    {
                        using (var rd = new StreamReader(r.GetResponseStream(), Encoding.UTF8))
                            raw = rd.ReadToEnd();
                    }
                    catch { }

                    if (!string.IsNullOrEmpty(raw))
                    {
                        try { return ReadError(JObject.Parse(raw)); } catch { }
                    }
                    return "HTTP " + (int)r.StatusCode + " " + wex.Message;
                }
                return wex.Status + ": " + wex.Message;
            }
            catch (Exception ex)
            {
                return ex.GetType().Name + ": " + ex.Message;
            }
        }

        private static string ReadError(JObject o)
        {
            var sb = new StringBuilder();
            if (o["Message"] != null) sb.Append(o["Message"].ToString());

            var ve = o["ValidationErrors"] as JArray;
            if (ve != null)
            {
                foreach (var e in ve)
                {
                    if (sb.Length > 0) sb.Append(" | ");
                    sb.Append(e["Name"]).Append(": ").Append(e["Error"]);
                }
            }
            return sb.Length > 0 ? sb.ToString() : "MyFatoorah rejected the request.";
        }

        private static string Trunc(string s, int n)
        {
            if (string.IsNullOrEmpty(s)) return s;
            return s.Length <= n ? s : s.Substring(0, n);
        }
    }
}
