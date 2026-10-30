#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
//==============================================================================
//  Helper/WhatsAppService.cs
//------------------------------------------------------------------------------
//  Sends the customer a WhatsApp message when their order is placed.
//
//  Every setting comes from Web.config appSettings, so the provider, the
//  credentials and the wording can all change without a rebuild - same rule as
//  MyFatoorahService.cs, which this file is modelled on.
//
//  OFF BY DEFAULT. With WhatsApp.Enabled missing or false nothing here does
//  anything at all, so deploying this cannot change behaviour until someone
//  fills the settings in.
//
//  THE PLATFORM RULE THIS FILE HAS TO WORK AROUND
//  ----------------------------------------------
//  WhatsApp does NOT let a business send free-form text to a customer out of
//  the blue. A business-initiated message must use a message TEMPLATE that
//  Meta has approved in advance; free-form is only allowed inside a 24-hour
//  window after the customer messages you first. An order confirmation is
//  business-initiated, so on the official API it has to be a template.
//
//  Hence two modes:
//
//    Provider = Meta   Official WhatsApp Cloud API. Sends an approved template
//                      with positional parameters. This is the correct choice
//                      for order confirmations on the official API.
//
//    Provider = Text   One POST of a plain text message to whatever URL is
//                      configured. Covers the third-party bridges (UltraMsg,
//                      Wati, 360dialog and friends), which accept free-form,
//                      and also covers Meta itself inside the 24-hour window.
//                      The request body is a template string in config, so a
//                      different provider is a config change, not a code one.
//
//  WHAT TO REGISTER WITH META (Provider = Meta)
//  --------------------------------------------
//  Create a template named by WhatsApp.TemplateName whose body is exactly:
//
//      Hi {{1}}, your order {{2}} is confirmed. Total: {{3}}. Thank you!
//
//  Three positional parameters, in this order:
//      {{1}} customer name      {{2}} order number      {{3}} total + currency
//
//  Keep it to three and keep it factual - templates are reviewed by Meta and
//  promotional wording is what gets them rejected. If you change the number of
//  parameters in the template you must change BuildTemplateParams below to
//  match, or Meta rejects the send with error 132000 (parameter count mismatch).
//
//  Add to the .csproj:
//      <Compile Include="Helper\WhatsAppService.cs" />
//==============================================================================

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using Newtonsoft.Json;

namespace HRMS.Web.Areas.Items.Legacy
{
    /// <summary>Outcome of one send. Never thrown - always returned.</summary>
    public class WhatsAppResult
    {
        public bool Sent { get; set; }
        public bool Skipped { get; set; }      // disabled, or nothing to send to
        public string Reason { get; set; }     // why it was skipped, or why it failed
        public string To { get; set; }         // the number actually dialled
        public string Raw { get; set; }        // provider response body, for the log
    }

    public static class WhatsAppService
    {
        // ---------------------------------------------------------------- config
        private static string Cfg(string key, string fallback = null)
        {
            string v = ConfigurationManager.AppSettings[key];
            return string.IsNullOrWhiteSpace(v) ? fallback : v.Trim();
        }

        private static bool CfgBool(string key, bool fallback)
        {
            bool b;
            return bool.TryParse(Cfg(key), out b) ? b : fallback;
        }

        private static int CfgInt(string key, int fallback)
        {
            int i;
            return int.TryParse(Cfg(key), out i) ? i : fallback;
        }

        public static bool Enabled { get { return CfgBool("WhatsApp.Enabled", false); } }

        private static string Provider { get { return Cfg("WhatsApp.Provider", "Meta"); } }
        private static int TimeoutMs { get { return CfgInt("WhatsApp.TimeoutMs", 15000); } }
        private static string Currency { get { return Cfg("WhatsApp.Currency", "KD"); } }
        private static string DefaultCountryCode { get { return Cfg("WhatsApp.DefaultCountryCode", "965"); } }

        // Meta Cloud API
        private static string MetaBaseUrl { get { return Cfg("WhatsApp.Meta.BaseUrl", "https://graph.facebook.com/v21.0"); } }
        private static string MetaPhoneNumberId { get { return Cfg("WhatsApp.Meta.PhoneNumberId"); } }
        private static string MetaAccessToken { get { return Cfg("WhatsApp.Meta.AccessToken"); } }
        private static string MetaTemplateName { get { return Cfg("WhatsApp.Meta.TemplateName", "order_confirmation"); } }
        private static string MetaTemplateLang { get { return Cfg("WhatsApp.Meta.TemplateLanguage", "en"); } }

        /// <summary>
        /// How many positional parameters the approved template declares. Meta
        /// rejects the send outright (error 132000) if what we pass does not
        /// match the template exactly, so this has to be able to change without
        /// a rebuild.
        ///
        /// Set it to 0 to send a template that takes no parameters. That is the
        /// case for Meta's built-in "hello_world", which is the only template
        /// that exists before you have had one approved - so 0 is what makes a
        /// first end-to-end smoke test possible.
        /// </summary>
        private static int MetaTemplateParamCount { get { return CfgInt("WhatsApp.Meta.TemplateParameterCount", 3); } }

        // Generic text provider
        private static string TextUrl { get { return Cfg("WhatsApp.Text.Url"); } }
        private static string TextBodyTemplate { get { return Cfg("WhatsApp.Text.BodyTemplate"); } }
        private static string TextAuthHeader { get { return Cfg("WhatsApp.Text.AuthorizationHeader"); } }
        private static string TextContentType { get { return Cfg("WhatsApp.Text.ContentType", "application/json"); } }

        /// <summary>
        /// The words the customer reads, in Text mode. Placeholders below are
        /// substituted; anything else is sent through untouched, so the wording
        /// and the language are a config change.
        /// </summary>
        private static string MessageTemplate
        {
            get
            {
                return Cfg("WhatsApp.MessageTemplate",
                    "Hi {CustomerName}, your order {OrderNo} is confirmed. " +
                    "Total: {Total} {Currency}. Tracking code: {TrackingCode}. Thank you!");
            }
        }

        // ------------------------------------------------------------------ send

        /// <summary>
        /// Sends one order confirmation. Does not throw: an unreachable provider,
        /// a bad token or a malformed number must never affect an order that is
        /// already committed, so every failure comes back as a result to log.
        /// </summary>
        public static WhatsAppResult SendOrderConfirmation(
            string mobile, string customerName, string orderNo,
            decimal total, string trackingCode)
        {
            var result = new WhatsAppResult();

            try
            {
                if (!Enabled)
                {
                    result.Skipped = true;
                    result.Reason = "WhatsApp.Enabled is false";
                    return result;
                }

                string to = NormaliseNumber(mobile);
                if (string.IsNullOrEmpty(to))
                {
                    // Mobile is optional on a pickup order, so this is a normal
                    // outcome rather than a fault.
                    result.Skipped = true;
                    result.Reason = "no usable mobile number on the order";
                    return result;
                }
                result.To = to;

                // Blank rather than the literal word "null" if the name is
                // missing - the customer sees this text.
                string name = string.IsNullOrWhiteSpace(customerName) ? "there" : customerName.Trim();
                string amount = total.ToString("0.000", CultureInfo.InvariantCulture);
                string order = string.IsNullOrWhiteSpace(orderNo) ? "" : orderNo.Trim();
                string tracking = string.IsNullOrWhiteSpace(trackingCode) ? "" : trackingCode.Trim();

                if (Provider.Equals("Text", StringComparison.OrdinalIgnoreCase))
                    return SendViaText(result, to, name, order, amount, tracking);

                return SendViaMeta(result, to, name, order, amount);
            }
            catch (Exception ex)
            {
                // Belt and braces. Nothing above should throw, but this method is
                // called from a path where an escape would be expensive.
                result.Sent = false;
                result.Reason = "unexpected: " + ex.Message;
                return result;
            }
        }

        // ---------------------------------------------------------- Meta Cloud API
        private static WhatsAppResult SendViaMeta(
            WhatsAppResult result, string to, string name, string order, string amount)
        {
            if (string.IsNullOrEmpty(MetaPhoneNumberId) || string.IsNullOrEmpty(MetaAccessToken))
            {
                result.Skipped = true;
                result.Reason = "WhatsApp.Meta.PhoneNumberId / AccessToken not configured";
                return result;
            }

            // Built as dictionaries rather than anonymous types so "components"
            // can be left OUT entirely for a zero-parameter template. Sending
            // an empty components array instead is not the same thing to Meta.
            var template = new Dictionary<string, object>
            {
                { "name", MetaTemplateName },
                { "language", new { code = MetaTemplateLang } }
            };

            object[] parameters = BuildTemplateParams(name, order, amount);
            if (parameters.Length > 0)
            {
                template["components"] = new object[]
                {
                    new { type = "body", parameters = parameters }
                };
            }

            var body = new Dictionary<string, object>
            {
                { "messaging_product", "whatsapp" },
                { "recipient_type", "individual" },
                { "to", to },
                { "type", "template" },
                { "template", template }
            };

            string url = MetaBaseUrl.TrimEnd('/') + "/" + MetaPhoneNumberId + "/messages";

            string raw;
            string err = Post(url, JsonConvert.SerializeObject(body),
                              "application/json", "Bearer " + MetaAccessToken, out raw);

            result.Raw = raw;
            result.Sent = err == null;
            result.Reason = err;
            return result;
        }

        /// <summary>
        /// Positional body parameters, in the order the approved template
        /// declares them. Meta matches these by POSITION, not by name - reorder
        /// this and the customer gets their order number where their name should
        /// be, with no error from the API.
        /// </summary>
        private static object[] BuildTemplateParams(string name, string order, string amount)
        {
            var all = new object[]
            {
                new { type = "text", text = name },                        // {{1}}
                new { type = "text", text = order },                       // {{2}}
                new { type = "text", text = amount + " " + Currency }      // {{3}}
            };

            int want = MetaTemplateParamCount;
            if (want <= 0) return new object[0];
            if (want >= all.Length) return all;

            var trimmed = new object[want];
            Array.Copy(all, trimmed, want);
            return trimmed;
        }

        // ------------------------------------------------------- generic text POST
        private static WhatsAppResult SendViaText(
            WhatsAppResult result, string to, string name, string order, string amount, string tracking)
        {
            if (string.IsNullOrEmpty(TextUrl) || string.IsNullOrEmpty(TextBodyTemplate))
            {
                result.Skipped = true;
                result.Reason = "WhatsApp.Text.Url / BodyTemplate not configured";
                return result;
            }

            string text = MessageTemplate
                .Replace("{CustomerName}", name)
                .Replace("{OrderNo}", order)
                .Replace("{Total}", amount)
                .Replace("{Currency}", Currency)
                .Replace("{TrackingCode}", tracking);

            // JsonConvert.ToString gives a correctly quoted and escaped JSON
            // string; the outer quotes are trimmed because the body template
            // supplies its own. Without this a message containing a quote or a
            // newline would produce a malformed request body.
            string jsonText = JsonConvert.ToString(text);
            jsonText = jsonText.Substring(1, jsonText.Length - 2);

            string body = TextBodyTemplate
                .Replace("{TO}", to)
                .Replace("{TEXT}", jsonText);

            string raw;
            string err = Post(TextUrl, body, TextContentType, TextAuthHeader, out raw);

            result.Raw = raw;
            result.Sent = err == null;
            result.Reason = err;
            return result;
        }

        // ------------------------------------------------------------------ http
        /// <summary>Returns null on success, or an error string. raw always gets the body.</summary>
        private static string Post(string url, string payload, string contentType,
                                   string authorization, out string raw)
        {
            raw = null;
            try
            {
                // Same trap as MyFatoorahService: .NET Framework honours whatever
                // SecurityProtocol the app pool was left at, and many still
                // default to TLS 1.0. graph.facebook.com is TLS 1.2+, so without
                // this the call dies with "Could not create SSL/TLS secure channel".
                ServicePointManager.SecurityProtocol =
                    (SecurityProtocolType)3072 | (SecurityProtocolType)12288;

                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "POST";
                req.ContentType = contentType;
                req.Accept = "application/json";
                req.Timeout = TimeoutMs;
                req.ReadWriteTimeout = TimeoutMs;
                if (!string.IsNullOrEmpty(authorization))
                    req.Headers["Authorization"] = authorization;

                byte[] bytes = Encoding.UTF8.GetBytes(payload);
                req.ContentLength = bytes.Length;
                using (var s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);

                using (var resp = (HttpWebResponse)req.GetResponse())
                using (var rd = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                    raw = rd.ReadToEnd();

                return null;
            }
            catch (WebException wex)
            {
                // Meta puts the useful part - "template does not exist",
                // "parameter count mismatch", "number not on WhatsApp" - in the
                // body of a 4xx, so the body is worth far more than the status.
                var r = wex.Response as HttpWebResponse;
                if (r != null)
                {
                    try
                    {
                        using (var rd = new StreamReader(r.GetResponseStream(), Encoding.UTF8))
                            raw = rd.ReadToEnd();
                    }
                    catch { }
                }
                return "http: " + wex.Message + (string.IsNullOrEmpty(raw) ? "" : " | " + raw);
            }
            catch (Exception ex)
            {
                return "http: " + ex.Message;
            }
        }

        // --------------------------------------------------------------- numbers
        /// <summary>
        /// Turns whatever was typed into the order form into the digits-only
        /// international form WhatsApp expects (e.g. 96512345678 - no plus, no
        /// spaces). Returns null when there is nothing usable.
        ///
        /// tblCustomer.Mobile is free text, so this has to cope with "1234 5678",
        /// "+965-1234-5678", "0096512345678" and "96512345678" all meaning the
        /// same person.
        /// </summary>
        public static string NormaliseNumber(string mobile)
        {
            if (string.IsNullOrWhiteSpace(mobile)) return null;

            var digits = new StringBuilder();
            foreach (char c in mobile)
                if (c >= '0' && c <= '9') digits.Append(c);

            string n = digits.ToString();
            if (n.Length == 0) return null;

            // 00 is the other way of writing a leading +.
            if (n.StartsWith("00")) n = n.Substring(2);

            string cc = DefaultCountryCode;
            if (!string.IsNullOrEmpty(cc))
            {
                // A local number gets the country code put in front of it. The
                // length guard is what stops a local number that happens to
                // begin with the country code's digits from being left short:
                // only treat it as already-prefixed if what follows is a
                // plausible subscriber number rather than a couple of digits.
                bool alreadyPrefixed = n.StartsWith(cc) && n.Length >= cc.Length + 7;
                if (!alreadyPrefixed) n = cc + n.TrimStart('0');
            }

            // Shortest real E.164 number is about 8 digits, longest is 15.
            if (n.Length < 8 || n.Length > 15) return null;

            return n;
        }
    }
}
